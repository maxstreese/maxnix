# install-maxnix — put this machine onto the ThinkPad, from the installer USB
# (./default.nix). Run as root, in a terminal where 1Password's CLI is signed
# in (`eval $(op signin)`); the README has the whole day as a checklist.
#
#   install-maxnix --luks op://<vault>/<item>/password \
#                  --sops-key op://<vault>/<item>/<field>
#
# In order, and stopping at the first thing that is not right:
#
#   1. checks   root, UEFI, the disk exists — shown by size and model before
#               anything happens to it
#   2. secrets  the LUKS passphrase and the metal sops key, from 1Password
#               (or from files: --luks-file, --sops-key-file), into a tmpfs
#               only, and the key checked against `metal` in .sops.yaml — a
#               wrong key would install a machine that cannot decrypt its
#               secrets, login password included
#   3. confirm  type `erase`, unless --yes
#   4. disko    destroy, format, mount, from ../maxnix/disk-layout.nix: the
#               same layout checks.metal-boots formats and boots. Built ahead
#               by the flake for one disk, not evaluated here: disko's CLI
#               evaluates the layout at run time against whatever nixpkgs the
#               installer has and builds its script there, which in the
#               offline test meant compiling glibc and failing, and on the day
#               would have meant an unpinned build over Wi-Fi
#   5. key      onto /persist/sops/age.key, where ../maxnix/secrets.nix reads
#               it, before the first boot needs it
#   6. install  nixos-install --flake <this repo>#t14s
#
# checks.metal-install runs 1 to 5 against a virtual disk with --no-install,
# then installs a small test system itself and boots it. Step 6 is NixOS's
# own installer command and the one part only install day runs.
#
# disk and diskoScript come together from the flake's mkInstallMaxnix: the
# ThinkPad's M.2 slot for the installer, a virtual disk for the test. The
# script reads the passphrase from workDir, which is why that is fixed.
{
  pkgs,
  disk,
  diskoScript,
  workDir,
  flake,
  metalRecipient,
}:
pkgs.writeShellApplication {
  name = "install-maxnix";
  runtimeInputs = [
    pkgs.age
    pkgs.coreutils
    pkgs.util-linux
    pkgs.nixos-install-tools
  ];
  text = ''
    disk=${pkgs.lib.escapeShellArg disk}
    recipient=${pkgs.lib.escapeShellArg metalRecipient}
    work=${pkgs.lib.escapeShellArg workDir}
    luks_ref="" luks_file="" key_ref="" key_file="" yes=0 install=1

    die() { echo "install-maxnix: $*" >&2; exit 1; }
    usage() {
      echo "usage: install-maxnix (--luks <op-ref> | --luks-file <file>)" >&2
      echo "                      (--sops-key <op-ref> | --sops-key-file <file>)" >&2
      echo "                      [--yes] [--no-install]" >&2
      exit 2
    }
    while [ $# -gt 0 ]; do
      case "$1" in
        --luks) luks_ref=$2; shift 2 ;;
        --luks-file) luks_file=$2; shift 2 ;;
        --sops-key) key_ref=$2; shift 2 ;;
        --sops-key-file) key_file=$2; shift 2 ;;
        # For tests only: the expected key is the test's, not metal's.
        --recipient) recipient=$2; shift 2 ;;
        --yes) yes=1; shift ;;
        --no-install) install=0; shift ;;
        *) usage ;;
      esac
    done
    if [ -z "$luks_ref$luks_file" ] || [ -z "$key_ref$key_file" ]; then usage; fi

    # ── 1. checks ──────────────────────────────────────────────────────
    [ "$(id -u)" = 0 ] || die "run as root (sudo -i first)"
    [ -d /sys/firmware/efi ] || die "not booted in UEFI mode, which the layout and systemd-boot need"
    if [ ! -b "$disk" ]; then
      echo "disks by path:" >&2
      ls -l /dev/disk/by-path >&2 || true
      die "no disk at $disk"
    fi
    target=$(readlink -f "$disk")
    echo "disk: $disk -> $target, $(lsblk -dno SIZE,MODEL "$target")" >&2

    # ── 2. secrets ─────────────────────────────────────────────────────
    # In /run, a tmpfs: nothing reaches a disk, and the trap clears it.
    rm -rf "$work"
    install -d -m 700 "$work"
    trap 'rm -rf "$work"' EXIT
    fetch() { # <op-ref> <file> <dest> <what>
      if [ -n "$2" ]; then
        cp "$2" "$3"
      else
        op whoami >/dev/null 2>&1 || die "1Password's CLI is not signed in: eval \$(op signin)"
        op read --no-newline "$1" > "$3" || die "could not read the $4 from 1Password"
      fi
      [ -s "$3" ] || die "the $4 is empty"
    }
    fetch "$luks_ref" "$luks_file" "$work/luks.key" "LUKS passphrase"
    fetch "$key_ref" "$key_file" "$work/age.key" "sops key"
    got=$(age-keygen -y "$work/age.key") || die "the sops key is not an age key"
    [ "$got" = "$recipient" ] || die "the sops key is not the machine's: its public half is not $recipient"
    echo "secrets: the LUKS passphrase, and the sops key matching $recipient" >&2

    # ── 3. confirm ─────────────────────────────────────────────────────
    if [ "$yes" != 1 ]; then
      echo "This erases EVERYTHING on $target. Type erase to go on:" >&2
      read -r answer
      [ "$answer" = erase ] || die "nothing was changed"
    fi

    # ── 4. disko ───────────────────────────────────────────────────────
    ${diskoScript} --yes-wipe-all-disks

    # ── 5. key ─────────────────────────────────────────────────────────
    install -D -m 600 "$work/age.key" /mnt/persist/sops/age.key
    echo "key: /persist/sops/age.key" >&2

    # ── 6. install ─────────────────────────────────────────────────────
    if [ "$install" = 1 ]; then
      nixos-install --no-root-passwd --no-channel-copy --flake "${flake}#t14s"
      echo "installed. Reboot, remove the USB stick, and type the LUKS passphrase." >&2
    fi
  '';
}
