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
{ hostPkgs, ... }:
{
  name = "maxnix-${compositor.name}";

  nodes.machine =
    { lib, ... }:
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
        command = compositor.session;
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
              """nohup alacritty >/tmp/client.log 2>&1 &'"""
          )
          machine.wait_until_succeeds("pgrep -u max -f alacrit[t]y")
          machine.sleep(8)
          shot = vnc_capture(machine, "${compositor.name}-session")
          colours = unique_colours(shot)
          machine.log(f"screen has {colours} distinct colours")
          assert colours > 50, (
              f"only {colours} distinct colours - the compositor drew nothing. "
              "An empty Hyprland workspace is solid black, so this is exactly "
              "the case a file-size check would wave through."
          )
    '';
}
