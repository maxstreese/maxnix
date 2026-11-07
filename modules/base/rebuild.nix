# Every machine is built from this flake, never from channels (decided
# 2026-11-07, README "Decisions, and why").
#
# A bare `sudo nixos-rebuild switch` reads /etc/nixos, and plain NixOS
# subscribes root to a channel. Left alone, that is a second way to build a
# machine, one that ignores this repo: on the WSL host, whose image ships a
# stock /etc/nixos/configuration.nix and two channel subscriptions, a
# `nix-channel --update` followed by that bare command would have replaced
# maxnix with NixOS-WSL's starter system. So:
#
#   - no channels: no nix-channel, nothing of them in NIX_PATH;
#   - /etc/nixos is a symlink to the clone, so the bare command builds
#     /etc/nixos#<hostname>, working tree included, the same system as
#     `--flake ~/maxnix#<hostname>`. Hostname and configuration name are
#     always the same word (README, "machine names").
#
# Both through tmpfiles rather than a hand edit, so a fresh machine or a
# freshly imported image converges on its first activation: L+ replaces
# whatever is at /etc/nixos, and r removes /root/.nix-channels, which turning
# channels off leaves behind. On metal the root is wiped at every boot, and
# tmpfiles runs at every boot, so the link is always there; the clone is on
# /home, which persists.
#
# Until the clone exists the link dangles and only the bare command fails:
# nothing at run time reads /etc/nixos, unlike maxnix.dev.liveConfig
# (./dev.nix), which points running config at the clone.
{ config, lib, ... }:
{
  options.maxnix.dev.etcNixosLink = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Make /etc/nixos a symlink to the clone (maxnix.dev.clonePath), so a
      bare `nixos-rebuild` builds this machine from it. Off in the dev VM
      (../../hosts/t14s/vm.nix): there the bare command would build
      nixosConfigurations.t14s, the metal system, where the VM needs the
      vmVariant's, which its `rebuild` builds. Without the link the bare
      command fails instead of building the wrong machine.
    '';
  };

  config = {
    nix.channel.enable = false;

    systemd.tmpfiles.rules = [
      "r /root/.nix-channels"
    ]
    ++ lib.optional config.maxnix.dev.etcNixosLink "L+ /etc/nixos - - - - ${config.maxnix.dev.clonePath}";
  };
}
