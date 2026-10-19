# The shared desktop layer: a greeter, and the bits the compositor expects to
# find. niri itself is in ./niri.nix. Hyprland ran next to it until
# 2026-10-18; what it needed of this layer is why the layer states things
# niri would have provided anyway (the keyring, below).
{ pkgs, ... }:
{
  imports = [
    ./greeter.nix
    ./lock-screen.nix
    ./niri.nix
    ./onepassword.nix
    ./gpu-check.nix
    ./steam.nix
    ./screen-recording.nix
  ];

  # The user layer's desktop half, on top of the core the base role imports.
  home-manager.users.max.imports = [ ../../home/max/desktop ];

  # Its unfree packages; see ../../home/max/desktop/apps.nix for why each is
  # wanted. Home Manager modules cannot declare their own: with useGlobalPkgs
  # they borrow the system's nixpkgs config.
  nixpkgs.config.allowUnfreePackages = [
    "spotify"
    "slack"
    # Both halves: the wrapper and the derivation it wraps each carry the
    # licence, and the allow-list matches on pname, so listing one leaves
    # the other refused.
    "discord"
    "discord-unwrapped"
  ];

  # The login screen lives in ./greeter.nix. It used to be configured here as
  # tuigreet; see that file for what changed and how to go back.

  # Terminals and launchers used to live here, installed machine-wide purely so
  # the compositors' *default* keybinds would not dead-end. The compositor is
  # now configured in home/max, so those are user packages and moved there
  # — which also let kitty and wofi go entirely.
  #
  # What stays is diagnostics: tools you want available before or without a
  # user session.
  environment.systemPackages = with pkgs; [
    wayland-utils # wayland-info: what the compositor actually advertises
  ];

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      dejavu_fonts

      # For DankMaterialShell. Its Nix modules handle no fonts at all —
      # checked, there is not a single font reference in them — and a Material
      # shell without Material Symbols draws every icon as an empty box. Inter
      # is the typeface the design language assumes.
      material-symbols
      inter
    ];
  };

  # Mesa, and the userspace bits a Wayland compositor expects to find.
  hardware.graphics.enable = true;

  # DRM access, needed by every compositor.
  users.users.max.extraGroups = [ "video" ];

  # Compositors need polkit for anything privileged (mounting, suspend).
  security.polkit.enable = true;

  # Tell Electron and Chromium-based apps to render on Wayland directly rather
  # than through XWayland. nixpkgs wraps such apps (1Password, Spotify, …) to
  # read this exact variable; without it they come up blurry on HiDPI and
  # ignore the compositor's fractional scaling. sessionVariables reach the
  # compositor sessions through PAM, same route as XKB_DEFAULT_LAYOUT.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # A Secret Service for the session. Firefox, Spotify, 1Password's system
  # authentication and anything else that "remembers a login" stores it in
  # the keyring; without one they either prompt every start or forget. The
  # niri module already enables this (mkDefault), but a keyring is part of
  # this layer's contract rather than a side effect of the compositor's
  # module — that was learned when Hyprland's did not set it — so it is
  # stated here.
  #
  # Enabling the daemon is half of it. The other half is unlocking the keyring
  # with the login password, and that is already covered: NixOS puts
  # pam_gnome_keyring into the `login` PAM service whenever this daemon is
  # enabled, and greetd's PAM service is a substack of `login` (greetd sets
  # useDefaultRules = false and delegates every phase to it). So the password
  # typed into Dank Greeter unlocks the keyring.
  #
  # Do NOT set security.pam.services.greetd.enableGnomeKeyring: greetd
  # replaces its rules wholesale, so that option renders nothing — it was
  # tried, and the built /etc/pam.d/greetd came out identical. The keyring
  # lines live in /etc/pam.d/login, which is what tests/desktop.nix asserts.
  services.gnome.gnome-keyring.enable = true;
}
