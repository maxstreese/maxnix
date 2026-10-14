# How many wrong passwords before an account locks, and for how long.
#
# The login password is the one barrier on a laptop that unlocks its disk by
# itself (the TPM enrolment in ./luks-tpm.nix takes no PIN): a stolen,
# powered-off machine boots to the greeter. Without a limit, that greeter,
# the lock screen and sudo take guesses for as long as anyone cares to type.
# NIST SP 800-63B-4 asks for at most 100 consecutive failures; this is well
# below that, and lenient enough that typos in a long passphrase do not lock
# the owner out. Decided 2026-10-14.
#
# pam_faillock, in the three places it has to be — nixpkgs' logFailures puts
# it in only one, as a counter without a lockout:
#
#   auth     preauth   before anything that can say yes: a locked account
#                      stays locked, password or fingerprint
#   auth     authfail  right after pam_unix fails: counts the failure, and
#                      [default=die] ends the attempt there
#   account            after a success: clears the count
#
# Positions are relative to nixpkgs' own rules, as its pam.nix asks: fixed
# numbers could silently reorder on an update and leave the stack open.
#
# Root too (even_deny_root). Root has the same password (./secrets.nix), and
# a root login at the text console would otherwise be the way around the
# limit. The emergency shell is unaffected: sulogin does not link PAM at all —
# it reads /etc/shadow itself (getspnam, crypt; checked 2026-10-14) — so a
# failed boot still offers a root shell to whoever knows the password.
#
# The count lives in /var/lib/faillock, preserved (./persistence.nix), not in
# faillock's default /var/run/faillock: a tmpfs, so a reboot would reset it.
#
# `faillock --user max` shows the count; `sudo faillock --user max --reset`
# clears it before the lock runs out.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Every service that asks for the login password:
  #   login      the text consoles, and the greeter, whose greetd service is
  #              a substack of login (../../modules/desktop/default.nix)
  #   sudo, su
  #   polkit-1   graphical password prompts, and run0
  #   dankshell  the lock screen, see below
  # Listed rather than derived from security.pam.services: setting options on
  # every member of that attrset while reading its names is infinite
  # recursion.
  services = [
    "login"
    "sudo"
    "su"
    "polkit-1"
    "dankshell"
  ];

  faillock = "${config.security.pam.package}/lib/security/pam_faillock.so";

  # nixpkgs builds linux-pam with its own etc in the store, and pam_faillock
  # reads its defaults from there: ignoring /etc/security/faillock.conf, it
  # locked after its built-in three failures and counted in the tmpfs.
  # Measured in tests/desktop.nix, 2026-10-14, which counts the failures for
  # exactly this reason. So every rule names the file, and the `faillock`
  # command, which has no option for a config file, is told the directory.
  conf = "/etc/security/faillock.conf";
  dir = "/var/lib/faillock";

  rulesFor =
    name:
    let
      auth = config.security.pam.services.${name}.rules.auth;
      account = config.security.pam.services.${name}.rules.account;
    in
    {
      # Ahead of the first rule that can authenticate, enabled or not, so it
      # stays ahead if fingerprint is switched on later. Only rules a service
      # has: unix-early, for one, exists in login alone.
      auth.faillock-preauth = {
        order =
          lib.foldl' lib.min auth.unix.order (
            map (r: r.order) (
              lib.attrVals (builtins.filter (r: auth ? ${r}) [
                "fprintd"
                "unix-early"
              ]) auth
            )
          )
          - 10;
        control = "required";
        modulePath = faillock;
        settings = {
          preauth = true;
          inherit conf;
        };
      };
      auth.faillock-authfail = {
        order = auth.unix.order + 10;
        control = "[default=die]";
        modulePath = faillock;
        settings = {
          authfail = true;
          inherit conf;
        };
      };
      account.faillock = {
        order = account.unix.order - 10;
        control = "required";
        modulePath = faillock;
        settings = { inherit conf; };
      };
    };
in
{
  security.pam.services =
    lib.genAttrs services (name: {
      rules = rulesFor name;
    })
    // {
      # DMS's lock screen checks the password through Quickshell's PamContext,
      # and chooses the PAM service itself: a custom path from its settings,
      # else /etc/pam.d/login if told it is "externally managed", else
      # /etc/pam.d/dankshell if that exists, else one it generates in the
      # user's config, else a `login` it ships — pam_env and pam_unix, no
      # lockout (Modules/Lock/Pam.qml and assets/pam/login in dms-shell 1.6.3).
      # Defining dankshell here puts the lock screen on a NixOS-built stack
      # with the rules above; none of the settings ahead of it are set in
      # ../../home/max/dms-state.
      #
      # Without fingerprint: DMS runs the reader in a PamContext of its own,
      # next to this one, and pam_fprintd in the password stack would make
      # every typed password wait for a finger first.
      dankshell = {
        rules = rulesFor "dankshell";
        fprintAuth = false;
      };
      # su is the one service where nixpkgs turns logFailures on: a bare
      # pam_faillock line of its own, counting without locking. Off, since the
      # rules above replace it; mkForce because nixpkgs sets it as a plain
      # value, not a default.
      su = {
        rules = rulesFor "su";
        logFailures = lib.mkForce false;
      };
    };

  environment.etc."security/faillock.conf".text = ''
    # ./login-limits.nix in the maxnix repo.
    deny = 10
    fail_interval = 900
    unlock_time = 600
    even_deny_root
    root_unlock_time = 600
    dir = ${dir}
  '';

  systemd.tmpfiles.rules = [ "d ${dir} 0700 root root -" ];

  # The `faillock` command, from the PAM the stacks above load, pointed at
  # the same directory. hiPrio over the unwrapped one, which looks in
  # /var/run/faillock and would show an empty count.
  environment.systemPackages = [
    (lib.hiPrio (
      pkgs.writeShellScriptBin "faillock" ''
        exec ${config.security.pam.package}/bin/faillock --dir ${dir} "$@"
      ''
    ))
  ];
}
