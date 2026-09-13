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
    # References the projects repo to be able to include the system configuration
    nix-go.url = "github:pigsinablanket/nix-go";
  };

  outputs = { nix-darwin, nix-go, ... }: {
    # Must match your Mac's hostname (scutil --get LocalHostName) so
    # `darwin-rebuild` finds it automatically.
    darwinConfigurations."my-mac" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin"; # Apple Silicon
      modules = [
        nix-go.darwinModules.linux-builder
        ({ system, ... }: { system.stateVersion = 7; })
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

VM: 4 cores / 8 GiB RAM / 40 GiB disk, Rosetta enabled (for x86 cross compilling), standalone k3s.

## 4. Env vars and parameters via `nix run`

The `apps` flake output wraps each service binary in a small shell script that exports env vars before `exec`-ing the real binary, forwarding any extra arguments. `PORT` is set to a non-default value so you can see the env var take effect:

```bash
# Env var from the wrapper: service1 listens on 9090, not its built-in 8080
nix run .#service1
curl -s localhost:9090/api/v1/greeting
# => {"service":"service1","greeting":"Hello from example package",...}

# Parameters after `--` are passed through to the binary
nix run .#service1 -- --greeting "hi from nix"
curl -s localhost:9090/api/v1/greeting
# => {"service":"service1","greeting":"hi from nix",...}
```
