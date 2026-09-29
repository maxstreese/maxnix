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
# The enroll secret is a credential: anyone holding it can enroll a machine
# as one of the company's. It goes in via sops-nix (./secrets.nix) once the
# age key exists, and the module hands it to the unit through LoadCredential,
# so it never reaches the store:
#
#   sops.secrets.fleet-enroll-secret = { };
#   maxnix.fleet = {
#     enable = true;
#     url = "https://fleet.<company>";
#     enrollSecretPath = config.sops.secrets.fleet-enroll-secret.path;
#   };
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
{
  config,
  lib,
  pkgs,
  ...
}:
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
      description = "The Fleet server's base URL, from IT.";
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

  config = lib.mkMerge [
    {
      # osquery on its own, whether or not the agent is enrolled.
      #
      # It is what Fleet asks its questions with, so `sudo osqueryi` answers
      # them the same way before IT does — e.g. `select * from
      # disk_encryption;` for the LUKS check. Only meaningful on metal: every
      # VM path takes an unencrypted root from qemu-vm.nix.
      environment.systemPackages = [ pkgs.osquery ];
    }

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.url != null;
          message = "maxnix.fleet.enable needs maxnix.fleet.url.";
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
        fleetUrl = cfg.url;
        inherit (cfg) enrollSecretPath;
        desktop.enable = cfg.desktop;
      };
    })
  ];
}
