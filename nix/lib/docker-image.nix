# `pkgs` is the linux system's packages (see `linuxPkgs` in
# default.nix): images must contain linux binaries even when built
# on darwin.
{ pkgs, version }:
pname: port: pkg:
  pkgs.dockerTools.buildLayeredImage {
    name = "testpoc/${pname}";
    tag = version;
    contents = [ pkg ];
    config = {
      Cmd = [ "${pkg}/bin/${pname}" ];
      Env = [ "PORT=${toString port}" ];
      ExposedPorts = { "${toString port}/tcp" = { }; };
    };
    meta.description = "Docker image for test poc ${pname}";
  }
