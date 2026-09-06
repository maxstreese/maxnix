# Virtual hardware shared by every way this host runs as a VM.
#
# Applied through two different mechanisms:
#   hosts/maxnix/vm.nix  -> nested under virtualisation.vmVariant, for build-vm
#   tests/desktop.nix    -> directly on the test node
#
# That duplication is the whole reason this file exists. The NixOS test
# framework imports qemu-vm.nix into each node at top level (see
# nixos/lib/testing/nodes.nix) and never looks at virtualisation.vmVariant, so
# anything nested under vmVariant is invisible to tests. A test node would
# silently get no GPU and fail in a way that looks like a compositor bug.
#
# Deliberately NOT here, because the two paths genuinely differ:
#   -display     build-vm wants a gtk window; the test wants egl-headless
#   diskImage    only meaningful for build-vm
#   9p share     depends on a launch directory, which a test does not have
{ config, lib, ... }:
let
  hostPkgs = config.virtualisation.host.pkgs;

  # nixpkgs' Mesa is patched to look for drivers under /run/opengl-driver/lib,
  # a path that only exists on NixOS. On Ubuntu, Nix-built QEMU therefore fails
  # to initialise GL ("MESA-LOADER: failed to open dri", "egl: render node init
  # failed") and core-dumps outright under -display gtk,gl=on.
  #
  # Pointing Mesa at nixpkgs' own Mesa fixes it without root and without
  # symlinking /run/opengl-driver (which is a tmpfs, so it would not survive a
  # reboot, and would pin a store path outside any GC root).
  #
  # LIBGL_DRIVERS_PATH does NOT work — nixpkgs Mesa ignores it for the GBM
  # loader. GBM_BACKENDS_PATH is the one that is honoured.
  mesa = hostPkgs.mesa;
  qemuWithGL = hostPkgs.symlinkJoin {
    name = "qemu-gl-on-ubuntu";
    paths = [ hostPkgs.qemu_kvm ];
    nativeBuildInputs = [ hostPkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/qemu-system-x86_64 \
        --set GBM_BACKENDS_PATH ${mesa}/lib/gbm \
        --set __EGL_VENDOR_LIBRARY_DIRS ${mesa}/share/glvnd/egl_vendor.d \
        --prefix LD_LIBRARY_PATH : ${mesa}/lib
    '';
  };
in
{
  virtualisation = {
    cores = 4;
    memorySize = 8192; # MiB
    diskSize = 16384; # MiB — a ceiling; the image grows into it
    graphics = true;

    # mkForce, because both consumers assign their own and both are wrong here:
    #   - the test framework assigns hostPkgs.qemu_test, built with
    #     nixosTestRunner = true, which disables SDL and therefore (by
    #     nixpkgs' own defaulting chain) OpenGL and virgl too
    #   - interactive mode assigns plain hostPkgs.qemu, which cannot find Mesa
    #     on a non-NixOS host
    # This machine always needs the wrapper, so it insists.
    qemu.package = lib.mkForce qemuWithGL;

    qemu.options = [
      # virtio-gpu + VGA compatibility + GL: gives the guest /dev/dri/card0 and
      # a renderD128 render node. niri and Hyprland both refuse to start
      # without one ("Could not successfully create backend on any GPU"), and
      # niri has no software-rendering fallback — unlike wlroots compositors,
      # which is how upstream's nixos/tests/sway.nix gets away with
      # WLR_RENDERER=pixman.
      #
      # xres/yres set the preferred mode. Note virtualisation.resolution does
      # NOT do this — that option only feeds services.xserver, and nothing here
      # runs X.
      "-device virtio-vga-gl,xres=1920,yres=1080"

      # A VNC server bound to loopback only.
      #
      # This is the *only* way to capture the screen while GL is on: QEMU's
      # screendump (which is what the test driver's machine.screenshot() and
      # get_screen_text() both use) fails with "Error: no surface", because a
      # GL scanout is a dmabuf rather than a CPU-readable surface. VNC's
      # readback path works fine. See tests/desktop.nix.
      "-vnc 127.0.0.1:9"
    ];
  };
}
