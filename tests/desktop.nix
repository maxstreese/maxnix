# Formalises the checks that were previously done by hand: booting the VM,
# forcing an autologin with a throwaway module, and grepping a serial console.
#
# HOW TO RUN (this matters — the obvious way does not work):
#
#   nix build .#checks.x86_64-linux.desktop.driverInteractive
#   ./result/bin/nixos-test-driver
#
# NOT `nix build .#checks.x86_64-linux.desktop`. A sandboxed build on this
# Ubuntu host can open neither /dev/kvm nor /dev/dri: both are crw-rw---- owned
# by root:kvm / root:render, and the only grant is an ACL for the human user,
# which does not apply to the nixbld build users (the sandbox also drops
# supplementary groups). So a sandboxed run gets no GPU — meaning niri cannot
# render at all — and silently falls back to TCG emulation for want of KVM.
# The interactive driver runs as you, outside the sandbox, where the ACL
# applies and both devices are available.
{ hostPkgs, ... }:
{
  name = "maxnix-desktop";

  # enableOCR is deliberately left off. The driver's OCR (get_screen_text,
  # wait_for_text) is built on screendump, which cannot read a GL scanout —
  # see vnc_capture below. Turning it on would only produce confusing failures.

  nodes.machine =
    { lib, ... }:
    {
    imports = [
      ../hosts/maxnix/configuration.nix
      ../modules/desktop
      ../modules/vm/qemu-guest.nix
    ];

    # The driver appends -nographic when it finds no DISPLAY in its own
    # environment, which would leave virtio-vga-gl without a GL-capable backend
    # and kill acceleration. egl-headless keeps GL alive and feeds the VNC
    # server that qemu-guest.nix sets up.
    virtualisation.qemu.options = [ "-display egl-headless" ];

    # Log straight into niri rather than driving tuigreet, so this test fails
    # for compositor reasons rather than greeter-typing reasons. Exercising the
    # real greeter login is worth a separate test.
    services.greetd.settings.initial_session = {
      command = "niri-session";
      user = "max";
    };

    # The test framework gives root a hashedPasswordFile for its backdoor
    # console, which collides with the initialPassword our host config sets and
    # emits a precedence warning. The file wins either way; drop ours so the
    # intent is explicit rather than accidental.
    users.users.root.initialPassword = lib.mkForce null;
  };

  # testScript takes the function form so `nodes` is in scope for interpolation.
  testScript =
    { nodes, ... }:
    ''
    import subprocess
    from pathlib import Path

    VNC = "${hostPkgs.vncdotool}/bin/vncdotool"
    ADDR = "localhost::5909"


    def vnc_capture(name):
        """Screenshot the guest over VNC.

        machine.screenshot() cannot be used while GL is on: it goes through
        QEMU's screendump, which fails with "Error: no surface" because a GL
        scanout is a dmabuf rather than a CPU-readable surface. VNC's readback
        path handles it fine.
        """
        path = Path(machine.out_dir) / (name + ".png")
        subprocess.run([VNC, "-s", ADDR, "capture", str(path)], check=True, timeout=120)
        size = path.stat().st_size
        assert size > 5000, f"{path} is {size} bytes — screen looks blank"
        machine.log(f"captured {path} ({size} bytes)")
        return path


    start_all()

    with subtest("the system boots and the greeter is running"):
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("greetd.service")

    with subtest("both compositors are installed"):
        machine.succeed("niri --version")
        # NOT `Hyprland --version`: it aborts with "XDG_RUNTIME_DIR is not set"
        # and dumps core. The driver's backdoor is a bare root shell with no
        # user session, and Hyprland demands a runtime dir even to print its
        # version. Presence on PATH is what this subtest is actually asking.
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

    with subtest("niri starts and drives the virtual display"):
        machine.wait_until_succeeds("pgrep -x niri")
        machine.wait_until_succeeds("ls /run/user/1000/niri.wayland-*.sock")
        sock = machine.succeed("ls /run/user/1000/niri.wayland-*.sock").split()[0]
        outputs = machine.succeed(f"NIRI_SOCKET={sock} niri msg outputs")
        machine.log(outputs)
        assert "Virtual-1" in outputs, "niri enumerated no output:\n" + outputs

    with subtest("the compositor actually renders"):
        vnc_capture("niri-session")
  '';
}
