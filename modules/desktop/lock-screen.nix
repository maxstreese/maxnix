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
}
