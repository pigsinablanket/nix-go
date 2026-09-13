{ inputs, ... }:
{
  systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

  # Expose the per-system `dockerImages` as a flake output:
  # .#dockerImages.<system>.<name>
  transposition.dockerImages = { };

  # nix-darwin module that sets up a local Linux builder VM for this
  # project's linux builds on Apple Silicon Macs:
  # .#darwinModules.linux-builder
  flake = {
    darwinModules.linux-builder = ../darwin/linux-builder.nix;
  };

  perSystem = { config, options, pkgs, lib, system, ... }:
    let
      helpers = (import ../lib) {
        inherit (inputs) nixpkgs;
        inherit system;
        src = ../..;
      };
      inherit (helpers) goModule goModuleLinux dockerImage web linuxPkgs;
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
          web = web.app pkgs;
        };

        dockerImages = {
          service1 = dockerImage "service1" 8080 (goModuleLinux "service1" "golang/apps/service1");
          service2 = dockerImage "service2" 8081 (goModuleLinux "service2" "golang/apps/service2");
          web = web.image (web.app linuxPkgs);
        };

        # buildGoModule runs `go test` in its check phase, so `nix flake check`
        # runs the Go test suites for the packages plus the example library.
        checks = {
          inherit (config.packages) service1 service2 web;
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
}
