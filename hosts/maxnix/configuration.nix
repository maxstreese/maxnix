# The machine.
#
# Nothing in this file knows or cares that it will run as a VM. Everything
# VM-shaped lives in ./vm.nix. Keeping that line clean is the whole point:
# this file stays true if the config is ever built for real hardware.
{ pkgs, ... }:
let
  # Prints everything that determines whether a Wayland compositor will start.
  # Run it in the VM before blaming niri or Hyprland for anything.
  gpu-check = pkgs.writeShellScriptBin "gpu-check" ''
    echo "== DRM devices =="
    if [ -d /dev/dri ]; then
      ls -l /dev/dri/
    else
      echo "  NONE. The guest has no GPU — a compositor cannot start."
    fi

    echo
    echo "== virtio_gpu kernel module =="
    if grep -q '^virtio_gpu ' /proc/modules 2>/dev/null || [ -d /sys/module/virtio_gpu ]; then
      echo "  loaded"
    else
      echo "  NOT loaded — no virtio GPU driver in the guest"
    fi

    echo
    echo "== DRM cards (bus driver; the DRM driver shows in the EGL section) =="
    # Glob card[0-9]* deliberately: /sys/class/drm also contains connector
    # entries like card0-Virtual-1, which are not cards.
    for c in /sys/class/drm/card[0-9]*; do
      case "$c" in *-*) continue ;; esac
      [ -e "$c/device/uevent" ] || continue
      echo "  $(basename "$c") -> $(grep -m1 '^DRIVER=' "$c/device/uevent" | cut -d= -f2)"
    done

    echo
    echo "== display adapter on the PCI bus =="
    ${pkgs.pciutils}/bin/lspci | grep -iE 'vga|display|3d' || echo "  none found"

    echo
    echo "== EGL renderer (want: virgl, NOT llvmpipe/softpipe) =="
    # eglinfo exits non-zero on a bare TTY because the X11 and Wayland
    # platforms are unavailable. That is expected; the GBM platform is the one
    # that matters, so parse the output regardless of exit status.
    ${pkgs.mesa-demos}/bin/eglinfo >/tmp/eglinfo.txt 2>&1 || true
    grep -iE 'EGL driver name|renderer|OpenGL version|EGL vendor' /tmp/eglinfo.txt \
      | sort -u | head -12 || echo "  no EGL info — see /tmp/eglinfo.txt"

    echo
    echo "== verdict =="
    if grep -qi virgl /tmp/eglinfo.txt 2>/dev/null; then
      echo "  OK: hardware-accelerated via virglrenderer."
    elif grep -qiE 'llvmpipe|softpipe|swrast' /tmp/eglinfo.txt 2>/dev/null; then
      echo "  SOFTWARE RENDERING. The device works but gl=on is not taking effect."
      echo "  Compositors may start, but slowly. Check -display gtk,gl=on."
    else
      echo "  Inconclusive — read the output above."
    fi
  '';
in
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
    # Throwaway credential for a local VM; it lands world-readable in the Nix
    # store, which is fine here and would not be on a real machine.
    # `initialPassword` only applies when the user is first created — see the
    # note about stale disk images in ./vm.nix.
    initialPassword = "maxnix";
  };
  users.users.root.initialPassword = "maxnix";

  # No password prompt on sudo. A VM you throw away is not worth the friction.
  security.sudo.wheelNeedsPassword = false;

  # Log straight in on the console.
  services.getty.autologinUser = "max";

  # Mesa, and the userspace bits a Wayland compositor expects to find.
  hardware.graphics.enable = true;

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

    # GPU diagnostics — see the verdict from `gpu-check`.
    gpu-check
    mesa-demos # eglinfo, es2_info, es2gears
    pciutils # lspci
  ];

  # Pins the defaults this config was written against so stateful services keep
  # their original semantics across nixpkgs upgrades. It is NOT a version to
  # keep current — set once, then leave alone.
  system.stateVersion = "26.11";
}
