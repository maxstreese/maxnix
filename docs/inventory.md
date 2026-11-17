# Inventory of the current host

What the Ubuntu host actually runs day to day, taken 2026-09-29 so that what
moves into maxnix is chosen from evidence rather than memory. The everyday
terminal tools came over on 2026-10-01; rows marked ✓ are in maxnix. Pick up
the rest from "Still to decide".

## How it was taken

Two questions, kept apart, because an installed list alone would carry over
years of leftovers:

- **What is installed**, per source: apt (packages added after the Ubuntu
  installer, i.e. `apt-mark showmanual` minus `/var/log/installer/
  initial-status.gz`), snap, Homebrew, mise, uv tools, cargo, `~/.local/bin`,
  `/usr/local/bin`, `/opt`, flatpak, `.desktop` files, autostart, systemd
  user units.
- **What is used**, from atuin's history database: runs per program in the
  last 90 days, all-time runs and last use. History starts 2026-03-12. Only
  the program name of each command was read — never its arguments, which is
  where typed secrets live. GUI apps leave no history, so their evidence is
  indirect: autostart, dock favourites, aliases that launch them.

All of it is read-only, and the raw lists never left the host. Redoing it
later is the same collection; the counts below will have moved.

## Decided

- **mise stays, for work repos only** (changed 2026-10-22). It was to go: it
  manages node, pnpm, java, uv, deno, sops, yq and more by downloading generic
  Linux binaries, which NixOS does not run (see the README finding). For my
  own projects that still holds, and runtimes are per-project flakes entered
  through the direnv + nix-direnv in `home/max/core/dev.nix`, with the few
  CLIs wanted everywhere in the user layer. But the work repos pin their tools
  in a `mise.toml` that is not mine to replace, so nix-ld now runs those
  downloads and mise has no global tools (README "Decisions, and why").
  sdkman goes, as before.
- **Three host services are not coming**: an endpoint-security agent, a
  second VPN client, and a remote-desktop tool. Twingate is the VPN here.
- **Ubuntu-only plumbing is not coming**: snapd, livepatch, the apt/snap/brew
  update alias (`sysup`) that Nix replaces.
- **Prompt and history** are Home Manager's atuin and starship modules, in
  `home/max/core/shell.nix`, for bash. zsh was enabled beside it until
  2026-11-17 and removed unused. atuin's history from the Ubuntu host has to
  be copied over by hand.
- **No JetBrains product comes over** (2026-11-17): IntelliJ IDEA, CLion,
  Rider and DataGrip all stay behind. Neovim, with language servers for Nix
  and Scala, is the editor.
- **DBeaver, not DataGrip.** DataGrip came over first and was swapped out the
  same day: DBeaver is free, so it needs no unfree allow-list entry.
- **Harlequin for SQL in the terminal**, with Trino and MySQL adapters
  packaged in `home/max/core/harlequin.nix`. It covers what `trino`, `mysql` and
  `psql` were typed for, so those three stay out (`trino-cli` is in anyway).

## Still to decide

1. **Neovim** (508 runs in 90 days, LazyVim) — decided 2026-11-17, neither
   of the two options first written here (keep `~/.config/nvim` as is, or
   port it to nixvim). Of what LazyVim brought, a file picker, grep, language
   servers for Nix and Scala and format on save were in use, so a small
   configuration with just those, plus tree-sitter highlighting, was written
   fresh: `home/max/core/neovim.nix`, plugins and servers from nixpkgs,
   settings in plain Lua.
2. **Shell aliases and functions** — `rt`, `clip` and `jsontidy` ported
   2026-11-17; see the last section for the rest.
3. **Rows proposed U but not added** — settled 2026-11-17: tldr (tealdeer)
   went in, mill turned out to need nothing (its row), beads is out.
4. **The "?" rows below** — settled 2026-11-17, each in its row.

## Already in maxnix

From before the inventory: git, gh, delta, fzf, direnv, kubectl, awscli2,
steampipe, duckdb, scala, claude-code, 1Password and `op`, Twingate, Docker
(rootless), ghostty, Firefox, Slack, Discord, Spotify, Steam,
Wootility, htop, osquery, vim, comma.

From the inventory (2026-10-01), marked ✓ in the tables: the everyday CLI in
`home/max/core/dev.nix`, atuin, starship and bat in `home/max/core/shell.nix`, OBS
and GIMP in `home/max/desktop/apps.nix`, DBeaver, Harlequin.

Not from the inventory, added since: sbomnix and nix-tree (CVE checks
against the running system), restic for the nightly backup, and rclone,
which the backup runs and the dev shell carries for authorising its Drive
token — it is not in the user layer.

## Terminal tools used this quarter

Homes: **U** user layer · **U+cfg** user layer, own file for its config ·
**S** system module · **P** per-project flake · **,** on demand via comma ·
**X** leave behind · **?** undecided. Versions are the pinned nixpkgs'.

| tool | 90d (all) | nixpkgs | home | note |
|---|---|---|---|---|
| nvim | 508 (2362) | neovim 0.12.5 | U+cfg ✓ | decision 1; `svim` function used it |
| aoe | 372 (806) | **missing** | U ✓ | upstream's release binary since 2026-11-14; its flake was removed 2026-10-06, as building it from source took CI from ~15 to ~55 min |
| rg | 269 (791) | ripgrep | U ✓ | also used by the `rt` function |
| mill | 130 (863) | mill 1.1.8 | X | nothing to install: every run is a repo's own `./mill` wrapper, which downloads the launcher and JVM the build pins (generic-linux binaries, so through nix-ld; not yet run on NixOS) |
| bat | 106 (264) | bat | U+cfg ✓ | `programs.bat` |
| pnpm | 75 (88) | pnpm | P | |
| glow | 63 (205) | glow | U ✓ | |
| kubectx / kubens | 57 (136) | kubectx | U ✓ | aliases to kubectl today |
| rt | 47 (104) | — | U ✓ | was a shell function: `rg --files` into `tree`; a program in `home/max/core/shell.nix` |
| btop | 33 (202) | btop | U ✓ | also the `jtop` alias |
| fd | 21 (96) | fd | U ✓ | `fdfind` on Ubuntu |
| trino | 17 (92) | trino-cli | U ✓ | Harlequin's Trino profile too |
| tldr | 16 (43) | tealdeer | U ✓ | fetches its pages on first use |
| argo | 11 (52) | argo-workflows | U ✓ | |
| duf | 9 (84) | duf | U ✓ | |
| helm | 9 (26) | kubernetes-helm | U ✓ | |
| jq | 8 (16) | jq | U ✓ | |
| harbor | 8 | harbor-cli | U ✓ | |
| clip, jsontidy | 8 | wl-clipboard ✓ | U ✓ | were aliases over xclip; programs over wl-copy in `home/max/core/shell.nix` |
| sqlfluff | 8 | sqlfluff | , or P | |
| deno | 7 | deno | P | |
| flux | 6 (9) | fluxcd | U ✓ | |
| agentsview | 5 (14) | not checked | X | not coming (2026-11-17) |
| bd | 5 | beads | X | not coming (2026-11-17) |
| uv | 4 (44) | uv | U ✓ | projects still pin their Python |
| kaf | 4 (15) | kaf | U ✓ | |
| visualvm | 4 (12) | visualvm | U ✓ | |
| websocat | 3 (29) | websocat | , | |
| betterleaks | 3 | betterleaks | U ✓ | |
| herdr | 3 | herdr | U ✓ | was upstream's flake while nixpkgs' 0.9.1 failed to link |
| tmux | 2 (43) | tmux | U ✓ | fading, but aoe runs on it |
| sops, age | 2 | sops, age | U ✓ | also what maxnix's own secrets need |
| dolt | 2 | dolt | , | |
| pwgen | 2 (17) | pwgen | U ✓ | proposed `,`; went in with the basics |
| logcli | via completion | grafana-loki | U ✓ | its address variable goes with it |
| promtool | 1 (19) | prometheus | U ✓ | proposed `,`; `prometheus.cli` brings promtool without the server |
| tree, unzip, whois, traceroute, wget, gpg | low | all present | U ✓ | small basics |

## Used before, not this quarter

opencode 0 (208), mysql 0 (165), psql 0 (128), sbt 0 (28), restish 0 (41).
Candidates for `,` — or P for sbt. Harlequin covers mysql and psql. restish
went in anyway on 2026-11-17, asked for directly.

## Installed, never in the history

k9s, lazygit, zoxide (installed but never initialised), difftastic,
ast-grep, nushell, babashka, typst, pandoc, yt-dlp, lnav, jo, jd, dotenvx,
temporal, cdk8s, cdxgen, opentofu, terraform, act, semgrep, usql, mongosh,
kind, kustomize, kubetail, mirrord, telepresence, minikube, talosctl, devpod,
dagger, flyway, powerpipe, coder, racket, aider, codex, gemini-cli, llm,
aichat, markitdown, docling, specify, httpie, rclone (now in the dev shell,
for the backup), onefetch, go, rustup.

Default is to drop them or use `,`. The exception is anything run by scripts
or IDEs rather than typed, which history cannot see.

## GUI apps

| app | evidence | nixpkgs | home |
|---|---|---|---|
| IntelliJ IDEA Ultimate, CLion, Rider, DataGrip | installed; launcher aliases for the first two | all present | X — no JetBrains product comes over (decided 2026-11-17); Neovim is the editor and DBeaver replaced DataGrip |
| Thunderbird | dock favourite | thunderbird | X — a favourite, but essentially never used |
| Zoom | installed | zoom-us | X |
| Obsidian | installed | obsidian | X |
| Threema | installed, as the 2.0 beta from Flatpak | threema-desktop is 1.2.50, the older client | X — the host runs the 2.0 beta, which nixpkgs does not have, and the older client is not wanted in its place (2026-11-17) |
| LibreOffice | dock favourite | libreoffice | X — a favourite, but essentially never used |
| Zed, Cursor, VS Code | installed; `code` 2 runs | all present | X — Neovim is the editor |
| DBeaver | installed | dbeaver-bin | U ✓ |
| Google Chrome | installed | google-chrome | U ✓ — already in `home/max/core/dev.nix`, where agent-browser needs it |
| Wireshark | installed | wireshark | S ✓ — `modules/desktop/wireshark.nix`, with the capture group |
| Altair, GitButler, Unity Hub | installed | all present | X |
| OBS, GIMP | installed | both present | U ✓ |
| Flameshot | installed | present | X — X11; niri and DMS have screenshots |
| JupyterLab desktop | installed | missing | X — marimo, per notebook through uv |
| Emacs, WezTerm | installed | both present | X — nvim and ghostty won |

## System services on the host

| service | proposal |
|---|---|
| PostgreSQL 17 server | X — not coming (2026-11-17); the alias that targeted it was last used in June, and a project that wants one can run a container |
| libvirt, VirtualBox | X — nothing for now (2026-11-17): the host has no VM defined in either, and this repo's own VMs are QEMU through Nix. libvirt with virt-manager is the one to add if a long-lived VM is ever wanted |
| Docker | ✓ rootless, `modules/base/containers.nix` |

## Shell configuration to port

- **Aliases:** `ll`/`la`/`l`, `kubectx`/`kubens`/`kubepo`, `jtop`, `clip`,
  `jsontidy`, `tp`, and launchers for IntelliJ and CLion. `clip` and
  `jsontidy` ✓ (2026-11-17, as programs in `home/max/core/shell.nix`); the
  `kubectx`/`kubens` aliases are moot now that the real tools are in. The
  rest are not ported, and a recount that day says to leave them: `jtop` 2
  runs in 90 days (18 all-time), the others none, most of them never.
- **Functions:** `rt` ✓ (same file). `svim` not ported: 11 runs, the last on
  2026-07-31.
- **Hooks:** starship and atuin ✓ (Home Manager modules); mise ✓ (Home Manager
  module), sdkman going; cargo and deno env; and a long run of `source <(… completion bash)`
  lines. Most of those completions come free once the package is in Home
  Manager.
- **Colour and variables:** the host's `ls`/`grep` colour aliases became eza
  and a `grep` alias, and `GODEBUG=netdns=go` came over (2026-11-17).
  `LOKI_ADDR` did not: it names a work host, which does not belong in the
  repo. `EDITOR=nvim` came with Neovim (2026-11-17).
- **Not from the host**, added 2026-11-17: fzf's Ctrl-T and Alt-C bindings
  (Ctrl-R stays atuin's) and zoxide, which the host had installed but never
  initialised.

## Unidentified

`pw`, `gi`, `dt`, `t`, `wt` (probably worktrunk), `cs` (probably coursier),
`rum`, and a set of personal PR-automation shell scripts. None of them comes
over (decided 2026-11-17), so what they were is left unanswered.
