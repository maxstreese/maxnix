# Development tools.
#
# User-level, like the rest of this directory: they are preferences, not
# something the machine needs in order to work. git is the exception and sits
# in environment.systemPackages — the guest needs it to clone and rebuild this
# repo before any user profile exists. Its *configuration* is still user-level,
# in ./git.nix.
{ inputs, pkgs, ... }:
{
  imports = [ inputs.nix-index-database.homeModules.nix-index ];

  # `,` runs a program from nixpkgs without installing it: `, ripgrep …`
  # fetches it, runs it, and leaves nothing behind but a store path the next
  # garbage collection takes.
  #
  # This is the pressure release for a recurring temptation. Something is
  # needed once — for a single debugging session, or to check whether a tool
  # is even the right one — and the path of least resistance is adding it
  # here, where it then stays forever and grows the closure. It is also the
  # honest answer to what nix-ld would have been used for, which this repo
  # looked at and rejected.
  #
  # The database is prebuilt and comes from a flake input, so nothing has to
  # index nixpkgs locally: building that database takes upwards of ten minutes
  # and leaves a cache file that is exactly the kind of undeclared state the
  # rest of this configuration works to eliminate.
  #
  # The full index is 102 MB. The small one is 1.8 MB and covers binaries,
  # which is all `,` itself needs — but nix-locate's other use is answering
  # "which package provides this header, or this .so", and that has come up
  # repeatedly here while chasing Mesa and GBM paths. 102 MB against a 12.5
  # GiB closure is under a percent, so the more useful one wins.
  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;

  # Per-project environments, entered by cd-ing into the directory.
  #
  # A project carries a flake and an .envrc, and its toolchain is whatever
  # that flake says rather than whatever this file happens to install. That
  # goes for data work too: there is no machine-wide Python environment with
  # polars and the like in it (README "Decisions, and why", notebooks).
  #
  # nix-direnv rather than bare direnv for two reasons. It caches the
  # evaluated environment, so re-entering a directory is instant instead of a
  # flake evaluation. And it keeps a GC root under the project's .direnv,
  # which matters now that nix.gc runs weekly with --delete-older-than 30d:
  # without it, collection would happily delete the dependencies of every
  # project not touched that month, and the next cd would rebuild them.
  #
  # .direnv is excluded from backups in ../../../modules/metal/backup.nix for the
  # same reason it is gitignored: it is a cache with a GC root in it, entirely
  # rebuildable from the flake beside it.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # mise, for work repos that pin their tools in a mise.toml. My own projects
  # carry a flake (direnv, above); mise is for repos I don't own, and its
  # downloads are upstream generic-linux builds that run only because of
  # nix-ld (../../../modules/base/nix-ld.nix). Nothing is installed through
  # it globally — tools wanted everywhere belong in home.packages below — so
  # it only ever acts inside a repo, and a repo's config acts only after
  # `mise trust`, the same gate as `direnv allow`.
  #
  # The activation hook goes into bash and zsh and puts a trusted repo's
  # tools ahead of this profile's on PATH. Its downloads land in
  # ~/.local/share/mise, which backups skip (../../../modules/metal/backup.nix).
  programs.mise = {
    enable = true;
    globalConfig.settings = {
      # mise detects NixOS and then defaults to compiling tools such as node
      # from source instead of downloading upstream builds, even with
      # nix-ld on. node 24's configure fails outright here (Python 3.14,
      # "too many values to unpack"; 2026-10-22), and even where it works it
      # is minutes of build per version. mise itself deprecates that default
      # and points at nix-ld, which is what makes the downloads run. Stated
      # explicitly until the default goes (mise 2027.8.0, per its warning).
      all_compile = false;

      # The self-update nag, which can never be acted on for a Nix-installed
      # mise: the store path is immutable and the version is whatever the
      # pinned nixpkgs carries. This goes for any Nix-installed tool with a
      # self-update check. Silence them rather than chase them.
      disable_update_warning = true;
    };
  };

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
    # rather than write them down — which is what ../../../modules/desktop/
    # onepassword.nix already provides.
    awscli2

    # steampipe queries APIs as if they were Postgres tables. It embeds its
    # own database and starts it on demand, so there is no service to enable
    # here.
    steampipe

    # Plain Python, for one-liners and scripts. No libraries on purpose: a
    # project's Python and its packages come from the project (direnv above),
    # and a scratch notebook brings its own through uv (below).
    python3

    # `scala` is Scala 3 (3.9 here; `scala_3` is the same derivation), and
    # brings scalac and scaladoc with it. No JDK alongside: the wrapper
    # carries OpenJDK 21. The `scala` command itself is scala-cli underneath
    # (it reports its own version 1.16), so a separate scala-cli is
    # redundant; sbt is not installed — add it here if a project wants it.
    scala

    # ── Everyday CLI ─────────────────────────────────────────────────────
    #
    # Carried over from the Ubuntu host on the evidence in
    # ../../../docs/inventory.md: each of these was typed in the last 90 days.
    # Rarer tools are left to `,` above.
    ripgrep
    fd
    glow
    btop
    duf
    jq
    tree
    unzip
    whois
    traceroute
    wget
    gnupg
    pwgen

    # Not from the inventory: asked for directly. Counts lines of code,
    # split into code, comments and blanks per language. Chosen over tokei
    # (same counts, fewer columns) and cloc (regex counting, slow) for its
    # per-file complexity column. cloc's one unique trick, diffing two
    # revisions (`, cloc --git --diff A B`), is occasional enough for `,`.
    scc

    # Terminal multiplexer.
    tmux

    # herdr, a terminal workspace manager for coding agents. Came from
    # upstream's flake while nixpkgs' 0.9.1 failed to link; 0.9.3 builds.
    herdr

    # ── Kubernetes and the platform around it ─────────────────────────────
    kubectx # kubectx and kubens
    kubernetes-helm
    fluxcd
    argo-workflows
    harbor-cli
    kaf

    # logcli has no package of its own; grafana-loki builds it alongside
    # loki, loki-canary and lokitool.
    grafana-loki

    # promtool only: prometheus splits it into its own `cli` output, so the
    # server does not come along.
    prometheus.cli

    # ── Data, JVM, Python ─────────────────────────────────────────────────
    trino-cli
    visualvm

    # uv. Its downloaded CPython is a generic-linux binary and runs because
    # nix-ld is on (../../../modules/base/nix-ld.nix); work repos' uv scripts
    # pin their own Python that way.
    #
    # It is also how a scratch notebook runs: `uvx marimo edit --sandbox
    # nb.py` resolves the dependencies the notebook declares inline (PEP 723)
    # into an environment of its own. Not set globally: UV_PYTHON, which
    # would override the Python a work repo pins. A project of my own that
    # wants a Nix Python sets UV_PYTHON and UV_PYTHON_DOWNLOADS=never in its
    # flake.
    uv

    # DBeaver Community, the database GUI. Free (Apache-2.0), so no
    # allow-list entry; it replaced DataGrip.
    dbeaver-bin

    # ── Inspecting this machine's own closure ─────────────────────────────
    #
    # sbomnix is TII's toolbox for the Nix store, from the team behind the
    # Ghaf platform. The tool wanted here is vulnxscan: a CVE scan of the
    # running system that combines vulnix, grype and OSV, and drops CVEs
    # nixpkgs has patched without bumping the version, by reading the patches
    # in each derivation. That is the false positive the employer's Fleet will
    # raise once it inventories Nix packages, because Fleet matches against
    # the NVD only (learned 2026-10-01). So `vulnxscan /run/current-system` is
    # how to answer "is this CVE real here?" before taking it to IT. The same
    # package brings sbomnix (a CycloneDX/SPDX SBOM of the system),
    # nix_outdated and nixgraph.
    #
    # It needs the system's .drv files, not just its outputs. A system built
    # here has them (keep-derivations is on by default); the VM does not,
    # since vm-deploy copies outputs only and the guest reports "No derivation
    # metadata found". Scan the VM's system from the host instead. A scan
    # against a closure that is only partly built degrades silently rather
    # than failing: tried 2026-10-01, it saw 49 components where the full
    # system has 1774, and grype and OSV found nothing.
    #
    # --triage looks packages up on repology.org, which the employer's DNS
    # resolves to 127.0.0.1, so on its network the flag crashes the run after
    # the scan, before anything is written.
    #
    # nix-tree is the follow-up question: what pulls a flagged library into
    # the closure, and so whether it can be dropped or has to wait for
    # nixpkgs.
    sbomnix
    nix-tree

    # ── Browser automation for agents ─────────────────────────────────────
    #
    # agent-browser drives a Chrome over CDP. Without one it offers
    # `agent-browser install`, which downloads Chrome for Testing — a
    # generic-linux binary this distribution cannot execute. It also searches
    # PATH (google-chrome first, then chromium and brave), so Google Chrome
    # here serves both agent-browser and any site that wants real Chrome.
    # Unfree; its allow-list entry is in ../../../modules/base/default.nix.
    # Started from somewhere without this profile's PATH, agent-browser will
    # not find it; AGENT_BROWSER_EXECUTABLE_PATH is the way round that.
    #
    # Microsoft's playwright-cli, the same idea built on Playwright, is not
    # in nixpkgs: NixOS/nixpkgs#490230 adds it and was still open on
    # 2026-10-02. Until it lands, `, playwright-mcp` covers the occasional
    # need.
    agent-browser
    google-chrome

    # ── Atlassian ─────────────────────────────────────────────────────────
    #
    # acli, Atlassian's own CLI for Jira and the rest of the Cloud suite.
    # Unfree; its allow-list entry is in ../../../modules/base/default.nix.
    acli

    # ── Secrets ───────────────────────────────────────────────────────────
    sops
    age
    betterleaks
  ];
}
