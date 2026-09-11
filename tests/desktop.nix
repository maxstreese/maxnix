# Compositor-agnostic checks: the machine boots, the greeter is up, both
# compositors are installed and offered as sessions, and the guest GPU works.
#
# Deliberately has NO autologin, so this exercises the configuration exactly as
# committed. Per-compositor behaviour lives in ./compositor.nix.
#
# HOW TO RUN:
#
#   nix run .#test-desktop
#
# NOT `nix build .#checks.x86_64-linux.desktop`. A sandboxed build on this
# Ubuntu host can open neither /dev/kvm nor /dev/dri: both are crw-rw---- owned
# by root:kvm / root:render, and the only grant is an ACL for the human user,
# which does not apply to the nixbld build users (the sandbox also drops
# supplementary groups). So a sandboxed run gets no GPU — meaning niri cannot
# render at all — and silently falls back to TCG emulation for want of KVM.
# The interactive driver runs as you, outside the sandbox, where the ACL
# applies and both devices are available — which is what the app in flake.nix
# wraps.
{ hostPkgs, ... }:
{
  name = "maxnix-desktop";

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../hosts/maxnix/configuration.nix
        ../modules/desktop
        ../modules/vm/qemu-guest.nix
      ];

      # The driver appends -nographic when it finds no DISPLAY in its own
      # environment, which would leave virtio-vga-gl without a GL-capable
      # backend and silently kill acceleration.
      # egl-headless keeps GL alive while leaving the framebuffer readable, and
      # -vnc is the only way to capture it: screendump (which backs the
      # driver's machine.screenshot() and get_screen_text()) fails with "Error:
      # no surface" on a GL scanout. These two flags go together — a gtk window
      # instead of egl-headless would make QEMU refuse -vnc entirely.
      virtualisation.qemu.options = [
        "-display egl-headless"
        "-vnc 127.0.0.1:9"
      ];

      # See the note in ./compositor.nix.
      users.users.root.initialPassword = lib.mkForce null;
    };

  testScript =
    { nodes, ... }:
    (import ./vnc.nix { inherit hostPkgs; })
    + ''
      start_all()

      with subtest("the system boots and the greeter is running"):
          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("greetd.service")

      with subtest("both compositors are installed"):
          machine.succeed("niri --version")
          # NOT `Hyprland --version`: it aborts with "XDG_RUNTIME_DIR is not
          # set" and dumps core. The driver's backdoor is a bare root shell
          # with no user session, and Hyprland demands a runtime dir even to
          # print its version. Presence on PATH is what this asks.
          machine.succeed("command -v Hyprland")

      with subtest("both register a session for the greeter to offer"):
          sessions = machine.succeed(
              "ls ${nodes.machine.services.displayManager.sessionData.desktops}/share/wayland-sessions/"
          )
          assert "niri.desktop" in sessions, sessions
          assert "hyprland.desktop" in sessions, sessions

      with subtest("the guest has a GPU with working virgl"):
          gpu = machine.succeed("gpu-check")
          machine.log(gpu)
          assert "virgl" in gpu.lower(), "no hardware acceleration:\n" + gpu

      with subtest("the greeter renders"):
          shot = vnc_capture(machine, "greeter")
          colours = unique_colours(shot)
          machine.log(f"greeter screen has {colours} distinct colours")
          # Threshold of 1, not the 50 the compositor tests use: tuigreet is a
          # text UI on the DRM console and legitimately draws in about three
          # colours. All this can prove is that the framebuffer is not a single
          # flat colour — i.e. something was drawn rather than nothing. A
          # stronger check would OCR the capture for "Username", at the cost of
          # OCR flakiness on console text.
          assert colours > 1, f"greeter screen is a single flat colour ({colours})"
    '';
}
