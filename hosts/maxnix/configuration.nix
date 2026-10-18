# The machine: what is only true of this ThinkPad, on top of the roles it
# imports (../../modules/base, desktop and metal; see flake.nix).
#
# Nothing in this file knows or cares that it currently runs as a VM.
# Everything VM-shaped lives in ./vm.nix and ../../modules/vm/qemu-guest.nix.
# Keeping that line clean is the whole point: this file stays true when the
# config is built for real hardware, which is where it is headed (README,
# "Why this exists").
{ ... }:
{
  networking.hostName = "maxnix";

  # NetworkManager, for a laptop that meets new networks all the time, and
  # what DMS's network widget talks to. Networks are joined in that widget or
  # with nmcli and kept, not declared: a rebuild for every café's Wi-Fi would
  # make the declarative way unusable, and the profiles survive the wiped
  # root on /persist (../../modules/metal/persistence.nix), which the backup covers. A few
  # fixed networks could still be declared from sops later
  # (networking.networkmanager.ensureProfiles), next to these. Decided
  # 2026-10-14. On every VM too: it hands QEMU's network the same DHCP the
  # scripted networking did, and gives the widget something to show.
  #
  # DNS through resolvconf, not systemd-resolved. Before NetworkManager,
  # resolved ran only because nixpkgs' Twingate module turns it on — and that
  # module does so only while NetworkManager is off. With it on, NetworkManager
  # writes /etc/resolv.conf through resolvconf and the Twingate client puts its
  # resolvers there; in the VM, 2026-10-14, resolv.conf held the client's
  # 100.95.0.x resolvers and names resolved. Left as nixpkgs pairs the two,
  # rather than forcing resolved back on beside a combination it avoids.
  networking.networkmanager.enable = true;

  # Without facter's own DHCP: from the hardware report it gives every
  # detected interface useDHCP — Wi-Fi, both Ethernets, the WWAN modem — and
  # that starts dhcpcd next to NetworkManager, two DHCP clients on one card.
  # Measured 2026-10-14: dhcpcd.service was wantedBy multi-user.target until
  # this was off.
  hardware.facter.detected.dhcp.enable = false;

  # Add, change and remove connections without a root prompt.
  users.users.max.extraGroups = [ "networkmanager" ];

  # Users exactly as declared, at every activation, and the password from
  # sops (./secrets.nix). Measured 2026-10-13 in checks.metal-boots: with
  # mutable users and the root wiped at every boot, /etc/shadow is rebuilt
  # from the config each time, so a `passwd` was undone by the next boot. And
  # nothing better was on offer — userborn's persistent password files are
  # symlinks into /etc, which passwd and chpasswd replace with a plain file on
  # the wiped root. So the password lives in the repo, encrypted, and
  # changing it is a sops edit and a rebuild (README, "Decisions, and why").
  # Every VM keeps a known plaintext one instead; see
  # ../../modules/vm/qemu-guest.nix.
  users.mutableUsers = false;
  maxnix.loginPassword.fromSops = true;
  # And with it the rest of what only metal may read, from a sops file the
  # VM's key cannot open (./secrets.nix).
  maxnix.secrets.metal.enable = true;

  # What the machine's secrets are for, all from sops (./secrets.nix): Fleet,
  # enrolled with the employer's server as agreed with IT (2026-09-29), with
  # its tray app; Harlequin's connection profiles; and the nightly backup to
  # Drive, into rclone:gdrive:maxnix-backup. Each needs the machine's key,
  # which metal gets on install day and the VM already has (./vm.nix, which
  # also gives the VM a backup folder of its own). The test nodes hold no key
  # and turn all four off (tests/desktop.nix, tests/niri.nix).
  maxnix.fleet.enable = true;
  maxnix.fleet.desktop = true;
  maxnix.harlequin.profiles.enable = true;
  maxnix.backup.enable = true;

  # Swap in RAM, compressed: pages that sit unused are packed with zstd
  # instead of taking room, so a memory spike — a large build, a few VMs —
  # is absorbed rather than ending in the OOM killer. nixpkgs' defaults as
  # they are: zstd, up to half the RAM as the device's size.
  #
  # No swap on disk, and so no hibernation, for now (decided 2026-10-15).
  # Whether resuming from hibernation works on this ThinkPad's AMD graphics,
  # and whether Secure Boot through lanzaboote leaves the kernel willing to,
  # shows only on the hardware. If it does, a swapfile in a btrfs subvolume of
  # its own (out of the root's rollback) adds it without repartitioning, and
  # systemd's suspend-then-hibernate gives a lid closed for days a full
  # battery back. zram stays either way, ahead of the file.
  zramSwap.enable = true;

  # Hardware detection, from a nixos-facter report of the machine itself: a
  # Lenovo ThinkPad T14s Gen 2a (AMD), taken 2026-10-14 on its Ubuntu, with
  # the pinned nixpkgs' nixos-facter 0.4.4 so the report matches the modules
  # that read it. It is the modern replacement for `nixos-generate-config`,
  # which writes Nix that you then hand-maintain forever; nixpkgs' modules
  # under nixos/modules/hardware/facter turn the JSON into configuration —
  # AMD microcode, redistributable firmware, the initrd's kernel modules.
  #
  # Retaken the same way after a hardware change:
  #
  #   sudo $(nix build --no-link --print-out-paths \
  #     nixpkgs#nixos-facter)/bin/nixos-facter -o facter.json
  #
  # then stripped before it lands here, because the repo is public: every
  # `serial` field (40 of them — disk, camera, monitor, USB devices) and the
  # /dev/disk/by-id names that carry the disk's serial and EUI. None of the
  # facter modules reads either; the metal toplevel's derivation was
  # identical with and without them. jq does both:
  #
  #   jq 'walk(if type == "object" and has("serial") then del(.serial) else . end)
  #     | walk(if type == "object" and has("unix_device_names") then
  #         .unix_device_names |= map(select(test("/by-id/") | not)) else . end)'
  #
  # The report does NOT choose the disk to install onto — that is
  # ../../modules/metal/disk-layout.nix's `device`, a human decision. A config with a complete
  # report and no fileSystems still fails the root-filesystem assertion.
  #
  # nixos-hardware has no profile for this model (t14s/amd has gen1 and gen4,
  # checked 2026-10-14), and its shared T14s ones add nothing the report does
  # not, beyond two hints for when the laptop services land: the kernel
  # parameter acpi_backlight=native, for brightness through thinkpad_acpi,
  # and, in the firmware, Config → Power → Sleep State set to "Linux" for
  # suspend to RAM to work.
  #
  # Metal only: ../../modules/vm/qemu-guest.nix sets it back to null for every
  # VM, whose hardware is QEMU's, not this.
  hardware.facter.reportPath = ./facter.json;

  # Wootility — configuration software for Wooting keyboards.
  #
  # The module installs it and, more importantly, the udev rules that tag the
  # keyboard's hidraw and usb nodes with uaccess, so the logged-in user may
  # talk to it without root. System-level because udev rules are.
  #
  # In the VM it will find no keyboard: the guest sees QEMU's emulated input
  # devices, not the real USB one. Pass the hardware through for a session
  # with (from the host, no root needed — the device node is root:input and
  # you are in that group):
  #
  #   QEMU_OPTS="-device usb-host,vendorid=0x31e3,productid=0x1312" nix run .#vm
  #
  # The host gives up the keyboard while that VM runs. On metal none of this
  # applies and the tool just works, which is the point of configuring it
  # here rather than leaving it to the host.
  hardware.wooting.enable = true;

  # Twingate — the zero-trust VPN client, as a system daemon.
  #
  # The module runs the daemon, seeds /etc/twingate from the package on first
  # start, relaxes reverse-path filtering (the tunnel's replies arrive on a
  # different interface than the kernel's strict check expects), and — only
  # where NetworkManager is off — turns on systemd-resolved for the client's
  # split DNS. Here NetworkManager is on, so DNS goes the way nixpkgs pairs
  # with it: through resolvconf, where the client puts its own resolvers
  # (see networking.networkmanager above). It also puts the `twingate` CLI
  # on PATH.
  #
  # No credential here, and none possible: you run `twingate setup` once to
  # name the network, then `twingate start`, which opens a browser to
  # authenticate. The network name lands in /etc/twingate, which is on the
  # disposable root disk — so a root-image reset means running setup again.
  services.twingate.enable = true;

  # Until setup has been run, the daemon exits immediately ("There is no
  # default profile"). Upstream's unit pairs Restart=always with
  # StartLimitIntervalSec=0, which disables the rate limit — so on an
  # unconfigured machine it respawns every 2 s forever, burning CPU and
  # filling the journal (655 lines in the first few minutes, measured). Give
  # the limit back: five tries, then the unit gives up and sits in `failed`,
  # where it is visible and quiet. `twingate setup` followed by
  # `systemctl start twingate` is the way back, and a configured daemon does
  # not exit, so this never triggers once it is in use.
  systemd.services.twingate.unitConfig.StartLimitIntervalSec = 30;

  # Unfree packages. `allowUnfreePackages` is a list matched against pname and
  # concatenated across modules, so each module names what it needs (see
  # ../../modules/desktop/onepassword.nix for the reasoning). Two groups land
  # here: wootility and twingate just above, and the *user* layer's — Home
  # Manager modules
  # cannot declare their own, because with useGlobalPkgs (below) they borrow
  # the system's nixpkgs config. See home/max/apps.nix for why each is wanted.
  nixpkgs.config.allowUnfreePackages = [
    "wootility"
    "twingate"
    "spotify"
    "claude-code"
    "slack"
    # See home/max/dev.nix: agent-browser's browser, and a real Chrome.
    "google-chrome"
    # Both halves: the wrapper and the derivation it wraps each carry the
    # licence, and the allow-list matches on pname, so listing one leaves
    # the other refused.
    "discord"
    "discord-unwrapped"
  ];

  # The user layer, whole for now: shell and dev next to the desktop. The
  # Home Manager plumbing is in ../../modules/base.
  home-manager.users.max = import ../../home/max;

  # Pins the defaults this config was written against so stateful services keep
  # their original semantics across nixpkgs upgrades. It is NOT a version to
  # keep current — set once, then leave alone.
  system.stateVersion = "26.11";
}
