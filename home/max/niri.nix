# niri configuration.
#
# Two modules, two namespaces, two jobs:
#
#   NixOS  programs.niri.enable                installs niri, registers the
#                                              .desktop session so greetd can
#                                              offer it, wires xdg-portals and
#                                              polkit. Must be system-level:
#                                              greetd reads that session list
#                                              before any user logs in.
#   here   wayland.windowManager.niri.settings generates
#                                              ~/.config/niri/config.kdl.
#
# The Home Manager option sits under wayland.windowManager, matching Hyprland —
# so despite both being "niri config", the two never collide.
{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  # The bindings shared with ./hyprland.nix, rendered into niri's shape.
  # ./binds.nix explains why they live in one place.
  #
  # niri spells modifiers Mod/Shift/Alt/Ctrl and joins them to the key with
  # "+", where Hyprland writes them as a separate comma-separated field. Both
  # spellings stay in their own renderer so neither leaks into the list.
  niriMods = {
    mod = "Mod";
    shift = "Shift";
    alt = "Alt";
    ctrl = "Ctrl";
  };
  sharedBinds = lib.listToAttrs (
    map (b: {
      name = lib.concatStringsSep "+" (map (m: niriMods.${m}) b.mods ++ [ b.key ]);
      value = {
        _props =
          lib.optionalAttrs (b ? title) { hotkey-overlay-title = b.title; }
          // lib.optionalAttrs (b.locked or false) { allow-when-locked = true; };
        # Kept as a list: niri's spawn is argv, so an empty string here is a
        # real argument rather than whitespace. ./hyprland.nix has to drop
        # those because a shell string cannot express one.
        inherit (b) spawn;
      };
    }) (import ./binds.nix)
  );
in
{
  wayland.windowManager.niri = {
    enable = true;

    # package would ideally be null here, since the NixOS module already
    # installs niri — but checkConfig asserts on a non-null package (it needs a
    # niri binary to validate against). Build-time validation is worth more
    # than avoiding a duplicate profile entry, and the cost is zero bytes: this
    # is the same store path the system layer installs.
    package = pkgs.niri;

    # Validate at build time by running niri against the generated config, so a
    # typo fails the build instead of dropping you into a broken session.
    checkConfig = true;

    # The NixOS module already defines a systemd user service for niri. Leaving
    # this on would define a second one.
    systemd.enable = false;

    settings = {
      # ── Mod is Super, as upstream ──────────────────────────────────────
      #
      # For as long as this runs as a VM inside a GNOME session, Super has a
      # catch: GNOME's `overlay-key` is Super_L. While QEMU holds the keyboard
      # grab, Mutter inhibits its own shortcuts for that window — but the bare
      # overlay key is the one thing it still handles itself, and the grab is
      # only honoured once GNOME has been told to allow it. scripts/vm-keys
      # arranges both for the duration of a run, and its header explains the
      # mechanism:
      #
      #   scripts/vm-keys run -- nix run .#vm
      #
      # Without it, Super-based binds are dead in the guest. This used to be
      # worked around with Alt as the modifier; the binds are now upstream's,
      # which is also what the eventual metal install wants — none of this
      # applies once there is no host compositor in the way.
      #
      # ── Only bind keys that exist at the UNSHIFTED level of the layout ──
      #
      # niri resolves binds against the base keysym of a physical key, not the
      # character you would type: "binding shifted keys requires spelling out
      # Shift and the unshifted version of the key, according to your XKB
      # layout". Getting this wrong produces a bind that is configured, shown
      # in the hotkey overlay, and completely dead.
      #
      # niri's own defaults are US-centric, and three of them do not survive
      # the move to `de`:
      #
      #   key    us base level        de base level      de needs
      #   [      bracketleft          8                  AltGr+8
      #   ]      bracketright         9                  AltGr+9
      #   /      slash                7                  Shift+7
      #
      # So Mod+BracketLeft/Right became Mod+Comma/Period (comma and period are
      # at base level on both layouts), and Mod+Shift+Slash became Mod+Shift+7
      # — which is the same physical key combination that types "/" on a German
      # keyboard, and still resolves on US since 7 is unshifted there too.
      #
      # Rule of thumb for anything added here: letters, digits, arrows and
      # function keys are portable across layouts; punctuation is not. Check
      # with `xkbcli compile-keymap --layout de` before trusting a key name
      # taken from documentation.
      binds = {
        "Mod+Q".close-window = { };

        # Focus: columns left/right, windows within a column up/down.
        "Mod+Left".focus-column-left = { };
        "Mod+Right".focus-column-right = { };
        "Mod+Up".focus-window-up = { };
        "Mod+Down".focus-window-down = { };

        # Move the focused column along the scrollable strip. Upstream's
        # scheme: Mod+key focuses, Mod+Ctrl+key moves.
        "Mod+Ctrl+Left".move-column-left = { };
        "Mod+Ctrl+Right".move-column-right = { };

        # Workspaces are vertical in niri; the strip scrolls horizontally.
        "Mod+Page_Down".focus-workspace-down = { };
        "Mod+Page_Up".focus-workspace-up = { };
        "Mod+Ctrl+Page_Down".move-column-to-workspace-down = { };
        "Mod+Ctrl+Page_Up".move-column-to-workspace-up = { };

        # Sizing, and the two floating/tiling escape hatches.
        "Mod+R".switch-preset-column-width = { };
        "Mod+F".maximize-column = { };
        "Mod+Comma".consume-or-expel-window-left = { };
        "Mod+Period".consume-or-expel-window-right = { };
        "Mod+V".toggle-window-floating = { };
        "Mod+Shift+V".switch-focus-between-floating-and-tiling = { };

        "Mod+O".toggle-overview = { };

        # ── DankMaterialShell ──────────────────────────────────────────────
        #
        # Reproduced from inputs.dms.homeModules.niri, which we cannot import
        # (see ./dms.nix). Upstream's keys, except two that collide with
        # binds above:
        #
        #   upstream        here              collided with
        #   Mod+Comma       Mod+Shift+Comma   Mod+Comma  consume-or-expel-left
        #   Mod+V           Mod+C             Mod+V      toggle-window-floating
        # Media and brightness keys. Portable across layouts, and allowed
        # while the screen is locked.
        "Print".screenshot = { };
        "Mod+Shift+7".show-hotkey-overlay = { };
        "Mod+Shift+E".quit = { };
      }
      # Everything that runs a command comes from ./binds.nix, rendered
      # above, so these are identical to Hyprland's by construction.
      // sharedBinds;

      # Stated explicitly, even though niri would pick this up from
      # XKB_DEFAULT_LAYOUT on its own — it leaves the field empty, so
      # libxkbcommon falls back to the environment.
      #
      # Relying on that absence is fragile: it would break silently the day
      # niri adopts a default (exactly as Hyprland has, with kb_layout = "us"),
      # or the day this Home Manager module starts emitting one. Both
      # compositors now state the layout, and both read it from the same place,
      # so neither depends on an upstream default staying absent.
      input.keyboard.xkb.layout = osConfig.environment.sessionVariables.XKB_DEFAULT_LAYOUT;

      # Client-side decorations off: niri draws its own focus ring, and CSD
      # title bars waste a row in a tiling layout.
      prefer-no-csd = { };
    };
  };
}
