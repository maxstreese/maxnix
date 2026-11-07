# NixOS under WSL on the Windows desktop (docs/desktop-pc.md): the base and
# GUI roles and NixOS-WSL, composed in flake.nix. No desktop role — WSLg
# draws Linux windows into Windows' own, so niri, DMS and the greeter have
# nothing to do — and no metal role: Windows owns the disk, the bootloader
# and the network, and the whole distribution is one VHDX file.
#
# Built here as `nix build .#checks.x86_64-linux.z690-wsl`; imported on Windows
# from `sudo nix run .#z690-wsl-tarball` (a nixos.wsl file) with `wsl --import`.
#
# Deliberately still open (docs/desktop-pc.md, "Still to decide"):
#
#   secrets    none yet. The guest needs an age key of its own and a
#              recipient in ../../.sops.yaml before anything is encrypted to
#              it; until then it declares no sops secrets at all.
#   password   NixOS-WSL's default: max has no password and sudo asks for
#              none (security.sudo.wheelNeedsPassword = mkDefault false in
#              its wsl-distro.nix). Windows' own login is the gate.
#
# 1Password comes from the GUI layer (../../modules/gui), the same modules as
# on the ThinkPad: the Linux app runs in this guest and WSLg draws its window,
# rather than bridging to the Windows app (decided 2026-11-06: a bridge would
# rest on a CLI and settings installed by hand on Windows, which nothing here
# describes). Once signed in, with "Use the SSH agent" and "Integrate with
# 1Password CLI" switched on in Settings → Developer, `op`, ssh and signed
# commits work as there. Unlocking differs: this host enables no polkit and
# runs no polkit agent, so "unlock with system authentication" is not
# offered and the app asks for the account password.
#
# What it takes from Windows — WSLg, the GPU driver, a URL opener — is all in
# ./windows.nix, with the rule that decides what may go there.
{ config, ... }:
{
  imports = [ ./windows.nix ];

  networking.hostName = "z690-wsl";

  wsl.enable = true;
  wsl.defaultUser = "max";

  # The 1Password app, started with the user's systemd instance and kept in
  # the background (--silent: no window until asked for), so the SSH agent
  # socket and `op`'s app integration exist from the first shell on. On the
  # ThinkPad the niri session starts it; here there is no session, only
  # WSLg's X server, whose socket NixOS-WSL mounts at /tmp/.X11-unix/X0.
  # DISPLAY is set explicitly because the user manager does not inherit it
  # from a login shell. X11 rather than Wayland: NIXOS_OZONE_WL is a desktop
  # role setting, and Electron without it takes X11, which WSLg serves
  # through XWayland. The mount may come up after the user manager, hence
  # the restart rather than an ordering this user unit cannot express
  # against a system mount.
  #
  # Untested until run on the desktop (docs/desktop-pc.md, section 3):
  # written 2026-11-06 from an Ubuntu distro on the same machine, where it
  # only builds.
  home-manager.users.max.systemd.user.services.onepassword = {
    Unit.Description = "1Password, in the background, for its SSH agent and op";
    Service = {
      ExecStart = "${config.programs._1password-gui.package}/bin/1password --silent";
      Environment = [ "DISPLAY=:0" ];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Pins the defaults this config was written against, per machine. Set once,
  # then leave alone.
  system.stateVersion = "26.11";
}
