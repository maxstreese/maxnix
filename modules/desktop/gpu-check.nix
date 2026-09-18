# gpu-check — does this machine have what a Wayland compositor needs?
#
# Prints everything that determines whether a compositor will start: DRM
# devices, the virtio_gpu module, the card's bus driver, the PCI display
# adapter, and the EGL renderer. Run it before blaming niri or Hyprland for
# anything.
#
# It lives in the desktop layer rather than with the machine because the
# question it answers is a desktop one, and it stays worth having on real
# hardware: "is this llvmpipe or the real GPU" is the same question there.
{ pkgs, ... }:
let
  # Prints everything that determines whether a Wayland compositor will start.
  # Run it on the machine before blaming niri or Hyprland for anything.
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
  environment.systemPackages = [ gpu-check ];
}
