# The lock screen's PAM stack, and with it the failed-login lockout.
#
# DMS's lock screen checks the password through Quickshell's PamContext,
# and chooses the PAM service itself: a custom path from its settings,
# else /etc/pam.d/login if told it is "externally managed", else
# /etc/pam.d/dankshell if that exists, else one it generates in the
# user's config, else a `login` it ships — pam_env and pam_unix, no
# lockout (Modules/Lock/Pam.qml and assets/pam/login in dms-shell 1.6.3).
# Defining dankshell here puts the lock screen on a NixOS-built stack, with
# the lockout of ../base/login-limits.nix; none of the settings ahead of it
# are set in ../../home/max/dms-state.
{ ... }:
{
  maxnix.loginLimits.services = [ "dankshell" ];

  # Without fingerprint: DMS runs the reader in a PamContext of its own,
  # next to this one, and pam_fprintd in the password stack would make
  # every typed password wait for a finger first.
  security.pam.services.dankshell.fprintAuth = false;

  # The lock settings that are not left to the settings UI.
  #
  # DMS's settings are mutable state on purpose (../../home/max/desktop/dms.nix),
  # which would leave these to whoever last opened the Power & Sleep tab, and
  # on a freshly installed machine to DMS's defaults. /etc/dms/cli-policy.json
  # is DMS's own way round that: `dms run` reads it at every start and hands
  # `lock_settings` to the shell, which then shows each as managed and keeps
  # it out of settings.json (core/internal/clipolicy and Common/AdminPolicy.qml
  # in dux-shell 2.1). Only lock-related keys can be managed this way.
  #
  #   lockBeforeSuspend        off by default. On, DMS takes a logind delay
  #                            inhibitor and suspends only once the lock is up,
  #                            for its own idle timer and power menu and for a
  #                            sleep logind starts itself, the lid included.
  #                            Without it the machine can go down with the
  #                            session still showing and come back up showing
  #                            it, for however long the lock then takes.
  #   loginctlLockIntegration  on by default, stated because the other two
  #                            things here rest on it: `loginctl lock-session`
  #                            locks, and DMS reports the lock to logind as
  #                            LockedHint, which is what
  #                            ../../home/max/desktop/lock.nix listens for.
  #
  # Not testable in a VM, where every sleep verb is refused
  # (../../hosts/t14s/vm.nix): whether the lid really waits for the lock is
  # first seen on metal. tests/niri.nix checks that the policy reaches the
  # shell.
  environment.etc."dms/cli-policy.json".text = builtins.toJSON {
    policy_version = 1;
    lock_settings = {
      lockBeforeSuspend = true;
      loginctlLockIntegration = true;
    };
  };
}
