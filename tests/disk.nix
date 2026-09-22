# Does the layout in ../hosts/maxnix/disk-layout.nix actually work?
#
# `checks.metal` proves the metal system *builds*. That is a different claim
# from "this disk layout partitions, formats and boots", and nothing in this
# repo made the second one until now: every VM path takes its disks from
# qemu-vm.nix, so the layout was a description nothing had ever executed.
#
# disko's own test harness does the whole thing — creates a blank virtual
# disk, runs the generated format-and-mount script against it, installs NixOS,
# reboots into the result — and it reads the same layout file the real machine
# does, so the thing under test cannot drift from the thing that ships.
#
# HOW TO RUN:
#   nix build .#checks.x86_64-linux.metal-boots
#
# It needs KVM and no GPU, so it belongs to the portable tier and runs in CI.
# It is also by some way the slowest check here: a full install, not a boot.
{
  pkgs,
  disko,
  preservation,
}:
disko.lib.testLib.makeDiskoTest {
  inherit pkgs;
  name = "maxnix-metal-boots";

  # The real layout, with one argument supplied: disko cannot create an
  # encrypted volume without a passphrase from somewhere, and there is no
  # human here to type one. /tmp/secret.key holding "secretsecret" is the
  # harness's own convention — it writes that file into the installer and
  # into the initrd. See the passwordFile option in ../hosts/maxnix/disk.nix.
  disko-config = import ../hosts/maxnix/disk-layout.nix {
    passwordFile = "/tmp/secret.key";
  };

  # The TPM unlock option the real machine carries, so that the fallback it
  # depends on is exercised here rather than assumed.
  #
  # It has to be passed explicitly: makeDiskoTest builds its installed system
  # from disko-config plus its own defaults and never imports
  # ../hosts/maxnix/disk.nix, so anything set there is invisible to this test.
  # That is not a guess — adding the option to disk.nix alone left this test's
  # derivation hash byte-identical.
  extraSystemConfig = {
    imports = [
      ../hosts/maxnix/luks-tpm.nix

      # Impermanence's bind mounts, and the module that implements them. The
      # installed system this harness builds imports none of the host's
      # modules, so both have to be handed over explicitly or the test would
      # judge a machine that has no persistence at all.
      preservation.nixosModules.preservation
      ../hosts/maxnix/persistence.nix
    ];
  };

  # The machine still asks for the passphrase at boot, because the layout puts
  # nothing in settings.keyFile — which is exactly the behaviour the real
  # machine has, and the reason this test is worth having. OCR reads the
  # prompt off the console; there is no other way to see it.
  enableOCR = true;
  bootCommands = ''
    machine.wait_for_text("[Pp]assphrase for")
    machine.send_chars("secretsecret\n")
  '';

  extraTestScript = ''
    # Encrypted at all. Partition 2 because 1 is the ESP.
    machine.succeed("cryptsetup isLuks /dev/vda2")

    # Every subvolume the layout declares. Asserted by name because a
    # mountpoint can be satisfied by the wrong subvolume, or by none at all
    # if it silently fell back to the root one.
    subvols = machine.succeed("btrfs subvolume list /")
    for name in ["root", "home", "nix", "persist", "log"]:
        assert f"path {name}" in subvols, f"missing subvolume {name}:\n{subvols}"

    # And that they are actually mounted where they belong. `findmnt` reports
    # the subvolume in its source, so this catches a mount that exists but
    # points at the wrong one.
    for path, subvol in [("/", "root"), ("/home", "home"), ("/nix", "nix"),
                         ("/persist", "persist"), ("/var/log", "log")]:
        src = machine.succeed(f"findmnt -no SOURCE {path}")
        assert f"[/{subvol}]" in src, f"{path} is not subvol {subvol}: {src}"

    # The ESP, and that a bootloader was actually installed on it. The system
    # booted, so this is belt and braces — but a machine that boots once from
    # an installer-written ESP and never again is a real failure mode.
    machine.succeed("findmnt -no FSTYPE /boot | grep -qx vfat")
    machine.succeed("test -d /boot/EFI/systemd -o -d /boot/EFI/BOOT")

    # ── Second boot ────────────────────────────────────────────────────
    #
    # Groundwork for impermanence, and deliberately written before any of it
    # exists. Impermanence's failure mode is "the second boot lost
    # something", which a test that boots once cannot detect at all — so the
    # harness has to be able to tell survival from loss *before* it is used
    # to judge either.
    #
    # Hence two markers with opposite expectations. Today the root is an
    # ordinary subvolume, so a file written to / survives; /run is a tmpfs,
    # so a file there cannot. Asserting both means a broken reboot — one
    # that silently kept the same running machine, or never came back —
    # fails rather than passing quietly, which a survival-only assertion
    # would do.
    #
    # When the root becomes ephemeral, the first expectation inverts and the
    # marker moves to /persist. That edit is the point of all this.
    machine.succeed("echo marker > /root-marker")
    machine.succeed("echo marker > /run/run-marker")

    # The one that distinguishes step 1 from having changed nothing.
    #
    # Without the wipe, a file under /var/lib/sbctl would survive a reboot
    # anyway — the root is still an ordinary subvolume — so "it survived"
    # proves nothing about preservation. What proves it is where the bytes
    # physically are: if the bind mount is real, the same file is visible
    # under /persist. If preservation silently did nothing, it is not.
    machine.succeed("echo marker > /var/lib/sbctl/preserved-marker")
    machine.succeed("test -f /persist/var/lib/sbctl/preserved-marker")
    first_machine_id = machine.succeed("cat /etc/machine-id").strip()

    machine.succeed("sync")
    machine.shutdown()

    # shutdown() then start() re-runs the same QEMU command against the same
    # disk files, so this is the installed system booting a second time.
    #
    # NOT create_test_machine(oldmachine=machine): that builds its disk paths
    # from oldmachine.state_dir, and the harness already used it once to go
    # from installer to booted machine. The booted machine is running the
    # *installer's* qcow2, and has none of its own, so asking for a third
    # machine based on it points QEMU at a file that does not exist and it
    # dies at once with a QMP ConnectionResetError. Found by writing it that
    # way first.
    machine.start()
    machine.wait_for_text("[Pp]assphrase for")
    machine.send_chars("secretsecret\n")
    machine.wait_for_unit("local-fs.target")

    # Survives today: the root persists. Inverts under impermanence.
    machine.succeed("test -f /root-marker")
    # Cannot survive, ever: /run is a tmpfs. This is what proves the reboot
    # actually happened.
    machine.fail("test -f /run/run-marker")

    # Preserved state comes back, and still through /persist rather than
    # having quietly reverted to a plain directory on the root.
    machine.succeed("test -f /var/lib/sbctl/preserved-marker")
    machine.succeed("test -f /persist/var/lib/sbctl/preserved-marker")
    machine.succeed("findmnt -no SOURCE /var/lib/sbctl | grep -q '\\[/persist/'")

    # machine-id is the one preserved *file*, and it is read in the initrd.
    # Assert it is the same one across the reboot rather than regenerated,
    # which is what would happen if the initrd mount had not worked.
    mid = machine.succeed("cat /etc/machine-id").strip()
    assert mid == first_machine_id, (
        f"machine-id changed across reboot: {first_machine_id} -> {mid}"
    )
  '';
}
