# The interactive shell: prompt, history, pager, and zsh beside bash.
#
# Modules rather than bare packages, because atuin and starship do nothing
# until a shell hook initialises them. Their modules write that hook into
# every shell enabled here — bash (./ssh.nix enables it) and zsh — so
# the two shells behave the same.
#
# The login shell stays bash; `zsh` starts one. Making it the login shell is
# users.users.max.shell plus programs.zsh.enable at the system level.
{ ... }:
{
  # zsh, with Home Manager writing ~/.zshrc so the integrations below reach it.
  programs.zsh.enable = true;

  # Shell history in a SQLite database, searched with Ctrl-R. The database
  # lives in ~/.local/share/atuin on the /home disk. History from the Ubuntu
  # host does not carry over by itself: copy history.db there, or
  # `atuin import auto` from a shell history file.
  programs.atuin.enable = true;

  programs.starship.enable = true;

  programs.bat.enable = true;
}
