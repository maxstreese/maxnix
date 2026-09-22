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
{ pkgs, disko }:
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
  extraSystemConfig = import ../hosts/maxnix/luks-tpm.nix;

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
  '';
}
