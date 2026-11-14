# maxnix

A declarative NixOS machine running **niri**, with **Quickshell** on top.
Hyprland ran next to it until 2026-10-18; see "Decisions, and why".

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
nix run .#vm-restore-key               # put the VM's sops key back from 1Password after a full reset
nix run .#z690-wsl-restore-key         # the same for the WSL host's key, run inside that guest
nix run .#test-desktop                 # boot, greeter, sessions, GPU
nix run .#test-niri                    # niri: IPC, output, layout, shell, render
nix run .#test-vm-starts               # the runner above actually starts (opens a window for 8s)
nix run .#blocked                      # which workarounds in docs/blocked.toml upstream has unblocked
```

Log in as `max` / `maxnix`. The guest has no view of the host's filesystem;
it is a separate machine that happens to run here, and the two sync through
git like any other pair.

Two ways to iterate on the running machine, both faster than a test run:

- **From inside.** Clone the repo to `~/maxnix` (on the `/home` disk, so it
  survives a root reset), edit there or run `claude` in it, then `rebuild` —
  ~30 s, no reboot. niri reloads its config on the spot, DMS restarts with
  the activation, and DMS's own theme settings need no rebuild at all.
  Commit and push as on any machine.
- **Without a rebuild at all,** for the two things where 30 s per keystroke is
  not a loop. `qs-dev` runs `home/max/quickshell/` straight from the clone and
  reloads on save, so writing QML is edit-and-look; in the VM the generated
  config points there too, so `qs -c maxnix` is live as well. DMS theming is
  already live because its settings file is mutable state DMS owns — theme in
  its UI, then `dms-capture` to copy the result into the clone, where git sees
  it. `dms-restore` puts it back after a root reset. See "Iterating on design"
  below.
- **From the host.** Edit here, `nix run .#vm-deploy`: builds on the host,
  copies the closure in over ssh, activates. Then drive and observe the
  desktop over the same channel: `nix run .#vm-ssh -- niri msg …`,
  `dms ipc`, and `nix run .#vm-ssh -- dms screenshot all --stdout --no-clipboard > shot.png` for a screenshot
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
| compositor | niri 26.04 |
| shell toolkit | Quickshell 0.3.0 |
| shell | Dux Modular Shell (bar, launcher, notifications, power menu) |
| greeter | DMS Greeter (Quickshell UI hosted in niri) |
| terminal | ghostty, opened through its D-Bus-activated systemd service |
| browser | Firefox, 1Password and Vimium preinstalled by policy, default for links |
| apps | Spotify, Slack, Discord, Claude Code — each signs in once via the browser |
| games | Steam, as a system module: it needs the 32-bit graphics stack and controller udev rules |
| vpn | Twingate, as a system daemon; `twingate setup` once, then `twingate start`. Until then the unit sits in `failed`, by design |
| dev tools | git (system-wide, needed to clone), DuckDB, kubectl, Scala 3, delta, fzf, gh, awscli2, steampipe, aoe |
| notebooks | none installed: `uvx marimo edit --sandbox nb.py` per notebook, dependencies declared inline; plain `python3` and uv are in the profile |
| git config | identity, aliases, ignores and SSH commit signing declared in Home Manager |
| keyboard | Wootility + its udev rules; needs USB passthrough to see the keyboard in the VM |
| ssh, `op` | both served by the 1Password app: agent socket in `ssh_config`, `op` unlocks through the app |
| credentials | 1Password app + `op` CLI; state on the guest disk, never in the repo |
| observability | Alloy → Prometheus (metrics, 2 y), Loki (logs, 1 y) and Tempo (traces, 30 d, with span metrics into Prometheus), Grafana on top; Alloy's built-in Beyla (eBPF) adds request rates, errors and latency for every process listening on a port, their CPU, memory and I/O, and byte counts of network flows (anonymous read-only; admin password generated in `/var/lib/grafana/admin-password`), all on loopback; Claude Code's OTel export and `grafana-local` (mcp-grafana, an Editor; in Claude Code `plugin:hm:grafana-local`, tools `mcp__plugin_hm_grafana-local__*`) for agents; on the WSL host also the NVIDIA GPU (utilisation, memory, temperature, power, clocks) from its own `nvidia-smi`, shown in the Nvidia GPU Metrics dashboard, while the ThinkPad's AMD GPU waits for metal. Besides the repo's own dashboards (Claude Code, Services), two established ones are provisioned from grafana.com at a pinned revision and hash: Node Exporter Full (1860) for the host, temperatures, fans and power included where the hardware reports them, and Nvidia GPU Metrics (14574); they replaced the repo's own Host dashboard (2026-11-08). Dashboards are JSON in `modules/base/observability/dashboards`: build in the UI and `grafana-capture`, or edit the files — live in the VM |

```
.github/workflows/checks.yml all of CI: install Nix, then `nix run .#ci`
.github/workflows/closure-diff.yml  on the lock refresh PR: which packages change on metal
renovate.jsonc               flake.lock and action-SHA updates, as PRs
hosts/t14s/secrets.nix     sops-nix: three post-quantum keys, secrets declared per consumer
hosts/t14s/secrets.yaml    the encrypted secrets; .sops.yaml at the root says who can open it
hosts/t14s/secrets-metal.yaml  metal's own, which the VM's key cannot open
flake.nix                    inputs, roles, mkHost, hosts, packages + apps + checks + devShell
                             `nix run .#install -- root@host` installs it for real
docs/inventory.md            what the current host runs daily; the list to migrate from
docs/desktop-pc.md           the second machine: maxnix under WSL, on its metal, for games
docs/blocked.toml            workarounds waiting on a third party, each with its check
tools/blocked.py             the checker behind `nix run .#blocked`
tools/blocked-report.py      its results as issues, one per entry that has become doable
.github/workflows/blocked.yml  runs that weekly and whenever flake.lock or the list changes
treefmt.nix                  what `nix fmt` runs, and what it deliberately does not
statix.toml                  the two statix lints this repo switches off, with reasons
hosts/t14s/                the ThinkPad: base + desktop + metal, and what is only its own
  configuration.nix          hostname, network, Twingate, wooting, zram, which features are on
  laptop.nix                 the laptop services its hardware report asks for
  vm.nix                     build-vm specifics: window, disk images, sshd, `rebuild`
hosts/z690-wsl/                   NixOS under WSL on the Windows desktop: base + gui + NixOS-WSL
  windows.nix                everything it takes from Windows: WSLg, GPU driver, URL opener
modules/                     roles a host is composed from (`roles` in flake.nix)
  base/default.nix           every machine: user, locale, keyboard, Nix settings, Home Manager
  base/containers.nix        rootless Docker, with DOCKER_HOST for the whole session
  base/dev.nix               where the clone lives, and the live-config switch
  base/login-limits.nix      pam_faillock in every stack that takes the login password
  base/observability/        metrics, logs, traces, Grafana; its dashboards/ as JSON
  base/rebuild.nix           built from the flake only: no channels, /etc/nixos → the clone
  desktop/{default,niri,greeter,lock-screen,onepassword-firefox,gpu-check,steam}.nix  niri and what it needs; imports gui
  gui/{default,onepassword}.nix  GUI apps that need a display but not niri; desktop role and z690-wsl
  metal/disk.nix             bootloader, and the layout wired into NixOS
  metal/disk-layout.nix      the LUKS2/btrfs layout as data, shared with its test
  metal/persistence.nix      the wiped root, and what survives it on /persist
  metal/backup.nix           restic: what to back up, and what to skip
  metal/fleet.nix            the employer's Fleet agent, off until IT supplies a URL
  vm/qemu-guest.nix          virtual hardware, shared by build-vm and test nodes
home/max/core/               user layer, every machine: shell, git, dev, harlequin, claude
home/max/desktop/            user layer, with the desktop role: niri, dms, quickshell,
                             ghostty, firefox, apps
home/max/gui/                user layer, with the gui role: onepassword (ssh agent, signing), herdr-desktop
home/max/{quickshell,dms-state}/  the QML and DMS state those two files deploy
tests/{desktop,niri,vnc}.nix                     integration tests
tests/disk.nix               formats, installs and boots the real disk layout
tests/fleet.nix              the Fleet agent starts and retries against no server
tests/containers.nix         rootless Docker runs a Docker Hub image behind the firewall
tests/secrets.nix            sops-nix decrypts a post-quantum key at activation
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
| compositor | niri only | decided 2026-10-18, reversing "both, for good". Two compositors were two configs that diverged wherever they were not generated from one list (niri's own window-management binds, layout, gaps, animation), a second desktop suite, a static check and a Lua port to follow upstream's churn. niri was already the greeter's compositor and the autologin session, and is validated at build time. Hyprland's config, suite and findings are in git history before this decision. Open for the desktop PC: Hyprland was further along on HDR and VRR (`docs/desktop-pc.md`), so niri's support is to check against that monitor |
| repo structure | hosts composed from roles: `modules/base`, `modules/desktop`, `modules/metal`, plus `hosts/<name>` | decided 2026-10-18, so a second machine (`docs/desktop-pc.md`) can take part of the machine rather than all of it. Roles import modules that define options; the host switches them on. Secrets stay with the host: which sops files and key a machine uses is its own. The user layer splits the same way: `home/max/core` comes with base, `home/max/desktop` with the desktop role, each role allowing its half's unfree packages. Hosts so far: `t14s` (base, desktop, metal) and `z690-wsl` (base, NixOS-WSL), the second only built by CI, since no NixOS test can boot WSL. Done as a refactor checked by store path: every one stayed the same except where expected — the order of the system's package list (its `sw` tree came out identical), comments inside test scripts, and the dashboards' path in the clone, which moved with observability into `modules/base`. A fourth role, `modules/gui` (with `home/max/gui`), split off the desktop role 2026-11-06 for GUI apps that need a display but not niri, starting with 1Password: the desktop role imports it, `z690-wsl` names it, so the WSL host gets the app, `op`, the SSH agent and signing from the ThinkPad's own modules under WSLg instead of a bridge to the Windows app. Metal's toplevel kept its store path; Firefox's allowed-browsers file stayed in the desktop role with Firefox |
| machine names | by hardware: `t14s` (the ThinkPad), `z690-wsl` (WSL on the Windows desktop), `z690` (that desktop on its own metal, when it gets a host); `maxnix` names the project — the repo, the `maxnix.*` options, Grafana's folder, the Drive backup folders, the VMs' password | decided 2026-10-19, when a second host made `maxnix` stop saying which machine. Hostname, `nixosConfigurations` name and `hosts/` directory are always the same word: the VM's `rebuild` and `nixos-rebuild --flake .` on metal pick the configuration by hostname. Renamed before metal's install day, so no machine's history, Fleet record from hardware or Secure Boot enrollment carries the old name; the VM's Fleet entry shows the new hostname from its next deploy |
| WSL host's coupling to Windows | self-contained by default, and always for credentials and dev tooling; the guest may use only interfaces Windows or WSL itself guarantees, each declared in `hosts/z690-wsl/windows.nix`: WSLg, the NVIDIA driver's `/usr/lib/wsl/lib`, and `rundll32.exe` to open http(s) links in the default Windows browser | decided 2026-11-07, after the first boot found no browser for `gh auth login` and 1Password had already gone the other way. The test is whether the target ships with Windows or WSL, not whether it is on this machine: 1Password's Windows CLI and agent are installed and switched on by hand, which nothing in the repo describes, so the Linux app runs in the guest (`modules/gui`); `rundll32.exe` is on every Windows and needs nothing about which browser is set. Considered and not taken: a stricter rule allowing only WSLg and the GPU. Its real gain is that interop could be switched off, closing the path by which anything in the guest can run code as max on Windows; its cost is a second browser under WSLg with its own sign-ins for every link and login, and, taken literally, the terminal too, while Windows Terminal and the Windows browser stay in daily use regardless. Interop therefore stays on, decided 2026-11-07 as its own question: switching it off would close that path but take the URL opener with it, for a gain that Windows Terminal and the Windows browser in daily use undercut anyway |
| VM disks | root is disposable, `/home` is its own image, host `/nix/store` shared over virtiofs | root can be deleted to reset the machine without losing a single login; the VM is a variant of the machine, not the artifact |
| repo in the guest | its own clone, no host share | the share was the fast loop and a hole in the boundary at once, and virtiofs broke it twice over (see findings); git syncs two machines, and the host deploys over ssh — the same model metal will use |
| niri config | Home Manager's module | no extra input, and `checkConfig` validates by running niri at build time |
| modifier key | Super, as upstream | QEMU's keyboard grab makes Mutter inhibit its shortcuts for the window; `scripts/vm-keys` covers the two things the grab cannot: the overlay key, and GNOME's remembered permission |
| shell | Dux Modular Shell now, own Quickshell later | a usable desktop today; DMS's QML is a worked example to learn from |
| greeter | DMS Greeter | matches DMS visually; **gives up** tuigreet's "works without GL" property |
| boot console | bootvine: a live tree of systemd's pending units from the initrd to the greeter, and at shutdown; not Plymouth, not bare text | decided 2026-11-12. Plymouth hides the boot behind a splash; this shows more of it than the scrolling lines did, and names the unit a boot hangs or fails on. It also takes over the LUKS passphrase prompt, which is why `checks.metal-boots` boots through it. Young (v0.1.3, one author) and root in the initrd, so it was first taken from its own flake, pinned to a release tag that lock file maintenance did not move, with its Cachix cache not taken. Since 2026-11-14 package and module are nixpkgs' own: nixpkgs gained both, the two modules declared `services.bootvine.enable` twice, and the lock refresh stopped evaluating. What that gives up is the pin: its version now moves with nixpkgs, reviewed there, and a bump shows in the closure diff on the lock PR. Desktop role, not base: WSL has no console. `q` or `Esc` gives the plain console back; an older generation boots without it |
| login passwords | metal: a yescrypt hash from sops (`login-password`) for `max` and root, users immutable; every VM: plaintext `maxnix` | decided 2026-09-17 as plaintext everywhere, changed 2026-10-13 for metal after measuring that the wiped root undid every `passwd` (Findings). Immutable users make the declared hash win at every activation, so `passwd` lasts only until the next one, and changing the password is a sops edit and a rebuild — the price of one a wipe cannot reset. Root shares the hash so the emergency shell still opens. The VMs hold no metal key and keep `maxnix`, which `vm-ssh` logs in with. `z690-wsl` (2026-11-07): a hash of its own, not metal's, from that host's own sops file and key, users immutable, root without one (`wsl -u root` needs none); it is what 1Password's system-authentication unlock asks for through polkit there. Not metal's because the WSL guest is the weaker place, reachable as root from Windows, so a password typed there should open nothing on the ThinkPad |
| networking | NetworkManager; networks joined in the UI (DMS's widget, `nmcli`) and preserved, not declared from sops | decided 2026-10-14. A laptop meets new networks all the time, and a rebuild per café would make the declarative way unusable; the profiles survive the wiped root on `/persist`, which the backup covers. sops-declared profiles can join them later for fixed networks, better once metal's secrets are out of the VM key's reach. `max` is in `networkmanager`, so saving a network asks for no password |
| swap | zram (compressed RAM), no swap on disk, so no hibernation for now | decided 2026-10-15. zram absorbs memory spikes for one line of config. Whether hibernation resumes reliably on this ThinkPad's AMD graphics, and whether lanzaboote's Secure Boot leaves the kernel willing to hibernate, shows only on the hardware; a swapfile in its own btrfs subvolume adds it later without repartitioning, with suspend-then-hibernate for a lid closed for days |
| power profiles | power-profiles-daemon, not TLP or tuned | decided 2026-10-14. DMS's power widget reads `org.freedesktop.UPower.PowerProfiles`, the interface power-profiles-daemon provides; TLP conflicts with it and DMS does not talk to it. Which driver it uses on this Ryzen shows only on the hardware (`powerprofilesctl`) |
| calendar | Dux Calendar syncing Google itself, for the company and a personal account, each through an OAuth client of its own; not khal | decided 2026-10-15. DMS prefers Dux Calendar when it runs, and khal would need a separate sync (vdirsyncer) to have anything to read. Own clients rather than Dux Calendar's built-in one, so no third-party app reads company calendar data: the company one Internal in the existing Workspace project, the personal one in a project of the personal account, since an Internal client admits only the organisation's accounts |
| failed logins | pam_faillock: 10 failures in 15 minutes lock an account for 10 minutes, root included; in `login` (consoles and greeter), `sudo`, `su`, `polkit-1` and the lock screen's `dankshell`; the count on `/persist` | decided 2026-10-14, when the TPM was to unlock the disk. Since the boot decision of 2026-10-15 (below) a cold boot stops at the LUKS passphrase, so this guards the lock screen of a laptop taken running or asleep; NIST SP 800-63B-4 asks for at most 100 failures, this is lenient enough for typos in a long passphrase. Root too, or a root login at the console would be the way around it; the emergency shell is unaffected, since `sulogin` does not use PAM. The lock screen gets a NixOS-built `/etc/pam.d/dankshell`, which DMS prefers over the `login` it ships without a lockout |
| locking | DMS's lock screen; the lock comes before any suspend, and 1Password locks with the screen | decided 2026-11-14. Lock before suspend is DMS's own, off by default, and switched on through `/etc/dms/cli-policy.json` (`modules/desktop/lock-screen.nix`), DMS's file for lock settings an administrator sets: the shell shows them as managed, and the rest of its settings stay the UI's. Without it a closed lid could suspend with the session still on screen. 1Password is locked by a user service that runs `1password --lock` when logind's LockedHint turns true for max's session (`home/max/desktop/lock.nix`), which follows the bind, the idle timer and the lock before suspend alike, and does not rest on a setting inside the app. Not taken: unlocking over IPC or `loginctl unlock-session` stays possible (the same policy file could switch both off); they are open only to what already runs as max |
| boot and login | one password at power-on: the LUKS passphrase, then greetd starts max's niri session (`initial_session`); no TPM unlock; the login keyring with an empty password | decided 2026-10-15, over typing a passphrase and then a password. Only someone who knows the passphrase gets past power-on, so the greeter added typing, not protection; the lock screen and sudo still take the login password. TPM unlock was dropped with it: together with autologin, the power button alone would open the session, and `modules/desktop/greeter.nix` refuses that combination. The keyring cannot be opened by the boot passphrase — greetd starts an autologin session without `pam_authenticate`, the step in which `pam_gnome_keyring` and `pam_systemd_loadkey` act (read in their sources) — so it has no password of its own, and LUKS protects its file. Metal only: VMs and test nodes have no LUKS and keep the greeter |
| backups | restic, to Google Drive over rclone; VM only until install day | Drive is the only destination the employer permits on this machine (learned 2026-09-23). restic was chosen before that, when the destination was unknown, for reaching the most backends — which is what made the constraint a config change rather than a rewrite |
| containers | Docker, rootless; no `docker` group | the work runs on Docker — compose, company image builds, Testcontainers 1.16, JetBrains — and Podman's compatibility is most of that, not all. Rootless because the `docker` group is root-equivalent and rootful Docker publishes ports past the firewall; its state also lands on `/home` rather than the wiped root. Images are excluded from backups |
| foreign binaries | `programs.nix-ld` on every host, plus mise for repos that pin tools in a `mise.toml`; my own projects keep a flake each | decided 2026-10-22, reversing "nix-ld was not kept" (Findings) for one reason: the work repos are not mine to convert, and they pin node, pnpm, uv and a dozen CLIs through mise, which downloads upstream generic-linux builds. Both repos were run end to end in the VM: every tool installs and runs, uv fetches and runs its own CPython, and the frontend's vitest (unit and Chromium component tests) passes, with Playwright's e2e suite running against Chromium. The cost is the loud failure: an undeclared binary now just runs, outside anything Nix can roll back or collect. The library list holds only what a named tool failed without, today Playwright's Chromium. On `z690-wsl` the Windows NVIDIA driver's `/usr/lib/wsl/lib` reaches foreign binaries through `LD_LIBRARY_PATH`, which nix-ld adds its own path to, set for every session in `hosts/z690-wsl/windows.nix` (2026-11-07): the driver's own `nvidia-smi` could not find `libnvidia-ml.so` without it, and Mesa's Vulkan driver found no GPU. In base, not desktop, because WSL runs the same repos. Considered and not taken: the Nix-backed mise plugins (a work repo's `node = "24"` reaches them only through hand-kept `tool_alias` mappings, exact pins often do not exist in nixpkgs, and npm's prebuilt binaries would need nix-ld anyway), a flake per work repo kept beside it (drifts from the team's pins), and a container per repo |
| notebooks and data work | nothing machine-wide: a project's Python comes from the project, a scratch notebook runs as `uvx marimo edit --sandbox` | decided 2026-11-14, removing the `python3.withPackages` environment (marimo, polars, duckdb, pyarrow, altair, numpy) that had been in the profile since 2026-09-18. Three reasons. It sat in `modules/base`, so in every host's closure, and its one fragile package stood in the way of the whole machine: from 2026-11-12 nixpkgs' marimo 0.25.1 would not build against `uv_build` 0.13.4 and the lock refresh failed on it. The library set was a guess, and adding to it meant a system rebuild. And the repo already said a project's dependencies belong to the project. Scratch notebooks now run on the CPython uv downloads, so they depend on nix-ld; accepted, and `UV_PYTHON` is not set globally because it would override the Python a work repo pins |
| device management | Fleet's agent (Orbit + osquery) via nixpkgs' `services.orbit`, with fleetd 1.63.0 built from upstream's tag, off until configured | the employer is adopting Fleet (learned 2026-09-29). Wired ahead of the URL and enroll secret; both come from sops, so turning it on is one line. `osquery` itself is a general system tool in `configuration.nix`; `osqueryi` also lets the machine be checked the way Fleet will check it. NixOS support is upstream since fleetd 1.63.0 (2026-10-28), which nixpkgs did not carry yet (1.55.0 plus four patches upstream now has), so `fleet.nix` overrides the version until it does. Whether the console reads the LUKS root and firewall correctly is first seen on metal; LUKS key escrow is still not offered to NixOS |
| backup secrets | sops-nix, rendered into an rclone.conf template | the repository password and the rclone OAuth token are both long-lived and must survive a reinstall, so neither can live only on the machine being backed up |
| rescue path | password login on the text consoles, no autologin | the greeter needs GL, a TTY does not; autologin would have made the lock screen decorative |
| git config | declared, not `git config --global` | a fresh guest had no identity at all, so the first commit inside would have failed. The cost is that the file is a store symlink, so `git config --global` no longer works |
| commit signing | SSH keys via 1Password, not GPG | supported by git since 2.34 and verified by GitHub, GitLab and Bitbucket; the private half never leaves the vault, and only public keys appear in this repo. Two keys: auth is scoped to an account on one host, signing to one identity everywhere |
| rebuilding | from this flake only, on every host: channels off, and `/etc/nixos` a symlink to the clone, so a bare `sudo nixos-rebuild switch` builds `/etc/nixos#<hostname>` from the working tree; not in the dev VM, which has `rebuild` | decided 2026-11-07, after the WSL host's image turned out to ship a stock `/etc/nixos/configuration.nix` and two channel subscriptions: a `nix-channel --update` and a bare rebuild would have replaced maxnix with NixOS-WSL's starter system. Through tmpfiles (`L+` for the link, `r` for `/root/.nix-channels`), so a fresh machine or image converges on its first activation, and on metal the link returns with every boot of the wiped root. Nothing at run time reads `/etc/nixos`, so a missing clone only makes the bare command fail. The VM keeps no link because the bare command would build `nixosConfigurations.t14s`, the metal system, not its `vmVariant`; without the link it fails instead |
| design loop | Quickshell config points at the clone in the VM; DMS theming is captured, not declared | the store is read-only, so a colour tweak would otherwise cost a 30 s rebuild. `maxnix.dev.liveConfig` makes generated Quickshell config an out-of-store symlink into the clone, so Quickshell's own file watcher has something that can change; it is off everywhere but the VM. DMS is the other way round — its settings UI already writes a mutable file, so `dms-capture` records that into the repo rather than declaring it and taking the UI's ability to save |
| DMS plugins | declared via `programs.dank-material-shell.plugins`, source as `flake = false` inputs; settings captured | pinned by `flake.lock` and bumped by Renovate like every other input, instead of whatever `dms plugins install` fetched that day. Settings stay out of Nix for the same reason as DMS theming: declaring any of them makes `plugin_settings.json` a store file the UI cannot save. Quick Capture records through gpu-screen-recorder on metal and wf-recorder in the VM, which has no encoder |
| observability | Alloy, Prometheus, Loki, Tempo and Grafana; not Mimir, VictoriaMetrics, OpenObserve or SigNoz | decided 2026-10-08 after comparing all four as single-machine backends; Tempo added 2026-10-09 for Claude Code's traces (beta since that day), with its span-metrics processor writing span durations into the same Prometheus rather than a second metrics store. Beyla added 2026-10-12 for servers only, after a probe of every process in the VM: short-lived clients such as `curl`, `nix` and `claude -p` exit before it attaches, so instrumenting everything bought desktop daemons, misdetections and noise, not the requests anyone asks about. An interactive Claude Code session it would attach to, but sees none of its API calls (see Findings), so Claude Code's own telemetry stays the only source for it; metrics only, no Beyla spans in Tempo, payload extraction off. Alloy is one binary for every planned input — OTLP, node_exporter, journald, and later eBPF network telemetry and profiling, both GA there. Loki's weakness, finding a record by an unindexed ID like Claude Code's `session.id`, costs the size of the streams a query selects; Claude Code's events are their own small stream, so at one machine's volume it does not bite. Prometheus over Mimir: clustering, tenants and object storage buy nothing on one box. mcp-grafana covers all of it, already the agent tool of choice. Claude Code's telemetry goes through a wrapper around `claude`, not session variables, so no other OTel SDK is redirected; prompt text is not sent. Agents get an Editor through `grafana-local` (2026-11-08, until then a Viewer with write tools off; since 2026-11-10 declared through Home Manager's `programs.claude-code.mcpServers`, which delivers it in a plugin named `hm`, so Claude Code lists it as `plugin:hm:grafana-local`): they build dashboards in Grafana to iterate on with you, `grafana-capture` puts a finished one in the repo, and the repo's own stay read-only to them; Editor rather than Admin, since its token sits where Claude Code reads it. Grafana's admin password comes from 1Password through sops (`grafana-admin-password`, one item for every host, 2026-11-08) and is reset to that value before every Grafana start, so a changed value reaches an existing database and a reset machine gets the same one back; it lives decrypted in `/run/secrets` only. Until then it was generated on the machine into `/var/lib/grafana/admin-password` and kept out of sops, since Grafana applies `admin_password` only when creating its database; the reset at start is what answers that. Test nodes, holding no sops key, still generate one. Anonymous visitors are Viewers, and `enforce_domain` refuses any host but `localhost`, which closes DNS rebinding from a browser tab |
| command bindings | in `home/max/desktop/niri.nix` with the rest, `repeat` stated on every one through helpers that encode the rule | the rule is repeat a step, never a spawn or a toggle — which overrides niri's default (`true`) on spawns and on mute. Named per binding since niri and Hyprland shared one list (`home/max/binds.nix`) and defaulted it oppositely, so every shared binding behaved differently per session until it was. Folded into `niri.nix` 2026-10-18, after Hyprland went, with `config.kdl` byte-identical |
| terminal | ghostty via `ghostty +new-window` | replaced alacritty 2026-09-18; windows come from ghostty's own D-Bus service, so they sit outside the compositor's cgroup |
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

**nixpkgs' Alloy cannot read a NixOS journal.** Its journal reader dlopens
libsystemd from `systemd-minimal-libs`, built without zstd, and NixOS compresses
its journal with zstd. The reader skips every file, reports itself healthy and
reads zero lines (`loki_source_journal_target_lines_total 0`).
`modules/base/observability` re-points the binary's RUNPATH at the full
systemd; tracked in `docs/blocked.toml`.

**preservation creates a preserved directory `root:root 0755`.** A service
with a systemd `StateDirectory` gets it chowned back at start; one without does
not. Loki failed its first boot in the VM on `mkdir /var/lib/loki/rules:
permission denied`, so persisted service directories state their owner in
`modules/metal/persistence.nix`, and the desktop suite checks they are up.

**Grafana 13 ships without its core datasources.** Prometheus, Loki and Tempo
are plugins now; without them Grafana logs `plugin prometheus not found` and tries
to download them from grafana.com at every start. `services.grafana.declarativePlugins`
with `pkgs.grafanaPlugins.{prometheus,loki,tempo}` pins them and turns the
installer off.

**Tempo 3.0 writes outside its state directory by default.** Its new
components (live store, block builder, backend scheduler) default to paths
under `/var/tempo`, which the module's sandbox does not allow. Each failed at
start with `mkdir /var/tempo: read-only file system` and took the OTLP receiver
and every query down with it (2026-10-09). `modules/base/observability`
points all of them into `/var/lib/tempo`, a list taken from the 3.0.3 source.

**Tempo's backend worker held up every stop.** Even idle, it waited out a 30 s
finish-on-shutdown timeout; caught in its retry backoff, it sat the full 90 s
until systemd killed it, and the next start lost the newest WAL block.
`backend_worker.finish_on_shutdown_timeout = "5s"` and `backoff.max_period =
"15s"` bring a stop to about 5 s; the observability suite times a restart and
fails above 20 s, and fails at 90 s with the two settings removed (2026-10-12).
One `failed to replay block … meta.json: no such file or directory` at every
start is not a loss: it is the empty head block opened at shutdown, and a WAL
block writes its `meta.json` only once it holds a trace. The suite allows that
line and no other replay failure.

**`claude -p` traces have no interaction span.** Interactive sessions root each
prompt in `claude_code.interaction`, with model requests and tool calls under
it; a `claude -p` run's trace is a bare `claude_code.llm_request` (measured
2026-10-12). Searching on the interaction span alone finds nothing from
scripted runs, which is why the dashboard's trace panel selects on
`resource.service.name="claude-code"`. Give Tempo's search API `start` and
`end`: without them, the same query returned no traces for one that was there
and was found once a window was given (2026-10-12).

**Beyla's network flows are packets, not processes.** Its socket filter sees
addresses and ports, never a PID or a hostname, and by default a flow carries
only its direction. Which process talked comes from the request metrics, and
only for processes it instruments; a CLI's traffic, Claude Code's included,
is bytes to an address. `modules/base/observability` adds addresses and
the server's port and leaves out the client's, which would make every
connection its own series. Probed in the VM, 2026-10-12.

**Grafana 13's classic API refuses a Viewer service account on top-level
dashboards.** A dashboard built in the UI without a folder grants Viewers
View, and an anonymous Viewer reads it; mcp-grafana's token gets 403,
"dashboards:read", from `/api/dashboards/uid/…` — and 200 from the newer
`/apis/dashboard.grafana.app/…` for the same dashboard. mcp-grafana 1.2.0
uses the newer one, so the agent sees such dashboards; a `curl` with the
token does not, which is how this was first misread as "the agent cannot see
them" (2026-10-08, corrected 2026-10-13). The observability suite has
mcp-grafana read a UI-built dashboard, so an update that changes APIs shows.

**nixpkgs' pam_faillock ignores `/etc/security/faillock.conf`.** linux-pam is
built with its own etc in the store, and pam_faillock reads its defaults from
there: with the file in `/etc`, the desktop suite's account locked after the
built-in three failures, counted in the tmpfs `/var/run/faillock`, not the
configured ten in `/var/lib/faillock` (2026-10-14). Every pam_faillock line
in `modules/base/login-limits.nix` names the file with `conf=`, and the
`faillock` command, which has no option for a config file, is wrapped with
`--dir`. A test asserting only "locked or not" would have passed; this one
counts.

**With a wiped root, mutable users lose every `passwd` at the next boot.**
`/etc/shadow` is on the root, so NixOS rebuilds it from the config each boot:
in `checks.metal-boots`, a password changed with `chpasswd` on the first boot
was back to the one from `initialPassword` on the second (2026-10-13). The
dev VM never showed it — its root is ext4 on a kept image, not the wiped
btrfs subvolume.

**userborn's persistent password files do not make `passwd` persistent.**
`services.userborn.passwordFilesLocation` keeps the files on a preserved
path and symlinks them into `/etc`. The ordering was fine — the bind mount of
`/var/lib/nixos` came up before userborn on both boots — but `passwd` and
`chpasswd` write a new file and rename it over `/etc/shadow`, replacing the
symlink with a plain file on the wiped root; the preserved copy never
changed, and the second boot had the old password back. It suits a system
nobody runs `passwd` on. Hence the hash from sops.

**Beyla cannot see Claude Code's API calls.** An interactive session lives
long enough for Beyla to attach, but Beyla skips its requests on purpose
(`beyla_avoided_services`, "existing OpenTelemetry instrumentation"), since
Claude Code exports its own. With `exclude_otel_instrumented_services =
false` it saw Claude Code's plaintext gRPC exports to Alloy on 127.0.0.1 and
not one request to the Anthropic API over four prompts: those are encrypted
inside the binary, where Beyla's uprobes fail to attach (20
`attaching_uprobe` errors). What it does see is the process's CPU, memory
and network bytes. Measured in the VM, 2026-10-13.

**Beyla in Alloy runs without root, but trips over a pin left by root.** With
capabilities on Alloy's dynamic user and no `CAP_SYS_ADMIN`, request metrics
arrive; it cannot create its pin directory in the root-only `/sys/fs/bpf`,
warns, and does without. But once anything running as root had pinned
`/sys/fs/bpf/otel/traces_ctx_v1` (`0600 root`) — a probe run by hand —
Alloy's Beyla failed every process with `load pinned map: permission denied`
and request metrics stopped, while flows carried on and nothing was marked
unhealthy. Removing the directory fixed it. Two more quirks of Alloy 1.17.1:
an `attributes` block must contain `kubernetes { enable = … }`, which the
reference lists as optional; `enforce_sys_caps = true` did not stop Beyla
when `CAP_PERFMON` was taken away, so the test, not that flag, guards the
capabilities; and leaving a protocol out of `metrics.instrumentations` does
not stop the kernel side from classifying packets as it — osqueryd's traffic
kept arriving as Couchbase operations until a `filters` block dropped
`db.system.name = couchbase`.

**Since Alloy 1.21 Beyla instruments itself, and discovery waits on it.** The
child runs as `/memfd:beyla (deleted)` and listens on its metrics port, so
`open_ports` picks it up and its default exclusion (`*beyla`) misses the
suffix. Attaching to its own Go binary fails over to tracefs
(`uprobe_events` is root's) after up to 3.5 minutes on a CI runner, and
servers started meanwhile go unseen until then. That made the
`observability` suite pass or fail by runner speed from 2026-10-25 to
2026-10-29, on unchanged code. An `exclude_instrument` for `/memfd:beyla*`
fixes it, and the suite checks it.

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

**A sandbox path is an input no hash covers.** `sandbox-paths` and
`extra-sandbox-paths` mount host paths into the build sandbox, and nothing
about them enters a derivation's hash, so two machines that differ only there
build the same derivation from different surroundings. The attempt above left
exactly that behind: the Ubuntu host's `/etc/nix/nix.conf` still had
`extra-sandbox-paths = /dev/dri` on 2026-11-14, eight weeks after it was shown
to be useless, so every local build could see a device no GitHub runner has.
Nothing is known to have used it. `nix run .#ci` now refuses to build on a
machine with anything but the sandbox's own `/bin/sh` in view, and
`checks.nix-sandbox` holds the machines defined here to the same.

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
*nothing* in a Wayland-only system. niri honours `XKB_DEFAULT_LAYOUT`;
Hyprland ignored it, because its own `kb_layout` defaults to `"us"`.

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

**virtiofs needs shared guest memory, and `build-vm` does not give it any.**
nixpkgs moved shared directories from 9p to virtiofs in September 2026. vhost-user
devices need the guest's RAM as a shared memory object, which only the NixOS
test driver switches on — so every test passed while `nix run .#vm` hung on a
vhost handshake. The virtiofsd warning about file handles and "Operation not
permitted" is a red herring. `modules/vm/qemu-guest.nix` set
`qemu.enableSharedMemory` by hand until nixpkgs PR #563324 made it the default
whenever virtiofs is in use (merged 2026-09-15; the workaround went
2026-10-01, after `nix run .#blocked` noticed). If a VM hangs on a vhost
handshake again, check that option first.

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

**Nothing in the VM may walk the whole store, and the garbage collector does.**
The guest's `/nix/store` is an overlay over the host's entire store, and
unprivileged virtiofsd holds one fd per file the guest has looked up, capped at
the host's hard limit (524,288; its start-up warnings about that limit and
about file handles are expected and say exactly this). The collector treats
every store entry the guest's database does not know as garbage, which is
nearly all of the host's. On 2026-11-12 the persistent Monday timer caught up
ten seconds into a boot, deleted 14,834 paths in under three minutes and died
with "Too many open files"; virtiofsd logged "No more file descriptors
available to the guest" in the same second and the session came up grey,
because nothing in the store could be opened any more. On the host, 514,698 of
the daemon's 523,682 fds were under store paths outside the VM's own closure
(`ls -l /proc/<virtiofsd>/fd`, grouped by store path, shows what was walked).
Nothing is lost: the share is read-only and the overlay's upper layer is a
tmpfs, so a reboot undoes it. `hosts/t14s/vm.nix` switches off `nix.gc` in the
VM next to `nix.optimise`, which was off already for the same reason. What
remains is `min-free` in `modules/vm/qemu-guest.nix`: a collection the daemon
starts by itself under 1 GiB free would do the same walk.

**A VM on virtiofs cannot suspend, and trying breaks its display.** The kernel
refuses to suspend a virtio-fs device ("virtio-fs: suspend/resume not yet
supported", `-EOPNOTSUPP`), so `systemctl suspend` fails for as long as the
store is shared that way. The failure is not clean: on 2026-11-12 DMS's idle
timer (`acSuspendTimeout`, 600 s) requested it, both the deep and the s2idle
attempt were refused, and virtio-gpu never completed another commit (a kworker
stuck in `drm_atomic_helper_wait_for_fences`, screenshots hung) while ssh and
every service carried on. Only restarting the VM brought the screen back. It
was the first suspend attempt in 40 recorded boots: the VM had never before
sat logged in and idle for ten minutes. `hosts/t14s/vm.nix` now disables the
sleep verbs in `systemd.sleep.settings`, so logind refuses the request before
the kernel freezes anything; the idle timer is left alone, since on metal
suspend is the point.

**The VM runner has no pre-start hook, but drive paths are shell-expanded.**
`qemu-vm.nix` creates only the root image, and its `emptyDiskImages` live in a
per-run temp directory. A persistent second disk therefore creates itself: its
`file` is a `$(…)` that makes the image on first use and prints the path,
anchored to `$OLDPWD` because the runner has already done `cd "$TMPDIR"`.
`/home` must be `neededForBoot`, because activation creates `/home/max` before
systemd mounts anything.

**niri scopes spawned programs by itself.** Under a systemd session niri puts
every `spawn` into its own transient scope (its spawning code says why), so no
`uwsm app --` or `systemd-run` is needed in the binds. Hyprland did not: it
launched binds as children of the compositor.

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
packages — so at the time the third option won: marimo lived in a
`python3.withPackages` environment, and nothing downloaded an interpreter at
all.

nix-ld came back on 2026-10-22, for the work repos and their mise toolchains,
and that environment went on 2026-11-14: a scratch notebook now runs as
`uvx marimo edit --sandbox`, on the CPython uv downloads, through nix-ld
(both in "Decisions, and why"). `UV_PYTHON` with `UV_PYTHON_DOWNLOADS=never`
remains the way for a project that wants a Nix Python under uv.

**On NixOS, mise compiles tools such as node from source by default — even
with nix-ld on.** It detects the distribution and sets `all_compile = true`,
which it has since deprecated in favour of nix-ld (the setting's own warning
says so; the default goes in mise 2027.8.0). node 24.22.0's `configure` does
not even get that far here: it fails on Python 3.14 with "too many values to
unpack" (2026-10-22). `programs.mise.globalConfig.settings.all_compile = false`
in `home/max/core/dev.nix` makes mise download the upstream build, which
nix-ld then runs. Of the work repos' tools, only node, pnpm, uv and bat are
dynamically linked; crane, flux, helm, kustomize, gh and jq are static builds
that need no loader at all.

**A tool's Nix wrapper can have a closed environment, which fails only at run
time.** The bare `marimo` package is wrapped with a fixed PYTHONPATH holding
its own runtime dependencies and nothing else, with no pip. It installs
cleanly, starts cleanly, and then a notebook's `import polars` fails, and
installing polars elsewhere in the profile does not help. Declaring the
library set alongside marimo in one `python3.withPackages` is what makes such
a global install honest. That is how marimo was installed here until
2026-11-14, when it left the profile altogether ("Decisions, and why").

**An unconfigured Twingate daemon respawns forever.** Its unit pairs
`Restart=always` with `StartLimitIntervalSec=0`, which turns off systemd's
rate limit — and before `twingate setup` has named a network the daemon exits
at once, so it restarts every 2 s indefinitely (655 journal lines in the first
few minutes). `hosts/t14s/configuration.nix` gives the limit back, so it
gives up after five tries and stays in `failed` until configured.

**Rootless Docker's socket variable never reaches the desktop.**
`virtualisation.docker.rootless.setSocketVariable` sets `DOCKER_HOST` in
`environment.extraInit`, which only shells read. Everything graphical is
started by the systemd user manager, and `tests/containers.nix` found its
environment carrying `XDG_RUNTIME_DIR` and no `DOCKER_HOST` — so an IDE's
Docker integration, and Testcontainers run from one, would have found no
daemon while `docker` in a login shell worked. A file in `/etc/environment.d`
fixes it: systemd's generator expands `${XDG_RUNTIME_DIR}` there, and the
manager then has the variable. Two smaller traps from the same test: a user
unit's PATH has no `sh`, and a published port being unreachable proves
nothing without the control that opening the firewall makes it reachable.

**A package taken from its own flake is compiled on every CI run.** Such a
flake is a build recipe, and its result is only reused where it already
exists: in the local store, or in a cache this machine trusts, which is
cache.nixos.org and so only what nixpkgs builds. A GitHub runner starts
empty. Twice that was most of CI. aoe's Rust build took runs from about 20
minutes to 54 and 59 (2026-10-02 to 10-06). bootvine's, also Rust, was a
ten-minute silent stretch and some 400 extra derivations in the log; taking
it from nixpkgs on 2026-11-14 cut the phase that builds what no cache serves
from about 29 minutes to 9. Locally the cost is smaller and still real: an
input that follows nixpkgs is rebuilt at every lock refresh. The two ways
out are the package from nixpkgs once it has one (bootvine), or upstream's
release binary, pinned by hash and patched for the store (aoe,
`home/max/core/aoe.nix`), which nixpkgs itself does for much of what is in
this closure. What is left compiling per run is the Dux shell, greeter and
their Quickshell, four to five minutes.

**DMS has a policy file for the lock settings, which is how they can be
declared without owning `settings.json`.** `dms run` reads
`/etc/dms/cli-policy.json` at every start (and `/usr/share/dms/` before it)
and hands `lock_settings` to the shell as `DMS_POLICY_LOCK_SETTINGS`; the
shell treats those keys as managed and leaves them out of what it saves. Only
a fixed list of keys is accepted, all about locking: `lockBeforeSuspend`,
`loginctlLockIntegration`, the lock timeouts, the fade and the fingerprint and
U2F switches (`core/internal/clipolicy` in dux-shell 2.1, read 2026-11-14). A
key outside the list is ignored with a warning, and a file that does not parse
manages nothing and turns every restriction switch on. `lockBeforeSuspend`
defaults to off.

**A systemd user service starts for every user manager, the greeter's
included.** nixpkgs' rootless Docker is a user unit wanted by
`default.target` and excludes only root. greetd's greeter is a system user
with a user manager of its own and no subordinate uid range, so at every boot
that shows a greeter the daemon failed three times there ("No subuid ranges
found for user 998") and stayed `failed` (seen 2026-11-14 in the desktop
suite's log; harmless, and in no test's way). `ConditionUser=!@system` in
`modules/base/containers.nix` skips it for every system user, and the desktop
suite asserts the greeter's unit is inactive with no restarts.

**Orbit ignores SIGTERM until it has enrolled.** While it retries against a
server it cannot reach, `systemctl stop orbit` sits out systemd's full 90 s
default before the SIGKILL — and so does every shutdown, which is where it
was noticed. `modules/metal/fleet.nix` cuts `TimeoutStopSec` to 5 s, and
`checks.fleet` now asserts a prompt stop.

**Orbit launches Fleet Desktop through a `sudo` it cannot find.** It starts
the tray app in the user's session with `sudo -n -i -u <user>`, and sudo is
a setuid wrapper in `/run/wrappers/bin`, which a systemd unit's PATH does
not include. The launch failed every 30 s with no error in the log — only
"running command". Session detection itself works under niri (`loginctl`
reports it as Wayland). `modules/metal/fleet.nix` adds the wrappers to the
unit's path when `maxnix.fleet.desktop` is on.

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

Eight VM suites, two static checks, builds of the metal system and of the
installer USB's, a check of how it lets people in, and a startup check. The two desktop suites — `desktop` and `niri` — boot
the whole machine from `hostModules`, so a test node cannot drift from what
`nix run .#vm` builds. The other six (`secrets`, `fleet`, `containers`,
`observability`, `metal-boots`, `metal-install`) each import only what they test, on small
nodes; the desktop suites already boot everything, and booting it again per
module would cost minutes and gigabytes to prove nothing new.

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
| desktop | 11 subtests | 13 |
| niri | 3 | 8 |
| sandboxed | yes, and cached | no — needs `/sys`, see above |

The portable tier is everything that does not look at the screen. It is not a
guess: without virgl niri (and Hyprland, while it was here) *starts* and
serves its IPC but enumerates zero outputs and draw nothing, so every screen assertion, and
everything downstream of having a surface, is gated. Verified 2026-09-21 by
running all three portable suites sandboxed (8 subtests, green) and the full
desktop suite with `+virgl` (6 subtests, green).

`test-vm-starts` is the odd one out and covers what the desktop suites
structurally cannot. They override `-display` to `egl-headless`, so the
`gtk,gl=on` path a human uses was exercised by nothing — which is how the
`-vnc` regression in `5231c9a` shipped with every suite green. QEMU validates
flag compatibility at startup, so "still alive after 8 s" suffices: `timeout`
reports that as exit 124, and any other status means QEMU bailed. It needs a
graphical session and flashes a window; that is inherent to testing
`-display gtk`.

Twelve checks sit alongside the desktop suites, all sandboxed and all in CI:
two static ones, and the metal stage — the installable systems (the ThinkPad
and the WSL host), a check of the ThinkPad's login stacks, and the suites for one module each. Subtest counts as of
2026-10-14.

| check | what it asserts | subtests |
| --- | --- | --- |
| `formatting` | every `.nix` file is nixfmt-clean; fix with `nix fmt` | — |
| `lint` | statix, deadnix, actionlint and the Renovate config validator find nothing; fix by hand, see below | — |
| `metal` | the machine as it would be *installed* builds | — |
| `z690-wsl` | the WSL host (`hosts/z690-wsl`) builds; nothing in CI can boot a WSL distribution, so its boot is checked on the desktop | — |
| `metal-boots` | that layout partitions, formats and boots | disko's own script |
| `metal-install` | `install-maxnix`, the installer USB's script: it refuses a sops key that is not the expected one, a disk that is not there and anything but `erase`; then partitions a virtual disk and puts the key on `/persist`, and the system booted from it decrypts with that key. Leaves only `nixos-install --system <the machine>`, a copy from the stick, to the day | disko's own script, plus the script's |
| `installer` | the installer USB's system builds; the image is that plus a squashfs, left to `nix build .#installer-iso` | — |
| `metal-auth` | metal's built `sudoers` asks `wheel` for a password, and each of its five password stacks has pam_faillock in place: before the first line that can let someone in, after the last password check, with its config file | — |
| `nix-sandbox` | every machine defined here builds in the sandbox and shows a build nothing of the host: `sandbox = true` and no `sandbox-paths` in the `nix.conf` each would install. The machine running the checks is asked the same by `nix run .#ci` before it builds anything | — |
| `secrets` | sops-nix decrypts a post-quantum age key at activation, root-only and in memory, and Fleet and the backup get their values from it | 4 |
| `fleet` | orbit starts with its secret, tries the configured server, keeps retrying without crashing, and stops promptly | 4 |
| `containers` | rootless Docker is max's, runs a Docker Hub image under compose with its storage on `/home`, and a published port stays behind the firewall until opened | 7 |
| `observability` | metrics, logs, events and traces reach their stores; Grafana, its datasources, dashboards and mcp-grafana work; data survives a restart; nothing listens beyond loopback but the Beyla child's metrics port (Alloy 1.21), which the firewall keeps in | 19 |

`ci` builds the static checks, then the metal stage, then the portable desktop
suites, each stage one `nix build`. The metal stage runs its suites in
parallel, the desktop stage one at a time: a guest keeps every page it
touches, so what bounds it is its memory ceiling, and two 8 GiB desktop
guests would take all of a 16 GB runner. The metal stage's ceilings
add up to 17 GiB, its measured peaks to about 9.4 (2026-10-12, before
`metal-install`); the numbers are in the comment above the flag in
`flake.nix`.

Every `runNixOSTest` suite goes through `runSuite` in `flake.nix`, which adds
`tests/waits.nix`. That file times each driver wait (and the screen poll in
`tests/vnc.nix`) and prints a line per wait. It appends each one to
`waits.jsonl` in the output and, when the driver exits (failed runs too),
prints a summary sorted by the share of its limit each wait used. A wait over
half its limit is marked `TIGHT`. It also multiplies every explicit `timeout=`
by one factor: 2 for the sandboxed tier GitHub builds, 1 for the GPU tier,
which reads `MAXNIX_TIMEOUT_SCALE` instead. Waits left at the driver's
15-minute default are not scaled. Added 2026-11-03, after timeouts that
passed here failed on slower runners. The 2 is a guess until the summaries
show the margins. The two disko suites build their scripts in
`makeDiskoTest` and are not covered; they only wait at defaults. Rewind VM
(rewindvm.dev), whose virtual clock would make guest timeouts independent of
host speed, was looked at the same day and does not fit. It runs one command
on one vCPU under its own init, with no devices and no nested KVM, and the
limits here are on the host side, in the test driver.

`metal` is the one check nothing else can stand in for. `packages.vm` builds
the vmVariant's toplevel and the desktop suites build a third variant again —
all of them get their disks and bootloader from `qemu-vm.nix`, so none of them
touches the metal path. Demonstrated by deleting
`boot.loader.systemd-boot.enable`: `checks.metal` fails, `nix build .#vm`
still succeeds. It catches a build, not a boot; whether the layout in
`disk.nix` would actually partition and come up is `metal-boots`.

`metal-boots` is disko's `makeDiskoTest`: it formats a blank virtual disk from
`modules/metal/disk-layout.nix`, installs NixOS onto it and reboots into the
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
  installer *script*, not the Nix it fetches at run time. Both are written
  once, in `.github/actions/install-nix/action.yml`, a local action the three
  workflows that install Nix share. Renovate keeps the version on upstream's
  latest release (github-tags of NixOS/nix, read out of the URL by a regex
  manager) in the weekly "Update CI" PR. Until 2026-11-14 each workflow named
  the version by hand, to match the developing machine's Nix, and nothing
  moved it: it sat on 2.34.8 a month past the security fixes in 2.34.9.
- **Freeing disk is required, not an optimisation.** The guest closure is
  12.5 GiB and a runner has roughly 14 GB free.

`renovate.jsonc` keeps the two pinned things moving: `flake.lock` and
the workflow's action SHAs. Three of its five settings exist only to defeat a
default that silently does nothing — the nix manager is beta and ships
disabled, `lockFileMaintenance` is off and `config:recommended` does not turn
it on, and either omission makes Renovate run happily while never touching
`flake.lock`. `helpers:pinGitHubActionDigests` maintains the SHA pins and
pins any action added later, so the policy is enforced rather than
remembered. Every PR automerges once all its checks are green (since
2026-11-10): `renovate.yml` also runs when CI finishes on a Renovate PR, and
that run merges it. This is a known gap, not an oversight: a green
`checks / portable` says the machine builds, boots and has its software, and
says nothing about what is on screen, so an update that breaks the greeter is
merged and found by the render suites on main. Renovate is a GitHub App and
has to be installed on the repo by hand; until it is, that file does nothing.

Its updates come as three PRs, grouped by how each is checked. "Lock file
maintenance" is never grouped with other updates (Renovate's documentation,
2026-10-16), and the config keeps it apart on purpose anyway. "Update
dependencies" holds every version bump of something the machine is built
from. "Update CI" holds everything pinned in a workflow file (action SHAs,
Renovate's own image) and comes on Mondays only, because Renovate alone
releases several times a day and nothing in the pipeline needs to be that
current. The version-bump PRs list their versions; the lock PR says only "All locks refreshed", because inputs that
follow a branch have no version, and no setting changes that. So
`.github/workflows/closure-diff.yml` comments on that PR with what it means
for the machine: `nix run .#closure-diff -- <base>` builds metal at the base
and at the PR and posts their `nvd diff`. Other Nix repos with Renovate do
the same, or list the moved inputs instead, which trades hashes for commit
dates without saying which packages change.

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
  named after the attribute. The Hyprland checks, while they existed, were
  broken by a misspelled dispatcher, an unknown keysym, an unknown option
  field and a renderer that dropped `repeating`.
- **Break the renderer, not the input.** Learned on Hyprland's bind
  assertion: flipping `repeat` in the shared bind list proved nothing, because
  the expectation was generated from that same list, so both sides moved
  together and the test stayed green. That is correct — the list is the
  source of truth — but it means the only fault that can demonstrate such a
  check is one in the code between the list and the compositor.

---

## Iterating on design

Everything else here builds config into the store and symlinks it into `$HOME`,
which is the right trade for a machine and the wrong one for choosing a colour:
the store is read-only, so every change costs a `rebuild`. ~30 s is fine for
Nix config and is not a loop for a 2px nudge. Two escapes, and they work in
opposite directions because the two problems are not the same.

**QML we write** — `home/max/quickshell/`, run with `qs-dev`:

```
qs-dev            # edit shell.qml, save, it reloads
```

Quickshell reloads the files it loaded when they change (`watchFiles` defaults
to true; `quickshell-core.qmltypes` carries the matching `onReload` and
`ReloadPopup`). Aimed at a store path that machinery is inert, because store
files never change — so the work is not building a loop but not preventing one.
`qs-dev` passes `--path` at the clone directly, so it is live regardless of how
the declared config was wired.

`maxnix.dev.liveConfig` (`modules/base/dev.nix`) does the same for the
*declared* config: on, `programs.quickshell.configs.maxnix` becomes an
out-of-store symlink to the clone, so `~/.config/quickshell/maxnix` is the
working tree and any launcher — including a future systemd service — is live.
Off, it is the directory copied into the store like everything else. It is off
by default and on only in `virtualisation.vmVariant`, because it makes the
running system depend on a mutable path: on a fresh install, before the clone
exists, the symlink would dangle.

Nothing starts `shell.qml` on its own — `programs.quickshell.systemd.enable` is
false and `activeConfig` is null — so the scratchpad cannot fight DMS for the
screen. DMS is still the shell.

**DMS theming** — already live, and the trap is the obvious fix. Its Home
Manager module generates `~/.config/dms/settings.json` only when
`programs.dank-material-shell.settings` is non-empty, and `home/max/desktop/dms.nix`
deliberately leaves it unset. That is *why* theming needs no rebuild: the file
is plain mutable state DMS owns. Declaring it from the repo would move it into
the store and take away the settings UI's ability to write it — trading the
fast loop for the version control, when the point is to have both.

So theming is captured rather than declared:

```
dms-capture       # ~/.config/dms -> home/max/dms-state, then git status
dms-restore       # the other way, after a root reset; restarts dms if it is up
```

`settings.json`, `clsettings.json`, `plugin_settings.json` and `themes/` are
copied; `plugins/` is not, because that is third-party code DMS installs rather
than configuration. `themes/` is replaced wholesale, so deleting a theme in the
UI is captured too. With `enableDynamicTheming` the palette is generated from
the wallpaper by matugen, so what is worth keeping is the choices, not the
generated colours.

**What this costs.** Nothing checks the live content: the suites build
`hostModules` and never the VM variant, so they keep testing the store copy,
which is also what metal gets. Nothing validates the QML either — there is no
equivalent of `niri validate`, because
Quickshell needs a Wayland session to load a config at all, so a syntax error
surfaces when you run it. Until a design is promoted back into the store,
"it is in git" and "it is what the machine will boot with" are two different
claims.

---

## Open points

**Tempo still hangs on an occasional stop.** With the backend worker fixed it
stops in about 5 s, but in roughly one stop in seven (VM shutdowns and test
restarts, 2026-10-12) something after the worker kept it alive until systemd's
kill, and it did not reproduce on demand. `TimeoutStopSec = 20s` caps it:
within 100 ms of a stop Tempo has cut everything it holds to its WAL, so the
kill costs nothing but the wait. Catching the cause needs Tempo's info log
running across ordinary shutdowns until the next one.

**Loki sometimes takes 9–27 s to stop, but only right after it started.**
Across every stop in the VM's journal (2026-10-13): within about the first
1.5 minutes of uptime, 8 of 21 stops took 9–27 s; later, 0 of 8 did, an hour's
uptime included; all the others took 0.5–0.9 s. It did not reproduce on demand
— repeated stops inside the same window were fast. In the one slow stop
caught at info level, Loki had left its ring and kept answering Alloy's pushes
(500, "empty ring") for seconds before exiting, so a module is still busy, not
the HTTP server holding on at the end. Ruled out: a fixed wait, its tracing
exporter (a no-op without OTEL environment variables), a process lingering
after it exits. Every slow stop is from the VM, booted and shut down within
minutes; on a machine up for hours it has always stopped in under a second,
and 27 s is well inside systemd's 90 s. Left alone on purpose: a shorter
TimeoutStopSec would kill it without knowing what it is doing. Finding the
module means catching a slow stop with `-log.level=debug`, restarting Loki in
a loop until one comes; time a stop by the journal's `Stopping`/`Stopped`
lines, not by how long `systemctl stop` takes to return — the latter once
read 9 s for a stop the journal put at 0.55 s.

**Backups are wired, authorised and on for metal; they run there from its
first boot with its key.** `modules/metal/backup.nix` has the
mechanism: restic, nightly, `/persist` and `/home`, caches and Steam excluded,
7/5/12/3 retention, and `checks.metal-boots` runs a real backup into a local
repository and inspects what landed in it. The destination is constrained:
this is a company machine and Google Drive is the only one the employer
permits (learned 2026-09-23), so the repository is `rclone:gdrive:maxnix-backup`.

The Google side is done (2026-10-02): a Cloud project `maxstreese-laptop-backup`
in the company Workspace, an Internal OAuth client of type Desktop with the
`drive.file` scope, and a token for it. Four values make it work, each kept in
1Password and, for the machine, in sops: the client id, secret and token,
rendered into an `rclone.conf` by a template in `hosts/t14s/secrets.nix`,
and the **repository password**, the client-side encryption key. Lose that one
and the backups are permanently unreadable, which is why it must not live
*only* on `/persist`.

On the machine, `backup-now` runs the nightly backup by hand and follows its
log, and `sudo restic-maxnix …` is restic with the unit's settings, for
snapshots, restores and `mount`. `nix run .#backup -- <command>` runs rclone or restic against the Drive with
those values from 1Password, from any machine with `op` signed in — the restore
path for the day this disk is gone along with its sops key. `nix run .#backup
-- authorize` issues a new token if the grant is ever revoked.

The VM backs up into a folder of its own, `maxnix-backup-vm`, so the whole path
is exercised before install day without its snapshots sharing retention with
metal's under the same hostname. Metal has `maxnix.backup.enable = true` since
2026-10-15 (`hosts/t14s/configuration.nix`); the first backup runs once its
key is on `/persist`.

Three questions for the employer went with it, treated as settled outside this
repo (2026-10-14), so they are recorded here as the questions only. restic
encrypts client-side, so IT cannot read these backups — that may be the
requirement or may violate one. `/home` sweeps in 1Password's local state, the
browser profile and SSH keys, encrypted but held on company infrastructure.
And the Drive quota: the organisation pools 190 TiB with no per-user cap set,
so ~1 TB fits, but whether it may be used is theirs to say.

**The Fleet agent is on, for the VM and for metal.** The employer is adopting
Fleet (learned 2026-09-29), and `modules/metal/fleet.nix` has the agent side:
nixpkgs' `services.orbit`, which is Orbit supervising its own osquery, behind
`maxnix.fleet`. `/var/lib/orbit` is preserved so the enrollment survives the
root wipe. `checks.fleet` boots it against a server that is not there and
shows that it starts, reads its secret and retries in-process without
crashing. The VM is enrolled with IT's server since 2026-09-29; metal is on
since 2026-10-15 (`hosts/t14s/configuration.nix`) and enrolls on its first
boot with its key, as a host of its own in IT's console.

What it took, neither of it code:

- **A URL and an enroll secret from IT** — now in hand. Both go in through
  sops-nix, the URL too: the repo is public, and where the company's Fleet
  server lives is not this repo's to publish. Orbit reads the URL from
  `ORBIT_FLEET_URL`, so a sops template renders it into an env file that
  overrides the unit's own placeholder (`https://fleet.invalid`, which never
  resolves). `checks.secrets` runs that whole chain with a throwaway key. It
  is secret at rest only: osqueryd's command line carries the hostname.
- **Five questions for the employer.** Fleet's built-in disk-encryption and
  firewall checks name Debian/Ubuntu, CentOS/Fedora and Arch, not NixOS, so a
  LUKS root and the NixOS firewall may report as missing — will IT accept
  that, or write custom checks? Is Fleet Desktop wanted (`maxnix.fleet.
  desktop`, untested under niri)? Should IT be able to run
  scripts here (`enableScripts`, off)? Do they rely on Enterprise-edition or
  MDM features, which Fleet supports only partly on Linux? And do they enforce
  a minimum agent version? The module turns off Orbit's self-update, so the
  agent is whatever the pinned nixpkgs carries and moves with `flake.lock`.

Those five were treated as settled with IT outside this repo (2026-10-14);
Fleet Desktop is on, as it is in the VM.

**The everyday terminal tools from the current host are here; the rest is
not yet.** `docs/inventory.md` records what the Ubuntu host has installed and
what its shell history shows is actually used, and marks with ✓ what came
over on 2026-10-01: the CLI tools, atuin and starship, DBeaver, and Harlequin
in place of per-database clients. Decided besides: sdkman gives way to
per-project flakes, mise stays for the work repos that pin tools with it, and
three host services stay behind. Still open: how to carry the Neovim config
over, the shell aliases and functions, a few tools proposed but not added, and
the rows marked "?".

**Bind reachability is only partly checked.** The dead German binds were found
by a hand-run audit, not by anything in the repo. niri rejects a bad keysym at
*build* time — its module runs `niri validate` while building `config.kdl` —
verified by injecting one into `home/max/desktop/niri.nix`.

One gap survives that, and nothing here closes it: nothing compares a keysym
against the *compiled keymap*, which is the check that would have caught
`Mod+BracketLeft` being unreachable on a German layout. A valid keysym that
sits on a shifted or AltGr level parses, shows in the hotkey overlay, and
never fires. It needs `xkbcli compile-keymap --layout de` or a human pressing
the key.

**The secrets layer is in use, on the VM and in tests; metal waits for install day.** Three post-quantum
age keys are recipients in `.sops.yaml`: `admin`, for a person editing, and
one each for the VM and metal. All three private halves are kept in
1Password, and the machine keys are *restored* onto disk rather than
generated there — the VM's onto its `/home` disk, metal's onto `/persist` at
install — so a wipe or reinstall never changes `.sops.yaml`. The commands are
in `hosts/t14s/secrets.nix`. The values are in two files:
`hosts/t14s/secrets.yaml`, which all three keys open, for what both
machines use, and `hosts/t14s/secrets-metal.yaml`, which only admin and
metal open, for what the VM must not read — the login password and metal's
restic password (split 2026-10-15; until then the VM's key, in a disk image
on the Ubuntu host, opened both). `checks.secrets` shows sops-nix decrypting a
post-quantum key at activation, from both files: the sops CLI handling one
says nothing about sops-nix, which decrypts with its own, older build.

Four consumers use it. The **login password**, as a yescrypt hash for
`max` and root on metal, decrypted ahead of the users (`neededForUsers`). The **Fleet enroll secret**, now in hand and
gated on the questions for IT above. The **restic repository password**, one
per machine (`restic-password` for the VM, `restic-password-metal`), which
must not live only on `/persist` since one disk failure would take the data
and the only key to its backups together. And the **rclone OAuth client and token** for
Google Drive, rendered into an `rclone.conf` template — shared, since
`drive.file` gives the one client every folder it made either way; what keeps
metal's snapshots from the VM is the restic password that encrypts them.

`nix run .#secret-set -- <name> <op-reference>` puts one value from 1Password
into whichever of the two files the machine reads it from (with `--host
z690-wsl` first, into the WSL host's own `hosts/z690-wsl/secrets.yaml`): only names the machine declares, nothing written if
1Password returns nothing, login passwords hashed with yescrypt on the way,
and read back to check.

`nix run .#vm-restore-key` puts the VM's key back from 1Password and checks
it against `.sops.yaml`; `nix run .#z690-wsl-restore-key` does the same for
the WSL host's key, from inside that guest. The dev shell sets `SOPS_AGE_KEY_CMD` to the admin item, so `sops` in
`nix develop` — or under direnv — fetches it from 1Password on its own.
The LUKS passphrase can never be a sops secret, because the machine key sits
on the disk that passphrase unlocks.

**The generation diff has never been seen.** Both rebuild paths call `nvd
diff` before activating, and `nvd` itself was verified against two real
toplevels — but neither path has been watched actually printing it, because
that needs a running VM and a real activation. The wiring is two lines
guarded with `|| true`, so the risk is low; it is inference rather than
observation.

**Colour thresholds are magic numbers** calibrated against today's screenshots.

**The greeter sometimes never draws in the desktop test.** Roughly one run in
five, the screen stays a single colour for the full 120 s while every other
subtest passes; an immediate rerun passes. Neither failure's log was kept, so
the cause is unknown. The test now dumps greetd's and the greeter compositor's
journal on that failure.

**Calendar accounts are added by hand, once per machine.** They are runtime
state — OAuth tokens in the keyring, data under `~/.local/share` — so the
configuration cannot declare them (`home/max/desktop/dms.nix`). Each needs a Desktop
OAuth client in Google Cloud with the Calendar API (and, for tasks, the Tasks
API) enabled; `dcal account setup google` prints the steps:

- company: in the existing Workspace project, audience Internal — no test
  users or verification needed;
- personal: a project in the personal account, audience External, the
  account itself as test user.

Keep each client's id and secret in 1Password. Then, in a graphical session,
`dcal account add google --client-id <id> --client-secret <secret>` per
account, which opens the browser for consent. Passing the secret as an
argument is acceptable: Google's guide for installed applications calls such
a client's secret not a secret, since it ships inside apps — though it also
says to keep it out of public repositories, hence 1Password, not this repo
(older versions of that guide, 2013–2020; the current wording was not
found).

For the personal account, publish the app ("In production") before adding
it. Google's OAuth documentation, checked 2026-10-15: an External app in
"Testing" gets refresh tokens that expire after seven days unless it asks
only for name, email and profile — Calendar is more — so it would have to be
added again every week. Moving to production does not by itself require
verification; an unverified app requesting sensitive scopes shows an
"unverified app" screen before consent and is capped at 100 new users,
neither of which matters for one person. Whether that screen can still be
clicked through was not stated there; expect "Advanced → Go to …". The
company client, Internal, is not affected.

**Write our own Quickshell config** — the last piece of the original plan, and
the reason Quickshell was on the list. Point
`programs.quickshell.configs.<name>` at a *string* path inside the guest's
clone for live editing, then fold it into the store once the design settles.

**The greeter does not visibly track the DMS palette yet.** `configHome` is
wired and the copy is verified byte-identical, but repainting `colors.json`
changed nothing on screen. Upstream documents `settings.json` as the file
carrying appearance; DMS has not written one here yet.

`nix run .#install -- root@<target>` is the other way in, kept for a
reinstall from a second machine: nixos-anywhere kexecs the target into an
installer over SSH, runs disko against `modules/metal/disk-layout.nix`,
installs and reboots — the same sequence `checks.metal-boots` rehearses
against a virtual disk. It is not the ThinkPad's path (there is no second
machine, below), and what it needs first — the LUKS passphrase for the
formatting step, the sops key through `--extra-files` — is noted at the app
in `flake.nix`.

There is deliberately no `install-vm-test` app. `--vm-test` is redundant with
`checks.metal-boots`, and on a LUKS layout it fails upstream before starting:
its harness injects `export password=disko` into the generated disko script
and disko's own shellcheck rejects it (SC2030/SC2031).

**Road to metal: install day, in order.** Onto the ThinkPad T14s Gen 2a this
repo was developed on, from a USB stick it builds itself (decided 2026-10-15:
there is no second machine with Nix for `nix run .#install`). Everything the
config did *because it was only a VM* is done — sudo, disk layout, hardware
report, secrets, networking, the laptop services, DMS's features — and no
`ROAD TO METAL` marker is left in the code.

Before the day:

1. In 1Password: the **LUKS passphrase** is the login password, from its
   own item (decided 2026-10-15: one password at power-on, lock screen and
   sudo; nothing technical needs the two to match or to differ), the
   **metal sops key** (kept there since it was made),
   the **login password**, the **metal restic password**, and the
   account's email and Secret Key, for signing the CLI in on the stick. The
   login password and the restic password are in
   `hosts/t14s/secrets-metal.yaml`. The login password kept its value
   through the split (decided 2026-10-15): its earlier hash stays in git
   history, readable with the VM's key, but a yescrypt hash of a long
   random password is not worth attacking offline.
2. Back up whatever on Ubuntu is in no other place: the install erases the
   whole disk.
3. Rehearse steps 5–9 in `nix run .#installer-vm` (window; `--no-stick
   --offline` for step 9 — online, a system installed with metal's key is
   metal to Fleet and to the backup; `--fresh` for a new disk), and delete
   `.vm/installer-disk.qcow2` afterwards, as it holds metal's key. Then
   build and write the stick from the same commit:
   `nix build .#installer-iso`, then
   `sudo dd if=result/iso/*.iso of=/dev/<stick> bs=4M status=progress oflag=sync`.
   The image carries the machine, built (below), so the stick is that
   commit's machine: build it last, after the final change to the lock or
   the config.
4. In the firmware (F1 at power-on): turn **Secure Boot off** — expected to
   be needed, since the stick is not signed for the factory keys; check on
   the day — and set Config → Power → Sleep State to "Linux".

On the day:

5. Boot the stick (F12 at power-on for the boot menu).
6. Wi-Fi: `nmtui`.
7. `sudo -i` first, then 1Password's CLI: `op account add`, then
   `eval $(op signin)`. In that order because install-maxnix runs as root
   and `op` keeps its sign-in per user and shell: signed in as `nixos`,
   root's `op` would not see it.
8. `install-maxnix --luks op://uxobupcysqhat566ymgikx46fm/z26gdcpznhbgxktpdsffrgh5lu/password --sops-key op://uxobupcysqhat566ymgikx46fm/qvls72inmhuw3op62wyhhudayy/notesPlain`.
   It checks UEFI and the disk, shows the disk's size and model, reads both
   secrets, refuses a sops key that is not `metal` in `.sops.yaml`, asks you
   to type `erase`, partitions, puts the key on `/persist` and runs
   `nixos-install --system` on the machine the stick carries, which copies
   it to the disk and fetches nothing. `checks.metal-install` runs all of that but the last
   step against a virtual disk.
9. Reboot, take the stick out, type the LUKS passphrase: the niri session
   starts by itself. The login password is for the lock screen and sudo.

After:

10. Secure Boot with the machine's own keys and Microsoft's beside them
    (`sbctl enroll-keys --microsoft`), in the order `modules/metal/disk.nix`
    gives. No TPM unlock (decided 2026-10-15; see "Decisions, and why").
11. The first app that asks for a keyring ("Choose password for new
    keyring"): leave both fields **empty**, then "Store passwords
    unencrypted?" → Continue. Autologin cannot unlock a keyring that has a
    password; this one opens by itself at first use after every boot (tried
    in the VM). Then
    `twingate setup`; the 1Password app; the calendar accounts (see
    "Calendar accounts are added by hand"); Fleet enrolls and the backup
    runs by themselves — check both.
12. What only the hardware shows: brightness (`acpi_backlight=native` if it
    does not work), suspend, that a closed lid comes back to the lock screen
    and not to the session, that locking the screen locks a signed-in
    1Password, `powerprofilesctl`, `fwupdmgr get-updates`,
    and whether hibernation is worth adding (see the swap decision). Also
    the weekly firmware check (`hosts/t14s/laptop.nix`), which the VM can
    only run against stand-ins: `systemctl --user start firmware-check`
    should end in a notification that stays, or in "no firmware updates" in
    `journalctl --user -u firmware-check`.

**The install path has run end to end, in the VM (2026-10-16).**
`nix run .#installer-vm` boots the real installer image as a USB stick under
UEFI, with an empty NVMe disk at the ThinkPad's by-path. Steps 5–9 ran there
by hand with the real secrets: `op account add` on the stick — a device
1Password had not seen — asked, after Secret Key and password, for a
six-digit code from the authenticator app rather than the YubiKey (the CLI
does not do security keys), and signed in; `install-maxnix` read the LUKS
passphrase and metal's key from 1Password, partitioned, and `nixos-install`
built the machine; booted with `--no-stick --offline`, the passphrase led
straight into niri with DMS, and lock screen, sudo and the empty-password
keyring behaved as intended. Before that, with throwaway secrets, the stick's
copy of this repo evaluated the machine to the same store path as the host.
What a VM cannot show is left to the hardware (steps 4, 12). Two things the
run taught: `sudo -i` has to come before `op` signs in (step 7), and the
VM needs a GL GPU, as niri draws nothing without one.

**The stick carries the machine, and the install needs no upstream
(2026-11-12).** Until then `install-maxnix` ended in `nixos-install --flake`,
which on the day would have fetched the flake's inputs from GitHub and
Codeberg, 1913 of the closure's 2168 store paths from cache.nixos.org, and
the other 255 (4.5 GiB: Chrome, Slack, Spotify, Discord, 1Password, Claude
Code, wootility, Twingate, Steam, Fleet, and what is built here) from their
vendors or by building — each path checked against the cache that day. All
of it after the disk is erased, on the only machine. Now the installer's
script names the built toplevel, so the image's store holds its closure
(22.6 GiB unpacked) and the last step is `nixos-install --system`, a copy.
The image is 9.4 GB and builds in 5 minutes with zstd at level 6; at
nixpkgs' level 19 the squashfs was still compressing after 25 minutes and
was cancelled. Tried in `installer-vm --offline`, where the guest has no
interface but `lo`, with a throwaway passphrase and key (`--luks-file`,
`--sops-key-file`, `--recipient`): partitioned and installed in about seven
minutes from an image file on the host's NVMe — a real stick will be slower
— and the disk then booted through bootvine's passphrase prompt into niri
with DMS. sops could not decrypt with the throwaway key, as it should not.
1Password's servers are the one upstream still needed on the day, for the
two secrets. What changed with it: the stick installs the commit it was
built from, not whatever the repo is by then.

No decision is left open before the day. The last, Secure Boot's keys, was
made 2026-10-16: Microsoft's stay beside the machine's. Removing them would
stop a Microsoft-signed system, such as one faking the LUKS prompt, from
booting in someone else's hands — but at the risk of hardware whose option
ROMs Microsoft signed, and of rescue sticks that boot only with Secure Boot
off; the attack needs physical access twice and was judged not worth that.

**Media and brightness keys** are GNOME keybindings like any other, so they
should follow the grab now. Not yet verified with a keypress.

**A second machine: the Windows desktop.** A Z690 board with an i9-12900KF
(no iGPU) and an RTX 3080 Ti, today on Windows with WSL2. Open since
2026-10-18: whether maxnix runs there as NixOS-WSL and on the metal, the
split into roles both would need (done for the system side, see "Decisions,
and why"), and whether
NixOS on that metal is the right goal for game development and games at all.
Evidence and options in `docs/desktop-pc.md`.
