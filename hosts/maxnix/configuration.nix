# The machine.
#
# Nothing in this file knows or cares that it will run as a VM. Everything
# VM-shaped lives in ./vm.nix. Keeping that line clean is the whole point:
# this file stays true if the config is ever built for real hardware.
{ pkgs, ... }:
{
  networking.hostName = "maxnix";

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "de"; # matches your host's X11 layout

  users.users.max = {
    isNormalUser = true;
    description = "Max";
    extraGroups = [ "wheel" ];
    # Throwaway credential for a local VM; it lands world-readable in the Nix
    # store, which is fine here and would not be on a real machine.
    # `initialPassword` only applies when the user is first created — see the
    # note about stale disk images in ./vm.nix.
    initialPassword = "maxnix";
  };
  users.users.root.initialPassword = "maxnix";

  # No password prompt on sudo. A VM you throw away is not worth the friction.
  security.sudo.wheelNeedsPassword = false;

  # Log straight in on the console. Step 1 is about proving the build→run loop,
  # so every avoidable prompt is removed.
  services.getty.autologinUser = "max";

  environment.systemPackages = with pkgs; [
    git
    htop
    vim
  ];

  # Pins the defaults this config was written against so stateful services keep
  # their original semantics across nixpkgs upgrades. It is NOT a version to
  # keep current — set once, then leave alone.
  system.stateVersion = "26.11";
}
