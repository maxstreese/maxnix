# The interactive shell: bash, with prompt, history and pager.
#
# Modules rather than bare packages, because atuin and starship do nothing
# until a shell hook initialises them. Their modules write that hook into
# every shell enabled here, which is bash alone.
#
# zsh was enabled beside it until 2026-11-17 and went unused, and half
# wired: nothing linked /share/zsh into the profiles, so it saw no package's
# completions. fish was weighed that day and not taken either; atuin and
# starship already cover what a change of shell would mostly buy.
{ lib, pkgs, ... }:
let
  # The Ubuntu host's aliases and functions that its history shows in use
  # (../../../docs/inventory.md, "Shell configuration to port"), as programs
  # rather than aliases or functions. They then work from scripts and any
  # other shell too, not only at an interactive bash prompt; shellcheck runs
  # at build; and each names what it needs, so none depends on what a role
  # happens to put on PATH. That last point is why `clip` is not a one-line
  # alias: wl-clipboard is otherwise only in the desktop role, and an alias
  # here would be dead on z690-wsl.

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

  # Shell history in a SQLite database, searched with Ctrl-R. The database
  # lives in ~/.local/share/atuin on the /home disk. History from the Ubuntu
  # host does not carry over by itself: copy history.db there, or
  # `atuin import auto` from a shell history file.
  programs.atuin.enable = true;

  programs.starship.enable = true;

  programs.bat.enable = true;

  # ls, coloured and with git status in long listings. The module's bash
  # integration aliases ls, ll, la, lt (tree) and lla to it. Chosen over
  # dircolors and `ls --color=auto`, which is what the Ubuntu host had: plain
  # `ls` came over uncoloured, on the most-typed command in the history.
  programs.eza.enable = true;

  # The other half of what the host's .bashrc did for colour. eza covers ls;
  # grep still needs asking when it writes to a terminal.
  home.shellAliases.grep = "grep --color=auto";

  # fzf's key bindings: Ctrl-T pastes picked files onto the command line,
  # Alt-C changes into a picked directory. Its third binding, Ctrl-R, is
  # switched off below so that history stays atuin's. The binary was already
  # here for git's `cleanup` alias (./git.nix).
  programs.fzf.enable = true;

  # `z part-of-a-name` jumps to the directory used most and most recently
  # that matches; `zi` picks among the matches with fzf. It learns from
  # every cd, so it is empty on a new machine. Installed on the host and
  # never initialised there, so this is its first real trial.
  programs.zoxide.enable = true;

  # bash, the login shell, with Home Manager writing ~/.bashrc. No
  # `source <(… completion bash)` lines here: completions are files in
  # share/bash-completion/completions, which bash-completion loads on the
  # first Tab. 1password-cli ships its own; restish's is built in ./dev.nix.
  programs.bash = {
    enable = true;
    # Before fzf's hook, which reads it: an empty command is how fzf is told
    # to leave Ctrl-R alone. Order 100 because the fzf module writes its
    # hook at 200, ahead of mkBefore's 500. In ~/.bashrc and not
    # home.sessionVariables, because those never reach a terminal here
    # (../../../modules/base/default.nix).
    initExtra = lib.mkOrder 100 ''
      FZF_CTRL_R_COMMAND=
    '';
  };
}
