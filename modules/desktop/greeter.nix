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
