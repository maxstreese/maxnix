# VM-only settings.
#
# Everything under `virtualisation.vmVariant` applies solely to the second
# evaluation that produces run-maxnix-vm. The base machine never sees it.
#
# These become QEMU command-line flags on the Ubuntu host — which is why the
# host needs nothing but a Nix daemon and /dev/kvm.
{ ... }:
{
  virtualisation.vmVariant =
    { config, ... }:
    let
      hostPkgs = config.virtualisation.host.pkgs;

      # ── Making nixpkgs' QEMU find a GPU on a non-NixOS host ──────────────
      #
      # nixpkgs' Mesa is patched to look for its drivers under
      # /run/opengl-driver/lib — a path that only exists on NixOS, created
      # there by `hardware.graphics.enable`. On Ubuntu it does not exist, so
      # Nix-built QEMU cannot initialise GL and dies:
      #
      #   MESA-LOADER: failed to open dri: /run/opengl-driver/lib/gbm/dri_gbm.so
      #   qemu-system-x86_64: egl: render node init failed
      #
      # ...and with -display gtk,gl=on it core-dumps on an epoxy assertion.
      # Note this is a HOST-side failure: QEMU never gets far enough to start
      # the guest.
      #
      # The usual advice is to symlink /run/opengl-driver on the host as root.
      # We don't: /run is a tmpfs so it would not survive a reboot, and it
      # would pin a store path outside any GC root. Instead we point Mesa at
      # nixpkgs' own Mesa with environment variables and wrap QEMU in them, so
      # the fix travels with the config and needs no root.
      #
      # LIBGL_DRIVERS_PATH does NOT work here — nixpkgs Mesa ignores it for the
      # GBM loader. GBM_BACKENDS_PATH is the one that is honoured.
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
        memorySize = 8192; # MiB — of your 30 GiB
        diskSize = 16384; # MiB — a ceiling; the qcow2 grows into it

        # Default is "./${hostname}.qcow2", i.e. wherever you happened to cd.
        # Pinned so a forgotten image in another directory cannot silently
        # supply stale state. If you change a password and it does not take,
        # this file is why: delete it and the VM is recreated from scratch.
        diskImage = "./.vm/maxnix.qcow2";

        # Step 2: a real window, and a real GPU.
        #
        # niri and Hyprland need an actual DRM device with working GLES. Plain
        # emulated VGA does not provide one, and the failure is famously
        # opaque: a black screen and "Could not successfully create backend on
        # any GPU". Getting this right *before* installing a compositor means
        # step 3 can only fail for compositor reasons.
        graphics = true;

        qemu.package = qemuWithGL;

        qemu.options = [
          # virtio-gpu + VGA compatibility + GL. Gives the guest
          # /dev/dri/card0 and a renderD128 render node.
          "-device virtio-vga-gl"

          # gl=on enables host-side virglrenderer, which translates the guest's
          # GL calls onto your AMD iGPU. Without it the device still appears
          # but everything falls back to software rasterisation.
          #
          # Override at runtime without rebuilding, e.g. to run headless:
          #   QEMU_OPTS="-display egl-headless" ./result/bin/run-maxnix-vm
          "-display gtk,gl=on,show-cursor=on"
        ];

        # The repo itself, mounted inside the VM at /mnt/maxnix. Lets you edit
        # Quickshell QML on the host and see it in the guest without a rebuild.
        #
        # $PWD does NOT work here. The generated runner does `cd "$TMPDIR"`
        # before this string is expanded, so $PWD would silently share an empty
        # temp directory. (diskImage above escapes this only because the runner
        # resolves it to an absolute path *before* that cd.)
        #
        # $OLDPWD is what the launch directory becomes after that single cd.
        # If a future nixpkgs adds a second cd to the runner this breaks
        # silently, so MAXNIX_REPO is the explicit escape hatch:
        #   MAXNIX_REPO=/path/to/repo ./result/bin/run-maxnix-vm
        sharedDirectories.maxnix = {
          source = ''"''${MAXNIX_REPO:-$OLDPWD}"'';
          target = "/mnt/maxnix";
          securityModel = "none";
        };
      };
    };
}
