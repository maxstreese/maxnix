# git.
#
# Carried over from the host's hand-written ~/.gitconfig, which existed
# only there: a fresh guest had no git identity at all, so the first
# commit made inside would have been rejected. Now it is a build artifact
# like every other dotfile here — which also means `git config --global`
# stops working, because ~/.config/git/config becomes a store symlink.
# Edit this file and rebuild instead.
#
# Spelling note: this Home Manager version folded userName, userEmail and
# aliases into a freeform `settings` block, the same modernisation that
# caught ./ssh.nix.
#
# Only the personal identity is here. If work repositories ever land in
# the guest, `programs.git.includes` takes a `condition` such as
# "gitdir:~/work/" with its own `contents`, so the address follows the
# directory rather than the machine.
#
# Commit signing is deliberately absent. It would sign with an SSH key
# from 1Password, served by the agent in ./ssh.nix, and no such key
# exists yet. When one does: signing.format = "ssh", signing.key = the
# *public* key (not a secret, so it can live here), and signing.signer
# pointed at op-ssh-sign, which the 1Password package ships.
{ pkgs, ... }:
{
  programs.git = {
    # This installs git into the user profile as well. It is the same store
    # path as the system-wide one in hosts/maxnix/configuration.nix, which
    # stays: the guest needs git to clone this repo before a user profile
    # exists at all.
    enable = true;

    # Becomes ~/.config/git/ignore, which git reads as the global excludes
    # file on its own — no core.excludesFile needed. Same list as the
    # host's ~/.gitignore_global.
    ignores = [
      # Scala
      ".bloop/"
      ".metals/"
      "project/metals.sbt"

      # Java
      "*.classpath"
      "*.project"
      "*.factorypath"
      "*.settings"

      # Editors
      ".idea/"
      ".vscode/"

      # Assistants
      ".aider*"
      "**/.claude/settings.local.json"
    ];

    settings = {
      user.name = "Max Streese";
      user.email = "max@streese.com";

      core.editor = "vim";
      init.defaultBranch = "main";

      # zdiff3 puts the common ancestor in the conflict markers, which makes
      # a three-way conflict readable rather than a guess.
      merge.conflictStyle = "zdiff3";

      # delta as the pager, installed below. The asymmetry is the host's and
      # is reproduced rather than tidied: plain delta for reading diffs,
      # side-by-side only for the interactive filter (`git add -p`).
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only --side-by-side";
      delta.navigate = true;

      alias = {
        # Fetch a .gitignore from gitignore.io: `git ignore scala,java`.
        ignore = ''!gi() { curl -sL https://www.gitignore.io/api/$@ ;}; gi'';

        # Pick a branch with fzf, delete it, prune the remote. Needs fzf.
        cleanup = ''!BRANCH=$(git branch -l --format='%(refname:short)' | grep -v 'main\|master' | fzf --prompt='Branch to delete: ') && git switch main && git pull && git branch -d $BRANCH && git remote prune origin'';

        # Clone as a bare repo plus a worktree for main.
        clone-aoe = ''!f() { repo="$1"; dir="$(basename "$repo" .git)"; git clone --bare "$repo" "$dir/.bare" && echo "gitdir: ./.bare" > "$dir/.git" && git -C "$dir" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' && git -C "$dir" fetch origin && git -C "$dir" worktree add main main; }; f'';
      };
    };
  };

  # Both are named by the settings above, so a missing one breaks git itself:
  # delta is the pager, and the `cleanup` alias shells out to fzf. They live
  # here rather than with the other tools in ./dev.nix because they are this
  # file's dependencies, not free-standing preferences.
  #
  # fzf's own shell integration (Ctrl-R history, Ctrl-T files) is a separate
  # Home Manager module and is deliberately not enabled; only the binary is
  # wanted here.
  home.packages = with pkgs; [
    delta
    fzf
  ];
}
