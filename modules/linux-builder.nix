# nix-darwin module: local Linux builder VM (Virtualization.framework +
# Rosetta) for building this project's x86_64-linux / aarch64-linux packages
# on Apple Silicon Macs.
#
# Usage, in your personal darwin flake:
#   inputs.nix-go.url = "github:<org>/nix-go";
#   modules = [ inputs.nix-go.darwinModules.linux-builder ... ];

{ pkgs, ... }:

{
  nix = {
    enable = true;
    settings = {
      "extra-experimental-features" = [ "nix-command" "flakes" ];
      trusted-users = [ "@admin" ];
    };

    linux-builder = {
      enable = true;
      package = pkgs.darwin.linux-builder-vz;        # Virtualization.framework + Rosetta
      systems = [ "aarch64-linux" "x86_64-linux" ];  # both arches from one VM
      config.virtualisation.vz.rosetta.enable = true;
      maxJobs = 4;
      config = {
        # k3s needs more than the builder defaults (1 core / 3 GiB / 20 GiB)
        virtualisation.cores = 4;
        virtualisation.darwin-builder.memorySize = 8192;   # MiB
        virtualisation.darwin-builder.diskSize = 40960;    # MiB
        services.k3s = {
          enable = true;
          role = "server";                 # default; standalone w/ embedded sqlite
          extraFlags = [ "--tls-san=127.0.0.1" ];  # so TLS works via tunnel
        };
      };
    };
  };
}
