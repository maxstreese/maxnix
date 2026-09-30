# Fleet, the employer's device management (learned 2026-09-29).
#
# Fleet is two halves. The server is IT's, and nothing of it runs here. The
# agent is ours: fleetd, which is Orbit supervising osquery, plus Fleet
# Desktop as an optional tray app. nixpkgs carries all three and a module for
# the agent, services.orbit, so this file is a thin wrapper around that.
#
# ── Off until two things exist ───────────────────────────────────────────
#
# The server's URL and an enroll secret, both from IT. Neither can be
# invented here, so this is disabled by default and asserts rather than
# silently doing nothing when half-configured — the same shape as
# ./backup.nix.
#
# Both come in through sops (./secrets.nix), and so does the URL: the repo
# is public, and IT would rather not publish where its Fleet server is. The
# enroll secret is a credential — anyone holding it can enroll a machine as
# one of the company's — and reaches the unit through LoadCredential. The
# URL reaches it as ORBIT_FLEET_URL in an EnvironmentFile, since that is how
# Orbit reads it. Neither is ever in the store. Turning it on is one line,
# with ./secrets.nix supplying both paths:
#
#   maxnix.fleet.enable = true;
#
# The URL is secret at rest only. On the running machine it is in osqueryd's
# command line (--tls_hostname), which every local user can read with ps.
#
# ── What differs from the Ubuntu .deb ────────────────────────────────────
#
# The module turns off Orbit's self-update and its keystore. The agent's
# version is therefore whatever the pinned nixpkgs carries and moves with
# flake.lock, not when IT pushes one — the console may call it outdated.
#
# NixOS is not on Fleet's list of supported Linux distributions, and its
# built-in disk-encryption and firewall checks name Debian/Ubuntu,
# CentOS/Fedora and Arch. A LUKS root and the NixOS firewall may still report
# as missing; that is a conversation with IT, not something to fix here.
#
# Orbit's state (the node key it enrolled with) lives in /var/lib/orbit and is
# preserved in ./persistence.nix; without that, every boot would enroll a new
# host. Its logs go to /var/log/orbit, which is already its own subvolume.
{ config, lib, ... }:
let
  cfg = config.maxnix.fleet;
in
{
  options.maxnix.fleet = {
    enable = lib.mkEnableOption "the Fleet agent (Orbit + osquery), enrolled with the employer's server";

    url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://fleet.example.com";
      description = ''
        The Fleet server's base URL, from IT, in plain text. Public along
        with the repo — so this machine uses urlEnvironmentFile instead and
        leaves this null.
      '';
    };

    urlEnvironmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/rendered/orbit.env";
      description = ''
        A file containing the line `ORBIT_FLEET_URL=https://…`, read by the
        Orbit unit as root. For a URL that should not be in the store or the
        repo. Orbit reads its URL from that variable, and systemd lets an
        EnvironmentFile override the unit's own Environment, so this wins
        over the placeholder the module is given.
      '';
    };

    enrollSecretPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/fleet-enroll-secret";
      description = ''
        File holding the enroll secret, read by the Orbit unit as root. A path
        on the machine, never the secret itself — putting it in a Nix option
        would copy it into the world-readable store.
      '';
    };

    desktop = lib.mkEnableOption ''
      Fleet Desktop, the tray app that shows this device's status and failing
      policies. Off until IT says it is wanted, and untested under niri and
      Hyprland: it needs a StatusNotifier tray, which DMS provides'';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.url != null) != (cfg.urlEnvironmentFile != null);
        message = "maxnix.fleet.enable needs exactly one of maxnix.fleet.url and maxnix.fleet.urlEnvironmentFile.";
      }
      {
        assertion = cfg.enrollSecretPath != null;
        message = "maxnix.fleet.enable needs maxnix.fleet.enrollSecretPath.";
      }
    ];

    # Only when enabled, so the unfree licence is never evaluated otherwise.
    # fleet-orbit is dual-licensed: MIT, plus Fleet's Enterprise Edition
    # licence for the ee/ parts compiled in, and nixpkgs marks it unfree for
    # the latter. See ./configuration.nix for how this list works.
    nixpkgs.config.allowUnfreePackages = [ "fleet-orbit" ];

    services.orbit = {
      enable = true;
      # With the URL in a file the module still needs a value. .invalid is
      # reserved never to resolve (RFC 2606), so if the file were ever
      # missing Orbit fails to connect rather than reaching somewhere real.
      fleetUrl = if cfg.url != null then cfg.url else "https://fleet.invalid";
      inherit (cfg) enrollSecretPath;
      desktop.enable = cfg.desktop;
    };

    # Fleet Desktop is started in the user's session with `sudo -n -i -u …`,
    # and sudo is a setuid wrapper in /run/wrappers/bin — not on a unit's
    # default PATH, and the nixpkgs module adds nothing. Without this every
    # launch failed silently: Orbit logged "running command" every 30 s and
    # never said it could not find sudo. Measured in the VM 2026-09-30.
    systemd.services.orbit.path = lib.mkIf cfg.desktop [ "/run/wrappers" ];

    systemd.services.orbit.serviceConfig = {
      EnvironmentFile = lib.mkIf (cfg.urlEnvironmentFile != null) cfg.urlEnvironmentFile;

      # Orbit ignores SIGTERM while it is retrying enrollment, so every stop
      # — and so every shutdown — sat out systemd's default 90 s before the
      # SIGKILL. Measured in ../../tests/fleet.nix: 90.1 s, then "State
      # 'stop-sigterm' timed out. Killing." An unenrolled Orbit has nothing
      # to lose, and osquery's RocksDB database is built to survive a kill,
      # so the wait is cut rather than worked around.
      TimeoutStopSec = "5s";
    };
  };
}
