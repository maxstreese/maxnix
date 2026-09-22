# maxnix

A declarative NixOS machine running **niri** and **Hyprland** side by side,
with **Quickshell** on top. Both compositors are in daily use; which one you
get is a pick at the login screen, not a decision this repo is working toward.

## Why this exists

The aim is a Linux that is declarative, reproducible and tailored to one
person, built and debugged with heavy LLM assistance. Today it runs as a VM on
an ordinary Ubuntu host, so it can be tinkered with for as long as it takes
without committing to it full time. The destination is to **live in it**: this
configuration is meant to become the real host install. The VM is a staging
environment for that future host, not a sandbox for its own sake.

That has two consequences for how work here is judged:

- **Prefer what transfers to metal.** A convenience that only makes sense
  inside a VM is a lower priority than a fix that still holds on hardware.
  Shortcuts taken "because it is only a VM" are debt, tracked under *Road to
  metal* below.
- **The VM boundary is what makes broad assistant permissions acceptable.**
  Inside the guest, rebuild, break and probe freely; nothing in there can
  reach the host's filesystem, not even the repo (there is no share — git is
  the only channel out). Anything that reaches the Ubuntu host from the
  host side — `scripts/vm-keys`, dconf, the portal permission store — is the
  exception: be conservative, explain, and save-and-restore.

The whole machine is defined here. Being a VM is a *variant* of that
definition, not a second description of it.

```bash
scripts/vm-keys run -- nix run .#vm    # start it; hands the keyboard to the guest, restores on exit
nix run .#vm                           # start it plainly — host keeps Super and its chords, see below
nix run .#vm-headless                  # no window; VNC on 127.0.0.1:5909 so something can watch
nix run .#vm-deploy                    # build here, activate in the running VM, no reboot
nix run .#vm-ssh -- niri msg outputs   # run a command in the running VM (or open a shell with no args)
nix run .#test-desktop                 # boot, greeter, sessions, GPU
nix run .#test-niri                    # niri: IPC, output, layout, shell, render
nix run .#test-hyprland                # same, for Hyprland
nix run .#test-vm-starts               # the runner above actually starts (opens a window for 8s)
```

Log in as `max` / `maxnix`. The guest has no view of the host's filesystem;
it is a separate machine that happens to run here, and the two sync through
git like any other pair.

Two ways to iterate on the running machine, both faster than a test run:

- **From inside.** Clone the repo to `~/Repositories/github.com/maxstreese/maxnix`
  (on the `/home` disk, so it survives a root reset), edit there or run
  `claude` in it, then `rebuild` — ~30 s, no reboot. Both compositors reload
  their config on the spot, DMS restarts with the activation, and DMS's own
  theme settings need no rebuild at all. Commit and push as on any machine.
- **From the host.** Edit here, `nix run .#vm-deploy`: builds on the host,
  copies the closure in over ssh, activates. Then drive and observe the
  desktop over the same channel: `nix run .#vm-ssh -- niri msg …`, `hyprctl`,
  `dms ipc`, and `nix run .#vm-ssh -- 'grim -' > shot.png` for a screenshot
  to look at.

First run only: open 1Password, sign in, and in Settings → Developer switch on
"Use the SSH agent" and "Integrate with 1Password CLI". Everything else that
needs a login — Firefox, Spotify, Claude Code, `ssh`, `op` — gets its
credentials from there. No credential is in this repo, and none ever should be.

---

## How it fits together

| layer | what |
|---|---|
| host, for now | Ubuntu 24.04, GNOME Wayland. Needs a Nix daemon, `/dev/kvm` and — for the GPU tier — a render node; both at mode 0666 so sandboxed builds can use KVM |
| distro | NixOS, `nixpkgs-unstable`, pinned by `flake.lock` |
| compositors | niri 26.04, Hyprland 0.56.2 — both in use, switched between at login |
| shell toolkit | Quickshell 0.3.0 |
| shell | DankMaterialShell (bar, launcher, notifications, power menu) |
| greeter | Dank Greeter (Quickshell UI hosted in niri) |
| terminal | ghostty, opened through its D-Bus-activated systemd service |
| browser | Firefox, 1Password and Vimium preinstalled by policy, default for links |
| apps | Spotify, Slack, Discord, Claude Code — each signs in once via the browser |
| games | Steam, as a system module: it needs the 32-bit graphics stack and controller udev rules |
| vpn | Twingate, as a system daemon; `twingate setup` once, then `twingate start`. Until then the unit sits in `failed`, by design |
| dev tools | git (system-wide, needed to clone), DuckDB, kubectl, Scala 3, delta, fzf, gh, awscli2, steampipe |
| notebooks | marimo, inside a declared `python3.withPackages` with polars, duckdb, pyarrow, altair, numpy |
| git config | identity, aliases, ignores and SSH commit signing declared in Home Manager |
| keyboard | Wootility + its udev rules; needs USB passthrough to see the keyboard in the VM |
| ssh, `op` | both served by the 1Password app: agent socket in `ssh_config`, `op` unlocks through the app |
| credentials | 1Password app + `op` CLI; state on the guest disk, never in the repo |

```
.github/workflows/checks.yml all of CI: install Nix, then `nix run .#ci`
.github/renovate.json5       flake.lock and action-SHA updates, as PRs
flake.nix                    inputs, hostModules, packages + apps + checks + devShell
treefmt.nix                  what `nix fmt` runs, and what it deliberately does not
statix.toml                  the two statix lints this repo switches off, with reasons
hosts/maxnix/
  configuration.nix          the machine: user, locale, keyboard, home-manager
  disk.nix                   bootloader, and the layout wired into NixOS
  disk-layout.nix            the LUKS2/btrfs layout as data, shared with its test
  vm.nix                     build-vm specifics: window, disk images, sshd, `rebuild`
modules/
  desktop/{default,niri,hyprland,greeter,onepassword,gpu-check,steam}.nix  system layer
  vm/qemu-guest.nix          virtual hardware, shared by build-vm and test nodes
home/max/*.nix               user layer, one file per program: default (the
                             layer itself), niri, hyprland, dms, ghostty,
                             firefox, apps, dev, git, ssh
tests/{desktop,compositor,vnc}.nix               integration tests
tests/disk.nix               formats, installs and boots the real disk layout
scripts/vm-keys              host tooling: release/restore GNOME shortcuts
```

**One idea worth internalising:** `nixos-rebuild build-vm` does not read a
separate VM description. It evaluates *this* configuration a second time with
`nixos/modules/virtualisation/qemu-vm.nix` layered on top, and emits a shell
script that runs on the Ubuntu host. `virtualisation.vmVariant` is where that
second evaluation's settings live. That is why the host needs nothing but Nix
and KVM — even the QEMU binary comes from the Nix store.

---

## Decisions, and why

| decision | choice | reasoning |
|---|---|---|
| channel | `nixpkgs-unstable`, also on the future host | these three packages move fast; stable would evaluate old versions. Decided 2026-09-17 to keep it |
| Home Manager | as a NixOS module | one `nix build`, one generation, no separate `home-manager switch` |
| compositors | both, for good | not an A/B: both stay and get switched between. NixOS makes two configs cheap, and shared DMS bindings make switching cheap too |
| VM disks | root is disposable, `/home` is its own image, host `/nix/store` shared over virtiofs | root can be deleted to reset the machine without losing a single login; the VM is a variant of the machine, not the artifact |
| repo in the guest | its own clone, no host share | the share was the fast loop and a hole in the boundary at once, and virtiofs broke it twice over (see findings); git syncs two machines, and the host deploys over ssh — the same model metal will use |
| niri config | Home Manager's module | no extra input, and `checkConfig` validates by running niri at build time |
| Hyprland config | `configType = "hyprlang"` | every tutorial is hyprlang; **removed in Hyprland 0.57**, so this expires |
| Hyprland session | under UWSM | systemd-managed session like niri's. The greeter also offers the unmanaged entry; hiding it would cost a package wrapper, so it stays |
| modifier key | Super, as upstream | QEMU's keyboard grab makes Mutter inhibit its shortcuts for the window; `scripts/vm-keys` covers the two things the grab cannot: the overlay key, and GNOME's remembered permission |
| shell | DankMaterialShell now, own Quickshell later | a usable desktop on both compositors today; DMS's QML is a worked example to learn from |
| greeter | Dank Greeter | matches DMS visually; **gives up** tuigreet's "works without GL" property |
| login passwords | plaintext `initialPassword`, kept for metal too | decided 2026-09-17; not on the road to metal |
| rescue path | password login on the text consoles, no autologin | the greeter needs GL, a TTY does not; autologin would have made the lock screen decorative |
| git config | declared, not `git config --global` | a fresh guest had no identity at all, so the first commit inside would have failed. The cost is that the file is a store symlink, so `git config --global` no longer works |
| commit signing | SSH keys via 1Password, not GPG | supported by git since 2.34 and verified by GitHub, GitLab and Bitbucket; the private half never leaves the vault, and only public keys appear in this repo. Two keys: auth is scoped to an account on one host, signing to one identity everywhere |
| app launching | Hyprland binds go through `uwsm app --` | own systemd unit per app, as upstream asks; niri scopes every `spawn` itself |
| terminal | ghostty via `ghostty +new-window` | replaced alacritty 2026-09-18; windows come from ghostty's own D-Bus service, so they sit outside the compositor's cgroup on both compositors |
| VM access | sshd in the guest, host loopback 2222, password auth | `vm-deploy` and `vm-ssh` drive the running VM from the host; loopback-only, and the password is public by decision, so a key would add nothing |
| credentials | 1Password in the guest | the repo installs, you sign in once; browser extension, SSH agent and `op` then serve every other login. Nothing secret in Nix or git |
| unfree packages | per-module `allowUnfreePackages` list | matched on pname and concatenated across modules, so each unfree package is named next to its reason and a new one still fails evaluation |

---

## Findings worth keeping

Things that cost real time to discover.

**nixpkgs' Mesa hardcodes `/run/opengl-driver`**, a NixOS-only path. On Ubuntu,
Nix-built QEMU cannot initialise GL and core-dumps under `-display gtk,gl=on`.
`LIBGL_DRIVERS_PATH` is ignored; **`GBM_BACKENDS_PATH` is the one honoured.**
`modules/vm/qemu-guest.nix` wraps QEMU with it — no root, no host changes.

**Only one thing may own QEMU's GL context.** `-display gtk,gl=on` and `-vnc`
cannot coexist (`Display vnc is incompatible with the GL context`). A window or
VNC, never both. Hence `vm-headless` as a separate app.

**`screendump` cannot capture a GL scanout** — `Error: no surface` — so the test
driver's `machine.screenshot()` and `get_screen_text()` are unusable here. VNC
readback works, which is what `tests/vnc.nix` does.

**The build sandbox denies `setgroups`, so only the `other` permission bits
reach a build.** `/dev/kvm` and `/dev/dri/renderD128` are `root:kvm` /
`root:render`, and adding the 32 `nixbld` users to those groups changes
nothing: Nix writes `deny` to `/proc/self/setgroups` before its gid map, which
the kernel requires without `CAP_SETGID` and which permanently forbids
supplementary groups. Inside a build, `id` reports `groups=100(nixbld)` alone.
That is why every CI recipe ships a udev rule with `MODE="0666"` rather than a
group — measured the hard way on 2026-09-21, after the group route was tried
and did nothing.

**Even world-readable, the sandbox cannot do GL: it does not mount `/sys`.**
With `/dev/kvm` and `/dev/dri/renderD128` at `0666` and
`extra-sandbox-paths = /dev/dri`, both open fine and KVM works — but Mesa
resolves a render node's driver through `/sys/dev/char/<major>:<minor>`, which
is absent, and `eglinfo` reports `eglInitialize failed`. So KVM-only tests are
ordinary sandboxed checks and GPU tests are not, at any permission. This is
the line the two test tiers are drawn along.

**niri has no software renderer.** Without virgl it starts, opens its socket,
and enumerates zero outputs. Mesa's `GBM_ALWAYS_SOFTWARE` does not rescue it.
Re-measured 2026-09-21 on both `-device virtio-gpu` and `-device virtio-vga`:
`niri msg outputs` returns empty and the screen stays a 2-3 colour text
console. This is the fact the portable test tier is built on.
wlroots compositors have pixman, which is how upstream's `nixos/tests/sway.nix`
gets away with no GPU; smithay-based niri does not.

**niri resolves binds against the *unshifted* keysym.** On `de`, `[` is AltGr+8
and `/` is Shift+7, so `Mod+BracketLeft` and `Mod+Shift+Slash` match nothing —
configured, shown in the hotkey overlay, completely dead. Letters, digits,
arrows and function keys are layout-portable; punctuation is not.

**`console.keyMap` and `XKB_DEFAULT_LAYOUT` are unrelated mechanisms** — TTY vs
Wayland — and neither implies the other. `services.xserver.xkb.layout` reaches
*nothing* in a Wayland-only system. Hyprland ignores `XKB_DEFAULT_LAYOUT`
because its own `kb_layout` defaults to `"us"`; niri honours it.

**QEMU's keyboard grab does work — once GNOME is allowed to honour it.** On
Wayland every key goes to Mutter first. When QEMU grabs the keyboard, GTK sends
a `keyboard-shortcuts-inhibit` request and Mutter then passes every chord
through, `Alt+Tab` and `Super+1` included (verified with `WAYLAND_DEBUG=1`).
Granting is a user decision, and because Ubuntu ships `qemu.desktop`, GNOME
Shell remembers the answer in the desktop portal's permission store. This host
had a remembered **Deny**, which makes the grab silently do nothing: request
sent, no dialog, no reply. That is the true story behind the old finding that
`Ctrl+Alt+G` "makes no difference". `scripts/vm-keys` sets the entry to
GRANTED for the run. The one thing the grab never covers is the bare overlay
key, which Mutter handles before the inhibitor check, so the script releases
that too. `grab-on-hover=on` in `vm.nix` engages the grab by pointing at the
window.

**Homebrew's `gsettings` shadows the system one** and reports schema *defaults*
rather than your dconf database. Use `/usr/bin/gsettings` or `dconf` when
reading GNOME settings.

**Hyprland 0.56 moved config and dispatchers to Lua.** `hyprctl dispatch exec`
now fails; `hyprctl dispatch exit` still works. Config lives at
`~/.config/hypr/hyprland.lua` unless you pin `configType = "hyprlang"`.

**virtiofs needs shared guest memory, and `build-vm` does not give it any.**
nixpkgs moved shared directories from 9p to virtiofs in September 2026. vhost-user
devices need the guest's RAM as a shared memory object, which only the NixOS
test driver switches on — so every test passed while `nix run .#vm` hung on a
vhost handshake. The virtiofsd warning about file handles and "Operation not
permitted" is a red herring. `modules/vm/qemu-guest.nix` sets
`qemu.enableSharedMemory` until nixpkgs PR #563324 makes it the default.

**1Password only talks to browsers it recognises by executable name.** nixpkgs'
Firefox is a wrapper that execs `.firefox-wrapped`, which is not on the list, so
the extension never connects and never says why. `/etc/1password/custom_allowed_browsers`
must name it, root-owned and mode 0755, or the app rejects the file.

**greetd's PAM stack is a substack of `login`**, and NixOS puts
`pam_gnome_keyring` into `login` whenever the keyring daemon is enabled — so the
password typed into the greeter already unlocks the keyring. Setting
`security.pam.services.greetd.enableGnomeKeyring` renders nothing, because
greetd replaces its rules wholesale; the keyring lines are in
`/etc/pam.d/login`, which is what the test asserts.

**Test nodes get a read-only `pkgs`.** `runNixOSTest` sets `node.pkgs`, which
makes every `nixpkgs.*` option on the node fail with "defined multiple times".
A module that adds to `allowUnfreePackages` therefore breaks every test until
`node.pkgsReadOnly = false` lets the node build its own `pkgs` from the same
options `nix run .#vm` uses.

**virtiofs shares are unusable as a live, two-way working tree**, for two
independent reasons, and it was this that ended the repo share. Unprivileged
virtiofsd acts only for a guest identity whose uid *and* gid match its own; the
guest user's default gid is 100 against 1000 on the host, so every create as a
normal user fails with EPERM while root works, which is why nixpkgs' own tests
never notice. And the module hardcodes `--cache=always`, so a file edited on
the host kept its old content in the guest until caches were dropped, and
`rebuild` cheerfully rebuilt the previous revision. 9p (one `-virtfs` flag and
a mount, `cache=mmap` for git) has neither problem and was verified, then
dropped along with the share itself.

**The VM runner has no pre-start hook, but drive paths are shell-expanded.**
`qemu-vm.nix` creates only the root image, and its `emptyDiskImages` live in a
per-run temp directory. A persistent second disk therefore creates itself: its
`file` is a `$(…)` that makes the image on first use and prints the path,
anchored to `$OLDPWD` because the runner has already done `cd "$TMPDIR"`.
`/home` must be `neededForBoot`, because activation creates `/home/max` before
systemd mounts anything.

**niri scopes spawned programs by itself; Hyprland does not.** Under a systemd
session niri puts every `spawn` into its own transient scope (its spawning
code says why). Hyprland launches binds as children of the compositor, so its
launcher binds carry `uwsm app --`, per the Hyprland wiki's UWSM page.

**A VM sees QEMU's emulated keyboard, not your real one.** So Wootility runs
in the guest but finds no device. Passing the hardware through works and needs
no root, because the USB node is `root:input` and you are in that group:
`QEMU_OPTS="-device usb-host,vendorid=0x31e3,productid=0x1312" nix run .#vm`.
The host has no keyboard for as long as that VM runs. On metal the udev rules
alone are enough.

**NixOS cannot run generic-linux binaries, and modern Python tooling is full
of them.** uv downloads its own CPython rather than using a system one, and
that binary dies before `main()` because there is no
`/lib64/ld-linux-x86-64.so.2`. `programs.nix-ld` puts a stub loader there and
is what the NixOS wiki and the error message both point at. It works: with it
on, a marimo notebook declaring polars inline ran its cells and imported
polars from PyPI.

It is also not the only way, and it was not kept. Pointing uv at a nixpkgs
interpreter (`UV_PYTHON`, with `UV_PYTHON_DOWNLOADS=never`) means no
generic-linux binary is ever executed, and the same notebook ran with the
nix-ld variables removed. uv and Nix are known to sit awkwardly together —
astral-sh/uv#4450 has been open since 2024, labelled *compatibility*, and
`uv venv` from a wrapped nixpkgs Python isolates itself from that Python's
packages — so the third option won: marimo lives in a `python3.withPackages`
environment, and nothing downloads an interpreter at all.

**A tool's Nix wrapper can have a closed environment, which fails only at run
time.** The bare `marimo` package is wrapped with a fixed PYTHONPATH holding
its own runtime dependencies and nothing else, with no pip. It installs
cleanly, starts cleanly, and then a notebook's `import polars` fails, and
installing polars elsewhere in the profile does not help. Declaring the
library set alongside marimo in one `python3.withPackages` is what makes the
global install honest; `home/max/dev.nix` carries the reasoning.

**An unconfigured Twingate daemon respawns forever.** Its unit pairs
`Restart=always` with `StartLimitIntervalSec=0`, which turns off systemd's
rate limit — and before `twingate setup` has named a network the daemon exits
at once, so it restarts every 2 s indefinitely (655 journal lines in the first
few minutes). `hosts/maxnix/configuration.nix` gives the limit back, so it
gives up after five tries and stays in `failed` until configured.

**Only public keys can be declared, which is exactly enough for signing.**
An SSH signing setup needs the public key, the signer program and an
allowed-signers file, none of them secret, so the whole thing lives in the
repo while the private half stays in 1Password. The auth key needs no
declaration at all: with an agent the server challenges and the agent offers
keys until one is recognised, so nothing local says which key belongs to
GitHub. Signing is the reverse, because nothing challenges a commit.

**`home.sessionVariables` reaches login shells and nothing else**, exactly as
its description says: "set at login". Home Manager writes them into
`hm-session-vars.sh` and only `~/.profile` sources it, so under Wayland, where
nothing sources a profile, the option sets a variable where nobody looks.
Measured in the guest: present under `bash -l`, absent under `bash -i`, absent
from `/etc/pam/environment` and from the systemd user environment. The gap is
long-standing upstream (home-manager#1011, and #3100 open since 2022 for the
Wayland case) with no blessed fix; the workarounds in the wild are sourcing
that file from `.bashrc`, `environment.extraInit`, or
`systemd.user.sessionVariables`.

NixOS' own `environment.sessionVariables` avoids the question: it writes
`/etc/pam/environment`, and pam_env applies that to the systemd **user**
manager too, so every app it starts inherits it — ghostty included. That is
how `XKB_DEFAULT_LAYOUT` and `NIXOS_OZONE_WL` already travel here, and the
`.bashrc` workaround was tried and dropped in favour of it.

**A business 1Password account gives you a second vault called Private.** So
`vault = "Private"` in `agent.toml` is ambiguous once two accounts are signed
in, and the entry needs `account` naming the sign-in address.

**Do not run `dms-greeter sync`.** Upstream's documented path symlinks the
greeter cache at live DMS config; the Nix module makes root-owned copies in
greetd's `preStart`. They fight.

---

## Tests

16 subtests across three `nixosTest` checks, plus a startup check. The three
share `hostModules` with the real machine, so a test node cannot drift from what
`nix run .#vm` builds.

**One command runs all of it, here and in CI:**

```
nix run .#ci
```

It probes for a usable render node, prints what it found, builds the portable
tier, and — only where a GPU exists — runs the full suites too, naming every
subtest it skipped. There is no "am I in CI" flag: the only difference between
a local run and a runner's is which line that probe prints.

The tiers come from one definition instantiated twice, differing only in a
`gpu` argument (`mkTests` in `flake.nix`):

| | `nix build .#checks…` / CI | `nix run .#test-<name>` |
| --- | --- | --- |
| `gpu` | `false` | `true` |
| QEMU | `-device virtio-vga` | `-device virtio-vga-gl` + `egl-headless` + `-vnc` |
| desktop | 4 subtests | 6 |
| niri / hyprland | 2 subtests each | all |
| sandboxed | yes, and cached | no — needs `/sys`, see above |

The portable tier is everything that does not look at the screen. It is not a
guess: without virgl both compositors *start* and serve their IPC but
enumerate zero outputs and draw nothing, so every screen assertion, and
everything downstream of having a surface, is gated. Verified 2026-09-21 by
running all three portable suites sandboxed (8 subtests, green) and the full
desktop suite with `+virgl` (6 subtests, green).

`test-vm-starts` is the odd one out and covers what the other three
structurally cannot. They all override `-display` to `egl-headless`, so the
`gtk,gl=on` path a human uses was exercised by nothing — which is how the
`-vnc` regression in `5231c9a` shipped with every suite green. QEMU validates
flag compatibility at startup, so "still alive after 8 s" suffices: `timeout`
reports that as exit 124, and any other status means QEMU bailed. It needs a
graphical session and flashes a window; that is inherent to testing
`-display gtk`.

Two static checks sit alongside the VM tests in the portable tier:

| check | what it asserts | fix it with |
| --- | --- | --- |
| `formatting` | every `.nix` file is nixfmt-clean | `nix fmt` |
| `lint` | statix, deadnix, actionlint and the Renovate config validator find nothing | by hand — see below |
| `metal` | the machine as it would be *installed* builds | by hand |
| `metal-boots` | that layout partitions, formats and boots | by hand |

`metal` is the one check nothing else can stand in for. `packages.vm` builds
the vmVariant's toplevel and the three suites build a third variant again —
all of them get their disks and bootloader from `qemu-vm.nix`, so none of them
touches the metal path. Demonstrated by deleting
`boot.loader.systemd-boot.enable`: `checks.metal` fails, `nix build .#vm`
still succeeds. It catches a build, not a boot; whether the layout in
`disk.nix` would actually partition and come up is `metal-boots`.

`metal-boots` is disko's `makeDiskoTest`: it formats a blank virtual disk from
`hosts/maxnix/disk-layout.nix`, installs NixOS onto it and reboots into the
result. It reads the *same* layout file the real machine does — that is why
the layout is plain data in its own file, since `makeDiskoTest` calls its
config with `lib` alone and cannot be handed a NixOS module. It also exercises
the real unlock path: the guest prints `Please enter passphrase for disk
disk-main-luks`, and the test reads that off the console with OCR and types
the answer, rather than taking a keyfile shortcut that the metal machine will
not have. Slowest check here by some way — a full install, not a boot.

`nix fmt` is treefmt driving nixfmt, configured in `treefmt.nix`, which also
records why shfmt and a Markdown formatter are deliberately absent. The linters
are kept *out* of `nix fmt` on purpose: treefmt can run them, but only in
`--fix` mode, and deadnix's fix is to delete a function argument. A formatter
that rewrites code is not a formatter, so `lint` only ever reports.

`nix flake check` **passes** as of the disko commit — it validates
`nixosConfigurations` too, and that only started working once the metal
configuration had a root filesystem and a bootloader. So
`nix flake check --max-jobs 1` is now a correct one-line replacement for
`nix run .#ci`. It is still not what CI runs, for one reason: it builds in
dependency order rather than cheapest-first, so a formatting typo would be
reported *after* the VM suites instead of in the second before them. That
ordering is the only thing `ci` adds over the one-liner.

`statix.toml` switches off two lints that disagree with conventions this repo
applies deliberately — `empty_pattern` (`{ ... }:` over `_:`) and
`repeated_keys` (sibling options separated by their explanations). Everything
else statix checks stays on; the file says why for each.

`.github/workflows/checks.yml` is the whole of CI: free disk space, check out,
install Nix, `nix run .#ci`. One `run:` step, deliberately — everything about
*what* gets tested lives in the flake, so the workflow never needs to know
what a tier is. It is named for what it verifies rather than for being CI —
every workflow would be "ci" — and its single job is `portable`, so the PR
status reads `checks / portable` and says in passing that the GPU tier is not
covered here. Three details in it are load-bearing:

- **Actions are pinned to full-length commit SHAs**, tag in a trailing
  comment. Tags are mutable; `tj-actions/changed-files` had all of its
  rewritten to malicious commits in March 2025. The `lint` check runs
  `actionlint` over the workflow, which also shellchecks every `run:` block.
- **`install_url` pins Nix itself.** Pinning the action's SHA pins the
  installer *script*, not the Nix it fetches at run time. The URL names
  2.34.8, matching `nix --version` here, so both environments run the same
  Nix.
- **Freeing disk is required, not an optimisation.** The guest closure is
  12.5 GiB and a runner has roughly 14 GB free.

`.github/renovate.json5` keeps the two pinned things moving: `flake.lock` and
the workflow's action SHAs. Three of its five settings exist only to defeat a
default that silently does nothing — the nix manager is beta and ships
disabled, `lockFileMaintenance` is off and `config:recommended` does not turn
it on, and either omission makes Renovate run happily while never touching
`flake.lock`. `helpers:pinGitHubActionDigests` maintains the SHA pins and
pins any action added later, so the policy is enforced rather than
remembered. Nothing automerges: a green `checks / portable` says the machine
builds, boots and has its software, and says nothing about what is on screen,
so an update that breaks the greeter would pass. Renovate is a GitHub App and
has to be installed on the repo by hand; until it is, that file does nothing.

The `lint` check validates it with `renovate-config-validator`, for the same
reason it runs `actionlint`: a mistake in either surfaces as a bot or a runner
quietly not doing its job, which is the kind of failure nobody notices.

No binary cache, on purpose. The Actions cache is 10 GB and the closure is
12.5 GiB, so it does not fit; and the bulk of that is upstream packages
`cache.nixos.org` already serves, so a second cache would move the same bytes
from a different host. Only our own derivations would benefit, and those are
small.

`nix develop` gives you the tools those checks assume, so "what does this repo
need installed" has a declared answer rather than being whatever the host
happens to have: `treefmt` (for one file, where `nix fmt` does the tree),
`statix` and `deadnix` (the `lint` check only reports, so `statix fix` and
`deadnix --edit` are deliberate acts), `actionlint` and `renovate` for the two files under `.github/`,
`vncdotool` and `magick` for looking at a running VM and recalibrating a
colour threshold, and `jq`. Note treefmt
caches on mtime — `treefmt --no-cache` to force the whole tree.

Hard-won lessons encoded in them:

- **Assert the observable, not the input.** `XKB_DEFAULT_LAYOUT=de` reached both
  compositors while Hyprland was still on US.
- **A passing test is not evidence.** The render check asserted PNG file size,
  which a solid-black 1920×1080 screen satisfies. It now counts distinct
  colours.
- **`command -v a b c` checks `a` and stops.** It prints the first name it
  resolves and exits 0, so a one-line "are these installed" assertion passes
  while every other name is missing. Three such checks here sat green for a
  while. They are a loop now, one name at a time.
- **User-profile binaries are not on root's PATH.** The driver's shell is
  root's, so anything Home Manager installed has to be resolved through the
  user's own login shell.
- **Poll, don't sleep.** DMS takes ~30 s to draw; a fixed wait caught an empty
  screen and called it success.
- **Thresholds are calibrations that expire.** `colours > 1` was right for
  tuigreet's text console and would have passed on a blank graphical greeter.
- **Verify the verifier.** Every check here was run against a deliberately
  broken config to confirm it fails — the layout test with the layout flipped
  to `us`, `test-vm-starts` with `-vnc` put back, `formatting` against a
  mangled file, `lint` against an unused argument and a manual `inherit`. A
  test only ever seen passing is indistinguishable from one that asserts
  nothing. The first attempt at that last one was itself vacuous: it injected
  `x = pkgs.hello`, which statix correctly ignores because the binding is not
  named after the attribute.

---

## Open points

**Bind reachability is not checked.** The dead German binds were found by a
hand-run audit, not by anything in the repo. A build-time check comparing bind
keysyms against the compiled keymap would catch the whole class.

**Colour thresholds are magic numbers** calibrated against today's screenshots.

**The greeter sometimes never draws in the desktop test.** Roughly one run in
five, the screen stays a single colour for the full 120 s while every other
subtest passes; an immediate rerun passes. Neither failure's log was kept, so
the cause is unknown. The test now dumps greetd's and the greeter compositor's
journal on that failure.

**Hyprland's `.conf` support is removed in 0.57.** Nothing forces the question
yet: `flake.lock` pins nixpkgs, so 0.57 arrives only when you run
`nix flake update`, and as of this writing nixpkgs-unstable still ships 0.56.2.
When it does land there are two options — port to `configType = "lua"`, or pin
Hyprland to 0.56. Dropping Hyprland is not one of them. The Lua API has been
mapped empirically (see the table in `home/max/hyprland.nix`; `hl.dsp.exec`
does not exist and the spelling was not obvious) and the port is blocked on
exactly one unknown: the `addreserved` equivalent that keeps the DMS bar from
being covered.

**Write our own Quickshell config** — the last piece of the original plan, and
the reason Quickshell was on the list. Point
`programs.quickshell.configs.<name>` at a *string* path inside the guest's
clone for live editing, then fold it into the store once the design settles.

**The greeter does not visibly track the DMS palette yet.** `configHome` is
wired and the copy is verified byte-identical, but repainting `colors.json`
changed nothing on screen. Upstream documents `settings.json` as the file
carrying appearance; DMS has not written one here yet.

**Road to metal.** Everything the config does *because it is only a VM*, to be
undone or replaced when this becomes the host install:

- `security.sudo.wheelNeedsPassword = false`, purely to skip typing in a
  throwaway guest.
- ~~No disk layout or bootloader.~~ Done: `hosts/maxnix/disk.nix` declares
  systemd-boot plus a LUKS2 + btrfs layout through disko, so the metal
  configuration now evaluates, *builds*, and — via `checks.metal-boots` —
  formats a disk and boots from it. What remains is the one fact that
  needs the machine — `disko.devices.disk.main.device` is a placeholder until
  `nixos-facter` on the target yields its `/dev/disk/by-id/…` path. Still
  missing: a hardware module (`nixos-hardware` profiles or a facter report)
  and swap, which wants RAM-sized hibernation space and is therefore also a
  fact about the unchosen machine. A swapfile on btrfs is just a file, so it
  costs nothing to defer; the partition layout around it does not.
- No hardware report. `hardware.facter.reportPath` is `null`; nixpkgs ships
  the facter modules, so install day is one line plus a JSON file — see the
  ROAD TO METAL note in `hosts/maxnix/configuration.nix` for both commands.
  The wiring is verified against a real report from the Ubuntu host: it turned
  on AMD microcode and redistributable firmware and filled in the initrd
  module list. It does *not* choose the disk — a report with no `fileSystems`
  still fails the root-filesystem assertion — so `disk-layout.nix`'s `device`
  stays a separate human decision from `ls /dev/disk/by-id`.
- No machine secrets. Nothing needs one yet, but a laptop wants a Wi‑Fi PSK
  at least; that is when sops-nix or agenix earns its place.
- No networking beyond QEMU's user-mode DHCP. A laptop needs NetworkManager,
  which is also what DMS's network widget talks to.
- `security.rtkit.enable` is off, so PipeWire cannot get real-time
  scheduling; every boot log shows the RTKit errors. Harmless without audio
  hardware, wrong on a machine with speakers.
- Nothing for Bluetooth, UPower or power profiles. DMS's battery and power
  widgets expect them.
- The three DMS features left off in `home/max/dms.nix` (VPN, audio
  visualiser, calendar) are off only because the VM cannot exercise them.
- `scripts/vm-keys`, `grab-on-hover`, sshd on loopback, `vm-deploy` and
  `rebuild`'s VM variant all describe the host/guest seam and stop meaning
  anything on metal. The
  compositor, shell, keyboard, 1Password and Firefox work transfers as-is.

Each shortcut in the config is marked `ROAD TO METAL` in its comment, so
`grep -rn 'ROAD TO METAL'` lists them.

**Media and brightness keys** are GNOME keybindings like any other, so they
should follow the grab now. Not yet verified with a keypress.

**Two compositor configs to keep in step.** Both compositors stay, so their
configs are a permanent pair rather than a temporary one. Switching is a logout
and a session pick, and both carry identical DMS bindings (`Super+Space`,
`Super+N`, `Super+X`, `Super+Shift+Comma`) precisely so muscle memory
transfers. The cost is ~170 lines of compositor-specific config, of which 30
are the same 15 bindings written twice, and it grows per feature added rather
than sitting still. Today a bind added to one file has to be added to the other
by hand; generating both from a single binding list would remove that.
