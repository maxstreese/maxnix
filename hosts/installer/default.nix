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
# And the machine itself, built, with its whole closure (22.6 GiB unpacked on
# 2026-11-12): install-maxnix names that toplevel, so it is in this system's
# closure and so in the image's store. The install copies it from the stick
# and needs no upstream. Until 2026-11-12 it was left out, as the install
# needs Wi-Fi anyway, for 1Password; but then an outage of GitHub, Codeberg,
# cache.nixos.org or any vendor whose unfree package is in the machine would
# have struck after the disk was erased. 1Password's servers are the one
# thing still needed on the day, and --luks-file / --sops-key-file are the
# way round even that. The price: the stick is that commit's machine exactly,
# so it is rebuilt whenever the lock or the config moves.
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

  # Not nixpkgs' level 19: with the machine in it the store is 23 GiB, and
  # at 19 its squashfs was still compressing after 25 minutes on four cores
  # when it was cancelled (2026-11-12). The stick is rebuilt whenever the
  # machine changes, size does not matter (the stick is 64 GB), and zstd
  # unpacks equally fast from any level.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
}
