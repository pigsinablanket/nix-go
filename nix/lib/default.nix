{ nixpkgs, system, src }:
let
  version = "0.1.0";
  inherit (nixpkgs) lib;
  pkgs = nixpkgs.legacyPackages.${system};

  # Docker images must contain linux binaries even when built on
  # darwin, so their contents come from the matching linux system
  # (on Apple Silicon those builds run on the local linux-builder VM).
  linuxSystem = if lib.hasSuffix "-linux" system
    then system
    else "${lib.removeSuffix "-darwin" system}-linux";
  linuxPkgs = nixpkgs.legacyPackages.${linuxSystem};
in
{
  inherit version pkgs linuxPkgs;

  goModule = import ./go-module.nix {
    inherit pkgs version src;
  };

  # Same builder for the linux system: docker image contents must be
  # linux binaries (see `linuxPkgs` above).
  goModuleLinux = import ./go-module.nix {
    pkgs = linuxPkgs;
    inherit version src;
  };

  dockerImage = import ./docker-image.nix {
    pkgs = linuxPkgs;
    inherit version;
  };

  web = import ./web.nix {
    inherit pkgs linuxPkgs version src;
  };
}
