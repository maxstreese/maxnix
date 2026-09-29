# Does the Fleet agent in ../hosts/maxnix/fleet.nix start, with no server?
#
# There is no Fleet server to enroll with: that is IT's, and running one here
# would mean MySQL, Redis and a server module nixpkgs does not have. So this
# proves the wiring, not enrollment — the unit starts, reads its secret
# through LoadCredential, tries the configured URL, and on failing to reach
# it waits to retry instead of spinning. Enrollment is first seen on the day
# IT hands over a URL and a secret.
#
# A small node that imports only ../hosts/maxnix/fleet.nix, not hostModules.
# The desktop suites already boot the whole machine with the agent off; what
# is new here is the agent turned on, and it needs nothing from the desktop
# to do that. It keeps this check to one short boot.
#
# HOW TO RUN:
#   nix build .#checks.x86_64-linux.fleet
{
  name = "maxnix-fleet";

  # ../hosts/maxnix/fleet.nix adds to nixpkgs.config.allowUnfreePackages, which
  # a read-only pkgs refuses. Same reason as in ./desktop.nix.
  node.pkgsReadOnly = false;

  nodes.machine = {
    imports = [ ../hosts/maxnix/fleet.nix ];

    maxnix.fleet = {
      enable = true;
      # The URL from a file, the way the machine gets it from sops. Port 1 on
      # loopback: nothing listens, so the connection is refused at once
      # rather than timing out, and nothing leaves the VM.
      urlEnvironmentFile = "/etc/fleet-test.env";
      enrollSecretPath = "/etc/fleet-test-enroll-secret";
    };
    environment.etc."fleet-test.env".text = "ORBIT_FLEET_URL=https://127.0.0.1:1\n";
    environment.etc."fleet-test-enroll-secret".text = "not-a-real-secret";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("orbit starts with its secret"):
        machine.wait_for_unit("orbit.service")
        # LoadCredential copied the file in, which is the step that fails the
        # unit at start if enrollSecretPath is wrong.
        secret = machine.succeed("cat /run/credentials/orbit.service/enroll-secret")
        assert secret == "not-a-real-secret", secret

    with subtest("orbit tries the configured server, and osqueryd with it"):
        machine.wait_until_succeeds("journalctl -u orbit.service | grep -q 'enroll failed, retrying'")
        machine.succeed("journalctl -u orbit.service | grep -q 'tls_hostname=127.0.0.1:1'")
        # The file's URL won over the placeholder the module was given. If the
        # override ever stopped working, this is where it would show.
        machine.fail("journalctl -u orbit.service | grep -q 'fleet.invalid'")
        machine.succeed("pgrep -x osqueryd")

    with subtest("and keeps retrying in-process rather than crashing"):
        # Measured on the first run: Orbit logs "enroll failed, retrying" and
        # stays up, so systemd's Restart=always never fires. A crash loop would
        # show up here as restarts; an agent that quietly gave up, as inactive.
        machine.sleep(30)
        machine.succeed("systemctl is-active orbit.service")
        restarts = machine.succeed("systemctl show -p NRestarts --value orbit.service").strip()
        assert restarts == "0", f"orbit restarted {restarts} times"
  '';
}
