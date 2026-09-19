# Steam.
#
# A NixOS module rather than a package, because Steam needs the system to
# meet it halfway. Enabling it turns on `hardware.graphics.enable32Bit` —
# Steam's runtime and most games are still 32-bit, so the whole graphics
# stack has to exist twice — and `hardware.steam-hardware`, the udev rules
# that let a normal user talk to controllers. Adding `pkgs.steam` to a
# package list gets you none of that and a client that cannot draw.
#
# Firewall ports for Remote Play, local network transfers and dedicated
# servers are separate options, all left off. They are inbound holes and
# nothing here needs them yet.
#
# ── In the VM ────────────────────────────────────────────────────────────
#
# It installs and starts, but expect the store and not much else: the guest
# renders through virgl, which is fine for a compositor and poor for a game.
# This is here for the machine it is becoming, not for the one it is.
{ ... }:
{
  nixpkgs.config.allowUnfreePackages = [
    "steam"
    "steam-unwrapped"
  ];

  programs.steam.enable = true;
}
