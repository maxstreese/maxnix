# NixOS under WSL on the Windows desktop (docs/desktop-pc.md): the base role
# and NixOS-WSL, composed in flake.nix. No desktop role — WSLg draws Linux
# windows into Windows' own — and no metal role: Windows owns the disk, the
# bootloader and the network, and the whole distribution is one VHDX file.
#
# Built here as `nix build .#checks.x86_64-linux.z690-wsl`; imported on Windows
# from `sudo nix run .#z690-wsl-tarball` (a nixos.wsl file) with `wsl --import`.
#
# Deliberately still open (docs/desktop-pc.md, "Still to decide"):
#
#   secrets    none yet. The guest needs an age key of its own and a
#              recipient in ../../.sops.yaml before anything is encrypted to
#              it; until then it declares no sops secrets at all.
#   password   NixOS-WSL's default: max has no password and sudo asks for
#              none (security.sudo.wheelNeedsPassword = mkDefault false in
#              its wsl-distro.nix). Windows' own login is the gate.
#   1Password  lives in Windows. Its SSH agent and op-ssh-sign reach the
#              guest only once bridged (wsl.ssh-agent, or npiperelay); until
#              then commits here go unsigned (../../home/max/desktop/
#              onepassword.nix is where signing lives, and this host does
#              not import it).
{ ... }:
{
  networking.hostName = "z690-wsl";

  wsl.enable = true;
  wsl.defaultUser = "max";

  # Pins the defaults this config was written against, per machine. Set once,
  # then leave alone.
  system.stateVersion = "26.11";
}
