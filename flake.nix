{
  description = "Test POC cloud admin environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    mission-control.url = "github:Platonic-Systems/mission-control";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      imports = [
        inputs.flake-root.flakeModule
        inputs.mission-control.flakeModule
      ];
      # Expose the per-system `dockerImages` as a flake output:
      # .#dockerImages.<system>.<name>
      transposition.dockerImages = { };

      # nix-darwin module that sets up a local Linux builder VM for this
      # project's linux builds on Apple Silicon Macs:
      # .#darwinModules.linux-builder
      flake = {
        darwinModules.linux-builder = ./modules/linux-builder.nix;
      };

      perSystem = { config, options, pkgs, lib, system, ... }:
        let
          version = "0.1.0";

          # Docker images must contain linux binaries even when built on
          # darwin, so their contents come from the matching linux system
          # (on Apple Silicon those builds run on the local linux-builder VM).
          linuxSystem = if lib.hasSuffix "-linux" system
            then system
            else "${lib.removeSuffix "-darwin" system}-linux";
          linuxPkgs = inputs.nixpkgs.legacyPackages.${linuxSystem};

          goModule = pks: pname: subPackage: pks.buildGoModule {
            inherit pname version;
            src = ./.;
            subPackages = [ subPackage ];
            vendorHash = null; # vendored via `go work vendor`
            meta = {
              description = "testpoc ${pname}";
              mainProgram = pname;
            };
          };

          dockerImage = pname: port: pkg: linuxPkgs.dockerTools.buildLayeredImage {
            name = "testpoc/${pname}";
            tag = version;
            contents = [ pkg ];
            config = {
              Cmd = [ "${pkg}/bin/${pname}" ];
              Env = [ "PORT=${toString port}" ];
              ExposedPorts = { "${toString port}/tcp" = { }; };
            };
            meta.description = "Docker image for test poc ${pname}";
          };

          # Hash-pinned offline yarn cache: fetches every tarball listed in
          # js/yarn.lock from the npm registry (network access happens here,
          # once) so the build itself stays offline and the repo doesn't carry
          # a 200+ MiB .yarn/cache.
          #
          # After changing js/yarn.lock, regenerate the missing hashes and
          # prefetch the new cache hash:
          #   nix shell nixpkgs#yarn-berry.yarn-berry-fetcher -c bash -c '
          #     yarn-berry-fetcher missing-hashes js/yarn.lock > js/missing-hashes.json
          #     yarn-berry-fetcher prefetch js/yarn.lock js/missing-hashes.json'
          # then paste the printed sha256-... into `hash` below.
          yarnDeps = pkgs.yarn-berry.fetchYarnBerryDeps {
            src = ./js;
            missingHashes = ./js/missing-hashes.json;
            hash = "sha256-IFUQDcXCyYjzve3Sh4pPwU4BvphUp9nkS+/VARIp4QU=";
          };

          # React + TypeScript + Vite app. The yarn-berry setup hook installs
          # deps from yarnDeps during the configure phase; buildPhase only
          # runs the app's own build scripts.
          web = pks: pks.stdenv.mkDerivation {
            pname = "web";
            inherit version;
            src = ./js;
            nativeBuildInputs = [
              pks.nodejs
              pks.yarn-berry
              pks.yarn-berry.yarnBerryConfigHook
            ];
            yarnOfflineCache = yarnDeps;
            missingHashes = ./js/missing-hashes.json;
            buildPhase = ''
              runHook preBuild
              yarn build
              runHook postBuild
            '';
            checkPhase = ''
              runHook preCheck
              yarn typecheck
              runHook postCheck
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out
              cp -r apps/web/dist $out/web
              runHook postInstall
            '';
            meta = {
              description = "testpoc web (React + TypeScript + Vite)";
            };
          };

          # writeTextDir (not writeText): dockerTools copies each content with
          # `rsync -ak $item/ layer/`, which requires a directory. This places
          # the config at /etc/nginx/web.conf inside the image.
          webNginxConf = root: linuxPkgs.writeTextDir "etc/nginx/web.conf" ''
            worker_processes auto;
            pid /tmp/nginx.pid;
            error_log /dev/stderr warn;

            events {
              worker_connections 1024;
            }

            http {
              include ${linuxPkgs.nginx}/conf/mime.types;
              access_log /dev/stdout;

              server {
                listen 8082;
                server_name _;
                root ${root};
                index index.html;

                location /api/health {
                  access_log off;
                  default_type text/plain;
                  return 200 "healthy\n";
                }

                location / {
                  try_files $uri $uri/ /index.html;
                }
              }
            }
          '';

          # The image has no base distro, so provide the minimal /etc files
          # nginx needs (it drops worker privileges to the compile-time
          # default user "nobody"), plus /var/log/nginx to silence the
          # pre-config error-log alert.
          webEtc = [
            (linuxPkgs.writeTextDir "etc/passwd" "root:x:0:0:root:/root:/sbin/nologin\nnobody:x:65534:65534:nobody:/:/sbin/nologin\n")
            (linuxPkgs.writeTextDir "etc/group" "root:x:0:\nnogroup:x:65534:\n")
            (linuxPkgs.writeTextDir "var/log/nginx/.keep" "")
            # nginx creates its /tmp/nginx_* temp dirs at startup; the
            # parent must exist.
            (linuxPkgs.writeTextDir "tmp/.keep" "")
          ];

          webImage = pkg:
            let root = "${pkg}/web"; in
            linuxPkgs.dockerTools.buildLayeredImage {
              name = "testpoc/web";
              tag = version;
              contents = [ linuxPkgs.nginx pkg (webNginxConf root) ] ++ webEtc;
              config = {
                Cmd = [ "nginx" "-c" "/etc/nginx/web.conf" "-g" "daemon off;" ];
                ExposedPorts = { "8082/tcp" = { }; };
              };
              meta.description = "Docker image for test poc web";
            };
        in
        {
          options.dockerImages = lib.mkOption {
            description = "Docker images for the test poc services";
            type = lib.types.lazyAttrsOf lib.types.package;
          };

          config = {
            packages = {
              service1 = goModule pkgs "service1" "golang/apps/service1";
              service2 = goModule pkgs "service2" "golang/apps/service2";
              web = web pkgs;
            };

            dockerImages = {
              service1 = dockerImage "service1" 8080 (goModule linuxPkgs "service1" "golang/apps/service1");
              service2 = dockerImage "service2" 8081 (goModule linuxPkgs "service2" "golang/apps/service2");
              web = webImage (web linuxPkgs);
            };

            # buildGoModule runs `go test` in its check phase, so `nix flake check`
            # runs the Go test suites for the packages plus the example library.
            checks = {
              inherit (config.packages) service1 service2 web;
              example = goModule pkgs "example" "golang/pkg/example";
            };

            # `nix run .#service1` / `nix run .#service2`
            apps = {
              service1 = {
                type = "app";
                program = "${config.packages.service1}/bin/service1";
              };
              service2 = {
                type = "app";
                program = "${config.packages.service2}/bin/service2";
              };
            };

            mission-control.scripts = {
              hello = {
                description = "test script";
                exec = "echo hello";
              };
            };

            devShells.default = pkgs.mkShell {
              name = "dev";

              inputsFrom = [ config.mission-control.devShell ];

              packages = with pkgs; [
                hasura-cli
                graphqurl
                prettier

                gopls
                golangci-lint-langserver
                go
                godef
                go-tools
                golangci-lint

                nodejs
                yarn-berry

                colima
                docker
                docker-compose
                docker-credential-helpers
                kubectl
              ];
            };
          };
        };
      };
}
