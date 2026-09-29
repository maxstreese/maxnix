# Containers: Docker, rootless.
#
# ── Docker rather than Podman ────────────────────────────────────────────
#
# The work this machine is for is built on Docker: compose files across the
# work repositories, Dockerfiles for the company's base and builder images,
# Testcontainers pinned at 1.16 in rtp-library-test (from before its Podman
# support was good), and the JetBrains IDEs' Docker integration. Podman's
# compatibility socket covers most of that and not all of it, and each gap
# would be found one project at a time. Rootless Docker gets the security
# property Podman is usually chosen for, without the compatibility tax.
#
# ── Rootless rather than the system daemon ───────────────────────────────
#
# Two reasons, both about the machine rather than about Docker:
#
#   The docker group is root. Anyone in it can `docker run -v /:/host` and
#   do anything to the machine. Here there is no group: the daemon runs as
#   max, as a systemd *user* service, and can do only what max can.
#
#   Rootful Docker publishes ports past the firewall. It writes its own
#   iptables rules, so `-p 5432:5432` is reachable from the network whatever
#   networking.firewall says. Rootless publishes through a userspace
#   forwarder, an ordinary socket the firewall does apply to.
#   ../../tests/containers.nix measures that from a second machine.
#
# And one about this repo: the rootful daemon's state is /var/lib/docker, on
# the root that ./persistence.nix wipes every boot. The rootless daemon's is
# ~/.local/share/docker, on /home, which survives — and which ./backup.nix
# therefore has to exclude.
#
# ── What is deliberately absent ──────────────────────────────────────────
#
#   virtualisation.docker.enable   the rootful daemon. Both at once would
#                                  compete for DOCKER_HOST.
#   extraGroups = [ "docker" ]     see above; that is the point.
#
# Already in place and needing nothing: max gets a subordinate uid/gid range
# because isNormalUser implies autoSubUidGidRange, and NixOS ships the
# setuid newuidmap/newgidmap wrappers the daemon maps them with.
#
# The package carries compose and buildx as CLI plugins, so `docker compose`
# and `docker buildx` need nothing extra.
_: {
  virtualisation.docker.rootless = {
    enable = true;
    # DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock in login shells — a TTY
    # or an ssh session. Not enough on its own; see below.
    setSocketVariable = true;
  };

  # DOCKER_HOST for everything else in the session, which is most of it.
  #
  # setSocketVariable writes to environment.extraInit, which only shells
  # read. Everything graphical here is started by the systemd user manager —
  # ghostty over D-Bus, the IDEs from the launcher — and the manager never
  # sees it: measured in ../../tests/containers.nix, its environment had
  # XDG_RUNTIME_DIR and no DOCKER_HOST. So Testcontainers inside an IDE, or
  # its Docker panel, would have found no daemon.
  #
  # environment.d is the manager's own mechanism: systemd's
  # environment-d-generator reads /etc/environment.d at user-manager start
  # and expands ''${XDG_RUNTIME_DIR} there, so no uid is written down. NixOS
  # ships the generator; with this file the manager's environment carries
  # DOCKER_HOST=unix:///run/user/1000/docker.sock, which the test asserts.
  environment.etc."environment.d/50-docker-host.conf".text = ''
    DOCKER_HOST=unix://''${XDG_RUNTIME_DIR}/docker.sock
  '';

  # No storage driver is set, on purpose. Docker 29 stores images through
  # containerd's overlayfs snapshotter by default, which the test reports on
  # btrfs as well — so no nested subvolumes appear under /home, and nothing
  # needs pinning.
}
