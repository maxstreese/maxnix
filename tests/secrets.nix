# Can this machine's sops setup decrypt at activation, with a post-quantum
# key like the real ones?
#
# The real keys in ../.sops.yaml are age1pq1… hybrids, and the sops CLI
# handles them — checked by hand. The machines, though, decrypt with
# sops-nix's own sops-install-secrets, built against an older sops. That is
# the half nothing else here exercises, and a mismatch would only surface
# on the first real deploy, as secrets that silently never appear.
#
# With Fleet switched on, it also runs the wiring in secrets.nix end to end:
# the enroll secret and the URL both decrypted, the URL rendered into Orbit's
# env file, and Orbit connecting to it.
#
# The key and the encrypted file are made at build time, so no real key is
# involved and the fixture cannot rot. The node takes ../hosts/maxnix/
# secrets.nix as is and overrides only the two paths a test must: which file
# to decrypt and which key to decrypt it with.
#
# HOW TO RUN:
#   nix build .#checks.x86_64-linux.secrets
{ sops-nix, ... }:
{ hostPkgs, lib, ... }:
let
  fixture =
    hostPkgs.runCommand "sops-pq-fixture"
      {
        nativeBuildInputs = [
          hostPkgs.age
          hostPkgs.sops
        ];
      }
      ''
            export HOME=$TMPDIR
            mkdir $out
            age-keygen -pq -o $out/key.txt 2>/dev/null
            cat > plain.yaml <<EOF
        probe: decrypted
        fleet-enroll-secret: not-a-real-secret
        fleet-url: https://127.0.0.1:1
        EOF
            sops encrypt --age "$(age-keygen -y $out/key.txt)" plain.yaml > $out/secrets.yaml
      '';
in
{
  name = "maxnix-secrets";

  # fleet.nix adds to nixpkgs.config.allowUnfreePackages, which a read-only
  # pkgs refuses. Same reason as in ./fleet.nix.
  node.pkgsReadOnly = false;

  nodes.machine = {
    imports = [
      sops-nix.nixosModules.sops
      ../hosts/maxnix/secrets.nix
      # On, so the wiring in secrets.nix runs exactly as on the machine:
      # both Fleet values from sops, the URL through the rendered env file.
      ../hosts/maxnix/fleet.nix
    ];
    maxnix.fleet.enable = true;

    sops.defaultSopsFile = lib.mkForce "${fixture}/secrets.yaml";
    # A key file on disk, as a restored machine key would be. It cannot be
    # the store path itself — sops-nix rejects a key inside the store — so
    # it is copied into place just before sops-nix's own activation step.
    sops.age.keyFile = lib.mkForce "/var/lib/sops-test/key.txt";
    system.activationScripts.sops-test-key = "install -D -m 600 ${fixture}/key.txt /var/lib/sops-test/key.txt";
    system.activationScripts.setupSecrets.deps = [ "sops-test-key" ];
    # Not validated at build time: the fixture is a store path the sandbox
    # would otherwise have to read during evaluation.
    sops.validateSopsFiles = false;
    sops.secrets.probe = { };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("a post-quantum key decrypts at activation"):
        value = machine.succeed("cat /run/secrets/probe")
        assert value == "decrypted", repr(value)

    with subtest("root-only, in memory"):
        mode = machine.succeed("stat -L -c '%a %U' /run/secrets/probe").strip()
        assert mode == "400 root", mode
        machine.succeed("findmnt -n -o FSTYPE --target /run/secrets.d | grep -qx ramfs")

    with subtest("Fleet gets both values from sops"):
        env = machine.succeed("cat /run/secrets/rendered/orbit.env")
        assert env == "ORBIT_FLEET_URL=https://127.0.0.1:1\n", repr(env)
        machine.wait_for_unit("orbit.service")
        secret = machine.succeed("cat /run/credentials/orbit.service/enroll-secret")
        assert secret == "not-a-real-secret", repr(secret)
        machine.wait_until_succeeds("journalctl -u orbit.service | grep -q 'tls_hostname=127.0.0.1:1'")
        machine.fail("journalctl -u orbit.service | grep -q 'fleet.invalid'")
  '';
}
