# The machine.
#
# Nothing in this file knows or cares that it currently runs as a VM.
# Everything VM-shaped lives in ./vm.nix. Keeping that line clean is the whole
# point: this file stays true when the config is built for real hardware,
# which is where it is headed (README, "Why this exists").
#
# One setting below is an honest shortcut taken because it is *only a VM
# today*. It is marked "ROAD TO METAL" and listed in the README, so it is
# found again when the time comes.
{ pkgs, ... }:
{
  networking.hostName = "maxnix";

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
  # appears nowhere in the NixOS module tree, and neither programs.niri nor
  # programs.hyprland reads services.xserver.xkb. Setting it alone evaluates
  # fine and leaves you on "us".
  #
  # This reaches the compositor because sessionVariables are written to
  # /etc/pam/environment, which pam_env applies in greetd's PAM session.
  #
  # It is a *default*, and only compositors that leave the layout unset will
  # consult it. niri does, and reports "German". Hyprland does NOT: its own
  # input:kb_layout defaults to "us", so it always passes a non-empty value and
  # libxkbcommon never falls back to the environment. home/max/hyprland.nix
  # therefore sets kb_layout explicitly — reading it back from this option, so
  # the layout is still defined in exactly one place.
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
    ];
    # A plaintext credential, world-readable in the Nix store. Decided
    # 2026-09-17: fine as it is, on the VM and on the eventual host alike, so
    # this is not on the road to metal. `initialPassword` only applies when
    # the user is first created — see the note about stale disk images in
    # ./vm.nix.
    initialPassword = "maxnix";
  };
  users.users.root.initialPassword = "maxnix";

  # ROAD TO METAL. No password prompt on sudo, purely to skip typing in a
  # guest whose disk is thrown away. On the real host this goes.
  security.sudo.wheelNeedsPassword = false;

  # No console autologin, deliberately (decided 2026-09-17). The text
  # consoles on Ctrl+Alt+F2…F6 keep their password prompt, and that is the
  # rescue path if the graphical greeter ever fails to draw: it needs working
  # GL, a TTY does not (see ../../modules/desktop/greeter.nix). Autologin
  # would have made the lock screen decorative — anyone at the keyboard, two
  # keystrokes, a root shell via passwordless sudo.

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
  # off fires shortly after the next boot instead of being skipped. The
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

  # ROAD TO METAL. Hardware detection, unconfigured because there is no
  # machine to detect yet.
  #
  # nixos-facter snapshots a machine to JSON — controllers, firmware, CPU,
  # graphics — and nixpkgs' own modules under nixos/modules/hardware/facter
  # turn that report into configuration. It is the modern replacement for
  # `nixos-generate-config`, which writes Nix that you then hand-maintain
  # forever.
  #
  # Nothing extra is needed to use it: the modules ship in nixpkgs and this
  # option already exists. On install day the whole change is to drop the
  # report next to this file and point at it:
  #
  #   # on the target, booted from a NixOS installer USB:
  #   sudo nix run nixpkgs#nixos-facter -- -o facter.json
  #   ls -l /dev/disk/by-id            # for disk-layout.nix's device
  #
  #   # here:
  #   hardware.facter.reportPath = ./facter.json;
  #
  # Note the second command. The report does NOT decide which disk to install
  # onto — that is a choice a human makes from the by-id listing, and it goes
  # in ./disk-layout.nix. Facter answers "what is this machine", not "where
  # should the system live". Verified rather than assumed: a config carrying a
  # complete report and no fileSystems still fails with "The 'fileSystems'
  # option does not specify your root file system".
  #
  # The consuming side is exercised, on this desktop, 2026-09-22: pointing
  # reportPath at a real report flipped hardware.cpu.amd.updateMicrocode and
  # hardware.enableRedistributableFirmware from false to true, left the Intel
  # equivalent false, and populated boot.initrd.availableKernelModules with 36
  # entries including nvme and tpm-crb. The report itself was thrown away —
  # this machine's hardware is not the target's — but the wiring is known to
  # work, which is the part that would be expensive to get wrong on the day.
  #
  # Left null rather than pointed at a placeholder file: with null the facter
  # modules evaluate to nothing at all, so the metal configuration still
  # builds, which is what keeps checks.metal honest in the meantime.
  hardware.facter.reportPath = null;

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
  # different interface than the kernel's strict check expects) and turns on
  # systemd-resolved, since the client publishes split-DNS for the networks it
  # serves. It also puts the `twingate` CLI on PATH.
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

    # niri and Hyprland have already written real files to
    # ~/.config/niri/config.kdl and ~/.config/hypr/hyprland.lua inside this
    # VM's disk image. Home Manager refuses to clobber existing regular files,
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

    # Backing tools for the `gpu-check` diagnostic, which is itself in
    # ../../modules/desktop/gpu-check.nix.
    mesa-demos # eglinfo, es2_info, es2gears
    pciutils # lspci
  ];

  # Pins the defaults this config was written against so stateful services keep
  # their original semantics across nixpkgs upgrades. It is NOT a version to
  # keep current — set once, then leave alone.
  system.stateVersion = "26.11";
}
