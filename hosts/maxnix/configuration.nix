# The machine.
#
# Nothing in this file knows or cares that it currently runs as a VM.
# Everything VM-shaped lives in ./vm.nix and ../../modules/vm/qemu-guest.nix.
# Keeping that line clean is the whole point: this file stays true when the
# config is built for real hardware, which is where it is headed (README,
# "Why this exists").
{ pkgs, ... }:
{
  networking.hostName = "maxnix";

  # NetworkManager, for a laptop that meets new networks all the time, and
  # what DMS's network widget talks to. Networks are joined in that widget or
  # with nmcli and kept, not declared: a rebuild for every café's Wi-Fi would
  # make the declarative way unusable, and the profiles survive the wiped
  # root on /persist (./persistence.nix), which the backup covers. A few
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

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  # ── Keyboard layout, in two independent places ───────────────────────────
  #
  # These are not the same mechanism and neither implies the other:
  #
  #   console.keyMap       the Linux virtual console — the TTY, and therefore
  #                        the greeter. Applied by loadkeys via
  #                        /etc/vconsole.conf.
  #   XKB_DEFAULT_LAYOUT   Wayland sessions. Compositors receive raw evdev
  #                        keycodes and map them through libxkbcommon, which
  #                        reads this variable. They never consult the console
  #                        keymap. Without it you get libxkbcommon's built-in
  #                        default, "us" — so the greeter was German and the
  #                        session was American.
  #
  # services.xserver.xkb.layout deliberately does NOT appear here. It is the
  # conventional NixOS spelling and it would do nothing: XKB_DEFAULT_LAYOUT
  # appears nowhere in the NixOS module tree, and programs.niri does not read
  # services.xserver.xkb. Setting it alone evaluates
  # fine and leaves you on "us".
  #
  # This reaches the compositor because sessionVariables are written to
  # /etc/pam/environment, which pam_env applies in greetd's PAM session.
  #
  # It is a *default*, and only compositors that leave the layout unset will
  # consult it. niri does, and reports "German"; Hyprland, while it ran here,
  # did not (its kb_layout defaults to "us"). home/max/niri.nix states the
  # layout anyway, reading it back from this option, so the layout is still
  # defined in exactly one place.
  #
  # Add XKB_DEFAULT_VARIANT / _OPTIONS here too if you ever want e.g.
  # nodeadkeys — your host currently sets neither.
  console.keyMap = "de";
  environment.sessionVariables.XKB_DEFAULT_LAYOUT = "de";

  users.users.max = {
    isNormalUser = true;
    description = "Max";
    extraGroups = [
      "wheel"
      "video" # DRM access, needed by every compositor
      "networkmanager" # add, change and remove connections without a root prompt
    ];
  };

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

  # No console autologin, deliberately (decided 2026-09-17). The text
  # consoles on Ctrl+Alt+F2…F6 keep their password prompt, and that is the
  # rescue path if the graphical greeter ever fails to draw: it needs working
  # GL, a TTY does not (see ../../modules/desktop/greeter.nix). Autologin
  # would have made the lock screen decorative — anyone at the keyboard, two
  # keystrokes, the whole session; and in the VMs, whose sudo asks for no
  # password (../../modules/vm/qemu-guest.nix), a root shell too.

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

  # The machine needs flakes so it can rebuild itself from a clone of this
  # repo. In the VM, `rebuild` (./vm.nix) activates the result without a
  # reboot; on metal it is plain nixos-rebuild.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Keeping the store from growing without bound.
  #
  # Nix never overwrites: every rebuild writes new store paths and leaves the
  # old ones alone. What keeps them alive is the system profile, which retains
  # every generation you have activated — that retention is exactly what makes
  # `nixos-rebuild --rollback` and the boot menu work. So the store grows with
  # every rebuild and nothing shrinks it unless asked.
  #
  # The measurements this is sized against: one system closure here is 12.5
  # GiB, and the Ubuntu host's hand-managed store had reached 60 GB by the
  # time this was written.
  # Monday 09:00 rather than the small hours, on purpose.
  #
  # Both timers are Persistent (the NixOS default, and it is what you want):
  # systemd records the last run, so a trigger missed while the machine was
  # off fires shortly after the next boot instead of being skipped — given
  # that the record survives the root wipe, which is why ./persistence.nix
  # preserves /var/lib/systemd/timers. The
  # consequence is that scheduling this for 03:15 on a Sunday — which looks
  # considerate — means a machine that sleeps at night never runs it *then*
  # and instead runs it at Monday's first boot, with no jitter
  # (randomizedDelaySec defaults to "0" for the collector), i.e. the moment
  # you open the lid.
  #
  # Picking an hour the machine is plausibly already awake makes the timer
  # fire when it says it will. The cost is that it runs during working hours;
  # the collection is mostly I/O and the optimiser is deferred 90 minutes so
  # the two never overlap.
  nix.gc = {
    automatic = true;
    dates = "Mon 09:00";
    # Without this the collection only removes what nothing points at —
    # build leftovers and old nix-shell inputs — and never touches a
    # generation, which is where the space actually is. This deletes
    # generations older than 30 days *first*, un-rooting their closures so
    # they become collectable.
    #
    # 30 days is a deliberate trade, not a default: those generations are
    # what you roll back *to*, and on a machine changed as often and as
    # experimentally as this one, that history is the safety net. A month of
    # it costs little on a real disk.
    options = "--delete-older-than 30d";
  };

  # Deduplicates the store by replacing byte-identical files across different
  # paths with hardlinks; typically reclaims 25-35%.
  #
  # Scheduled 90 minutes after the collection above, on purpose: running it
  # afterwards means it only hardlinks paths that survived, instead of doing
  # that work for paths about to be deleted. This one already carries 30
  # minutes of jitter by default (randomizedDelaySec = "1800").
  #
  # The alternative is nix.settings.auto-optimise-store, which does the same
  # deduplication inline as each path is added. That spreads the cost across
  # every build rather than concentrating it in one timer; this way round the
  # cost is predictable and off-peak.
  nix.optimise = {
    automatic = true;
    dates = [ "Mon 10:30" ];
  };

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
  # ./disk-layout.nix's `device`, a human decision. A config with a complete
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

  # Mesa, and the userspace bits a Wayland compositor expects to find.
  hardware.graphics.enable = true;

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

  # Environment for the *user* layer that can only be set here.
  #
  # marimo checks PyPI on startup and nags when it is behind, which on a
  # Nix-installed package is advice that cannot be followed: the store path
  # is immutable and the version is whatever the pinned nixpkgs carries.
  # ../../home/max/dev.nix explains the lag.
  #
  # This looks like it belongs in the user layer, and Home Manager's
  # home.sessionVariables is the obvious option — but that option means
  # exactly what it says, "set at login", and lands in a file only
  # ~/.profile sources. A terminal window is an interactive shell, and under
  # Wayland nothing sources a profile, so the variable would be set where
  # nobody looks. Measured in the guest: present under `bash -l`, absent
  # under `bash -i`, absent from the systemd user environment.
  #
  # sessionVariables here goes through /etc/pam/environment instead, which
  # pam_env applies to the whole session — including the systemd *user*
  # manager, and therefore every app it starts, ghostty among them. Verified
  # the same way XKB_DEFAULT_LAYOUT was, which travels this exact route.
  environment.sessionVariables.MARIMO_SKIP_UPDATE_CHECK = "1";

  # Home Manager as a NixOS module, so one `nix build` rebuilds the machine and
  # the user layer together into a single generation — no separate
  # `home-manager switch`. The user config itself lives in ../../home/max.
  home-manager = {
    # Use the system's pkgs and nixpkgs config rather than a second instance.
    useGlobalPkgs = true;
    # Install user packages into the system profile instead of
    # ~/.nix-profile, which keeps them inside the generation.
    useUserPackages = true;

    # niri had already written a real ~/.config/niri/config.kdl (and
    # Hyprland its own config, back when it ran here) inside this VM's disk
    # image. Home Manager refuses to clobber existing regular files,
    # so without this the very first activation fails with a confusing error.
    # With it, they are renamed aside — which is also a neat demonstration of
    # the imperative state this whole layer exists to replace.
    backupFileExtension = "hm-bak";

    users.max = import ../../home/max;
  };

  environment.systemPackages = with pkgs; [
    git
    htop
    vim

    # Diffs two system generations by store path: what was added, removed or
    # version-bumped. Both rebuild paths print one before activating, and it
    # is on PATH so a generation can be compared against any other after the
    # fact — `nvd diff /run/booted-system /run/current-system` being the one
    # worth knowing, which says what has changed since this boot.
    nvd

    # Backing tools for the `gpu-check` diagnostic, which is itself in
    # ../../modules/desktop/gpu-check.nix.
    mesa-demos # eglinfo, es2_info, es2gears
    pciutils # lspci

    # The machine as SQL tables: processes, packages, mounts, users, open
    # sockets. `sudo osqueryi`, since many tables need root. It is also what
    # the employer's Fleet asks its questions with (./fleet.nix), so e.g.
    # `select * from disk_encryption;` answers the LUKS check the way Fleet
    # will — on metal only, as every VM path has an unencrypted root. The
    # agent brings its own copy; this one is for asking by hand.
    osquery
  ];

  # The machine observing itself: metrics, logs, Grafana, and Claude Code's
  # telemetry. See ./observability.nix. Needs no secret, so on everywhere,
  # metal and every test node alike.
  maxnix.observability.enable = true;

  # Pins the defaults this config was written against so stateful services keep
  # their original semantics across nixpkgs upgrades. It is NOT a version to
  # keep current — set once, then leave alone.
  system.stateVersion = "26.11";
}
