# Integration test for one compositor: log straight into it, then check that it
# claims the GPU, drives the virtual display, and actually draws something.
#
# Parameterised because niri and Hyprland differ only in how you ask them what
# they are doing. Instantiated once per compositor in flake.nix.
#
# HOW TO RUN — the sandboxed path does not work, see tests/desktop.nix:
#   nix run .#test-niri
#   nix run .#test-hyprland
compositor:
{ hostPkgs, lib, ... }:
{
  name = "maxnix-${compositor.name}";

  # The framework hands every node a prebuilt, read-only pkgs, and then any
  # module touching nixpkgs.* fails with "defined multiple times". This
  # machine's modules do touch it — modules/desktop/onepassword.nix adds to
  # nixpkgs.config.allowUnfreePackages — so let the node build its own pkgs
  # from those options instead, exactly as `nix run .#vm` does. Costs one
  # extra nixpkgs evaluation per test; buys a node that cannot diverge from
  # the real machine in what it is allowed to install.
  node.pkgsReadOnly = false;

  nodes.machine =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # The greeter would read Exec= out of this very file and hand it to
      # greetd. Do the same, at runtime, so the test launches exactly what a
      # login does — including uwsm for Hyprland — and cannot drift from the
      # session file if its Exec changes.
      desktops = config.services.displayManager.sessionData.desktops;
      runSession = pkgs.writeShellScript "run-${compositor.session}-session" ''
        entry="${desktops}/share/wayland-sessions/${compositor.session}.desktop"
        exec $(sed -n 's/^Exec=//p' "$entry")
      '';
    in
    {
      # The real machine, plus the virtual hardware. hostModules comes from
      # flake.nix so this node is the same definition `nix run .#vm` builds.
      imports = compositor.hostModules ++ [ ../modules/vm/qemu-guest.nix ];

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

      # Skip the greeter and land in a session, so a failure here is a
      # compositor failure rather than a greeter-typing failure. The greeter
      # itself is covered by tests/desktop.nix.
      services.greetd.settings.initial_session = {
        command = "${runSession}";
        user = "max";
      };

      # The test framework gives root a hashedPasswordFile for its backdoor
      # console, which collides with the initialPassword our host config sets
      # and emits a precedence warning. The file wins either way; drop ours so
      # the intent is explicit rather than accidental.
      users.users.root.initialPassword = lib.mkForce null;
    };

  testScript =
    (import ./vnc.nix { inherit hostPkgs; })
    + ''
      start_all()
      machine.wait_for_unit("multi-user.target")

      with subtest("${compositor.name} comes up and exposes its IPC"):
          # Waiting on the IPC socket rather than pgrep on purpose: Hyprland's
          # process name is the wrapper (.Hyprland-wrapped, truncated to 15
          # chars in comm), so `pgrep -x Hyprland` finds nothing. The IPC
          # appearing is also the more meaningful signal.
          machine.wait_until_succeeds("${compositor.ipcReady}")

      with subtest("${compositor.name} drives the virtual display"):
          outputs = machine.succeed("${compositor.outputs}")
          machine.log(outputs)
          assert "Virtual-1" in outputs, (
              "${compositor.name} enumerated no output:\n" + outputs
          )

      with subtest("${compositor.name} uses the configured keyboard layout"):
          # Asserts the *observable* layout rather than that the input was set.
          # XKB_DEFAULT_LAYOUT=de reaches both compositors' environments, but
          # Hyprland ignores it (its kb_layout defaults to "us"), so checking
          # the variable would have passed while the keyboard was still US.
          #
          # "German" is xkb's description for layout "de", set once in
          # hosts/maxnix/configuration.nix. If you change that layout, this
          # string changes with it.
          layout = machine.succeed("${compositor.layout}")
          machine.log(layout)
          assert "German" in layout, (
              "${compositor.name} is not on the configured layout:\n" + layout
          )

      with subtest("${compositor.name} starts the DankMaterialShell service"):
          # DMS is started from the session target, not by a spawn line in the
          # compositor config, so this also checks that the compositor actually
          # reaches graphical-session.target.
          machine.wait_until_succeeds(
              "su max -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user is-active dms'"
          )

      with subtest("${compositor.name} renders a client window"):
          # Launch a normal Wayland client against the compositor's socket,
          # rather than going through the compositor's own IPC.
          #
          # `hyprctl dispatch exec` would have been the obvious route, but
          # Hyprland 0.56 moved dispatchers to a Lua API and the old form now
          # fails with:
          #   error: [string "return hl.dispatch(exec kitty)"]:1: ')' expected
          #   → Note: dispatch in lua is a shorthand for hl.dispatch(...)
          # and hl.dsp.exec is nil, so the replacement spelling is a moving
          # target. Starting the client ourselves is compositor-agnostic,
          # immune to that churn, and a better test anyway: it exercises a real
          # client connecting to a real Wayland socket.
          machine.succeed(
              """su max -c 'export XDG_RUNTIME_DIR=/run/user/1000; """
              """export WAYLAND_DISPLAY=$(cd "$XDG_RUNTIME_DIR" && ls -1 wayland-[0-9] | head -1); """
              """nohup ${compositor.launch} >/tmp/client.log 2>&1 &'"""
          )
          # Bounded wait, and on failure show what the client and its service
          # said — a terminal that never appears otherwise fails as a silent
          # fifteen-minute timeout. Match on the command line, not the process
          # name: like Hyprland, ghostty runs through a Nix wrapper whose comm
          # is truncated to `.ghostty-wrappe`, so `pgrep -x ghostty` finds
          # nothing even while the window is on screen.
          try:
              machine.wait_until_succeeds("pgrep -u max -f 'bin/ghostt[y]'", timeout=120)
          except Exception:
              machine.log(machine.succeed("cat /tmp/client.log || true"))
              machine.log(machine.succeed(
                  "su max -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user status app-com.mitchellh.ghostty.service --no-pager -l' || true"
              ))
              machine.log(machine.succeed("journalctl -b --no-pager _UID=1000 | tail -n 60"))
              raise
    ''
    + lib.optionalString (compositor.appUnit != null) ''

          # The terminal must be running as a systemd unit of its own, not as
          # a child inside the compositor's — that is the point of ghostty's
          # D-Bus service and, on Hyprland, of `uwsm app --` in the binds.
          units = machine.wait_until_succeeds(
              "su max -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user list-units --plain --no-legend \"${compositor.appUnit}\"' | grep -E 'active +running'"
          )
          machine.log(units)
    ''
    + ''

          # 3000 sits well above a bare compositor with one terminal (measured
          # 533-545) and well below DankMaterialShell once it has drawn its bar
          # and wallpaper (~6500). So this asserts the whole stack is on screen,
          # not merely that the compositor is not black.
          wait_for_rich_screen(machine, "${compositor.name}-session", minimum=3000)
    '';
}
