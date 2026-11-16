# tmux, and my configuration for it.
#
# aoe runs every agent session inside tmux (./aoe.nix), so this is the
# terminal those sessions live in, not an occasional tool.
#
# The settings are the ones from the Ubuntu host's ~/.tmux.conf, declared
# 2026-11-16: until then tmux was installed bare and a new machine would
# have had tmux's defaults. Written to ~/.tmux.conf, not through
# programs.tmux, for two reasons. That module writes
# ~/.config/tmux/tmux.conf and adds defaults of its own, and the point here
# is the file as it was. And aoe looks for a tmux config to decide whether
# to draw its own status bar ([tmux] status_bar = "auto"); its binary names
# ~/.tmux.conf, and whether it also knows the XDG path was not something to
# find out by losing the behaviour.
#
# Not here, though Claude Code's terminal documentation suggests them for
# tmux: allow-passthrough and extended-keys. Shift+Enter already inserts a
# newline inside aoe on the host without them, and a desktop notification
# per waiting session is not wanted (2026-11-16).
{ lib, pkgs, ... }:
let
  tmux = lib.getExe pkgs.tmux;
  # By store path: the binding below runs from tmux's server, whose PATH is
  # whatever the first client had. wl-clipboard is otherwise only in the
  # desktop half of the profile (../desktop/default.nix).
  wlPaste = lib.getExe' pkgs.wl-clipboard "wl-paste";
in
{
  home.packages = [ pkgs.tmux ];

  home.file.".tmux.conf".text = ''
    set-window-option -g alternate-screen on

    # vi keys in copy mode.
    setw -g mode-keys vi

    # Copies go to the terminal, which owns the system clipboard: tmux
    # passes the terminal's own clipboard sequence on and sets none itself.
    set -s set-clipboard external

    # Middle-click pastes the system clipboard (not tmux's own buffer) when
    # tmux owns the mouse. A program in the pane that wants the mouse itself
    # still gets the click.
    bind -T root MouseDown2Pane select-pane -t = \; if -F "#{||:#{pane_in_mode},#{mouse_any_flag}}" \
      { send-keys -M } { run "${wlPaste} -n | ${tmux} load-buffer -b sysclip - && ${tmux} paste-buffer -d -p -b sysclip -t '#{pane_id}'" }
  '';
}
