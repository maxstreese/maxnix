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
#   -vnc         coupled to -display, see below
#   diskImage    only meaningful for build-vm
#
# On -vnc specifically: only ONE thing may own QEMU's GL context. A window and
# a VNC server are therefore mutually exclusive while GL is on —
#
#   -display gtk,gl=on -vnc ...     qemu: Display vnc is incompatible with
#                                   the GL context   (refuses to start)
#   -display egl-headless -vnc ...  fine; egl-headless exists precisely to
#                                   render GL off-screen and hand it over
#
# So -vnc belongs with whichever -display asked for it. It lived here briefly
# and broke `build-vm` outright, which the tests could not catch because they
# all override -display to egl-headless.
{ config, lib, ... }:
let
  hostPkgs = config.virtualisation.host.pkgs;

  gpu = config.maxnix.vm.gpu;

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
  inherit (hostPkgs) mesa;

  # QEMU's GTK window otherwise prints, on every start:
  #   Gtk-Message: Failed to load module "canberra-gtk-module"
  #
  # The request comes from the *host* desktop, not from anything here: GNOME
  # asks every GTK app to load the sound-event module, and this QEMU is
  # Nix-built so it cannot see Ubuntu's copy. Clearing GTK_MODULES does not
  # help — that variable holds "gail:atk-bridge" and the canberra entry arrives
  # through GTK's settings, which the environment does not override. So satisfy
  # the request rather than suppress it: nixpkgs' libcanberra-gtk3 ships
  # exactly the file GTK looks for, lib/gtk-3.0/modules/libcanberra-gtk-module.so.
  canberra = hostPkgs.libcanberra-gtk3;

  qemuWithGL = hostPkgs.symlinkJoin {
    name = "qemu-gl-on-ubuntu";
    paths = [ hostPkgs.qemu_kvm ];
    nativeBuildInputs = [ hostPkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/qemu-system-x86_64 \
        --set GBM_BACKENDS_PATH ${mesa}/lib/gbm \
        --set __EGL_VENDOR_LIBRARY_DIRS ${mesa}/share/glvnd/egl_vendor.d \
        --prefix LD_LIBRARY_PATH : ${mesa}/lib \
        --prefix GTK_PATH : ${canberra}/lib/gtk-3.0
    '';
  };
in
{
  # Whether this VM gets a GL-capable GPU.
  #
  # On (the default) the guest gets virtio-vga-gl backed by the host's real
  # GPU, which is what niri and Hyprland need to draw anything at all.
  #
  # Off, the guest still boots and both compositors still *start* — the
  # Wayland IPC socket appears — but they enumerate no outputs and nothing is
  # ever drawn. Measured 2026-09-21 on both `-device virtio-gpu` and
  # `-device virtio-vga`: `niri msg outputs` returns empty and the screen
  # stays a 2-3 colour text console. Without virgl there is no GL driver for
  # the virtio GPU, so niri finds no render device ("error getting the render
  # node for the primary GPU") and comes up headless.
  #
  # So this is not a performance knob. Off means every assertion about what is
  # on screen has to be skipped, which is exactly what tests/desktop.nix and
  # tests/compositor.nix do with their own `gpu` flag.
  #
  # It exists because a GitHub-hosted runner has KVM but no /dev/dri, and
  # because a sandboxed `nix build` cannot do GL on this host either: the Nix
  # sandbox does not mount /sys, so Mesa cannot identify the render node and
  # eglInitialize fails even with the device world-readable. Both of those are
  # the same tier, and this option is how a node opts into it.
  options.maxnix.vm.gpu = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Give the guest a GL-capable virtio GPU backed by the host's.";
  };

  # Collect garbage during a build when the disk gets tight, rather than only
  # on the weekly timer in ../../hosts/maxnix/configuration.nix.
  #
  # This is here and not there because it is a fact about *being a VM*: the
  # root image above is capped at 16 GiB and one system closure is 12.5 GiB,
  # so a deploy of a meaningfully different closure has roughly 3.5 GiB to
  # land in. A weekly timer can easily fire too late for that; these two
  # settings make the daemon free space at the moment it runs out.
  #
  # When free space drops below min-free mid-build, the daemon collects until
  # max-free is available, then carries on. It is best-effort — it cannot free
  # what is still rooted — so a build can still fail on a full disk; it just
  # will not fail on a disk full of garbage.
  #
  # Metal will want its own numbers, and a bigger disk makes them less
  # interesting; that belongs with the disk layout whenever that lands.
  config.nix.settings = {
    min-free = 1024 * 1024 * 1024; # 1 GiB
    max-free = 3 * 1024 * 1024 * 1024; # 3 GiB
  };

  config.virtualisation = {
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
    # Only when GL is wanted. Without it the stock qemu_test the framework
    # picks is correct and the Mesa wrapper would be dead weight.
    qemu.package = lib.mkIf gpu (lib.mkForce qemuWithGL);

    # ── Workaround for a nixpkgs bug; remove once upstream fixes it ─────
    #
    # nixpkgs replaced 9p with virtiofs for every shared directory (PR
    # #552774, nixpkgs-unstable from 2026-09). virtiofs is a vhost-user
    # device, and vhost-user needs the guest's RAM to be a shared memory
    # object so the daemon can map it. qemu-vm.nix only adds that
    # `-object memory-backend-memfd,share=on` when this option is set, and
    # nothing sets it for build-vm — only the NixOS test driver does, which
    # is why the tests passed while `nix run .#vm` hung.
    #
    # Without it every virtiofsd handshake collapses and the guest never
    # boots. The symptoms are misleading:
    #   virtiofsd: Failed to open file handle for the root node: Operation
    #              not permitted            <- a red herring; it falls back
    #   qemu:      vhost_set_vring_kick failed: Input/output error
    #   virtiofsd: Waiting for daemon failed: HandleRequest(InvalidParam)
    #
    # WATCH: https://github.com/NixOS/nixpkgs/pull/563324
    # ("nixos/qemu-vm: virtiofsd requires shared memory") makes this option
    # default to true whenever virtiofs is in use. Once flake.lock has a
    # nixpkgs containing that PR, this block is a no-op and can be deleted.
    # Check with:
    #   grep -n 'enableSharedMemory' \
    #     $(nix eval --raw --impure --expr \
    #       '(builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath')/nixos/modules/virtualisation/qemu-vm.nix
    # and look for a `default = useVirtiofs` rather than `mkEnableOption`.
    qemu.enableSharedMemory = true;

    # xres/yres set the preferred mode in both branches. Note that
    # virtualisation.resolution does NOT do this — that option only feeds
    # services.xserver, and nothing here runs X.
    qemu.options = [
      (
        if gpu then
          # virtio-gpu + VGA compatibility + GL: gives the guest
          # /dev/dri/card0 and a renderD128 render node with virgl, which is
          # the only way either compositor puts anything on screen.
          "-device virtio-vga-gl,xres=1920,yres=1080"
        else
          # The same device without GL. The guest still gets a framebuffer,
          # so it boots and the console is readable, but the kernel reports
          # `[drm] features: -virgl` and neither compositor enumerates an
          # output. Everything that does not look at the screen still works.
          #
          # Earlier revisions of this comment claimed niri "refuses to start"
          # without a GPU. Measured 2026-09-21: it starts fine and serves its
          # IPC socket. What it does not do is render.
          "-device virtio-vga,xres=1920,yres=1080"
      )
    ];
  };
}
