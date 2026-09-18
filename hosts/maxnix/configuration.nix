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
  ];

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
