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
# ── Commit signing ───────────────────────────────────────────────────
#
# SSH rather than GPG: git has supported it since 2.34, GitHub, GitLab and
# Bitbucket all verify it, and the key can live in 1Password and be used
# without ever touching disk. The private half never leaves the vault; the
# agent in ./ssh.nix serves it and op-ssh-sign asks the app to sign.
#
# Everything below is a *public* key, which is not a secret, which is the
# only reason signing can be declared in a repo at all.
#
# Two keys exist, scoped along different axes:
#
#   auth     "GitHub SSH Auth (maxstreese)"    one account on one host
#   signing  "Git Signing (max@streese.com)"   one identity, every host
#
# The auth key needs no configuration here: with an agent, the server
# challenges and the agent offers keys until one is recognised, so nothing
# local has to say which key belongs to GitHub. Signing is the opposite —
# nobody challenges, so the key has to be named.
#
# `allowedSigners` is what makes local verification work. Without it even
# your own commits cannot be verified on this machine and you are trusting
# the forge's badge alone; Home Manager writes the file and points
# gpg.ssh.allowedSignersFile at it. `signByDefault` covers both
# commit.gpgSign and tag.gpgSign.
#
# When a second identity appears, it gets its own line in allowedSigners
# and its own key, selected per directory by the `includes` above.
{ osConfig, pkgs, ... }:
{
  programs.git = {
    # This installs git into the user profile as well. It is the same store
    # path as the system-wide one in hosts/maxnix/configuration.nix, which
    # stays: the guest needs git to clone this repo before a user profile
    # exists at all.
    enable = true;

    signing = {
      format = "ssh";

      # The public half, as git wants it. The `key::` prefix is the current
      # spelling; a bare "ssh-ed25519 ..." still works but git's own docs
      # call that form deprecated.
      key = "key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICpkKkztOSruWMC2XiaEgTxn9atTVXws50qEN1cCuMpe";

      signByDefault = true;

      # op-ssh-sign from the very package the system installs, rather than a
      # second copy resolved from pkgs or a hardcoded /opt path as on a
      # conventional distribution.
      signer = "${osConfig.programs._1password-gui.package}/bin/op-ssh-sign";

      # Who this key speaks for. `namespaces="git"` restricts it to git
      # signatures, so the same key cannot be used to verify signatures made
      # for some other purpose.
      allowedSigners = ''
        max@streese.com namespaces="git" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICpkKkztOSruWMC2XiaEgTxn9atTVXws50qEN1cCuMpe
      '';
    };

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
        ignore = "!gi() { curl -sL https://www.gitignore.io/api/$@ ;}; gi";

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
