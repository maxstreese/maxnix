# install-maxnix — put this machine onto the ThinkPad, from the installer USB
# (./default.nix). Run as root, in a terminal where 1Password's CLI is signed
# in (`eval $(op signin)`); the README has the whole day as a checklist.
#
#   install-maxnix
#
# Where the two secrets are in 1Password is built in (the flake's
# installSecrets, with the reason). Each can be named differently, for an
# item that has moved since the stick was built or, from a file, for the
# test and for a day 1Password is not reachable:
#
#   install-maxnix [--luks <op-ref> | --luks-file <file>]
#                  [--sops-key <op-ref> | --sops-key-file <file>]
#
# In order, and stopping at the first thing that is not right:
#
#   1. checks   root, UEFI, the disk exists — shown by size and model before
#               anything happens to it
#   2. secrets  the LUKS passphrase and the metal sops key, from 1Password
#               (or from files, as above), into a tmpfs
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
#   6. header   a copy of the LUKS header, the 16 MiB at the start of the
#               encrypted partition that hold the key the passphrase
#               unlocks. Damage there (a bad sector, a stray write) makes
#               the passphrase useless and the whole disk unreadable, and a
#               copy is what puts it back (README, install day). Into the
#               1Password vault the passphrase came from, as the document
#               "MaxNix LUKS Header <host> <date>", named as the other
#               items of a machine are, with the file in it called
#               luks-header-<LUKS UUID>.img (decided 2026-11-17). A header
#               fits one disk only and restoring another's destroys what is
#               there, so the title says which machine, for the day there is
#               a second one, and the file name which disk: `cryptsetup
#               luksUUID` on the partition has to give the same. It is
#               worthless without the passphrase. Where the upload fails, or
#               the passphrase came from a file, it is left at
#               /persist/luks-header.img to be stored by hand: failing here
#               would leave an erased disk and no system
#   7. install  nixos-install --system <the machine, built>: the toplevel
#               the flake built for nixosConfigurations.t14s, which is on the
#               stick with its whole closure because this script names it
#               (decided 2026-11-12). Nothing is evaluated, fetched or built
#               here: it is copied from the stick's store to the disk. With
#               --flake, as it was until then, this step needed GitHub and
#               Codeberg for the flake's inputs, cache.nixos.org for 1913 of
#               the closure's 2168 paths and a dozen vendors' download
#               servers for the rest (measured that day) — all after step 4
#               had erased the only machine there is
#
# checks.metal-install runs 1 to 6 against a virtual disk with --no-install,
# then installs a small test system itself and boots it. Step 7 is NixOS's
# own installer command, and with the upload to 1Password in step 6 the
# part only install day runs.
#
# disk and diskoScript come together from the flake's mkInstallMaxnix: the
# ThinkPad's M.2 slot for the installer, a virtual disk for the test. The
# script reads the passphrase from workDir, which is why that is fixed.
# luksRef and sopsKeyRef are the 1Password references used where no flag
# names another source. hostName is the machine's, for the header copy's
# title.
# `toplevel` is the system to install, or null where step 7 never runs: the
# test's script must not drag the machine's 22 GiB into its nodes.
{
  pkgs,
  disk,
  diskoScript,
  workDir,
  metalRecipient,
  hostName,
  luksRef,
  sopsKeyRef,
  toplevel ? null,
}:
pkgs.writeShellApplication {
  name = "install-maxnix";
  runtimeInputs = [
    pkgs.age
    pkgs.coreutils
    pkgs.cryptsetup
    pkgs.gawk
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
      echo "usage: install-maxnix [--luks <op-ref> | --luks-file <file>]" >&2
      echo "                      [--sops-key <op-ref> | --sops-key-file <file>]" >&2
      echo "                      [--yes] [--no-install]" >&2
      echo "without flags, both secrets come from their items in 1Password" >&2
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
    # The built-in references, each only where no flag named a source.
    [ -n "$luks_ref$luks_file" ] || luks_ref=${pkgs.lib.escapeShellArg luksRef}
    [ -n "$key_ref$key_file" ] || key_ref=${pkgs.lib.escapeShellArg sopsKeyRef}

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

    # ── 6. header ──────────────────────────────────────────────────────
    # The partition under the mapping disko just opened, so this cannot
    # name a different disk than the one that was formatted.
    luks_part=$(cryptsetup status crypted | awk '$1 == "device:" { print $2 }')
    [ -b "$luks_part" ] || die "cannot find the partition under /dev/mapper/crypted"
    cryptsetup luksHeaderBackup "$luks_part" --header-backup-file "$work/luks-header.img"
    luks_uuid=$(cryptsetup luksUUID "$luks_part")
    title=${pkgs.lib.escapeShellArg "MaxNix LUKS Header ${hostName}"}" $(date +%F)"
    stored=0
    if [ -n "$luks_ref" ]; then
      vault=''${luks_ref#op://}
      vault=''${vault%%/*}
      if op document create "$work/luks-header.img" --vault "$vault" \
        --title "$title" --file-name "luks-header-$luks_uuid.img" >/dev/null; then
        stored=1
        echo "header: a copy of the LUKS header is in 1Password, vault $vault," >&2
        echo "        as \"$title\"" >&2
      fi
    fi
    if [ "$stored" != 1 ]; then
      install -m 600 "$work/luks-header.img" /mnt/persist/luks-header.img
      echo "header: NOT in 1Password. A copy of the LUKS header is at" >&2
      echo "        /persist/luks-header.img: store it off this disk, as" >&2
      echo "        \"$title\", file luks-header-$luks_uuid.img." >&2
    fi

    # ── 7. install ─────────────────────────────────────────────────────
    if [ "$install" = 1 ]; then
      ${
        if toplevel == null then
          ''die "this build of install-maxnix carries no system to install; only --no-install works"''
        else
          ''
            nixos-install --no-root-passwd --no-channel-copy --system ${toplevel}
            echo "installed. Reboot, remove the USB stick, and type the LUKS passphrase." >&2
          ''
      }
    fi
  '';
}
