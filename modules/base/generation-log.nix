# What changed, each time the running system does: a changelog in the journal.
#
# After every switch and at every boot, this compares the running system with
# the one it saw last and logs `nvd diff` of the two, headed by one line:
#
#   generation changed: 26.11.20261112.2074cc6 (x9y2762q) -> 26.11.20261113.e126e9e (pljmcs5m): 3 version changes, 0 added, 0 removed
#
# The journal goes to Loki (./observability), where it is kept for a year:
#
#   {unit="generation-log.service"} |= "generation changed"
#
# and the two dashboards of this repo draw that query as annotations, so a
# graph that changes shape has a line on it at the moment of an update. The
# PR comment on a lock refresh says what an update will bring
# (../../tools/closure-table.py); this says what was running when.
#
# ── How it knows ─────────────────────────────────────────────────────────
#
# switch-to-configuration restarts sysinit-reactivation.target on every
# switch, after the activation has pointed /run/current-system at the new
# system, and a oneshot that target wants is started again each time
# (nixpkgs' systemd-tmpfiles-resetup hangs off the same target). multi-user.target
# covers the boot, where the change may be a rollback picked in the boot
# menu, which no switch ever saw.
#
# Not a path unit on /run/current-system: systemd watches the file a path
# names, and replacing a symlink is an event on its directory. Tried
# 2026-11-15 with a transient path unit on a symlink: neither `ln -sfn` nor
# a rename over it fired.
#
# What it compares against is a path in its state directory, since the
# system that ran before is otherwise only known to the profile, which
# `switch-to-configuration test` (the VM's `rebuild`) never touches. On
# metal that directory is persisted (../metal/persistence.nix); where it is
# not there, the first run records the system and has nothing to say.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  generationLog = pkgs.writeShellApplication {
    name = "generation-log";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.nvd
      # nvd asks `nix-build --version` before anything else and reads the
      # closures through nix-store; a unit's PATH has neither.
      config.nix.package
    ];
    text = ''
      # With two systems as arguments it only prints, for trying it by hand:
      #   generation-log /nix/var/nix/profiles/system-41-link /run/current-system
      if [ $# -eq 2 ]; then
        last=$(readlink -f "$1")
        new=$(readlink -f "$2")
        state=
      else
        state=''${STATE_DIRECTORY:?run as the generation-log unit}
        new=$(readlink -f /run/current-system)
        last=$(cat "$state/last" 2>/dev/null || true)
        [ "$new" != "$last" ] || exit 0
      fi

      # nixos-system-t14s-26.11.20261113.e126e9e, with the start of its hash:
      # two systems from one nixpkgs differ only there.
      label() {
        local base=''${1##*/}
        echo "''${base#*-nixos-system-} (''${base:0:8})"
      }

      if [ -z "$last" ]; then
        echo "generation recorded: $(label "$new"), the first seen here"
      elif [ ! -e "$last" ]; then
        echo "generation changed: $(label "$last") -> $(label "$new"): the earlier one is no longer in the store"
      elif report=$(nvd diff "$last" "$new"); then
        count() { grep -c "$1" <<<"$report" || true; }
        # nvd lists a package as changed when anything about its paths
        # differs, the number of copies included: "<none> x2 -> <none>" is
        # two paths becoming one, not a version. Counted are the rows whose
        # versions differ once the "xN" is taken off, and only rows with an
        # arrow: nvd's "Selection state changes" also start with [C and have
        # one version and no arrow. Without this a switch
        # between two systems of the same packages said "13 version changes"
        # (../../tests/observability.nix, 2026-11-15).
        moved=$(sed -n -E 's/^\[[UDC].\] +#[0-9]+ +[^ ]+ +//p' <<<"$report" \
          | sed -E 's/ x[0-9]+//g' \
          | awk -F' -> ' 'NF == 2 && $1 != $2' | wc -l)
        echo "generation changed: $(label "$last") -> $(label "$new"): $moved version changes, $(count '^\[A') added, $(count '^\[R') removed"
        echo "$report"
      else
        # Said, not failed: the system did change, and what is missing is
        # only the list.
        echo "generation changed: $(label "$last") -> $(label "$new"): nvd could not compare them"
      fi
      if [ -n "$state" ]; then
        echo "$new" > "$state/last"
      fi
    '';
  };
in
{
  systemd.services.generation-log = {
    description = "Log what changed when the running system changes";
    # A changelog must not be able to fail an update, and without care it
    # can: switch-to-configuration ends with status 4 if any unit it started
    # has failed, whether the target requires that unit or only wants it.
    # It did so twice in ../../tests/observability.nix (2026-11-15), while
    # nvd could not find nix-build and again while the script could not find
    # awk. Hence the `-` on ExecStart below, which has systemd take any exit
    # status as success: what went wrong is still in the journal.
    wantedBy = [
      "multi-user.target"
      "sysinit-reactivation.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "generation-log";
      ExecStart = "-${lib.getExe generationLog}";
    };
  };
}
