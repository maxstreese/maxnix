# NixOS under WSL on the Windows desktop (docs/desktop-pc.md): the base and
# GUI roles and NixOS-WSL, composed in flake.nix. No desktop role — WSLg
# draws Linux windows into Windows' own, so niri, DMS and the greeter have
# nothing to do — and no metal role: Windows owns the disk, the bootloader
# and the network, and the whole distribution is one VHDX file.
#
# Built here as `nix build .#checks.x86_64-linux.z690-wsl`; imported on Windows
# from `sudo nix run .#z690-wsl-tarball` (a nixos.wsl file) with `wsl --import`.
#
# Secrets and max's login password are in ./secrets.nix: a sops file and key
# of this host's own, and a password that is not metal's. sudo asks for none
# (security.sudo.wheelNeedsPassword = mkDefault false in NixOS-WSL's
# wsl-distro.nix); Windows' own login is the gate.
#
# 1Password comes from the GUI layer (../../modules/gui), the same modules as
# on the ThinkPad: the Linux app runs in this guest and WSLg draws its window,
# rather than bridging to the Windows app (decided 2026-11-06: a bridge would
# rest on a CLI and settings installed by hand on Windows, which nothing here
# describes). Once signed in, with "Use the SSH agent" and "Integrate with
# 1Password CLI" switched on in Settings → Developer, `op`, ssh and signed
# commits work as there. "Unlock with system authentication" asks for max's
# login password through polkit and the agent below, as on the ThinkPad.
# After an app restart the account password is still needed once.
#
# What it takes from Windows — WSLg, the GPU driver, a URL opener — is all in
# ./windows.nix, with the rule that decides what may go there.
{ config, pkgs, ... }:
{
  imports = [
    ./windows.nix
    ./secrets.nix
  ];

  networking.hostName = "z690-wsl";

  wsl.enable = true;
  wsl.defaultUser = "max";

  # max's password from sops (./secrets.nix). On since 2026-11-07, once the
  # host's key was restored and the hash was in ./secrets.yaml.
  maxnix.loginPassword.fromSops = true;

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

  # "Unlock with system authentication" for 1Password, as on the ThinkPad:
  # the app asks polkit, whose policy for it (polkitPolicyOwners in
  # ../../modules/gui/onepassword.nix) admits max, and an authentication
  # agent asks for max's login password (./secrets.nix). On the ThinkPad the
  # desktop role turns polkit on and the shell draws the prompt; here neither
  # exists, so both are named. pam_faillock already covers polkit-1
  # (../../modules/base/login-limits.nix).
  security.polkit.enable = true;

  # The agent, as a user service like 1Password's above and for the same
  # reasons (no session to start it, WSLg's X server at :0). It has to run in
  # the same logind session as the app it answers for: WSL gives max a login
  # session per terminal and one for the user manager (class "manager"), and
  # both services live in the latter. MATE's agent rather than polkit-gnome:
  # GTK, small, and still released (polkit-gnome's last was 2011).
  home-manager.users.max.systemd.user.services.polkit-agent = {
    Unit.Description = "polkit authentication agent, drawn through WSLg";
    Service = {
      ExecStart = "${pkgs.mate-polkit}/libexec/polkit-mate-authentication-agent-1";
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
