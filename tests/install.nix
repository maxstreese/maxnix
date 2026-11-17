# Does install-maxnix (../hosts/installer/install-maxnix.nix) do install day's
# steps right — and refuse when it should?
#
# Built on disko's makeDiskoTest, like ./disk.nix, through two of its hooks:
#
#   postDisko          after the harness has formatted the virtual disk,
#                      install-maxnix runs on it: first the refusals, then for
#                      real — partitioning it again from ../modules/metal/
#                      disk-layout.nix and putting the sops key on /persist
#   extraSystemConfig  the system the harness then installs onto that disk
#                      and boots carries the machine's secrets wiring, so the
#                      key install-maxnix placed has to decrypt a secret at
#                      first boot, from where ../hosts/t14s/secrets.nix
#                      reads it
#
# --no-install skips the script's last step, `nixos-install --system
# <the machine>`: NixOS's own installer command, copying the whole machine
# from the stick's store, 22 GiB these nodes would have to carry. The
# harness installs its own test system instead, and the script is built
# here without a system (null). So this proves the steps that are
# install-maxnix's — checks,
# secrets, disko, key — and leaves the one command it delegates.
#
# The key is a throwaway, made at build time, as in ./secrets.nix; its
# public half stands in for `metal` through --recipient.
#
# rescue-maxnix (../hosts/installer/rescue-maxnix.nix), the stick's command
# for a machine that no longer boots, runs in the same postDisko: on the
# disk install-maxnix made, closed again first. The harness then installs
# through the mounts rescue-maxnix made, so the boot proves them. Its last
# step, nixos-enter, is NixOS's own and is not run here.
{
  pkgs,
  disko,
  preservation,
  sops-nix,
  mkInstallMaxnix,
  mkRescueMaxnix,
}:
let
  fixture =
    pkgs.runCommand "install-fixture"
      {
        nativeBuildInputs = [
          pkgs.age
          pkgs.sops
        ];
      }
      ''
        export HOME=$TMPDIR
        mkdir $out
        age-keygen -o $out/key.txt 2>/dev/null
        age-keygen -y $out/key.txt > $out/recipient
        echo 'probe: decrypted' > plain.yaml
        sops encrypt --age "$(cat $out/recipient)" plain.yaml > $out/secrets.yaml
      '';
  # "secretsecret", the passphrase the harness types at boot (./disk.nix).
  args = "--luks-file /tmp/secret.key --sops-key-file /tmp/age.key --no-install";
  # install-maxnix as the flake builds it, for the harness's empty disk, and
  # for one that is not there.
  forDisk = mkInstallMaxnix "/dev/vdb" "test" null;
  forNoDisk = mkInstallMaxnix "/dev/nope" "test" null;
  # rescue-maxnix for the same disk, binding one of the machine's preserved
  # directories.
  rescue = mkRescueMaxnix "/dev/vdb" [ "/var/lib/sbctl" ];
in
disko.lib.testLib.makeDiskoTest {
  inherit pkgs;
  name = "maxnix-install";

  disko-config = import ../modules/metal/disk-layout.nix {
    passwordFile = "/tmp/secret.key";
  };

  extraInstallerConfig = {
    environment.systemPackages = [
      forDisk
      rescue
    ];
    # install-maxnix refuses a machine not booted in UEFI mode, as the
    # ThinkPad must be; the harness boots its installer without firmware.
    virtualisation.useEFIBoot = true;
  };

  extraSystemConfig =
    { lib, ... }:
    {
      imports = [
        sops-nix.nixosModules.sops
        ../hosts/t14s/secrets.nix
        # Declares maxnix.harlequin.profiles, which secrets.nix reads.
        ../modules/base/dev.nix
        # secrets.nix reads their switches; both stay off.
        ../modules/metal/fleet.nix
        ../modules/metal/backup.nix
        preservation.nixosModules.preservation
        ../modules/metal/persistence.nix
      ];
      # The machine's key path, /persist/sops/age.key, as secrets.nix sets
      # it — only the file to decrypt is the test's.
      sops.defaultSopsFile = lib.mkForce "${fixture}/secrets.yaml";
      sops.validateSopsFiles = false;
      sops.secrets.probe = { };
    };

  # Off the serial console, not by OCR, for the reason in ./disk.nix. No
  # bootvine here, so the line is systemd's own: its agent for the screen's
  # console, the one send_chars types into, saying it has started asking.
  bootCommands = ''
    import datetime
    machine.wait_for_console_text(
        "Starting password query on /dev/tty1",
        timeout=datetime.timedelta(minutes=15),
    )
    machine.send_chars("secretsecret\n")
  '';

  postDisko = ''
    machine.succeed("cp ${fixture}/key.txt /tmp/age.key")
    recipient = machine.succeed("cat ${fixture}/recipient").strip()
    run = "install-maxnix ${args}"

    # Without flags the secrets are 1Password's, at the references the
    # flake builds in: nothing is signed in here, so it stops there, and
    # not at a usage message asking for them.
    out = machine.fail("install-maxnix --yes --no-install 2>&1")
    assert "1Password's CLI is not signed in" in out, out

    # The refusals, each before anything is written. A key that is not the
    # expected one — here, metal's, the default:
    out = machine.fail(run + " --yes 2>&1")
    assert "is not the machine's" in out, out
    # A disk that is not there:
    out = machine.fail(f"${forNoDisk}/bin/install-maxnix ${args} --recipient {recipient} --yes 2>&1")
    assert "no disk at /dev/nope" in out, out
    # Anything but `erase` at the prompt:
    out = machine.fail(f"echo no | {run} --recipient {recipient} 2>&1")
    assert "nothing was changed" in out, out

    # For real, confirmed at the prompt as on the day.
    out = machine.succeed(f"(echo erase | {run} --recipient {recipient}) 2>&1")
    machine.succeed("${pkgs.cryptsetup}/bin/cryptsetup isLuks /dev/vdb2")
    mode = machine.succeed("stat -c '%a %U' /mnt/persist/sops/age.key").strip()
    assert mode == "600 root", mode

    # The copy of the LUKS header, left on /persist because nothing here is
    # signed in to 1Password, with the name to store it under: the title
    # the upload would have given it and this disk's UUID. That it is this
    # disk's header, and enough to
    # open it: the passphrase unlocks the partition with the header read
    # from the copy.
    header = "/mnt/persist/luks-header.img"
    cs = "${pkgs.cryptsetup}/bin/cryptsetup"
    uuid = machine.succeed(f"{cs} luksUUID /dev/vdb2").strip()
    assert '"MaxNix LUKS Header test ' in out, out
    assert f"luks-header-{uuid}.img" in out, out
    machine.succeed(f"{cs} isLuks {header}")
    machine.succeed(
        f"{cs} open --test-passphrase --header {header} "
        "--key-file /tmp/secret.key /dev/vdb2"
    )

    # ── rescue-maxnix ──────────────────────────────────────────────────
    #
    # The stick's other command (../hosts/installer/rescue-maxnix.nix), on
    # the disk install-maxnix just made: closed first, so it has to open and
    # mount it itself. Two markers go in before, one in /home and one in a
    # preserved directory, and both have to be there afterwards and after
    # the boot below: it must not have formatted anything.
    machine.succeed("echo marker > /mnt/home/rescue-marker")
    machine.succeed("mkdir -p /mnt/persist/var/lib/sbctl")
    machine.succeed("echo marker > /mnt/persist/var/lib/sbctl/rescue-marker")
    machine.succeed("rescue-maxnix --unmount")
    machine.fail("mountpoint -q /mnt")
    machine.fail("test -e /dev/mapper/crypted")

    # A bare --luks is 1Password's too, at the built-in reference, and
    # stops the same way.
    out = machine.fail("rescue-maxnix --luks --no-enter 2>&1")
    assert "1Password's CLI is not signed in" in out, out
    machine.fail("test -e /dev/mapper/crypted")

    # A wrong passphrase: refused, and nothing left half open.
    machine.succeed("echo wrongwrong > /tmp/wrong.key")
    out = machine.fail("rescue-maxnix --luks-file /tmp/wrong.key --no-enter 2>&1")
    assert "could not open and mount" in out, out
    machine.fail("mountpoint -q /mnt")
    machine.fail("test -e /dev/mapper/crypted")

    # The right one: every subvolume where the machine has it, under /mnt.
    rescue = "rescue-maxnix --luks-file /tmp/secret.key --no-enter"
    machine.succeed(rescue)
    for path, subvol in [("/mnt", "root"), ("/mnt/home", "home"), ("/mnt/nix", "nix"),
                         ("/mnt/persist", "persist"), ("/mnt/var/log", "log")]:
        src = machine.succeed(f"findmnt -no SOURCE {path}")
        assert f"[/{subvol}]" in src, f"{path} is not subvol {subvol}: {src}"
    machine.succeed("findmnt -no FSTYPE /mnt/boot | grep -qx vfat")
    machine.succeed("test -f /mnt/home/rescue-marker")
    # The preserved directory is bound to where the machine has it, so a
    # repair from inside finds the Secure Boot keys.
    machine.succeed("test -f /mnt/var/lib/sbctl/rescue-marker")
    machine.succeed("findmnt -no SOURCE /mnt/var/lib/sbctl | grep -q '\\[/persist/'")
    machine.succeed("test -f /mnt/persist/sops/age.key")

    # A second run refuses instead of mounting over the first.
    out = machine.fail(rescue + " 2>&1")
    assert "mounted already" in out, out
    # And once more with the passphrase typed at the prompt, the way it is
    # meant to be used; the file has it without a newline, the prompt reads
    # a line.
    machine.succeed("rescue-maxnix --unmount")
    machine.succeed("(cat /tmp/secret.key; echo) | rescue-maxnix --no-enter")
    machine.succeed("test -f /mnt/var/lib/sbctl/rescue-marker")
    # Left mounted: the harness installs its system through these mounts,
    # so that it boots at all is the proof they are the right ones.
  '';

  extraTestScript = ''
    # The key install-maxnix put on /persist is the one the booted machine
    # decrypts with.
    machine.wait_for_unit("multi-user.target")
    value = machine.succeed("cat /run/secrets/probe")
    assert value == "decrypted", repr(value)

    # What was on the disk before rescue-maxnix opened it is still there.
    machine.succeed("test -f /home/rescue-marker")
    machine.succeed("test -f /var/lib/sbctl/rescue-marker")
  '';
}
