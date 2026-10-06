# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A declarative NixOS machine (niri + Hyprland side by side, DankMaterialShell/Quickshell on top), currently staged as a VM on an Ubuntu host and meant to become the real metal install. `README.md` is long and load-bearing: its "Decisions, and why", "Findings worth keeping", "Tests" and "Open points" sections record things that cost real time to discover. Read the relevant section before changing behaviour in that area.

## Commands

All entry points are flake outputs; run from the repo root (the VM's disk images are created relative to the launch directory). `nix develop` (or direnv via `.envrc`) provides treefmt, statix, deadnix, actionlint, renovate, vncdotool, imagemagick, jq.

```bash
nix run .#ci                     # everything CI runs: static → metal → portable VM suites → GPU suites if /dev/dri/renderD128 opens
nix fmt                          # treefmt (nixfmt only); `treefmt --no-cache <file>` for one file
nix build .#checks.x86_64-linux.formatting     # any single check by name:
nix build .#checks.x86_64-linux.lint           #   statix + deadnix + actionlint + renovate-config-validator (report-only)
nix build .#checks.x86_64-linux.hyprland-config #  Hyprland --verify-config on the generated Lua config
nix build .#checks.x86_64-linux.metal          #   the installable toplevel builds
nix build .#checks.x86_64-linux.niri           #   portable tier of a VM suite (also desktop, hyprland, metal-boots, fleet, containers, secrets)
nix run .#test-niri              # full (GPU) suite for one of desktop|niri|hyprland; `-- --interactive` for a REPL
nix build .#ci                   # shellchecks the ci runner itself without running it
nix run .#blocked                # which workarounds in docs/blocked.toml upstream has unblocked
```

VM loop: `nix run .#vm` (window), `.#vm-headless` (VNC on 127.0.0.1:5909), `.#vm-deploy` (build on host, activate in running VM, no reboot), `.#vm-ssh -- <cmd>` (e.g. `niri msg outputs`, `hyprctl …`, `dms ipc …`, `'grim -' > shot.png`). Inside the guest: `rebuild` (~30 s). `qs-dev` runs `home/max/quickshell/` live; `dms-capture` / `dms-restore` move DMS theming state between `~/.config/DankMaterialShell` and `home/max/dms-state`. Guest login: `max` / `maxnix`.

Run the GPU `test-*` apps one at a time — they share a VNC port.

## Architecture

- **One machine definition, several evaluations.** `hostModules` in `flake.nix` is the machine. `nixosConfigurations.maxnix` adds `hosts/maxnix/vm.nix`; `packages.vm` is its `virtualisation.vmVariant` (`build-vm` re-evaluates the same config with `qemu-vm.nix` layered on). Every test node imports the same `hostModules`, so tests cannot drift from the real machine. VM-only settings belong under `virtualisation.vmVariant`, not in a separate description.
- **Layers.** `hosts/maxnix/*` = machine-specific system config (disk/LUKS/btrfs via disko, impermanence via `preservation`, backups, Fleet, rootless Docker, sops secrets, dev). `modules/desktop/*` = system desktop layer (compositors, greeter, 1Password, Steam). `modules/vm/qemu-guest.nix` = virtual hardware shared by build-vm and test nodes. `home/max/*` = Home Manager user layer (as a NixOS module), one file per program. Custom options live under `maxnix.*` (e.g. `maxnix.backup`, `maxnix.fleet`, `maxnix.dev.liveConfig`, `maxnix.vm.gpu`).
- **Shared key bindings.** `home/max/binds.nix` is the single list both compositors render (with `repeat` stated per binding — repeat steps, never spawns/toggles). Hyprland binds launch via `uwsm app --`; niri scopes spawns itself. Hyprland config is `configType = "lua"`; its API reference is `$out/share/hypr/stubs/hl.meta.lua` in the package, not the wiki.
- **Two test tiers from one definition.** `mkTests gpu` builds each suite twice. `gpu = false` (the `checks` output, sandboxed, cached, what GitHub CI reaches) omits screen assertions because niri has no software renderer and the Nix sandbox can't do GL. `gpu = true` runs through the interactive driver via `nix run .#test-*`. `checks` = `staticChecks // metalChecks // portableVmTests`; `ci` builds those groups cheapest-first. Test-related knowledge belongs in `flake.nix`, not in `.github/workflows/checks.yml` (which is just "install Nix, `nix run .#ci`").
- **Workarounds waiting on upstream** are listed in `docs/blocked.toml`, each with a check; `tools/blocked.py` evaluates them and a weekly workflow files issues.

## Conventions

- Comments explain *why*, often with dates and measured evidence; match that density and keep README's tables/findings current when a decision or finding changes.
- Linting is report-only and kept out of `nix fmt` on purpose; use `statix fix` / `deadnix --edit` deliberately. `statix.toml` disables `empty_pattern` (keep `{ ... }:` for modules) and `repeated_keys` (keep separated, commented siblings).
- Unfree packages are allowed per module via `nixpkgs.config.allowUnfreePackages`, named next to their reason. Test nodes that need this set `node.pkgsReadOnly = false`.
- VM-only shortcuts are marked `ROAD TO METAL` in comments (`grep -rn 'ROAD TO METAL'`). Prefer changes that still hold on hardware.
- No credentials in the repo. Secrets go through sops-nix (`hosts/maxnix/secrets.yaml`, recipients in `.sops.yaml`); everything else comes from 1Password at runtime.
- Verify a new check by breaking the thing it guards and confirming it fails (break the renderer, not the input list it's generated from).
- Inside the guest, rebuild and probe freely. Anything touching the Ubuntu host itself (`scripts/vm-keys`, dconf, the portal permission store) is the exception: be conservative and save-and-restore.
- niri resolves binds against unshifted keysyms, so punctuation binds are not layout-portable (the keyboard layout is `de`). Stick to letters, digits, arrows, F-keys.
- Workflow cron schedules run at night UTC on minute 17, never on a full or quarter hour (GitHub delays or drops runs at those times under load).
