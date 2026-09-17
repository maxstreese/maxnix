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
# keep a password login (no autologin — hosts/maxnix/configuration.nix
# explains). Log in there, `rebuild` or roll back, done.
#
# The trade is deliberate: the GPU path has been stable and tested for a while
# (tests/desktop.nix asserts virgl works on every run), and matching DMS
# visually is the point of having chosen DMS.
#
# To go back: drop this file from ../desktop/default.nix's imports and restore
# the tuigreet block there. Nothing else depends on it.
{
  config,
  lib,
  ...
}:
{
  programs.dms-greeter = {
    enable = true;

    # The greeter is a Quickshell client, so something has to be its Wayland
    # compositor. niri rather than Hyprland: it is the lighter of the two, its
    # config is validated at build time by checkConfig, and it has no
    # deprecation warning pending. This does not influence which session you
    # then log in to — both remain on offer.
    compositor.name = "niri";

    # Use the niri the system already installs rather than resolving a second
    # copy from pkgs.
    compositor.package = config.programs.niri.package;

    # Track the user's DankMaterialShell palette, so the login screen and the
    # desktop are visibly the same thing rather than two Material themes that
    # happen to be adjacent.
    #
    # This expands to three files the greeter copies into its own cache:
    #   ~/.config/DankMaterialShell/settings.json
    #   ~/.local/state/DankMaterialShell/session.json
    #   ~/.cache/DankMaterialShell/dms-colors.json   -> colors.json
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
  services.greetd.settings.default_session.user = lib.mkDefault "greeter";
}
