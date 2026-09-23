# Integration test for one compositor: log straight into it, then check that it
# claims the GPU, drives the virtual display, and actually draws something.
#
# Parameterised because niri and Hyprland differ only in how you ask them what
# they are doing. Instantiated once per compositor in flake.nix.
#
# HOW TO RUN:
#   nix run .#test-niri                    every subtest, needs a GPU
#   nix build .#checks.x86_64-linux.niri   the portable subtests, sandboxed
# and the same two for hyprland. See tests/desktop.nix for why the GPU tier
# cannot be a sandboxed build.
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

      # Drives which virtio device the guest gets; see that module. With it
      # off every subtest that looks at the screen is skipped below.
      maxnix.vm.gpu = compositor.gpu;

      # The driver appends -nographic when it finds no DISPLAY in its own
      # environment, which would leave virtio-vga-gl without a GL-capable
      # backend and silently kill acceleration.
      # egl-headless keeps GL alive while leaving the framebuffer readable, and
      # -vnc is the only way to capture it: screendump (which backs the
      # driver's machine.screenshot() and get_screen_text()) fails with "Error:
      # no surface" on a GL scanout. These two flags go together — a gtk window
      # instead of egl-headless would make QEMU refuse -vnc entirely.
      #
      # Both are pointless without GL — egl-headless needs a host render node,
      # and there is no GL scanout to capture — so with gpu = false the
      # framework's own -nographic is left alone.
      virtualisation.qemu.options = lib.optionals compositor.gpu [
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

  # Two tiers, and the split is measured rather than guessed.
  #
  # Anything that inspects the screen, or that is downstream of the
  # compositor having an output at all, needs a real GPU: without virgl the
  # compositor starts and serves its IPC but enumerates nothing and draws
  # nothing (see ../modules/vm/qemu-guest.nix). Those subtests sit behind
  # `compositor.gpu`, so this same test also runs on a machine with no GPU,
  # which is what CI is.
  #
  # Measured 2026-09-21 with gpu = false: the IPC socket appears, and
  # `niri msg outputs` succeeds but returns empty. The portable tier is
  # therefore the two subtests that only talk to the IPC. Everything else is
  # gated, DMS and the client window included: neither was measured without
  # a GPU, and both are downstream of having a surface to draw on, so they
  # are classed with the screen assertions rather than assumed to work.
  testScript =
    lib.optionalString compositor.gpu (import ./vnc.nix { inherit hostPkgs; })
    + ''
      start_all()
      machine.wait_for_unit("multi-user.target")

      with subtest("${compositor.name} comes up and exposes its IPC"):
          # Waiting on the IPC socket rather than pgrep on purpose: Hyprland's
          # process name is the wrapper (.Hyprland-wrapped, truncated to 15
          # chars in comm), so `pgrep -x Hyprland` finds nothing. The IPC
          # appearing is also the more meaningful signal.
          machine.wait_until_succeeds("${compositor.ipcReady}")

    ''
    + lib.optionalString (compositor.binds != null) ''

      with subtest("${compositor.name} registered the shared bindings"):
          # Asks the compositor what it actually bound, rather than trusting
          # that a config it accepted means what it says.
          #
          # This is the failure mode worth guarding: a key name the compositor
          # cannot resolve is not fatal. It logs, if anything, and carries on
          # with one bind silently missing — the compositor still starts, the
          # IPC still answers, and every other assertion here still passes.
          # The repo has a whole class of dead binds from exactly that —
          # though under a Lua config `checks.hyprland-config` now rejects an
          # unknown keysym at build time, so this is no longer the only guard
          # against it (the calibration is in flake.nix). What a parse still
          # cannot show is what this subtest is for: that the compositor
          # really starts with this config, registers every bind, and keeps
          # the flags, none of which --verify-config reports.
          #
          # Matched on modifiers and key rather than on the command, because
          # under a Lua config the command is not in the IPC output at all:
          # every bind reports `dispatcher: __lua` and an opaque `arg: N`.
          # The old assertion looked for "spotlight" in this output and would
          # now be checking a string that can never appear.
          import json, re

          registered = machine.succeed("${compositor.binds}")
          machine.log(registered)

          actual, kind, modmask = set(), None, None
          for line in registered.splitlines():
              entry = line.strip()
              if re.fullmatch(r"bind[a-z]*", entry):
                  kind, modmask = entry, None
              elif entry.startswith("modmask:"):
                  modmask = int(entry.split(":", 1)[1])
              elif entry.startswith("key:") and kind is not None:
                  actual.add((kind, modmask, entry.split(":", 1)[1].strip()))

          # Derived from home/max/binds.nix in flake.nix, so it cannot drift
          # from the shared list: add a binding there and it is asserted here
          # without touching this file. The kind carries the flags, so
          # `bindle` also asserts that locked and repeating survived.
          expected = {tuple(row) for row in json.loads(r"""${compositor.expectBinds}""")}
          missing = expected - actual
          assert not missing, (
              f"declared in binds.nix but not registered: {sorted(missing)}\n\n"
              + registered
          )

          # And that nothing was dropped outside the shared list either: the
          # window-management binds are Hyprland's own and not in binds.nix.
          # Counted from the generated config rather than hardcoded, so this
          # stays honest as bindings are added or removed.
          declared = int(machine.succeed("${compositor.declaredBinds}").strip())
          assert len(actual) == declared, (
              f"config declares {declared} bindings, compositor registered "
              f"{len(actual)}\n\n" + registered
          )
    ''
    + ''

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
    ''
    + lib.optionalString compositor.gpu ''

      with subtest("${compositor.name} drives the virtual display"):
          outputs = machine.succeed("${compositor.outputs}")
          machine.log(outputs)
          assert "Virtual-1" in outputs, (
              "${compositor.name} enumerated no output:\n" + outputs
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
    + lib.optionalString (compositor.gpu && compositor.appUnit != null) ''

      # The terminal must be running as a systemd unit of its own, not as
      # a child inside the compositor's — that is the point of ghostty's
      # D-Bus service and, on Hyprland, of `uwsm app --` in the binds.
      units = machine.wait_until_succeeds(
          "su max -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user list-units --plain --no-legend \"${compositor.appUnit}\"' | grep -E 'active +running'"
      )
      machine.log(units)
    ''
    + lib.optionalString compositor.gpu ''

      # 3000 sits well above a bare compositor with one terminal (measured
      # 533-545) and well below DankMaterialShell once it has drawn its bar
      # and wallpaper (~6500). So this asserts the whole stack is on screen,
      # not merely that the compositor is not black.
      wait_for_rich_screen(machine, "${compositor.name}-session", minimum=3000)
    '';
}
