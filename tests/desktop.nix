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
{ hostModules, ... }:
{ hostPkgs, ... }:
{
  name = "maxnix-desktop";

  # The framework hands every node a prebuilt, read-only pkgs, and then any
  # module touching nixpkgs.* fails with "defined multiple times". This
  # machine's modules do touch it — modules/desktop/onepassword.nix adds to
  # nixpkgs.config.allowUnfreePackages — so let the node build its own pkgs
  # from those options instead, exactly as `nix run .#vm` does. Costs one
  # extra nixpkgs evaluation per test; buys a node that cannot diverge from
  # the real machine in what it is allowed to install.
  node.pkgsReadOnly = false;

  nodes.machine =
    { lib, ... }:
    {
      # The real machine, plus the virtual hardware. hostModules comes from
      # flake.nix so this node is the same definition `nix run .#vm` builds.
      imports = hostModules ++ [ ../modules/vm/qemu-guest.nix ];

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
          desktops = "${nodes.machine.services.displayManager.sessionData.desktops}/share/wayland-sessions"
          sessions = machine.succeed(f"ls {desktops}")
          assert "niri.desktop" in sessions, sessions
          # The package ships two Hyprland entries; the UWSM-managed one is
          # the session meant to be used, so it is the one asserted on.
          assert "hyprland-uwsm.desktop" in sessions, sessions
          entry = machine.succeed(f"cat {desktops}/hyprland-uwsm.desktop")
          assert "uwsm start" in entry, entry

      with subtest("1Password, Firefox, Spotify and Claude Code are installed and wired up"):
          machine.succeed("command -v 1password op firefox spotify claude")
          # Chromium-based apps read this to pick Wayland; it travels through
          # PAM like the keyboard layout does.
          machine.succeed("grep -q '^NIXOS_OZONE_WL' /etc/pam/environment")
          # The extension only ever connects if the wrapped Firefox's real
          # executable name is on 1Password's allow-list. Asserting the file's
          # content, not merely its presence: an empty file is the failure
          # mode this guards against.
          machine.succeed("grep -qx .firefox-wrapped /etc/1password/custom_allowed_browsers")
          # Keyring unlock at login is a PAM stack detail nothing else surfaces.
          # greetd delegates to `login` via substack, and `login` carries the
          # keyring module — both halves of that chain are asserted.
          machine.succeed("grep -q pam_gnome_keyring /etc/pam.d/login")
          machine.succeed("grep -Eq '^auth[[:space:]]+substack[[:space:]]+login' /etc/pam.d/greetd")

      with subtest("the guest has a GPU with working virgl"):
          gpu = machine.succeed("gpu-check")
          machine.log(gpu)
          assert "virgl" in gpu.lower(), "no hardware acceleration:\n" + gpu

      with subtest("the greeter renders"):
          # Dank Greeter is a Quickshell UI hosted in niri, so this is a real
          # graphical screen: measured at ~5300-5700 colours once drawn, and
          # exactly 1 before that. The old tuigreet greeter was a text console
          # drawing in three colours, which is why this check used to assert
          # `> 1` — that threshold would now pass on a blank screen.
          #
          # Polling rather than a fixed wait, for the same reason as the
          # compositor tests: the greeter needs tens of seconds to appear and a
          # single early capture caught a flat black frame.
          #
          # This has failed intermittently — a flat black screen for the whole
          # timeout, roughly one run in five — and both times the console log
          # was not kept. So on failure, dump what greetd and the greeter's
          # compositor logged before re-raising, to make the next one count.
          try:
              wait_for_rich_screen(machine, "greeter", minimum=3000)
          except AssertionError:
              machine.log(machine.succeed(
                  "journalctl -b --no-pager -u greetd.service | tail -n 80"
              ))
              machine.log(machine.succeed(
                  "journalctl -b --no-pager _COMM=niri _COMM=dms-greeter _COMM=quickshell | tail -n 80 || true"
              ))
              raise
    '';
}
