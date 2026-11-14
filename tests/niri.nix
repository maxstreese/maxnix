# Integration test for the niri session: log straight into it, then check that
# it claims the GPU, drives the virtual display, and actually draws something.
#
# This was tests/compositor.nix, parameterised over niri and Hyprland, which
# differed only in how you ask them what they are doing. With Hyprland gone
# (2026-10-18) niri's answers are written in directly.
#
# HOW TO RUN:
#   nix run .#test-niri                    every subtest, needs a GPU
#   nix build .#checks.x86_64-linux.niri   the portable subtests, sandboxed
# See tests/desktop.nix for why the GPU tier cannot be a sandboxed build.
#
# No subtest asks niri which binds it registered: niri has no IPC for that
# (`niri msg binds` is not a subcommand), and needs none. The home-manager
# module runs `niri validate` while building config.kdl, so an unusable key
# fails the *build* with "error loading config" — checked by injecting a bogus
# keysym. Hyprland, while it ran here, accepted such a config and needed a
# runtime assertion on `hyprctl binds`.
{ hostModules, gpu }:
{ hostPkgs, lib, ... }:
let
  # niri's IPC socket, which the driver's bare root shell has to be pointed at.
  niriSocket = "NIRI_SOCKET=$(ls /run/user/1000/niri.wayland-*.sock | head -1)";

  # The weekly firmware check (../hosts/t14s/firmware-check.nix), built around
  # stand-ins: a fwupdmgr that answers `get-updates` with the given text and
  # exit status, and a notify-send that writes its arguments to
  # /tmp/notified. The guest has no firmware devices and no LVFS, and what
  # the script can get wrong is how it reads fwupdmgr.
  firmwareCheckWith =
    { answer, status }:
    hostPkgs.callPackage ../hosts/t14s/firmware-check.nix {
      fwupd = hostPkgs.writeShellScriptBin "fwupdmgr" ''
        case "$1" in
          refresh) exit 2 ;;
          get-updates) cat ${hostPkgs.writeText "fwupdmgr-answer" answer}; exit ${toString status} ;;
        esac
      '';
      libnotify = hostPkgs.writeShellScriptBin "notify-send" ''
        printf '%s\n' "$@" > /tmp/notified
      '';
    };
  # The shape of `fwupdmgr get-updates --json` (fwupd 2.0, 2026-11-10): one
  # device with releases, newest first, and one without.
  firmwareCheck = {
    updates = firmwareCheckWith {
      status = 0;
      answer = builtins.toJSON {
        Devices = [
          {
            Name = "System Firmware";
            Version = "0.1.18";
            Releases = [
              { Version = "0.1.37"; }
              { Version = "0.1.36"; }
            ];
          }
          {
            Name = "UEFI dbx";
            Version = "20230501";
          }
        ];
      };
    };
    # What fwupdmgr does when no device has one: says so and exits 2.
    none = firmwareCheckWith {
      status = 2;
      answer = "No updates available";
    };
    # A device list in which nothing has a release.
    noReleases = firmwareCheckWith {
      status = 0;
      answer = builtins.toJSON {
        Devices = [
          {
            Name = "UEFI dbx";
            Version = "20230501";
          }
        ];
      };
    };
  };
in
{
  name = "maxnix-niri";

  # The framework hands every node a prebuilt, read-only pkgs, and then any
  # module touching nixpkgs.* fails with "defined multiple times". This
  # machine's modules do touch it — modules/gui/onepassword.nix adds to
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
      # login does and cannot drift from the session file if its Exec
      # changes.
      desktops = config.services.displayManager.sessionData.desktops;
      runSession = pkgs.writeShellScript "run-niri-session" ''
        entry="${desktops}/share/wayland-sessions/niri.desktop"
        exec $(sed -n 's/^Exec=//p' "$entry")
      '';
    in
    {
      # The real machine, plus the virtual hardware. hostModules comes from
      # flake.nix so this node is the same definition `nix run .#vm` builds.
      imports = hostModules ++ [ ../modules/vm/qemu-guest.nix ];

      # Drives which virtio device the guest gets; see that module. With it
      # off every subtest that looks at the screen is skipped below.
      maxnix.vm.gpu = gpu;

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
      virtualisation.qemu.options = lib.optionals gpu [
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

      # The firmware check's test builds, in the guest's store and not on
      # PATH.
      virtualisation.additionalPaths = lib.attrValues firmwareCheck;

      # The test framework gives root a hashedPasswordFile for its backdoor
      # console, which collides with the initialPassword our host config sets
      # and emits a precedence warning. The file wins either way; drop ours so
      # the intent is explicit rather than accidental.
      users.users.root.initialPassword = lib.mkForce null;

      # What uses the machine's sops secrets, off: a test node holds no key,
      # and sops-nix would fail to decrypt them at activation. The wiring is
      # tested where a key exists, in ./secrets.nix.
      maxnix.fleet.enable = lib.mkForce false;
      maxnix.harlequin.profiles.enable = lib.mkForce false;
      maxnix.backup.enable = lib.mkForce false;
      # No sops key on a test node: Grafana generates its password here.
      maxnix.observability.grafanaAdminPasswordFromSops = lib.mkForce false;
    };

  # Two tiers, and the split is measured rather than guessed.
  #
  # Anything that inspects the screen, or that is downstream of the
  # compositor having an output at all, needs a real GPU: without virgl the
  # compositor starts and serves its IPC but enumerates nothing and draws
  # nothing (see ../modules/vm/qemu-guest.nix). Those subtests sit behind
  # `gpu`, so this same test also runs on a machine with no GPU,
  # which is what CI is.
  #
  # Measured 2026-09-21 with gpu = false: the IPC socket appears, and
  # `niri msg outputs` succeeds but returns empty. The portable tier is
  # therefore the two subtests that only talk to the IPC. Everything else is
  # gated, DMS and the client window included: neither was measured without
  # a GPU, and both are downstream of having a surface to draw on, so they
  # are classed with the screen assertions rather than assumed to work.
  testScript =
    lib.optionalString gpu (import ./vnc.nix { inherit hostPkgs; })
    + ''
      start_all()
      machine.wait_for_unit("multi-user.target")

      with subtest("niri comes up and exposes its IPC"):
          # Waiting on the IPC socket rather than pgrep on purpose: the IPC
          # appearing is the more meaningful signal, and a Nix-wrapped
          # program's process name is its wrapper's (see ghostty below).
          machine.wait_until_succeeds("ls /run/user/1000/niri.wayland-*.sock")

      with subtest("niri uses the configured keyboard layout"):
          # Asserts the *observable* layout rather than that the input was set.
          # XKB_DEFAULT_LAYOUT=de reached Hyprland's environment too, while it
          # ran here, and Hyprland ignored it (its kb_layout defaults to "us"),
          # so checking the variable would have passed on a US keyboard.
          #
          # "German" is xkb's description for layout "de", set once in
          # modules/base/default.nix. If you change that layout, this
          # string changes with it.
          layout = machine.succeed("${niriSocket} niri msg keyboard-layouts")
          machine.log(layout)
          assert "German" in layout, (
              "niri is not on the configured layout:\n" + layout
          )

      with subtest("max's session checks for firmware updates weekly, and notifies only when there are any"):
          # ../hosts/t14s/laptop.nix. The timer, in max's session: a user
          # unit, so it is asked of his manager and not the system's.
          machine.succeed(
              "su max -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user is-active firmware-check.timer'"
          )
          # The script, around stand-ins (see firmwareCheckWith above). With
          # an update: one notification, naming the device and both versions,
          # and not the device that has none.
          machine.succeed("rm -f /tmp/notified; ${firmwareCheck.updates}/bin/firmware-check")
          notified = machine.succeed("cat /tmp/notified")
          assert "System Firmware: 0.1.18 → 0.1.37" in notified, notified
          assert "UEFI dbx" not in notified, notified
          assert "fwupdmgr update" in notified, notified
          # Without: fwupdmgr's exit 2, and a device list with no release.
          # Both succeed and say nothing.
          for build in ["${firmwareCheck.none}", "${firmwareCheck.noReleases}"]:
              machine.succeed(f"rm -f /tmp/notified; {build}/bin/firmware-check")
              machine.fail("test -e /tmp/notified")
    ''
    + lib.optionalString gpu ''

      with subtest("niri drives the virtual display"):
          outputs = machine.succeed("${niriSocket} niri msg outputs")
          machine.log(outputs)
          assert "Virtual-1" in outputs, (
              "niri enumerated no output:\n" + outputs
          )

      with subtest("niri starts the Dux Modular Shell service"):
          # DMS is started from the session target, not by a spawn line in the
          # compositor config, so this also checks that the compositor actually
          # reaches graphical-session.target.
          machine.wait_until_succeeds(
              "su max -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user is-active dms'"
          )

      with subtest("niri gives DMS its calendar from Dux Calendar"):
          # ../home/max/desktop/dms.nix: Dux Calendar's daemon starts with the
          # session, and DMS — which prefers it over khal, deliberately not
          # installed — connects to its socket. DMS looks for a calendar only
          # once one is shown, not at start: in the VM the handshake came the
          # moment the dashboard opened (2026-10-15): its calendar card, on
          # the Overview tab, is the first thing to use DMS's CalendarService,
          # which only then starts looking. So open that tab, as a click on
          # the clock would, and wait for DMS's own line saying it connected.
          # The tab is required: `dash open` without one exits 0 having
          # opened nothing, so its answer is checked, not its status.
          # Accounts are runtime state and none exist here. Each wait has a
          # timeout of its own: the driver's default is 15 minutes, which is
          # how long the first run with dcal broken took to say so.
          user = "su max -c 'XDG_RUNTIME_DIR=/run/user/1000 "
          machine.wait_until_succeeds(user + "systemctl --user is-active dcal'", timeout=60)
          machine.wait_until_succeeds(
              user + "dms ipc call dash open overview' | grep -q DASH_OPEN_SUCCESS",
              timeout=60)
          machine.wait_until_succeeds(
              "journalctl -b | grep -q 'connected to dankcal'", timeout=120)

      with subtest("niri renders a client window"):
          # Launch a normal Wayland client against the compositor's socket,
          # rather than going through the compositor's own IPC. Started by
          # hand since Hyprland 0.56 broke `hyprctl dispatch exec`, and the
          # better test anyway: it exercises a real client connecting to a
          # real Wayland socket.
          machine.succeed(
              """su max -c 'export XDG_RUNTIME_DIR=/run/user/1000; """
              """export WAYLAND_DISPLAY=$(cd "$XDG_RUNTIME_DIR" && ls -1 wayland-[0-9] | head -1); """
              """nohup ghostty +new-window >/tmp/client.log 2>&1 &'"""
          )
          # Bounded wait, and on failure show what the client and its service
          # said — a terminal that never appears otherwise fails as a silent
          # fifteen-minute timeout. Match on the command line, not the process
          # name: ghostty runs through a Nix wrapper whose comm
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

      # The terminal must be running as a systemd unit of its own, not as
      # a child inside the compositor's — that is the point of ghostty's
      # D-Bus service. Even a client started by hand, as above, opens its
      # window from that service, so it lands in that unit.
      units = machine.wait_until_succeeds(
          "su max -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user list-units --plain --no-legend \"app-com.mitchellh.ghostty.service\"' | grep -E 'active +running'"
      )
      machine.log(units)

      # 3000 sits well above a bare compositor with one terminal (measured
      # 533-545) and well below Dux Modular Shell once it has drawn its bar
      # and wallpaper (~6500). So this asserts the whole stack is on screen,
      # not merely that the compositor is not black.
      wait_for_rich_screen(machine, "niri-session", minimum=3000)

      with subtest("locking the screen is a real lock, and takes 1Password with it"):
          user = "su max -c 'XDG_RUNTIME_DIR=/run/user/1000 "
          # ../modules/desktop/lock-screen.nix: the policy file is only worth
          # something if `dms run` hands it to the shell, so read it off the
          # shell's own environment rather than off /etc.
          policy = machine.succeed(
              # `|| true`: a process that exits mid-scan makes grep report an
              # error, and the driver runs this with pipefail.
              "(grep -z -h '^DMS_POLICY_LOCK_SETTINGS=' /proc/[0-9]*/environ 2>/dev/null || true)"
              " | tr '\\0' '\\n' | sort -u")
          assert '"lockBeforeSuspend":true' in policy, policy
          assert '"loginctlLockIntegration":true' in policy, policy

          # ../home/max/desktop/lock.nix. The hint is what DMS sets once the
          # lock surface is secure, so waiting for it is waiting for a lock
          # that holds, not for the request to have been made.
          locked = (
              "for s in $(loginctl list-sessions --no-legend | awk '$3 == \"max\" {print $1}'); do "
              "loginctl show-session $s -p LockedHint --value; done | grep -qx "
          )
          machine.wait_until_succeeds(user + "systemctl --user is-active lock-1password'", timeout=60)
          machine.succeed(locked + "no")
          machine.succeed(user + "dms ipc call lock lock'")
          machine.wait_until_succeeds(locked + "yes", timeout=60)
          # 1Password is installed and not running here, and saying so is the
          # listener having seen the lock and reached the app's turn. That it
          # locks a signed-in app is seen by hand: there is no account here.
          machine.wait_until_succeeds(
              "journalctl -b _SYSTEMD_USER_UNIT=lock-1password.service | grep -q 'screen locked: '",
              timeout=60)
          # And back, so a later subtest finds the session as this one did.
          machine.succeed(user + "dms ipc call lock unlock'")
          machine.wait_until_succeeds(locked + "no", timeout=60)
    '';
}
