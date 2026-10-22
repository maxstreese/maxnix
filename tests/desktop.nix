# Compositor-agnostic checks: the machine boots, the greeter is up, niri is
# installed and the only session offered, and the guest GPU works.
#
# Deliberately has NO autologin, so this exercises the configuration exactly as
# committed. The niri session itself is tested in ./niri.nix.
#
# HOW TO RUN:
#
#   nix run .#test-desktop                    every subtest, needs a GPU
#   nix build .#checks.x86_64-linux.desktop   the portable subtests, sandboxed
#
# The two differ only in the `gpu` argument; see the gate further down.
#
# Why the split, and why the full suite is not a `nix build`:
#
#   KVM      a sandboxed build CAN use it, but only because /dev/kvm is mode
#            0666 on this host. Group membership does not work: the Nix
#            sandbox denies setgroups, so a build's supplementary groups are
#            dropped and only the `other` bits are reachable. That is also
#            why every CI recipe ships a udev rule rather than a group.
#   GPU      a sandboxed build CANNOT use it, at any permission. The sandbox
#            does not mount /sys, so Mesa cannot resolve the render node's
#            driver and eglInitialize fails even with the device world
#            readable. Measured 2026-09-21.
#
# So the GPU tier needs the interactive driver, which runs as you, outside the
# sandbox — that is what the app in flake.nix wraps. The portable tier has no
# such need and is an ordinary check.
{
  hostModules,
  gpu,
  ...
}:
{
  hostPkgs,
  lib,
  ...
}:
let
  # A stand-in for what mise downloads: a binary whose loader is the FHS path
  # and which carries no RPATH, so it finds neither its loader nor its
  # libraries unless nix-ld supplies both. Made from pigz because pigz needs
  # zlib, which only nix-ld's library list provides, and built locally so the
  # check needs no network. runCommand has no fixup phase, so nothing
  # re-patches it on the way into the store.
  foreignBinary = hostPkgs.runCommand "foreign-pigz" { } ''
    install -D -m 755 ${hostPkgs.pigz}/bin/pigz $out/bin/pigz
    ${lib.getExe hostPkgs.patchelf} --set-interpreter /lib64/ld-linux-x86-64.so.2 --remove-rpath $out/bin/pigz
  '';
in
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
    { lib, pkgs, ... }:
    {
      # The real machine, plus the virtual hardware. hostModules comes from
      # flake.nix so this node is the same definition `nix run .#vm` builds.
      imports = hostModules ++ [ ../modules/vm/qemu-guest.nix ];

      # Which virtio device the guest gets; see that module.
      maxnix.vm.gpu = gpu;

      # To drive a PAM service directly, as the lockout subtest does.
      environment.systemPackages = [ pkgs.pamtester ];

      # In the guest's store, but deliberately not on PATH.
      virtualisation.additionalPaths = [ foreignBinary ];

      # The driver appends -nographic when it finds no DISPLAY in its own
      # environment, which would leave virtio-vga-gl without a GL-capable
      # backend and silently kill acceleration.
      # egl-headless keeps GL alive while leaving the framebuffer readable, and
      # -vnc is the only way to capture it: screendump (which backs the
      # driver's machine.screenshot() and get_screen_text()) fails with "Error:
      # no surface" on a GL scanout. These two flags go together — a gtk window
      # instead of egl-headless would make QEMU refuse -vnc entirely.
      #
      # Both are pointless without GL, so with gpu = false the framework's own
      # -nographic is left alone.
      virtualisation.qemu.options = lib.optionals gpu [
        "-display egl-headless"
        "-vnc 127.0.0.1:9"
      ];

      # See the note in ./niri.nix.
      users.users.root.initialPassword = lib.mkForce null;

      # What uses the machine's sops secrets, off: a test node holds no key,
      # and sops-nix would fail to decrypt them at activation. The wiring is
      # tested where a key exists, in ./secrets.nix.
      maxnix.fleet.enable = lib.mkForce false;
      maxnix.harlequin.profiles.enable = lib.mkForce false;
      maxnix.backup.enable = lib.mkForce false;
    };

  testScript =
    { nodes, ... }:
    lib.optionalString gpu (import ./vnc.nix { inherit hostPkgs; })
    + ''
      start_all()

      with subtest("the system boots and the greeter is running"):
          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("greetd.service")

      with subtest("niri is installed"):
          machine.succeed("niri --version")

      with subtest("niri is the one session the greeter offers"):
          # Exactly one: Hyprland's two entries went with it on 2026-10-18,
          # and a session that reappears here (a module enabling a compositor
          # as a side effect) would be offered at login unconfigured.
          desktops = "${nodes.machine.services.displayManager.sessionData.desktops}/share/wayland-sessions"
          sessions = machine.succeed(f"ls {desktops}").split()
          assert sessions == ["niri.desktop"], sessions

      with subtest("the store is kept from growing without bound"):
          # Timers rather than the options that create them: an option set to
          # true that produced no unit would pass an option check and change
          # nothing on the machine.
          machine.succeed("systemctl is-enabled nix-gc.timer")
          machine.succeed("systemctl is-enabled nix-optimise.timer")
          # The collection is near-pointless without this flag — it would
          # remove build leftovers and never a generation, which is where the
          # space is. So assert the flag reached the thing that actually runs.
          #
          # That is NOT the unit file: NixOS compiles `script =` into its own
          # derivation and the unit only carries
          # `ExecStart=…/unit-script-nix-gc-start`. Asserting against
          # `systemctl cat` therefore fails even when the flag is set
          # correctly, which is how this was first written.
          unit = machine.succeed("systemctl cat nix-gc.service")
          start = [
              line.split("=", 1)[1]
              for line in unit.splitlines()
              if line.startswith("ExecStart=")
          ][0]
          gc = machine.succeed(f"cat {start}")
          assert "--delete-older-than 30d" in gc, gc
          # And the mid-build safety net, which is VM-shaped: the root image
          # is 16 GiB and one closure is 12.5 GiB.
          conf = machine.succeed("cat /etc/nix/nix.conf")
          assert "min-free = 1073741824" in conf, conf
          assert "max-free = 3221225472" in conf, conf

      with subtest("the daily-driver software is installed and wired up"):
          # One `command -v` per name, in a loop that exits on the first
          # miss. NOT `command -v a b c`: that reports only the first name it
          # resolves and returns 0, so such a check passes while every other
          # name is missing — which is how three of these assertions here sat
          # green while asserting almost nothing.
          def installed(progs, user):
              names = " ".join(progs)
              cmd = f"for b in {names}; do command -v $b || exit 1; done"
              # User-profile binaries are not on root's PATH, so the user's
              # own login shell has to resolve them.
              machine.succeed(f"su - max -c '{cmd}'" if user else cmd)

          # System profile: installed by NixOS modules, available before any
          # user logs in. git is here because the guest clones this repo with
          # it, before a user profile exists.
          installed(
              # nvd: both rebuild paths print a generation diff before
              # activating, so it has to be on the machine, not just in the
              # dev shell.
              ["git", "nvd", "1password", "op", "twingate", "wootility", "steam", "steam-run"],
              user=False,
          )

          # User profile: preferences, installed by Home Manager.
          installed(
              [
                  "firefox", "spotify", "slack", "discord", "claude", "ghostty",
                  # duckdb/kubectl/scala are the dev tools; delta is git's
                  # pager and fzf backs its `cleanup` alias, so a missing one
                  # of those two breaks git itself.
                  "duckdb", "kubectl", "scala", "marimo", "delta", "fzf",
                  "gh", "aws", "steampipe",
                  # `,` and nix-locate. Asserted by name because the whole
                  # point is that they are on PATH without being thought
                  # about; a silently missing `,` just looks like a typo.
                  ",", "nix-locate",
                  # direnv, which is what makes a project's own flake the
                  # source of its toolchain rather than this file.
                  "direnv",
              ],
              user=True,
          )

          # The point of installing marimo inside a python3.withPackages
          # environment rather than bare: a notebook can import the data
          # libraries. The bare package cannot, and fails only at run time.
          machine.succeed(
              "su - max -c 'python3 -c \"import marimo, polars, duckdb, altair, pyarrow, numpy\"'"
          )
          # direnv being on PATH says nothing about it being hooked into the
          # shell, and a direnv that never fires is indistinguishable from an
          # absent one. Both halves are asserted: the function that makes
          # `use flake` in ../.envrc a valid directive, and the shell hook
          # that runs direnv on every prompt.
          #
          # The path is direnv/lib/hm-nix-direnv.sh, not direnvrc: direnv
          # auto-loads every .sh under its lib directory, and home-manager
          # only writes direnvrc when programs.direnv.stdlib is set, which it
          # is not here. Asserting against direnvrc failed, which is how the
          # right path was found.
          machine.succeed(
              "grep -q use_flake /home/max/.config/direnv/lib/hm-nix-direnv.sh"
          )
          machine.succeed(
              "su max -c 'HOME=/home/max grep -q \"direnv hook bash\" ~/.bashrc'"
          )
          # mise, for the work repos, the same two halves: on PATH, and
          # hooked into the shell, since an unhooked mise never puts a repo's
          # pinned tools on PATH and the repo silently gets this profile's.
          installed(["mise"], user=True)
          machine.succeed(
              "su max -c 'HOME=/home/max grep -q \"mise.* activate bash\" ~/.bashrc'"
          )
          # What mise downloads are generic-linux binaries, and they run
          # only through nix-ld (modules/base/nix-ld.nix). Run as max from a
          # login shell, where mise's downloads would run, and with a library
          # (zlib) that only nix-ld's list provides.
          machine.succeed(
              "su - max -c 'echo foreign | ${foreignBinary}/bin/pigz | ${foreignBinary}/bin/pigz -d | grep -qx foreign'"
          )

          # The udev rules are what let a normal user talk to the keyboard;
          # without them wootility finds the device and cannot open it.
          machine.succeed("grep -rq 31e3 /etc/udev/rules.d/")
          # Chromium-based apps read this to pick Wayland; it travels through
          # PAM like the keyboard layout does.
          machine.succeed("grep -q '^NIXOS_OZONE_WL' /etc/pam/environment")
          # ssh is pointed at the 1Password agent socket. The file is Home
          # Manager's, so it exists only once the user's activation has run.
          machine.wait_for_unit("home-manager-max.service")
          machine.succeed("grep -q '1password/agent.sock' /home/max/.ssh/config")
          # A guest with no git identity cannot commit. Assert what git
          # resolves, not merely that a file exists.
          machine.succeed(
              "su max -c 'HOME=/home/max git config --global user.email' | grep -qx max@streese.com"
          )
          # Commit signing: the signer must exist as a real file (it is a
          # store path, so a wrong reference is a dangling symlink rather
          # than an error), and the allowed-signers file is what makes
          # verification work locally rather than only on the forge.
          machine.succeed(
              "test -x \"$(su max -c 'HOME=/home/max git config --global gpg.ssh.program')\""
          )
          machine.succeed(
              "grep -q 'namespaces=\"git\"' "
              "\"$(su max -c 'HOME=/home/max git config --global gpg.ssh.allowedSignersFile')\""
          )
          # The 1Password agent must be told which account a vault lives in;
          # both accounts have a vault called Private.
          machine.succeed("grep -q '^account = ' /home/max/.config/1Password/ssh/agent.toml")
          # Silencing marimo's update nag only works if the variable travels
          # the PAM route; Home Manager's home.sessionVariables would reach a
          # login shell and not a terminal window. There is no logged-in user
          # session in this test, so PAM's file is what can be checked here.
          machine.succeed("grep -q '^MARIMO_SKIP_UPDATE_CHECK' /etc/pam/environment")
          # Steam is a system module, not a package: without the 32-bit
          # graphics stack it installs but cannot draw.
          machine.succeed("test -e /run/opengl-driver-32/lib")
          # Vimium alongside 1Password, both force-installed by policy. Run
          # as max: firefox lives in the user profile, so root cannot resolve
          # it, and the policy file sits beside the binary in the store.
          machine.succeed(
              "su - max -c 'grep -q vimium-ff "
              "\"$(dirname \"$(readlink -f \"$(command -v firefox)\")\")\"/../lib/firefox/distribution/policies.json'"
          )
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

      with subtest("the observability stack runs on the whole machine"):
          # ../tests/observability.nix covers what it does, on nodes without
          # this machine's persistence. That gap hid a real failure: the
          # preserved /var/lib/loki came up root-owned and Loki could not
          # start. So here, on the full machine, every store must be up and
          # its data directory owned by its service.
          for unit in ["alloy", "prometheus", "loki", "tempo", "grafana"]:
              machine.wait_for_unit(f"{unit}.service")
          for path, owner in [("/var/lib/prometheus2", "prometheus"),
                              ("/var/lib/loki", "loki"),
                              ("/var/lib/grafana", "grafana")]:
              got = machine.succeed(f"stat -c %U {path}").strip()
              assert got == owner, f"{path} owned by {got}, not {owner}"

      with subtest("NetworkManager runs alone, and max can add a connection it keeps"):
          # ../hosts/t14s/configuration.nix: NetworkManager rather than
          # the scripted networking, and no dhcpcd beside it.
          machine.wait_for_unit("NetworkManager.service")
          machine.fail("systemctl is-active dhcpcd.service")
          # Joined as max, not root: the networkmanager group is what lets
          # DMS's widget and nmcli save a network without a prompt.
          machine.succeed("runuser -u max -- nmcli connection add type dummy"
                          " ifname probe0 con-name probe")
          # Saved where ../modules/metal/persistence.nix keeps it, root-only.
          path = "/etc/NetworkManager/system-connections/probe.nmconnection"
          mode = machine.succeed(f"stat -c '%a %U' {path}").strip()
          assert mode == "600 root", f"{path} is {mode}"
          machine.succeed("runuser -u max -- nmcli connection delete probe")
          machine.fail(f"test -e {path}")

      with subtest("the laptop services answer, the way DMS's widgets ask them"):
          # ../hosts/t14s/laptop.nix, over the system bus: what Quickshell's
          # UPower service and DMS's power widget read. In a VM there is no
          # battery and only a placeholder power driver, so this checks that
          # each service answers, not what it reports.
          def bus(args):
              return machine.succeed(f"busctl --system {args}").strip()
          profile = bus("get-property org.freedesktop.UPower.PowerProfiles"
                        " /org/freedesktop/UPower/PowerProfiles"
                        " org.freedesktop.UPower.PowerProfiles ActiveProfile")
          assert profile == 's "balanced"', profile
          bus("call org.freedesktop.UPower /org/freedesktop/UPower"
              " org.freedesktop.UPower EnumerateDevices")
          bus("get-property org.freedesktop.fwupd / org.freedesktop.fwupd DaemonVersion")
          # Real-time audio: the greeter's PipeWire asks rtkit for it as it
          # starts. Granted, rather than the "RTKit error: ... ServiceUnknown"
          # every boot logged before rtkit was on.
          machine.wait_until_succeeds(
              "journalctl -b -u rtkit-daemon | grep -q 'owned by .* RT at priority'", timeout=120)
          machine.fail("journalctl -b | grep -q 'RTKit error'")

      with subtest("swap is compressed RAM, and nothing on disk"):
          # ../hosts/t14s/configuration.nix: zram with zstd, no swap
          # partition or file — hibernation is left for the hardware.
          swaps = machine.succeed("swapon --show=NAME,TYPE --noheadings").split("\n")
          swaps = [s.split() for s in swaps if s.strip()]
          assert swaps and all(n.startswith("/dev/zram") for n, _ in swaps), swaps
          algo = machine.succeed("cat /sys/block/zram0/comp_algorithm")
          assert "[zstd]" in algo, algo

      with subtest("ten wrong passwords lock the account, at the console and the lock screen"):
          # ../modules/base/login-limits.nix, through the stacks as built:
          # login (the consoles, and the greeter by substack) and dankshell
          # (DMS's lock screen). The VM's password is the plaintext one from
          # ../modules/vm/qemu-guest.nix.
          def tries(service, password):
              return machine.execute(
                  f"printf '%s\\n' '{password}' | pamtester {service} max authenticate")[0]

          for service in ["login", "dankshell"]:
              assert tries(service, "maxnix") == 0, f"{service}: the right password is refused"
          for _ in range(10):
              assert tries("login", "not-the-password") != 0
          # Locked: the right password no longer gets through either way in.
          for service in ["login", "dankshell"]:
              assert tries(service, "maxnix") != 0, f"{service}: still open after ten failures"
          # Counted where ../modules/metal/persistence.nix keeps it, not in
          # faillock's tmpfs default.
          tally = machine.succeed("faillock --user max")
          failures = machine.succeed("faillock --user max | grep -c ' V$'").strip()
          assert failures == "10", f"faillock counted {failures}:\n{tally}"
          machine.succeed("test -s /var/lib/faillock/max")
          # And the way back short of waiting.
          machine.succeed("faillock --user max --reset")
          for service in ["login", "dankshell"]:
              assert tries(service, "maxnix") == 0, f"{service}: still locked after a reset"
    ''
    # Everything past here looks at the screen, which needs a real GPU:
    # without virgl the greeter never draws and gpu-check reports no
    # acceleration. See ../modules/vm/qemu-guest.nix for the measurement.
    + lib.optionalString gpu ''

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
