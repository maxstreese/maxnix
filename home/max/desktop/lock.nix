# What locks when the screen does.
#
# The lock screen itself is DMS's, on the PAM stack and under the policy in
# ../../../modules/desktop/lock-screen.nix. This file is for the other things
# a locked screen should mean, of which there is one so far.
#
# ── 1Password ────────────────────────────────────────────────────────────
#
# An unlocked 1Password behind a locked screen is one password away from
# every other, and it also serves the SSH agent and `op`. The app has a
# setting of its own for locking with the screen, which is state in its data
# directory and knows the desktops it was written for; this does not depend
# on either. It runs `1password --lock`, which hands the request to the
# running app, whenever logind's LockedHint turns true for one of max's
# sessions.
#
# LockedHint and not logind's Lock signal: the signal is a request, sent by
# `loginctl lock-session` and by DMS on its way to locking, while the hint is
# what DMS sets once the lock surface is up and secure (Modules/Lock/Lock.qml,
# notifyLockedHint). So this follows every way the screen locks, the bind,
# the idle timer and the lock before suspend alike, and only real locks.
#
# gdbus rather than busctl or dbus-monitor to listen: those ask the bus to
# become a monitor, which the system bus grants to root alone. gdbus adds an
# ordinary match rule, and these property changes are broadcast.
{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  onepassword = lib.getExe' osConfig.programs._1password-gui.package "1password";

  lockOnePassword = pkgs.writeShellApplication {
    name = "lock-1password";
    runtimeInputs = [
      pkgs.glib
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      me=$(id -un)
      gdbus monitor --system --dest org.freedesktop.login1 | while IFS= read -r line; do
        case "$line" in
          *"'org.freedesktop.login1.Session'"*"'LockedHint': <true>"*) ;;
          *) continue ;;
        esac
        # "/org/freedesktop/login1/session/_32: org.freedesktop.DBus.…": the
        # object path is everything before the first colon.
        session=''${line%%:*}
        owner=$(busctl --system get-property org.freedesktop.login1 "$session" \
          org.freedesktop.login1.Session Name 2>/dev/null) || continue
        [ "$owner" = "s \"$me\"" ] || continue
        # By command line: the app runs through a Nix wrapper, so its process
        # name is not `1password`. Not running means nothing is unlocked, and
        # `--lock` would start the app only to lock it.
        if pgrep -u "$me" -f '/share/1password/' >/dev/null; then
          ${onepassword} --lock && echo "screen locked: locked 1Password"
        else
          echo "screen locked: 1Password is not running, nothing to lock"
        fi
      done
    '';
  };
in
{
  systemd.user.services.lock-1password = {
    Unit = {
      Description = "Lock 1Password when the screen locks";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.getExe lockOnePassword;
      # The listener ends if the bus connection does; it has no state to lose.
      Restart = "always";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
