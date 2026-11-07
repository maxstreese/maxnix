# A second machine: the Windows desktop

There is a second machine besides the ThinkPad: a desktop PC that runs
Windows today, with WSL2 (Ubuntu) on it. Two questions, looked at
2026-10-18 from a first session in that WSL: can maxnix run (1) under WSL, as
NixOS-WSL, and (2) on the desktop's metal? A third came out of the second:
for game development and playing games, is NixOS on that metal the right goal
at all? Nothing here is decided; what gets decided moves into README's
"Decisions, and why" and is marked here, as `inventory.md` does.

The repo is public, so this records the hardware by model only. Firmware
versions, device instance IDs, MAC-derived identifiers and whatever else
Windows reported about the individual machine stayed out, as serials stay out
of `hosts/t14s/facter.json`.

## 1. The hardware, and how it was read

| | |
|---|---|
| board | ASUS ROG Maximus Z690 Hero, UEFI (AMI) |
| CPU | Intel Core i9-12900KF, 16 cores / 24 threads — the KF has **no integrated GPU** |
| GPU | NVIDIA GeForce RTX 3080 Ti, the only one |
| memory | 64 GB |
| disks | three WD NVMe SSDs: 1 TB, 2 TB, 2 TB |
| network | Intel I225-V (2.5 GbE), Intel Wi-Fi 6E AX211, Bluetooth |
| audio | Realtek USB audio (the board's), NVIDIA HDMI audio, USB headsets |

Read from Windows, not by `nixos-facter`: WSL's interop runs
`powershell.exe` from inside the guest, and Windows' CIM classes
(`Win32_ComputerSystem`, `Win32_BaseBoard`, `Win32_Processor`,
`Win32_VideoController`, `Get-PhysicalDisk`, `Win32_NetworkAdapter`) answer
without admin rights.

Facter run inside WSL would describe the wrong machine. WSL2 is a Hyper-V
guest: its PCI bus holds a Microsoft paravirtual GPU (vendor `0x1414`, behind
`/dev/dxg`) and virtio devices (`0x1af4`), nothing else. A report of the
metal needs Linux booted on the metal (section 4).

Not known yet: whether Secure Boot is on (`Confirm-SecureBootUEFI` needs an
elevated shell), which NVMe Windows lives on, and whether it is
BitLocker-encrypted. All three matter before a disk is given to disko.

## 2. What WSL offers

Measured 2026-10-18: kernel 6.18 (`microsoft-standard-WSL2`), systemd as PID 1
(`[boot] systemd=true`), 24 CPUs and 31 GB of the 64 handed to the guest, 954 GB
free on its root, WSLg (a Wayland/X compositor that draws into Windows
windows), and a render node `/dev/dri/renderD128` backed by Mesa's d3d12
driver on DirectX.

`/dev/kvm` exists and the CPU's `vmx` flag is visible: nested virtualisation
is on. So the repo's own VM loop should work here much as on the Ubuntu
laptop — `nix run .#vm` through WSLg, `.#vm-headless`, the portable `checks`
— once Nix is installed and `/dev/kvm` is opened to `0666` as README's host
row asks. The GPU tier is doubtful: QEMU's virgl on Mesa on d3d12 on DirectX
is a long chain, and nothing here has tried it. Not run yet: there is no Nix
in that WSL, and installing it needs sudo in the user's own terminal.

## 3. maxnix as NixOS-WSL

[NixOS-WSL](https://github.com/nix-community/NixOS-WSL) is a NixOS module
plus a tarball builder: the result is imported with `wsl --import` and boots
as a WSL distribution with systemd. It does not run a bootloader, a disk
layout, a display manager or a session compositor — Windows does those jobs.

maxnix cannot be pointed at it today, and not because of WSL: the repo has
one definition of "the machine" and nothing finer to choose from.

- `hostModules` in `flake.nix` is a flat list — disko, lanzaboote,
  preservation, `laptop.nix`, `modules/desktop`, the greeter — taken whole.
- `hosts/t14s/configuration.nix` mixed (until the split, 2026-10-18) what is true of the user everywhere
  (user `max`, timezone, keymap, Nix settings, gc and optimise), what is true
  of the ThinkPad (the facter report, `hardware.graphics`, zram, wooting) and
  what is policy for that machine (NetworkManager, Twingate, Fleet, backups).
- `home/max/default.nix` imported (until the split, 2026-10-18) DMS, Quickshell, niri, Ghostty and Firefox
  next to shell, git, ssh, dev and harlequin.

The proposal is roles that hosts compose:

```
modules/
  base/       user, locale and keymap, Nix settings, sops, shell and dev,
              containers, observability
  desktop/    as today: niri, greeter, 1Password, Steam
  metal/      disko + LUKS/btrfs, lanzaboote, preservation, facter, backup, Fleet
hosts/
  t14s/       base + desktop + metal + laptop.nix + facter.json (the ThinkPad)
  z690-wsl/   base + NixOS-WSL (wsl.enable, wsl.defaultUser, wsl.useWindowsDriver)
  z690/       base + desktop + metal + an NVIDIA/gaming role (section 5)
home/max/
  core/       shell, git, ssh, dev, harlequin
  desktop/    DMS, Quickshell, niri, Ghostty, Firefox, apps, binds
```

In the flake: a small `mkHost`, `nixosConfigurations.z690-wsl`, its
`tarballBuilder` as a package, and a `checks.z690-wsl` that builds the toplevel —
there is no booting a WSL distribution in a NixOS test, so a build is the
honest tier. The desktop suites must go on importing exactly the ThinkPad's
set of modules, or "the tests cannot drift from the real machine" stops
being true. The same split is what a desktop host needs, so it is not
WSL-only work.

What WSL changes, to work through rather than assume:

- **sops**: the guest needs its own age key, placed by hand once, and a
  recipient in `.sops.yaml` — as metal's is.
- **1Password** (decided 2026-11-06): the Linux app runs in the guest, from
  the same modules as on the ThinkPad, now in a `gui` role the desktop role
  imports and `z690-wsl` names; WSLg draws its window, and a user service
  starts it in the background so the agent socket and `op` exist from the
  first shell. Considered first and dropped: bridging to the Windows app
  (its SSH agent through `npiperelay` on the named pipe or Windows'
  `ssh.exe`, the CLI as `op.exe` through interop). That rests on a CLI and
  settings installed by hand on Windows that nothing in the repo describes,
  which is the kind of dependency maxnix exists to avoid. The price: a
  second sign-in, and unlocking with the account password, since the guest
  runs no polkit agent for system authentication. Untested until run in the
  guest.
- **What the guest may take from Windows** (decided 2026-11-07, README
  "Decisions, and why"): self-contained by default, and always for
  credentials and dev tooling; interfaces Windows or WSL itself guarantees
  are allowed, each declared in `hosts/z690-wsl/windows.nix`. So far: WSLg,
  the GPU driver, and links opened in the default Windows browser through
  `rundll32.exe` (as `BROWSER` and as xdg-open's http(s) handler; both
  work in the guest). The
  first boot is what raised it: `gh auth login` found no browser, and an
  SSH clone had no key before 1Password's agent exists, so the first clone
  is over HTTPS. Interop stays on for now; switching it off is a separate
  security decision.
- **Rootless Docker**: should work with systemd on; untested.
- **Observability**: Prometheus, Loki, Tempo and Grafana are ordinary
  services. Beyla needs eBPF and BTF from the WSL kernel; whether it gets
  them is unknown.
- **What does not apply**: disk, LUKS, impermanence, Secure Boot, greeter,
  backups of `/` (the distribution is one VHDX file on Windows), Fleet.
- **Memory and cores**: WSL gives the guest half the host's RAM by default
  (the 31 of 64 GB in section 2). The motive for using this machine at all is
  the laptop running short of memory, so `%UserProfile%\.wslconfig` on
  Windows should raise it (`[wsl2]` `memory=`, `processors=`, `swap=`) and
  set `[experimental]` `autoMemoryReclaim=gradual`, so the VM hands page cache
  back to Windows rather than keep it. That file is Windows' own and not in
  this repo. Repos belong on the guest's own filesystem: `/mnt/c` goes through
  9P and is much slower.
- **GPU compute**: paravirtualised, not passed through. The Windows NVIDIA
  driver exposes the card as `/dev/dxg` and puts its user-space libraries
  (`libcuda`, `libd3d12`, `nvidia-smi`) under `/usr/lib/wsl/lib`. No Linux
  NVIDIA driver is involved. `wsl.useWindowsDriver` (set in
  `hosts/z690-wsl`, 2026-11-03) links those into `/run/opengl-driver/lib`.
  The use in mind is TornadoVM for Java (finance work), and its backend
  matters: PTX goes through the CUDA driver API, which WSL supports. OpenCL
  on NVIDIA under WSL has historically been missing or limited, and
  Microsoft's OpenCL-on-D3D12 offers only 1.2, so the OpenCL backend is
  doubtful. SPIR-V/Level Zero is Intel-only. Nsight profiling is partial
  under WSL. Open: a prebuilt JDK or TornadoVM SDK runs through nix-ld,
  whose library path does not include `/run/opengl-driver/lib`. Whether it
  finds `libcuda` without `LD_LIBRARY_PATH` is to be seen, and only then
  added to `modules/base/nix-ld.nix` (nothing goes in there on speculation).
- **GUI apps through WSLg** (noted 2026-11-06): the host has no desktop role,
  so `home/max/desktop` and every app in it stay off WSL; only the TUIs in
  `home/max/core` come along. That makes WSL the weaker place for work
  that has a desktop app, today herdr-desktop next to the `herdr` TUI.
  WSLg should draw such apps as Windows windows, but herdr-desktop is GPUI
  on wgpu, Vulkan with an OpenGL fallback, and in WSL both go through
  Mesa's d3d12 layer (Vulkan as the experimental dozen driver). So try it
  before building anything: `nix run nixpkgs#herdr-desktop` in the guest,
  noting whether it renders, at what scaling, and whether clipboard and
  links reach Windows. If it holds up, GUI apps that do not need niri move
  out of `home/max/desktop/apps.nix` into a layer both the desktop role and
  this host import. Not yet checked: whether herdr has a Windows build that
  attaches to `herdr-core` in WSL, as VS Code and Zed do, which would make
  WSLg unnecessary for it.
  First run (2026-11-06, herdr-desktop 0.1.10, on the desktop's Ubuntu
  26.04 WSL distro with Nix installed, not yet the NixOS-WSL guest): plain
  `nix run nixpkgs#herdr-desktop` panics with "Failed to create surface for
  any enabled backend", because a Nix binary on Ubuntu has no
  `/run/opengl-driver` and finds no GL or Vulkan driver at all. Through
  nixGL (`nixGLIntel` + `nixVulkanIntel`, its pinned Mesa 25.0.5) it opens
  a window that renders sharp at Windows scaling and responds normally;
  the process had Mesa's dzn loaded on WSL's `libd3d12`/`libdxcore` from
  `/usr/lib/wsl/lib` (llvmpipe's `lvp` too, and wgpu doesn't log which
  adapter it took). So WSLg carries it; what the guest adds is
  `/run/opengl-driver` via `hardware.graphics`, which should stand in for
  nixGL there. Clipboard and links not yet tried. Side effect to know: on
  first start herdr turns on linger for the user and starts `herdr-core`
  as transient `systemd-run --user` units (`hc-serve-*`), which outlive
  the window.

## 4. A facter report of the metal

Facter has to run on Linux booted on the hardware itself. Netboot (PXE, e.g.
pixiecore served from the ThinkPad) or a Ventoy stick are other ways to get
Linux there, but still boot it on the metal; a USB stick is the plain one.

The repo's own installer ISO (`nix build .#installer-iso`) is enough, though
it is built for the ThinkPad: facter does not care, and `install-maxnix` is
simply not run. Wired network is the easy start, since the I225-V needs no
setup. With the pinned nixpkgs, as `hosts/t14s/configuration.nix` asks:

```bash
sudo $(nix build --no-link --print-out-paths --inputs-from /etc/maxnix \
  nixpkgs#nixos-facter)/bin/nixos-facter -o facter.json
```

then the `jq` strip from that same comment, before the file goes anywhere.

Getting the file off the live system without copying it out by hand, best
first:

1. **magic-wormhole**: `nix run nixpkgs#magic-wormhole -- send facter.json`,
   and `wormhole receive <code>` on the ThinkPad (or a phone app). End to
   end encrypted, nothing left behind anywhere public.
2. **A branch push**: the stripped report is meant for the public repo
   anyway; the ISO has git and `op`, so a GitHub token can come from
   1Password instead of being typed.
3. **A writable stick**: Ventoy keeps an exFAT data partition next to the
   ISO; or a second, plain stick.

Not the Windows NVMe: a BitLocker volume will not mount, and with Fast
Startup on Windows leaves NTFS hibernated, where a write from Linux risks it.

Worth making first-class: a `report-hardware` command in `hosts/installer`
that runs facter, strips the report and sends it — about twenty lines, and
the same again for the next machine.

## 5. Game development and games: the right goal?

Partly. "No Windows at all" probably does not hold, for reasons that have
nothing to do with maxnix.

**Playing.** Proton plays most of a Steam library, and NVIDIA on Wayland is
usable since explicit sync landed. The hard stop is kernel-level anti-cheat,
which some competitive multiplayer games require and Linux does not get.
Check the actual library against areweanticheatyet.com and ProtonDB before
deciding anything. HDR and VRR were further along in Hyprland than in niri,
and niri is the only compositor since 2026-10-18 (README, "Decisions, and
why"), so check niri's support against the monitor in question.

**Developing.** It depends on the engine:

- Godot: native, first-class on Linux.
- Unity: has a Linux editor, but Linux is the second-class platform.
- Unreal: the Linux editor works; marketplace plugins and many tools
  assume Windows, and it is not packaged for NixOS.
- Console SDKs and devkits are Windows-only.
- Shipping for Windows means testing on Windows. Proton is not QA.

**NixOS on top of that.** Engines and their toolchains ship as prebuilt
binaries that expect a conventional filesystem: `nix-ld`, `buildFHSEnv` or
`steam-run` per tool. Impermanence means every engine cache, project
directory and game library needs a persisted subvolume, sized for games.
Editors full of popups and floating panels need window rules under a tiling
compositor.

**The hardware.** NVIDIA is the one item maxnix does not handle today: it
needs `hardware.nvidia` with the open kernel modules (fine for Ampere), an
unfree allowance next to its reason, and niri's known NVIDIA tuning (its
VRAM heap reuse setting). And with no iGPU, a Windows VM with the GPU passed
through means single-GPU passthrough — the host loses its display while the
VM runs. Not the comfortable way out.

**Current lean:** dual boot on separate disks. Windows keeps the 1 TB for
anti-cheat games and testing Windows builds; NixOS takes one 2 TB disk as
the daily system, composed from base + desktop + metal + an NVIDIA/gaming
role (section 3). Each disk boots on its own, chosen from the firmware's boot
menu — no shared bootloader for one OS to break. When lanzaboote enrolls its
keys, it keeps Microsoft's (`sbctl enroll-keys -m`): Windows needs them, and
so does the GPU's option ROM, without which the screen can stay black at
boot.

## Still to decide

- [ ] Install Nix in WSL; run `nix run .#vm-headless` and the portable checks.
- [ ] Go through the game library on anti-cheat and ProtonDB.
- [ ] Settle the engine.
- [ ] Take the facter report from a stick (section 4).
- [ ] Find out Secure Boot, BitLocker and which disk Windows is on.
- [x] Split the roles (section 3): done 2026-10-18 (README, "Decisions, and
  why"), `home/max` into core and desktop with it.
- [x] `hosts/z690-wsl`, repo side: builds (`checks.z690-wsl`), image from
  `sudo nix run .#z690-wsl-tarball`. Open there: its age key and which secrets it
  gets, the login password (NixOS-WSL's default for now: none, and sudo asks
  for none).
- [x] 1Password in the guest, repo side (`modules/gui`, 2026-11-06): builds.
- [ ] In the guest: the app starts under WSLg (`systemctl --user status
  onepassword`), sign in, switch on the SSH agent and CLI integration; then
  `op whoami`, `ssh -T git@github.com` and a signed commit.
- [x] In the guest: `xdg-open https://github.com` and `gh auth login` open
  the Windows browser (`hosts/z690-wsl/windows.nix`; works, 2026-11-07).
- [ ] Import it on the desktop and boot it; see whether Beyla gets eBPF.
- [ ] In the guest: `nvidia-smi`, then a TornadoVM sample on the PTX backend;
  note whether `libcuda` is found without `LD_LIBRARY_PATH` (section 3).
- [ ] In the guest: `nix run nixpkgs#herdr-desktop` through WSLg; decides
  whether GUI apps get a layer of their own for this host (section 3).
  Renders on the Ubuntu distro through nixGL; still to do in the guest
  itself, plus clipboard and links.
- [ ] A desktop host.
