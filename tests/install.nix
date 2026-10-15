# Does install-maxnix (../hosts/installer/install-maxnix.nix) do install day's
# steps right — and refuse when it should?
#
# Built on disko's makeDiskoTest, like ./disk.nix, through two of its hooks:
#
#   postDisko          after the harness has formatted the virtual disk,
#                      install-maxnix runs on it: first the refusals, then for
#                      real — partitioning it again from ../hosts/maxnix/
#                      disk-layout.nix and putting the sops key on /persist
#   extraSystemConfig  the system the harness then installs onto that disk
#                      and boots carries the machine's secrets wiring, so the
#                      key install-maxnix placed has to decrypt a secret at
#                      first boot, from where ../hosts/maxnix/secrets.nix
#                      reads it
#
# --no-install skips the script's last step, `nixos-install --flake
# …#maxnix`: NixOS's own installer command, building the whole machine, which
# a sandbox cannot do offline. The harness installs its own test system
# instead. So this proves the steps that are install-maxnix's — checks,
# secrets, disko, key — and leaves the one command it delegates.
#
# The key is a throwaway, made at build time, as in ./secrets.nix; its
# public half stands in for `metal` through --recipient.
{
  pkgs,
  disko,
  preservation,
  sops-nix,
  mkInstallMaxnix,
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
  forDisk = mkInstallMaxnix "/dev/vdb";
  forNoDisk = mkInstallMaxnix "/dev/nope";
in
disko.lib.testLib.makeDiskoTest {
  inherit pkgs;
  name = "maxnix-install";

  disko-config = import ../hosts/maxnix/disk-layout.nix {
    passwordFile = "/tmp/secret.key";
  };

  extraInstallerConfig = {
    environment.systemPackages = [ forDisk ];
    # install-maxnix refuses a machine not booted in UEFI mode, as the
    # ThinkPad must be; the harness boots its installer without firmware.
    virtualisation.useEFIBoot = true;
  };

  extraSystemConfig =
    { lib, ... }:
    {
      imports = [
        sops-nix.nixosModules.sops
        ../hosts/maxnix/secrets.nix
        # secrets.nix reads their switches; both stay off.
        ../hosts/maxnix/fleet.nix
        ../hosts/maxnix/backup.nix
        preservation.nixosModules.preservation
        ../hosts/maxnix/persistence.nix
      ];
      # The machine's key path, /persist/sops/age.key, as secrets.nix sets
      # it — only the file to decrypt is the test's.
      sops.defaultSopsFile = lib.mkForce "${fixture}/secrets.yaml";
      sops.validateSopsFiles = false;
      sops.secrets.probe = { };
    };

  enableOCR = true;
  bootCommands = ''
    machine.wait_for_text("[Pp]assphrase for")
    machine.send_chars("secretsecret\n")
  '';

  postDisko = ''
    machine.succeed("cp ${fixture}/key.txt /tmp/age.key")
    recipient = machine.succeed("cat ${fixture}/recipient").strip()
    run = "install-maxnix ${args}"

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
    machine.succeed(f"echo erase | {run} --recipient {recipient}")
    machine.succeed("${pkgs.cryptsetup}/bin/cryptsetup isLuks /dev/vdb2")
    mode = machine.succeed("stat -c '%a %U' /mnt/persist/sops/age.key").strip()
    assert mode == "600 root", mode
  '';

  extraTestScript = ''
    # The key install-maxnix put on /persist is the one the booted machine
    # decrypts with.
    machine.wait_for_unit("multi-user.target")
    value = machine.succeed("cat /run/secrets/probe")
    assert value == "decrypted", repr(value)
  '';
}
