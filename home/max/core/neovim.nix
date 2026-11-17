# Neovim: the editor, and $EDITOR.
#
# A small configuration written for this machine, not the LazyVim setup the
# Ubuntu host ran (508 runs in the inventory's 90 days). Of what LazyVim
# brought, four things were in use: a file picker, project grep, language
# servers for Nix and Scala, and format on save. Those are here, with
# tree-sitter highlighting, and little else; Neovim itself has grown the
# rest (LSP client, completion, commenting), so three plugins are enough:
# the picker, the language servers' definitions, and tree-sitter's grammars.
#
# Plugins and language servers come from nixpkgs, pinned by flake.lock like
# everything else. That replaces lazy.nvim and Mason, both of which download
# at run time. Considered and not taken: nixvim, which would add a flake
# input and put a Nix translation between this file and Neovim's own
# documentation, for a configuration of some seventy lines; and carrying
# ~/.config/nvim over as it was, which would have kept a distribution's
# worth of defaults for the sake of four features.
#
# The settings are plain Lua in ./nvim/maxnix.lua. Home Manager writes
# ~/.config/nvim/init.lua, which sets up the plugins' paths and then loads
# that file.
{
  config,
  osConfig,
  pkgs,
  ...
}:
let
  dev = osConfig.maxnix.dev;
in
{
  programs.neovim = {
    enable = true;
    # EDITOR=nvim, where NixOS' default is nano. This half sets it through
    # home.sessionVariables, which reach login shells only (README
    # "Findings"); the .bashrc line below is the half a terminal sees.
    defaultEditor = true;

    plugins = with pkgs.vimPlugins; [
      fzf-lua
      nvim-lspconfig

      # Tree-sitter highlighting. Neovim does the highlighting itself; this
      # brings what it needs per language, a compiled parser and the queries
      # that map syntax nodes to highlight groups. Every grammar nixpkgs
      # builds rather than a chosen list, so that any file opened is
      # covered and there is no list to keep: upstream's own way, compiling
      # a parser on first use, needs a C compiler at run time.
      nvim-treesitter.withAllGrammars
    ];

    # On nvim's own PATH rather than the profile's: these are the editor's
    # dependencies, and it should not matter what a role or a project
    # happens to provide. fzf, fd and ripgrep are in the profile as well
    # (./dev.nix, ./git.nix) and are repeated here for the same reason.
    # metals brings its own JDK.
    extraPackages = with pkgs; [
      fzf
      fd
      ripgrep
      nixd
      nixfmt
      metals
    ];

    initLua = ''
      require("maxnix")
    '';
  };

  # EDITOR for interactive shells, which is where git and the like are
  # started from. Not environment.sessionVariables, the usual way round the
  # login-shell gap here: that is system-wide, and root has no nvim, which is
  # in this user's profile only.
  programs.bash.initExtra = ''
    export EDITOR=nvim
  '';

  # With maxnix.dev.liveConfig (the VM), a link to the clone, so an edit to
  # the Lua takes effect at the next start of nvim without a rebuild; adding
  # a plugin or a server still needs one. Everywhere else the file is copied
  # into the store like every other generated config.
  xdg.configFile."nvim/lua/maxnix.lua".source =
    if dev.liveConfig then
      config.lib.file.mkOutOfStoreSymlink "${dev.clonePath}/home/max/core/nvim/maxnix.lua"
    else
      ./nvim/maxnix.lua;
}
