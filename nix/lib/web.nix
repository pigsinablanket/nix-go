{ pkgs, linuxPkgs, version, src }:
let
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
    src = src + /js;
    missingHashes = src + /js/missing-hashes.json;
    hash = "sha256-IFUQDcXCyYjzve3Sh4pPwU4BvphUp9nkS+/VARIp4QU=";
  };

  # React + TypeScript + Vite app. The yarn-berry setup hook installs
  # deps from yarnDeps during the configure phase; buildPhase only
  # runs the app's own build scripts.
  app = pks: pks.stdenv.mkDerivation {
    pname = "web";
    inherit version;
    src = src + /js;
    nativeBuildInputs = [
      pks.nodejs
      pks.yarn-berry
      pks.yarn-berry.yarnBerryConfigHook
    ];
    yarnOfflineCache = yarnDeps;
    missingHashes = src + /js/missing-hashes.json;
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
  nginxConf = root: linuxPkgs.writeTextDir "etc/nginx/web.conf" ''
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
  etc = [
    (linuxPkgs.writeTextDir "etc/passwd" "root:x:0:0:root:/root:/sbin/nologin\nnobody:x:65534:65534:nobody:/:/sbin/nologin\n")
    (linuxPkgs.writeTextDir "etc/group" "root:x:0:\nnogroup:x:65534:\n")
    (linuxPkgs.writeTextDir "var/log/nginx/.keep" "")
    # nginx creates its /tmp/nginx_* temp dirs at startup; the
    # parent must exist.
    (linuxPkgs.writeTextDir "tmp/.keep" "")
  ];

  image = pkg:
    let root = "${pkg}/web"; in
    linuxPkgs.dockerTools.buildLayeredImage {
      name = "testpoc/web";
      tag = version;
      contents = [ linuxPkgs.nginx pkg (nginxConf root) ] ++ etc;
      config = {
        Cmd = [ "nginx" "-c" "/etc/nginx/web.conf" "-g" "daemon off;" ];
        ExposedPorts = { "8082/tcp" = { }; };
      };
      meta.description = "Docker image for test poc web";
    };
in
{ inherit app image; }
