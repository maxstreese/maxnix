# The interactive shell: prompt, history, pager, and zsh beside bash.
#
# Modules rather than bare packages, because atuin and starship do nothing
# until a shell hook initialises them. Their modules write that hook into
# every shell enabled here — bash and zsh — so the two shells behave the
# same.
#
# The login shell stays bash; `zsh` starts one. Making it the login shell is
# users.users.max.shell plus programs.zsh.enable at the system level.
{ pkgs, ... }:
let
  # The Ubuntu host's aliases and functions that its history shows in use
  # (../../../docs/inventory.md, "Shell configuration to port"), as programs
  # rather than aliases or functions. One definition then serves bash, zsh
  # and scripts, where a function would be written once per shell's init;
  # shellcheck runs at build; and each names what it needs, so none depends
  # on what a role happens to put on PATH. That last point is why `clip` is
  # not a one-line alias: wl-clipboard is otherwise only in the desktop role,
  # and an alias here would be dead on z690-wsl.

  # The tree of a directory as ripgrep sees it: hidden files in, .git and
  # everything ignored out. `rt` or `rt some/dir`.
  rt = pkgs.writeShellApplication {
    name = "rt";
    runtimeInputs = with pkgs; [
      ripgrep
      tree
    ];
    text = ''
      rg --hidden --glob='!.git/' --files "''${1:-.}" | tree -a --fromfile
    '';
  };

  # Standard input to the clipboard: `kubectl get … | clip`. Was xclip on the
  # host; wl-copy here, which also works under WSLg.
  clip = pkgs.writeShellApplication {
    name = "clip";
    runtimeInputs = [ pkgs.wl-clipboard ];
    text = ''
      exec wl-copy "$@"
    '';
  };

  # Pretty-print the JSON in the clipboard, in place. A clipboard that is not
  # JSON is left as it was, with jq's error as the explanation.
  jsontidy = pkgs.writeShellApplication {
    name = "jsontidy";
    runtimeInputs = with pkgs; [
      jq
      wl-clipboard
    ];
    text = ''
      tidy=$(wl-paste --no-newline | jq .)
      printf '%s\n' "$tidy" | wl-copy
    '';
  };
in
{
  home.packages = [
    rt
    clip
    jsontidy
  ];

  # zsh, with Home Manager writing ~/.zshrc so the integrations below reach it.
  programs.zsh.enable = true;

  # Shell history in a SQLite database, searched with Ctrl-R. The database
  # lives in ~/.local/share/atuin on the /home disk. History from the Ubuntu
  # host does not carry over by itself: copy history.db there, or
  # `atuin import auto` from a shell history file.
  programs.atuin.enable = true;

  programs.starship.enable = true;

  programs.bat.enable = true;

  # bash, the login shell, with Home Manager writing ~/.bashrc. No
  # `source <(… completion bash)` lines here: completions are files in
  # share/bash-completion/completions, which bash-completion loads on the
  # first Tab. 1password-cli ships its own; restish's is built in ./dev.nix.
  programs.bash.enable = true;
}
