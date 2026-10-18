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
# env file, and Orbit connecting to it. With the backup switched on, the same
# for its four: the password file, and the three Drive values rendered into
# rclone.conf where the restic unit is told to look. Nothing is uploaded; the
# timer does not fire on a first boot, and there is no network to reach. And
# the login password: a hash in sops becoming max's and root's in
# /etc/shadow, and winning over a `passwd` at the next activation. The node
# is metal, so the login password and the restic password come from a second
# file, as metal's own do, and are absent from the shared one.
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
          hostPkgs.mkpasswd
        ];
      }
      ''
            export HOME=$TMPDIR
            mkdir $out
            age-keygen -pq -o $out/key.txt 2>/dev/null
            # A hash, as the real secret is, made the way ../hosts/maxnix/
            # secrets.nix says to make it.
            echo -n not-a-real-login | mkpasswd -m yescrypt --stdin > $out/login-hash
            cat > plain.yaml <<EOF
        probe: decrypted
        fleet-enroll-secret: not-a-real-secret
        fleet-url: https://127.0.0.1:1
        restic-password: the-vms-password
        rclone-drive-client-id: test-client-id
        rclone-drive-client-secret: test-client-secret
        rclone-drive-token: '{"token_type":"Bearer","refresh_token":"not-a-real-token"}'
        EOF
            # Metal's own, in a file of their own as on the machine: read
            # from the shared one by mistake, they would not be there.
            cat > metal.yaml <<EOF
        restic-password-metal: not-a-real-password
        login-password: '$(cat $out/login-hash)'
        EOF
            sops encrypt --age "$(age-keygen -y $out/key.txt)" plain.yaml > $out/secrets.yaml
            sops encrypt --age "$(age-keygen -y $out/key.txt)" metal.yaml > $out/secrets-metal.yaml
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
      ../modules/metal/fleet.nix
      # Likewise, with the default rclone: repository.
      ../modules/metal/backup.nix
    ];
    maxnix.fleet.enable = true;
    maxnix.backup.enable = true;
    # As on the machine (../hosts/maxnix/configuration.nix).
    maxnix.loginPassword.fromSops = true;
    maxnix.secrets.metal.enable = true;
    users.mutableUsers = false;
    users.users.max.isNormalUser = true;
    # The test framework gives root a hashedPasswordFile of its own for the
    # backdoor console; ours has to win here, or this would test theirs.
    users.users.root.hashedPasswordFile = lib.mkForce "/run/secrets-for-users/login-password";

    sops.defaultSopsFile = lib.mkForce "${fixture}/secrets.yaml";
    maxnix.secrets.metal.sopsFile = "${fixture}/secrets-metal.yaml";
    # A key file on disk, as a restored machine key would be. It cannot be
    # the store path itself — sops-nix rejects a key inside the store — so
    # it is copied into place just before sops-nix's own activation step.
    sops.age.keyFile = lib.mkForce "/var/lib/sops-test/key.txt";
    system.activationScripts.sops-test-key = "install -D -m 600 ${fixture}/key.txt /var/lib/sops-test/key.txt";
    system.activationScripts.setupSecrets.deps = [ "sops-test-key" ];
    # And before the step that decrypts the login password, which runs
    # earlier still, ahead of the users (neededForUsers). Without this the
    # users came up with "password file … does not exist".
    system.activationScripts.setupSecretsForUsers.deps = [ "sops-test-key" ];
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

    with subtest("the backup gets its password and an rclone.conf from sops"):
        # Metal's own password, from metal's file, and the unit pointed at it.
        pw = machine.succeed("cat /run/secrets/restic-password-metal")
        assert pw == "not-a-real-password", repr(pw)
        machine.fail("test -e /run/secrets/restic-password")
        conf = machine.succeed("cat /run/secrets/rendered/rclone.conf")
        for line in ["[gdrive]", "type = drive", "scope = drive.file",
                     "client_id = test-client-id",
                     "client_secret = test-client-secret",
                     'token = {"token_type":"Bearer","refresh_token":"not-a-real-token"}']:
            assert line in conf.splitlines(), f"missing {line!r}:\n{conf}"
        mode = machine.succeed("stat -L -c '%a %U' /run/secrets/rendered/rclone.conf").strip()
        assert mode == "400 root", mode
        # And the unit is pointed at exactly these files.
        env = machine.succeed("systemctl show -p Environment restic-backups-maxnix.service")
        assert "RCLONE_CONFIG=/run/secrets/rendered/rclone.conf" in env, env
        assert "RESTIC_REPOSITORY=rclone:gdrive:maxnix-backup" in env, env
        assert "RCLONE_DRIVE_STOP_ON_UPLOAD_LIMIT=true" in env, env
        unit = machine.succeed("systemctl cat restic-backups-maxnix.service")
        assert "/run/secrets/restic-password-metal" in unit, unit

    with subtest("the login password is the hash from sops, and outlasts a passwd"):
        want = "${fixture}/login-hash"
        expected = machine.succeed(f"cat {want}").strip()
        mode = machine.succeed("stat -L -c '%a %U' /run/secrets-for-users/login-password").strip()
        assert mode == "400 root", mode
        for user in ["max", "root"]:
            got = machine.succeed(f"getent shadow {user} | cut -d: -f2").strip()
            assert got == expected, f"{user}: {got!r}"
        # A passwd works until the next activation, which puts the declared
        # one back: what keeps a wiped root from resetting it is the same
        # thing that undoes a manual change.
        machine.succeed("echo 'max:set-by-hand' | chpasswd")
        assert machine.succeed("getent shadow max | cut -d: -f2").strip() != expected
        # The activation script itself: test nodes carry no
        # switch-to-configuration.
        machine.succeed("/run/current-system/activate")
        got = machine.succeed("getent shadow max | cut -d: -f2").strip()
        assert got == expected, f"after activation: {got!r}"
  '';
}
