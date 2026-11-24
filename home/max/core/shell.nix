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
{ pkgs, ... }:
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
  # Alt-C changes into a picked directory. Its third binding, Ctrl-R, stays
  # atuin's. The binary was already here for git's `cleanup` alias
  # (./git.nix).
  #
  # What gives atuin the key is order: Home Manager sources atuin's hook
  # after fzf's, and the later binding wins. historyWidget.command says the
  # same thing to Home Manager, which since a lock refresh in November 2026
  # warns at every evaluation when fzf and a history manager both claim
  # Ctrl-R and neither is told to stand down. The option alone would not do
  # it here: it sets FZF_CTRL_R_COMMAND as a session variable, and those
  # never reach a terminal on this machine (./dev.nix).
  #
  # Until 2026-11-24 an empty FZF_CTRL_R_COMMAND was written into ~/.bashrc
  # by hand ahead of fzf's hook, which Home Manager could not see as the
  # answer. Loading both generated files in a bare shell showed what that
  # line had been buying: nothing in emacs and vi-insert mode, where atuin
  # has Ctrl-R either way, and in vi-command mode readline's own search in
  # place of fzf's. Nothing here uses vi mode.
  programs.fzf = {
    enable = true;
    historyWidget.command = "";
  };

  # `z part-of-a-name` jumps to the directory used most and most recently
  # that matches; `zi` picks among the matches with fzf. It learns from
  # every cd, so it is empty on a new machine. Installed on the host and
  # never initialised there, so this is its first real trial.
  programs.zoxide.enable = true;

  # bash, the login shell, with Home Manager writing ~/.bashrc. No
  # `source <(… completion bash)` lines here: completions are files in
  # share/bash-completion/completions, which bash-completion loads on the
  # first Tab. 1password-cli ships its own; restish's is built in ./dev.nix.
  programs.bash.enable = true;
}
