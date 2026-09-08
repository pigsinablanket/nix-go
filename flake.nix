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

      perSystem = { config, options, pkgs, lib, ... }:
        let
          version = "0.1.0";

          goModule = pname: subPackage: pkgs.buildGoModule {
            inherit pname version;
            src = ./.;
            subPackages = [ subPackage ];
            vendorHash = null; # vendored via `go work vendor`
            meta = {
              description = "testpoc ${pname}";
              mainProgram = pname;
            };
          };

          dockerImage = pname: pkg: pkgs.dockerTools.buildLayeredImage {
            name = "testpoc/${pname}";
            tag = version;
            contents = [ pkg ];
            config = {
              Cmd = [ "${pkg}/bin/${pname}" ];
            };
            meta.description = "Docker image for test poc ${pname}";
          };
        in
        {
          options.dockerImages = lib.mkOption {
            description = "Docker images for the test poc services";
            type = lib.types.lazyAttrsOf lib.types.package;
          };

          config = {
            packages = {
              service1 = goModule "service1" "golang/apps/service1";
              service2 = goModule "service2" "golang/apps/service2";
            };

            dockerImages = {
              service1 = dockerImage "service1" config.packages.service1;
              service2 = dockerImage "service2" config.packages.service2;
            };

            # buildGoModule runs `go test` in its check phase, so `nix flake check`
            # runs the Go test suites for the packages plus the example library.
            checks = {
              inherit (config.packages) service1 service2;
              example = goModule "example" "golang/pkg/example";
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
