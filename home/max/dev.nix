# Development tools.
#
# User-level, like the rest of this directory: they are preferences, not
# something the machine needs in order to work. git is the exception and sits
# in environment.systemPackages — the guest needs it to clone and rebuild this
# repo before any user profile exists. Its *configuration* is still user-level,
# in ./git.nix.
{ pkgs, ... }:
{
  # gh, through its module rather than as a bare package, for one setting:
  # `gh repo clone` and friends default to HTTPS, which would ignore the SSH
  # auth key entirely and ask for a token instead. This points them at the
  # 1Password agent like every other git operation.
  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };

  home.packages = with pkgs; [
    # duckdb brings the `duckdb` CLI; the library rides along for anything
    # that links it. No server to run — it is in-process by design.
    duckdb

    kubectl

    # awscli2, the v2 line. Home Manager has a programs.awscli module for
    # ~/.aws/config and credentials, deliberately unused: there are no
    # profiles to declare yet, and when there are, its own advice is to use
    # `credential_process` to pull them from a password manager at runtime
    # rather than write them down — which is what ../../modules/desktop/
    # onepassword.nix already provides.
    awscli2

    # steampipe queries APIs as if they were Postgres tables. It embeds its
    # own database and starts it on demand, so there is no service to enable
    # here.
    steampipe

    # ── marimo, in a Python that can actually import things ──────────────
    #
    # marimo is a reactive Python notebook; `marimo edit foo.py` opens it in
    # the browser (Firefox, per ./firefox.nix).
    #
    # It comes from a python3.withPackages environment rather than the bare
    # `marimo` package, and that is the whole point. The bare package is
    # wrapped with a *closed* PYTHONPATH: marimo's own runtime dependencies
    # and nothing else, no polars, no pandas, and no pip to add any. A
    # notebook doing `import polars` fails, and installing polars elsewhere
    # in the profile changes nothing. A global marimo that cannot import
    # anything is a trap dressed as a convenience.
    #
    # So the library set is declared here, built for this machine, and shared
    # by the notebook and a plain `python3` shell. Adding one is an edit and
    # a rebuild. nixpkgs also has pandas, matplotlib, plotly and
    # scikit-learn.
    #
    # ── If a notebook needs something nixpkgs lacks ──────────────────────
    #
    # `marimo edit --sandbox` reads PEP 723 inline metadata from the notebook
    # and resolves it with uv, which is not installed here. Adding uv is not
    # enough on its own: uv downloads its own CPython, a generic-linux binary
    # this distribution cannot execute. Two ways round that, both verified in
    # the guest:
    #
    #   UV_PYTHON=${python3}/bin/python3 with UV_PYTHON_DOWNLOADS=never, so
    #     uv never fetches an interpreter. Nothing global changes.
    #   programs.nix-ld.enable, which puts a stub loader at /lib64 for every
    #     process on the machine.
    #
    # The first keeps the impurity out of the machine, so prefer it. The
    # NixOS wiki leads with the second.
    (python3.withPackages (
      ps: with ps; [
        marimo

        # What the notebooks are for.
        polars
        duckdb
        pyarrow
        altair
        numpy
      ]
    ))

    # `scala` is Scala 3 (3.9 here; `scala_3` is the same derivation), and
    # brings scalac and scaladoc with it. No JDK alongside: the wrapper
    # carries OpenJDK 21. The `scala` command itself is scala-cli underneath
    # (it reports its own version 1.16), so a separate scala-cli is
    # redundant; sbt is not installed — add it here if a project wants it.
    scala
  ];

  # marimo checks PyPI on startup and nags when it is behind. On a
  # Nix-installed package that advice is unusable: the store path is
  # immutable, there is no pip, and the version is whatever the pinned
  # nixpkgs carries — today 0.24.0 against 0.24.2 upstream, and nixpkgs
  # master has 0.24.0 too, so the lag is nixpkgs', not this repo's. It
  # closes when nixpkgs' updater bot bumps it and `nix flake update` picks
  # it up.
  #
  # This generalises: any Nix-installed tool with a self-update check will
  # nag forever, because the action it asks for cannot be taken. Silence
  # them rather than chase them.
  #
  # The variable that silences it is NOT here, and not a home.sessionVariables
  # entry either, because that option only reaches login shells. It is set at
  # the system level in ../../hosts/maxnix/configuration.nix, which is the
  # one route that reaches a terminal inside the compositor.
}
