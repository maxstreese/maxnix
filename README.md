# maxnix

A declarative NixOS VM running **niri** and **Hyprland** side by side, with
**Quickshell** on top, built to learn how the pieces fit — while the host stays
an ordinary Ubuntu install. Both compositors are in daily use; which one you
get is a pick at the login screen, not a decision this repo is working toward.

The whole machine is defined here. Being a VM is a *variant* of that
definition, not a second description of it.

```bash
scripts/vm-keys run -- nix run .#vm    # start it; hands the keyboard to the guest, restores on exit
nix run .#vm                           # start it plainly — host keeps Super and its chords, see below
nix run .#vm-headless                  # no window; VNC on 127.0.0.1:5909 so something can watch
nix run .#test-desktop                 # boot, greeter, sessions, GPU
nix run .#test-niri                    # niri: IPC, output, layout, shell, render
nix run .#test-hyprland                # same, for Hyprland
nix run .#test-vm-starts               # the runner above actually starts (opens a window for 8s)
```

Log in as `max` / `maxnix`. Inside the VM, `rebuild` reapplies the config from
`/mnt/maxnix` in ~35 s without rebooting.

First run only: open 1Password and sign in. Everything else that needs a
login — Firefox, and later Spotify and Claude — gets its credentials from
there. No credential is in this repo, and none ever should be.

---

## How it fits together

| layer | what |
|---|---|
| host | Ubuntu 24.04, GNOME Wayland. Only needs a Nix daemon and `/dev/kvm` |
| distro | NixOS, `nixpkgs-unstable`, pinned by `flake.lock` |
| compositors | niri 26.04, Hyprland 0.56.2 — both in use, switched between at login |
| shell toolkit | Quickshell 0.3.0 |
| shell | DankMaterialShell (bar, launcher, notifications, power menu) |
| greeter | Dank Greeter (Quickshell UI hosted in niri) |
| browser | Firefox, 1Password extension preinstalled by policy |
| credentials | 1Password app + `op` CLI; state on the guest disk, never in the repo |

```
flake.nix                    inputs, hostModules, packages + apps + checks
hosts/maxnix/
  configuration.nix          the machine: user, locale, keyboard, home-manager
  vm.nix                     build-vm specifics: window, disk image, repo share, `rebuild`
modules/
  desktop/{default,niri,hyprland,greeter,onepassword}.nix  system-level enable
  vm/qemu-guest.nix          virtual hardware, shared by build-vm and test nodes
home/max/{default,niri,hyprland,dms,firefox}.nix user-level config
tests/{desktop,compositor,vnc}.nix               integration tests
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
| channel | `nixpkgs-unstable` | these three packages move fast; stable would evaluate old versions |
| Home Manager | as a NixOS module | one `nix build`, one generation, no separate `home-manager switch` |
| compositors | both, for good | not an A/B: both stay and get switched between. NixOS makes two configs cheap, and shared DMS bindings make switching cheap too |
| VM disk | ephemeral, host `/nix/store` shared over virtiofs | rebuilds in seconds; the VM is not a standalone artifact |
| niri config | Home Manager's module | no extra input, and `checkConfig` validates by running niri at build time |
| Hyprland config | `configType = "hyprlang"` | every tutorial is hyprlang; **removed in Hyprland 0.57**, so this expires |
| modifier key | Super, as upstream | QEMU's keyboard grab makes Mutter inhibit its shortcuts for the window; `scripts/vm-keys` covers the two things the grab cannot: the overlay key, and GNOME's remembered permission |
| shell | DankMaterialShell now, own Quickshell later | a usable desktop on both compositors today; DMS's QML is a worked example to learn from |
| greeter | Dank Greeter | matches DMS visually; **gives up** tuigreet's "works without GL" property |
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

**The build sandbox can open neither `/dev/kvm` nor `/dev/dri`** on this host:
both are `crw-rw----` and the only grant is an ACL for the human user, which
does not apply to `nixbld`. `--option extra-sandbox-paths /dev/dri` exposes the
path but not access. So `nix build .#checks…` is useless here; the interactive
driver runs as you, outside the sandbox.

**niri has no software renderer.** Without virgl it starts, opens its socket,
and enumerates zero outputs. Mesa's `GBM_ALWAYS_SOFTWARE` does not rescue it.
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

**Do not run `dms-greeter sync`.** Upstream's documented path symlinks the
greeter cache at live DMS config; the Nix module makes root-owned copies in
greetd's `preStart`. They fight.

---

## Tests

16 subtests across three `nixosTest` checks, plus a startup check. The three
share `hostModules` with the real machine, so a test node cannot drift from what
`nix run .#vm` builds.

Run them with `nix run .#test-<name>`, **not** `nix build .#checks…` — see the
sandbox finding above.

`test-vm-starts` is the odd one out and covers what the other three
structurally cannot. They all override `-display` to `egl-headless`, so the
`gtk,gl=on` path a human uses was exercised by nothing — which is how the
`-vnc` regression in `5231c9a` shipped with every suite green. QEMU validates
flag compatibility at startup, so "still alive after 8 s" suffices: `timeout`
reports that as exit 124, and any other status means QEMU bailed. It needs a
graphical session and flashes a window; that is inherent to testing
`-display gtk`.

Hard-won lessons encoded in them:

- **Assert the observable, not the input.** `XKB_DEFAULT_LAYOUT=de` reached both
  compositors while Hyprland was still on US.
- **A passing test is not evidence.** The render check asserted PNG file size,
  which a solid-black 1920×1080 screen satisfies. It now counts distinct
  colours.
- **Poll, don't sleep.** DMS takes ~30 s to draw; a fixed wait caught an empty
  screen and called it success.
- **Thresholds are calibrations that expire.** `colours > 1` was right for
  tuigreet's text console and would have passed on a blank graphical greeter.
- **Verify the verifier.** Every check here was run against a deliberately
  broken config to confirm it fails — the layout test with the layout flipped
  to `us`, `test-vm-starts` with `-vnc` put back. A test only ever seen passing
  is indistinguishable from one that asserts nothing.

---

## Open points

**Bind reachability is not checked.** The dead German binds were found by a
hand-run audit, not by anything in the repo. A build-time check comparing bind
keysyms against the compiled keymap would catch the whole class.

**Colour thresholds are magic numbers** calibrated against today's screenshots.

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
`programs.quickshell.configs.<name>` at a *string* path under `/mnt/maxnix` for
live editing, then fold it into the store once the design settles.

**The greeter does not visibly track the DMS palette yet.** `configHome` is
wired and the copy is verified byte-identical, but repainting `colors.json`
changed nothing on screen. Upstream documents `settings.json` as the file
carrying appearance; DMS has not written one here yet.

**Login state lives on a disk this repo treats as disposable.** 1Password,
Firefox and every later sign-in persist in `.vm/maxnix.qcow2`, and deleting
that file is the documented reset. A second qcow2 for `/home` would let root be
thrown away while the sign-ins survive. Not a host share: browser profiles and
Electron apps use sqlite with file locks, which virtiofs is the wrong place for.

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
