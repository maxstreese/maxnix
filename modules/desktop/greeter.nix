# The login screen.
#
# ── What this replaces, and what that costs ──────────────────────────────────
#
# Until now this was tuigreet: a terminal UI on tty1, chosen deliberately
# because it needs no GL. That meant a broken compositor still left a working
# login screen — a property that was genuinely useful while we were fighting
# virgl in steps 2 and 3.
#
# Dank Greeter gives that up. It is a Quickshell UI, so it needs a Wayland
# compositor to host it and therefore needs working GL. If the GPU setup ever
# breaks, you now get no greeter at all rather than a text one.
#
# On the real host that trade is sharper than in the VM: a GPU driver
# regression after an update means no login screen. The rescue path is
# deliberate and does not depend on GL: the text consoles on Ctrl+Alt+F2…F6
# keep a password login (no autologin — modules/base/default.nix
# explains). Log in there, `rebuild` or roll back, done.
#
# The trade is deliberate: the GPU path has been stable and tested for a while
# (tests/desktop.nix asserts virgl works on every run), and matching DMS
# visually is the point of having chosen DMS.
#
# To go back: drop this file from ../desktop/default.nix's imports and restore
# the tuigreet block there. Nothing else depends on it.
#
# ── Autologin, where the disk asked for a passphrase ─────────────────────────
#
# Decided 2026-10-15: one password at power-on, not two. On metal the LUKS
# passphrase is typed at every boot, and only someone who knows it gets
# that far, so asking again at the greeter adds typing, not protection. So
# greetd starts max's niri session itself (initial_session), once per boot;
# logging out lands on the greeter as before. The lock
# screen and sudo still ask for the login password.
#
# Only where a LUKS volume is unlocked at boot, which is metal alone: every
# VM and test node gets an empty boot.initrd.luks.devices from qemu-vm.nix,
# so they keep the greeter and the tests that go through it.
#
# And never with a disk that unlocks itself: TPM or FIDO2 unlock plus
# autologin would open the session for anyone who presses the power button.
# The assertion below stops such a build; the TPM layer this machine once
# planned was dropped for this (modules/metal/disk.nix).
#
# The keyring does not open through this. greetd starts an initial_session
# without pam_authenticate (greetd's context.rs: authenticate = false), and
# both pam_gnome_keyring and pam_systemd_loadkey — which would hand on the
# boot passphrase — act only in that step (read in their sources,
# 2026-10-15). So the keyring gets an empty password instead, chosen once
# when an app first asks for it: its file on /home is then protected by
# LUKS, and in backups by restic, rather than by a password of its own.
# While the session runs it is open either way.
#
# Measured in the dev VM with autologin forced on (2026-10-15): the session
# came up on tty1 with no greeter process; the existing keyring, which had a
# password, stayed locked; on a fresh one the first `secret-tool store` put
# up "Choose password for new keyring", and left empty, "Store passwords
# unencrypted?" → Continue made "Default keyring". After a reboot it reported
# Locked until first use and then opened without a prompt, secret intact.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The niri session as its .desktop entry runs it, the same way the
  # greeter would start it.
  niriSession = pkgs.writeShellScript "autologin-niri-session" ''
    entry="${config.services.displayManager.sessionData.desktops}/share/wayland-sessions/niri.desktop"
    exec $(${pkgs.gnused}/bin/sed -n 's/^Exec=//p' "$entry")
  '';
  selfUnlocking = lib.filter (o: lib.hasPrefix "tpm2-device=" o || lib.hasPrefix "fido2-device=" o) (
    lib.concatMap (d: d.crypttabExtraOpts) (lib.attrValues config.boot.initrd.luks.devices)
  );
in
{
  options.maxnix.autoLogin.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.boot.initrd.luks.devices != { };
    defaultText = lib.literalExpression "config.boot.initrd.luks.devices != { }";
    description = ''
      Start max's niri session at boot without the greeter, because the
      LUKS passphrase typed before it already identified the person. On
      wherever a LUKS volume is unlocked at boot.
    '';
  };

  config.assertions = [
    {
      assertion = !(config.maxnix.autoLogin.enable && selfUnlocking != [ ]);
      message = "maxnix.autoLogin needs a disk unlocked by a typed passphrase, not by ${toString selfUnlocking}: together they would open the session for anyone at the power button";
    }
  ];

  config.services.greetd.settings.initial_session = lib.mkIf config.maxnix.autoLogin.enable {
    user = "max";
    command = "${niriSession}";
  };

  config.programs.dms-greeter = {
    enable = true;

    # The greeter is a Quickshell client, so something has to be its Wayland
    # compositor: niri, the session compositor too. It was chosen over
    # Hyprland while both ran here, for being the lighter of the two and
    # validated at build time by checkConfig.
    compositor.name = "niri";

    # Use the niri the system already installs rather than resolving a second
    # copy from pkgs.
    compositor.package = config.programs.niri.package;

    # Track the user's DankMaterialShell palette, so the login screen and the
    # desktop are visibly the same thing rather than two Material themes that
    # happen to be adjacent.
    #
    # This expands to three files the greeter copies into its own cache:
    #   ~/.config/dms/settings.json
    #   ~/.local/state/dms/session.json
    #   ~/.cache/dms/dms-colors.json   -> colors.json
    # each also at its pre-2.0 path under DankMaterialShell/, listed first so
    # the dms one wins where both exist (DMS 2.0 renamed the dirs, 2026-10-20).
    #
    # The copy happens in greetd's preStart, which runs as root, so it can read
    # a 0700 home directory; each copy is guarded on the file existing, so a
    # machine that has never run DMS just uses the greeter's defaults. It also
    # reads the wallpaper path out of session.json and copies the image itself,
    # rewriting the path to point into the cache — otherwise the greeter, which
    # runs as `greeter`, could not read a wallpaper living under /home/max.
    #
    # ── Do NOT run `dms-greeter sync` on this machine ───────────────────
    #
    # Upstream's documentation describes syncing via a `dms-greeter sync`
    # command that adds your user to the greeter group, sets ACLs, and
    # *symlinks* the greeter cache at your live DMS config. The Nix module
    # takes a different route — root-owned *copies* made in greetd's preStart —
    # and the two would fight each other. Running sync here would replace the
    # module's copies with symlinks that the next rebuild undoes.
    #
    # The trade: the module's copies are a snapshot taken when greetd starts,
    # so the greeter shows the DMS state from *last* boot. Upstream's symlinks
    # are live. In exchange we need no group membership, no ACLs, and no
    # imperative setup step.
    #
    # ── What actually changes the greeter's appearance ──────────────────
    #
    # Of the three files, upstream documents settings.json as the one carrying
    # theme and appearance preferences; session.json carries the wallpaper.
    # colors.json on its own does not appear to drive what you see: repainting
    # every hex value in it bright green and restarting greetd left the login
    # screen pixel-identical.
    #
    # On a machine that has never had DMS configured, only colors.json exists,
    # so this option has nothing to sync yet and the greeter uses its defaults.
    # It starts mattering once you change a theme or wallpaper in DMS and those
    # two files appear.
    configHome = config.users.users.max.home;
  };

  # The module sets services.greetd.settings.default_session.command with
  # mkDefault, so any explicit command elsewhere would silently win and the
  # greeter would never appear. ../desktop/default.nix no longer sets one.
  #
  # Consequences of dropping tuigreet, so they are not a surprise:
  #   --power-shutdown / --power-reboot   Dank Greeter has its own power menu
  #   --greeting / --asterisks            styled by the greeter instead
  #   --sessions                          the module discovers sessions itself
  #     from services.displayManager.sessionPackages
  config.services.greetd.settings.default_session.user = lib.mkDefault "greeter";
}
