# nix-go

Proof-of-concept monorepo: Go services + React/TypeScript frontend, all built and packaged by Nix flakes.

Nix is not required to work on the code itself: the source tree is a regular Go workspace (vendored deps) and a regular Yarn/TypeScript project, so contributors who don't use Nix can ignore `flake.nix` and `nix/` and use any Go/Node install.

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
    # Can also be pointed to local version for development
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

## 5. Useful flake commands

Quick reference for day-to-day commands, run from the repo root. `.` always means "this flake".

```bash
# List everything this flake provides (packages, apps, dev shells)
nix flake show

# Open a shell with the project's tools (Go, Node, ...); leave with exit
nix develop

# Build a package; the result is linked at ./result
nix build .#service1

# Build if needed, then run the package
nix run .#service1

# Sanity check: evaluate the flake and run its checks
nix flake check

# Update flake inputs (nixpkgs, flake-parts, ...) to their latest revisions
nix flake update
```

A few notes:

- `nix flake update` rewrites `flake.lock` — review the diff before committing.
- `nix flake check` is a cheap "is my flake still valid?" test, worth running before pushing.

### The dev shell

`nix develop` is the workhorse for day-to-day development. It opens a shell with the tools from `devShells.default` on your PATH, so you can do normal Go and JS work without installing anything on your machine — tool versions are pinned in the flake, so everyone gets the same toolchain:

```bash
nix develop
# (nix-go) $ go test ./...
# (nix-go) $ golangci-lint run
# (nix-go) $ go build ./golang/apps/service1
# (nix-go) $ exit
```

The prompt is prefixed with `(nix-go)` while you're inside; `exit` to leave. For a one-off command (scripts, CI), skip the interactive shell: `nix develop -- go test ./...`.

## 6. Future Additions

- **devenv** ([devenv.sh](https://devenv.sh)): declarative dev-environment management. `devenv up` / `devenv down` would start and stop all services (service1, service2, web) in one command with logs and auto-restart, instead of running each in its own terminal.
- **k3s**: the Linux builder VM (see section 3) already runs a standalone k3s server. The built docker images could be loaded into it and deployed as workloads, giving a local Kubernetes environment to test the full stack end-to-end.
- **Binary cache + GitHub Actions CI**: push built derivations to a shared [Cachix](https://cachix.org) cache and run `nix flake check` / `nix build` on PRs in CI. New machines and CI pull prebuilt results instead of recompiling everything from scratch. Caching server can be self-hosted.
- **agenix** ([agenix](https://github.com/ryantm/agenix)): age-based secret management. Secrets are encrypted in the repo (or a private secrets repo) and decrypted at build time or in the dev shell, so services get credentials without hardcoded values or untracked `.env` files.

### Extra thoughts

- **Local databases via nix-darwin**: run Postgres as nix-darwin services on the Mac, so the full stack comes up with no manual setup.
- **Hot reload in the dev shell**: a `nix watch`-based dev script that rebuilds and restarts a service on code change, instead of rebuilding by hand.
- **direnv**: automatically activate the dev shell and its env vars when entering the repo, so you don't have to run `nix develop` manually.
- **Nix linting**: nixpkgs-fmt / statix / treefmt wired into the dev shell and `nix flake check` so the Nix code itself gets checked.
- **justfile** ([just](https://github.com/casey/just)): a small task runner checked into the repo. Recipes like `just test`, `just lint`, `just build` wrap the common commands and run inside the dev shell, so the toolchain is always present and the README no longer has to list every invocation.
