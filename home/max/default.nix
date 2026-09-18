# The user layer.
#
# Home Manager runs the same module system as the rest of this repo, scoped to
# one user instead of the machine. It builds dotfiles into /nix/store and
# symlinks them into $HOME, so ~/.config files stop being things you edit and
# become build artifacts — the same trade NixOS makes for /etc.
#
# The split with the system layer: NixOS *enables* a thing (installs it,
# registers its session, wires portals); this layer *configures* it. Note that
# programs.niri exists in both namespaces and they are not the same option —
# see ./niri.nix.
{ lib, pkgs, ... }:
{
  imports = [
    ./dms.nix
    ./niri.nix
    ./hyprland.nix
    ./firefox.nix
    ./apps.nix
    ./ssh.nix
  ];

  home.username = "max";
  home.homeDirectory = "/home/max";

  # Same rule as system.stateVersion, and a separate value: it pins the
  # defaults this config was written against. Set once, then leave alone.
  home.stateVersion = "26.11";

  # ── The terminal: ghostty ────────────────────────────────────────────
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
  programs.ghostty.enable = true;

  # ── git ──────────────────────────────────────────────────────────────
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

  # The launcher both compositor configs spawn, and the clipboard tools.
  #
  # These were in environment.systemPackages until now — installed machine-wide
  # purely so the compositors' default keybinds would not dead-end. They are
  # user preferences, so this is where they belong.
  #
  # kitty and wofi are gone: they existed only because Hyprland's *default*
  # config named them. Now that both compositors are configured here, one
  # terminal and one launcher serve both, which is also one less thing to
  # keep consistent between them.
  home.packages = with pkgs; [
    fuzzel
    wl-clipboard

    # ── Development tools ────────────────────────────────────────────────
    #
    # User-level, like the rest of this file: they are preferences, not
    # something the machine needs in order to work. git is the exception and
    # sits in environment.systemPackages — the guest needs it to clone and
    # rebuild this repo before any user profile exists.
    #
    # `scala` is Scala 3 (3.9 here; `scala_3` is the same derivation), and
    # brings scalac and scaladoc with it. No JDK alongside: the wrapper
    # carries OpenJDK 21. The `scala` command itself is scala-cli underneath
    # (it reports its own version 1.16), so a separate scala-cli is
    # redundant; sbt is not installed — add it here if a project wants it.
    # delta is git's pager and fzf backs the `cleanup` alias; both are
    # required by the git settings above.
    delta
    fzf

    # duckdb brings the `duckdb` CLI; the library rides along for anything
    # that links it. No server to run — it is in-process by design.
    duckdb
    kubectl
    scala

    # wev prints every Wayland key event its window receives, with the keysym.
    #
    # This is the debugger for a whole class of problem this setup keeps
    # producing, where nothing errors and a key simply does nothing:
    #
    #   - is the host compositor swallowing this key before the guest sees it?
    #     (bare Super never arrives unless scripts/vm-keys has released it,
    #     and "nothing visibly happened" proves nothing without this)
    #   - what keysym does this physical key actually produce on the current
    #     layout? (bracketleft is AltGr+8 on de, slash is Shift+7 — binding the
    #     US names produced three dead binds)
    #
    # niri's own documentation points at wev for the second question. Run it,
    # focus its window, press the key, read the sym: field in the terminal.
    wev
  ];


  # Enabling both compositors' Home Manager modules collides here: niri's sets
  # xdg.portal.enable = true and Hyprland's sets it false, and the module
  # system has no way to pick.
  #
  # Neither is needed. Portals are already configured at the system level by
  # the NixOS modules (programs.niri wires xdg-desktop-portal-gnome,
  # programs.hyprland wires xdg-desktop-portal-hyprland), and that is the layer
  # that should own them — a portal backend is machine-wide infrastructure, not
  # a user preference. So this turns the user-level duplicate off outright.
  xdg.portal.enable = lib.mkForce false;

  programs.home-manager.enable = true;
}
