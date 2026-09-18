# The terminal: ghostty.
#
# Both compositor configs spawn it as `ghostty +new-window`. Home Manager
# installs ghostty's D-Bus-activatable systemd user service by default, and
# `+new-window` talks to it directly: if no instance is running, the session
# bus asks systemd to start the service; if one is, it opens a window in
# ~20 ms instead of the ~300 ms a fresh process needs. Every window then
# lives in ghostty's own unit, app-com.mitchellh.ghostty.service — outside
# the compositor's cgroup on both compositors, which is the separation
# `uwsm app --` (Hyprland) and niri's per-spawn scopes exist for.
#
# Do not set `class` in ghostty's config: the docs warn it breaks the D-Bus
# activation the service relies on. Nothing else is configured yet; the
# defaults are what the tests' colour thresholds were checked against.
#
# ghostty replaced alacritty (2026-09-18). It renders through OpenGL, which
# virgl provides in the guest; the compositor tests draw a terminal and
# count colours, so a renderer that fails to come up fails the test.
{ ... }:
{
  programs.ghostty.enable = true;
}
