{ pkgs, version, src }:
pname: subPackage:
  pkgs.buildGoModule {
    inherit pname version src;
    subPackages = [ subPackage ];
    vendorHash = null; # vendored via `go work vendor`
    meta = {
      description = "testpoc ${pname}";
      mainProgram = pname;
    };
  }
