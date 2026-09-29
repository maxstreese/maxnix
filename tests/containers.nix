# Does rootless Docker in ../hosts/maxnix/containers.nix work, and is a
# published port really behind the firewall?
#
# HOW TO RUN:
#   nix build .#checks.x86_64-linux.containers
{ pkgs, ... }:
let
  # The real image from Docker Hub, fetched at build time: test VMs have no
  # network, so it is pinned by digest and loaded rather than pulled.
  postgres = pkgs.dockerTools.pullImage {
    imageName = "postgres";
    imageDigest = "sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24";
    hash = "sha256-WbUFmk1vvoPwDyoGlMq5nL1h2W4QXd0zeCxUOEXrEnU=";
    finalImageName = "postgres";
    finalImageTag = "17-alpine";
  };

  compose = pkgs.writeText "compose.yaml" ''
    services:
      db:
        image: postgres:17-alpine
        environment:
          POSTGRES_PASSWORD: test
        ports:
          - "5432:5432"
        healthcheck:
          test: ["CMD", "pg_isready", "-U", "postgres"]
          interval: 1s
          retries: 60
  '';
in
{
  name = "maxnix-containers";

  nodes.machine = {
    imports = [ ../hosts/maxnix/containers.nix ];

    users.users.max = {
      isNormalUser = true;
      # Starts max's user manager at boot, and with it the docker user
      # service. On the machine a login does that.
      linger = true;
    };

    # The machine's own default, stated so the test does not depend on it.
    networking.firewall.enable = true;
    environment.systemPackages = [ pkgs.netcat ];
    virtualisation.diskSize = 4096;
  };

  nodes.outside = { pkgs, ... }: { environment.systemPackages = [ pkgs.netcat ]; };

  testScript = ''
    import shlex

    def as_max(cmd):
        # As a unit of max's user manager, which is how everything in the
        # session is started — ghostty over D-Bus, the IDEs from the
        # launcher. A plain `sh`, not a login shell, so DOCKER_HOST has to
        # come from the manager's own environment.
        out = "/tmp/as-max.out"
        status, _ = machine.execute(
            f"systemd-run --user -M max@ --wait --collect --quiet"
            f" -p WorkingDirectory=/home/max"
            f" -p StandardOutput=truncate:{out} -p StandardError=append:{out}"
            f" /bin/sh -c {shlex.quote(cmd)}"
        )
        output = machine.succeed(f"cat {out}")
        assert status == 0, f"as max: {cmd!r} failed ({status}):\n{output}"
        return output

    start_all()
    # linger starts the user manager during boot; ask it nothing before then.
    machine.wait_for_unit("user@1000.service")
    machine.wait_for_unit("docker.service", user="max")

    with subtest("the session knows where the daemon is"):
        env = machine.succeed("systemctl --user -M max@ show-environment")
        assert "DOCKER_HOST=unix:///run/user/1000/docker.sock" in env, env

    with subtest("the daemon is max's, and max is not in the docker group"):
        info = as_max("docker info --format '{{json .SecurityOptions}}'")
        assert "rootless" in info, info
        machine.fail("id -nG max | grep -qw docker")
        machine.fail("test -e /var/run/docker.sock")
        print(as_max("docker info --format 'driver={{.Driver}} root={{.DockerRootDir}}'"))

    with subtest("compose and buildx are there"):
        as_max("docker compose version")
        as_max("docker buildx version")

    with subtest("a Docker Hub image runs under compose"):
        as_max("docker load --input ${postgres}")
        as_max("mkdir -p db && cp ${compose} db/compose.yaml")
        as_max("cd db && docker compose up --detach --wait")
        as_max("cd db && docker compose exec -T db psql -U postgres -tAc 'select 1'")
        # The published port answers on the machine itself.
        machine.wait_until_succeeds("nc -z 127.0.0.1 5432")

    with subtest("its storage is on /home"):
        machine.succeed("test -d /home/max/.local/share/docker")
        machine.fail("test -e /var/lib/docker")

    with subtest("and the published port is behind the firewall"):
        # compose published 5432 on every interface; from the network it must
        # still be closed, because nothing opened it in the firewall. Rootful
        # Docker would answer here.
        outside.wait_for_unit("multi-user.target")
        outside.succeed("ping -c 1 machine")
        outside.fail("nc -z -w 3 machine 5432")

    with subtest("and opening it in the firewall is what lets it through"):
        # The control for the check above: the same probe succeeds once the
        # port is allowed, so a pass there means "blocked", not "broken".
        machine.succeed("iptables -I nixos-fw -p tcp --dport 5432 -j nixos-fw-accept")
        outside.succeed("nc -z -w 3 machine 5432")
  '';
}
