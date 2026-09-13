# nix-go

Proof-of-concept monorepo: Go services + React/TypeScript frontend, all built and packaged by Nix flakes.

## 1. Install Nix on macOS (via [Lix](https://lix.systems))

Lix is a drop-in replacement for the Nix package manager. We use its installer because the official Nix installer has no uninstaller (manual removal on macOS is a pain). The official implementation of Nix is still used.

```bash
curl -sSf -L https://install.lix.systems/lix | sh -s -- install
```

Verify with `nix --version` — it should print `nix (Nix) ...`.

## 2. Set up your Mac with a system flake

A *system flake* is a `flake.nix` that describes your Mac's configuration; [nix-darwin](https://github.com/nix-darwin/nix-darwin) turns it into the actual system. It's separate from a *project flake* like this repo's `flake.nix`: the system flake describes the machine (installed tools, services, the build VM), while the project flake describes how to build and package the code. The system flake consumes the project flake as an input (the `nix-go.url` line below).

The standard location for the system flake is `/etc/nix-darwin/flake.nix`:

```bash
sudo mkdir -p /etc/nix-darwin
sudo chown "$USER" /etc/nix-darwin
```

Create `/etc/nix-darwin/flake.nix`:

```nix
{
  description = "My Mac";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-go.url = "github:pigsinablanket/nix-go";
  };

  outputs = { nix-darwin, nix-go, ... }: {
    # Must match your Mac's hostname (scutil --get LocalHostName) so
    # `darwin-rebuild` finds it automatically.
    darwinConfigurations."my-mac" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin"; # Apple Silicon
      modules = [
        nix-go.darwinModules.linux-builder
      ];
    };
  };
}
```

Install it (`darwin-rebuild` is not in your PATH yet, so run it via `nix run`):

```bash
sudo nix run nix-darwin/master#darwin-rebuild -- switch
```

The first run also builds the Linux builder VM image, so it takes a while. Afterwards, apply changes with:

```bash
sudo darwin-rebuild switch
```

## 3. Linux builds on Apple Silicon

The `linux-builder` module imported in step 2 (from this repo's `nix/darwin/linux-builder.nix`) sets up a local Linux builder VM (Virtualization.framework + Rosetta) so `x86_64-linux` and `aarch64-linux` builds run on your Mac.

After step 2, the VM starts automatically at boot and registers itself as a Nix builder — Linux-target builds are dispatched to it with no extra setup:

```bash
nix build .#service1 --system x86_64-linux
nix build .#dockerImages.aarch64-darwin.service1
```

VM: 4 cores / 8 GiB RAM / 40 GiB disk, Rosetta enabled, standalone k3s.
