# rescue-maxnix — get into the installed machine from the installer USB
# (./default.nix) when it does not boot by itself, without erasing anything.
# Run as root.
#
#   rescue-maxnix [--luks [<op-ref>] | --luks-file <file>] [--no-enter]
#   rescue-maxnix --unmount
#
# Why it exists (decided 2026-11-16): after install day the stick is the only
# other thing that boots this laptop, and until then all it could do was
# ./install-maxnix.nix, which erases the disk. A boot partition that is
# damaged or full, or Secure Boot refusing every generation, is past what the
# boot menu's older generations can fix; the way back is to open the disk
# from outside and repair it from inside. The commands for that are few, but
# they are the layout's, subvolume by subvolume, and the day the laptop does
# not boot is not the day to type them from memory.
#
# In order:
#
#   1. checks      root, the disk is there, nothing is mounted at /mnt yet
#   2. passphrase  typed at a prompt, as at every boot; or from 1Password
#                  (--luks: the item install-maxnix reads it from, unless a
#                  reference follows) or a file (--luks-file), into a tmpfs
#                  only. The prompt stays the default: it needs no network
#                  and no sign-in on the day the machine does not boot
#   3. mount       disko's mount script for ../../modules/metal/disk-layout.nix:
#                  the same layout the install formatted, opened and mounted
#                  at /mnt. It only opens and mounts; the script that formats
#                  is not in this command
#   4. state       the directories the machine keeps on /persist, bound to
#                  where the running machine has them (../../modules/metal/
#                  persistence.nix). The booted system does this itself; from
#                  outside nothing would, and /var/lib/sbctl would be an empty
#                  directory: a repair of the boot files would then sign with
#                  nothing, or make new Secure Boot keys. The list is the
#                  machine's as of the commit the stick was built from
#   5. enter       nixos-enter: a root shell inside the installed system.
#                  Leaving it leaves the disk mounted, for copying things out;
#                  `rescue-maxnix --unmount` closes it again
#
# The root at /mnt is the one the last boot left: the wipe happens in the
# initrd of a boot, and this is not one. The roots of earlier boots are under
# old_roots on the btrfs top level (persistence.nix), which this does not
# mount.
#
# checks.metal-install runs 1 to 4 against a virtual disk, with a wrong
# passphrase first, and the system the harness then installs through these
# mounts boots. Step 5 is NixOS's own command.
#
# disk, mountScript and workDir come from the flake, as for install-maxnix;
# `preserved` is the list for step 4, luksRef the reference a bare --luks
# reads.
{
  pkgs,
  disk,
  mountScript,
  workDir,
  preserved,
  luksRef,
}:
pkgs.writeShellApplication {
  name = "rescue-maxnix";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.cryptsetup
    pkgs.util-linux
    pkgs.nixos-install-tools
  ];
  text = ''
    disk=${pkgs.lib.escapeShellArg disk}
    work=${pkgs.lib.escapeShellArg workDir}
    preserved=(${pkgs.lib.escapeShellArgs preserved})
    luks_ref="" luks_file="" enter=1 unmount=0

    die() { echo "rescue-maxnix: $*" >&2; exit 1; }
    usage() {
      echo "usage: rescue-maxnix [--luks [<op-ref>] | --luks-file <file>] [--no-enter]" >&2
      echo "       rescue-maxnix --unmount" >&2
      exit 2
    }
    while [ $# -gt 0 ]; do
      case "$1" in
        # With a reference after it, that one; bare, the built-in one.
        --luks)
          case "''${2-}" in
            op://*) luks_ref=$2; shift 2 ;;
            *) luks_ref=${pkgs.lib.escapeShellArg luksRef}; shift ;;
          esac
          ;;
        --luks-file) luks_file=''${2-}; shift 2 || usage ;;
        --no-enter) enter=0; shift ;;
        --unmount) unmount=1; shift ;;
        *) usage ;;
      esac
    done

    [ "$(id -u)" = 0 ] || die "run as root (sudo -i first)"

    if [ "$unmount" = 1 ]; then
      if mountpoint -q /mnt; then umount -R /mnt; fi
      if [ -e /dev/mapper/crypted ]; then cryptsetup close crypted; fi
      echo "unmounted, and the disk is closed" >&2
      exit 0
    fi

    # ── 1. checks ──────────────────────────────────────────────────────
    if [ ! -b "$disk" ]; then
      echo "disks by path:" >&2
      ls -l /dev/disk/by-path >&2 || true
      die "no disk at $disk"
    fi
    if mountpoint -q /mnt; then
      die "/mnt is mounted already: nixos-enter --root /mnt, or rescue-maxnix --unmount"
    fi
    target=$(readlink -f "$disk")
    echo "disk: $disk -> $target, $(lsblk -dno SIZE,MODEL "$target")" >&2

    # ── 2. passphrase ──────────────────────────────────────────────────
    # In /run, a tmpfs, and cleared by the trap: disko's script reads the
    # passphrase from a file.
    rm -rf "$work"
    install -d -m 700 "$work"
    trap 'rm -rf "$work"' EXIT
    if [ -n "$luks_file" ]; then
      cp "$luks_file" "$work/luks.key"
    elif [ -n "$luks_ref" ]; then
      op whoami >/dev/null 2>&1 || die "1Password's CLI is not signed in: eval \$(op signin)"
      op read --no-newline "$luks_ref" > "$work/luks.key" || die "could not read the LUKS passphrase from 1Password"
    else
      printf 'LUKS passphrase: ' >&2
      IFS= read -rs passphrase
      echo >&2
      printf '%s' "$passphrase" > "$work/luks.key"
    fi
    [ -s "$work/luks.key" ] || die "the LUKS passphrase is empty"

    # ── 3. mount ───────────────────────────────────────────────────────
    if ! ${mountScript}; then
      if mountpoint -q /mnt; then umount -R /mnt; fi
      if [ -e /dev/mapper/crypted ]; then cryptsetup close crypted; fi
      die "could not open and mount the disk: a wrong passphrase, or not the layout this stick was built for"
    fi

    # ── 4. state ───────────────────────────────────────────────────────
    for dir in "''${preserved[@]}"; do
      if [ -d "/mnt/persist$dir" ]; then
        mkdir -p "/mnt$dir"
        mount --bind "/mnt/persist$dir" "/mnt$dir"
      fi
    done

    echo "mounted at /mnt, nothing was changed. Generations on the disk:" >&2
    found=0
    for generation in /mnt/nix/var/nix/profiles/system-*-link; do
      [ -e "$generation" ] || [ -L "$generation" ] || continue
      found=1
      echo "  ''${generation#/mnt}" >&2
    done
    [ "$found" = 1 ] || echo "  (none)" >&2

    # ── 5. enter ───────────────────────────────────────────────────────
    if [ "$enter" = 1 ]; then
      echo "entering the installed system; exit leaves it mounted" >&2
      nixos-enter --root /mnt || true
      echo "still mounted at /mnt. rescue-maxnix --unmount when done." >&2
    fi
  '';
}
