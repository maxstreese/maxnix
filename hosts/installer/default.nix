# The installer USB: nixpkgs' minimal installer, plus what install day needs
# so nothing has to be fetched or remembered on it.
#
#   nix build .#installer-iso
#   sudo dd if=result/iso/*.iso of=/dev/<stick> bs=4M status=progress oflag=sync
#
# On it: NetworkManager (nixpkgs' installer has it; `nmtui` for Wi-Fi), the
# 1Password CLI for the LUKS passphrase and the machine's sops key, disko and
# git from this flake's pins, flakes switched on, this repo at /etc/maxnix,
# and install-maxnix (./install-maxnix.nix), which does the rest. The
# README's install-day checklist walks through it.
#
# Not the machine's own closure: nixos-install builds and fetches it over the
# network, like any install. It would make the image ~13 GB for a step that
# needs Wi-Fi anyway, for 1Password.
{
  lib,
  modulesPath,
  pkgs,
  installMaxnix,
  flake,
  disko,
  ...
}:
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # 1Password's CLI is unfree; named here, next to its reason, as everywhere
  # in this repo.
  nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "1password-cli";

  environment.systemPackages = [
    installMaxnix
    disko
    pkgs.git
    pkgs._1password-cli
  ];

  # The repo as it was when the image was built — the same tree
  # install-maxnix installs from.
  environment.etc.maxnix.source = flake;

  # The same keyboard as the machine, for typing the LUKS passphrase and the
  # 1Password password.
  console.keyMap = "de";

  isoImage.volumeID = "MAXNIX_INSTALL";
}
