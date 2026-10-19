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
- **1Password**: the Windows app holds the vault. Its SSH agent reaches the
  guest through `npiperelay` on the agent's named pipe, and the CLI as
  `op.exe` through interop; the Linux desktop app has nothing to do there.
- **Rootless Docker**: should work with systemd on; untested.
- **Observability**: Prometheus, Loki, Tempo and Grafana are ordinary
  services. Beyla needs eBPF and BTF from the WSL kernel; whether it gets
  them is unknown.
- **What does not apply**: disk, LUKS, impermanence, Secure Boot, greeter,
  backups of `/` (the distribution is one VHDX file on Windows), Fleet.

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
  for none), 1Password's agent and signing bridged from Windows.
- [ ] Import it on the desktop and boot it; see whether Beyla gets eBPF.
- [ ] A desktop host.
