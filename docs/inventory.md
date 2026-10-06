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

- **mise goes.** It manages node, pnpm, java, uv, deno, sops, yq and more by
  downloading generic Linux binaries, which NixOS does not run (see the
  README finding). Runtimes become per-project flakes entered through the
  direnv + nix-direnv already in `home/max/dev.nix`; the few CLIs wanted
  everywhere go in the user layer. sdkman goes for the same reason.
- **Three host services are not coming**: an endpoint-security agent, a
  second VPN client, and a remote-desktop tool. Twingate is the VPN here.
- **Ubuntu-only plumbing is not coming**: snapd, livepatch, the apt/snap/brew
  update alias (`sysup`) that Nix replaces.
- **Prompt and history** are Home Manager's atuin and starship modules, in
  `home/max/shell.nix`, which also enables zsh beside bash so both get the
  hooks. atuin's history from the Ubuntu host has to be copied over by hand.
- **DBeaver, not DataGrip.** DataGrip came over first and was swapped out the
  same day: DBeaver is free, so it needs no unfree allow-list entry.
- **Harlequin for SQL in the terminal**, with Trino and MySQL adapters
  packaged in `home/max/harlequin.nix`. It covers what `trino`, `mysql` and
  `psql` were typed for, so those three stay out (`trino-cli` is in anyway).

## Still to decide

1. **Neovim** (508 runs in 90 days, LazyVim). Keep `~/.config/nvim` as is,
   symlinked out of the store into a clone like `maxnix.dev.liveConfig`, or
   port it to Nix (nixvim)? Either way Mason's downloaded language servers
   will not run; LSPs and formatters have to come from nixpkgs.
2. **Shell aliases and functions** — none ported yet; see the last section.
3. **Rows proposed U but not added**: tldr (tealdeer), bd (beads), mill.
4. **The "?" rows below.**

## Already in maxnix

From before the inventory: git, gh, delta, fzf, direnv, kubectl, awscli2,
steampipe, duckdb, scala, claude-code, 1Password and `op`, Twingate, Docker
(rootless), marimo, ghostty, Firefox, Slack, Discord, Spotify, Steam,
Wootility, htop, osquery, vim, comma.

From the inventory (2026-10-01), marked ✓ in the tables: the everyday CLI in
`home/max/dev.nix`, atuin, starship, bat and zsh in `home/max/shell.nix`, OBS
and GIMP in `home/max/apps.nix`, DBeaver, Harlequin.

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
| nvim | 508 (2362) | neovim 0.12.5 | U+cfg | decision 1; `svim` function uses it |
| aoe | 372 (806) | **missing** | U ✓ | upstream's flake, pinned to a release tag |
| rg | 269 (791) | ripgrep | U ✓ | also used by the `rt` function |
| mill | 130 (863) | mill 1.1.8 | P or U | not added yet |
| bat | 106 (264) | bat | U+cfg ✓ | `programs.bat` |
| pnpm | 75 (88) | pnpm | P | |
| glow | 63 (205) | glow | U ✓ | |
| kubectx / kubens | 57 (136) | kubectx | U ✓ | aliases to kubectl today |
| rt | 47 (104) | — | U | shell function: `rg --files` into `tree`; not ported |
| btop | 33 (202) | btop | U ✓ | also the `jtop` alias |
| fd | 21 (96) | fd | U ✓ | `fdfind` on Ubuntu |
| trino | 17 (92) | trino-cli | U ✓ | Harlequin's Trino profile too |
| tldr | 16 (43) | tealdeer | U | not added yet |
| argo | 11 (52) | argo-workflows | U ✓ | |
| duf | 9 (84) | duf | U ✓ | |
| helm | 9 (26) | kubernetes-helm | U ✓ | |
| jq | 8 (16) | jq | U ✓ | |
| harbor | 8 | harbor-cli | U ✓ | |
| clip, jsontidy | 8 | wl-clipboard ✓ | U | aliases over xclip; wl-copy on Wayland; aliases not ported |
| sqlfluff | 8 | sqlfluff | , or P | |
| deno | 7 | deno | P | |
| flux | 6 (9) | fluxcd | U ✓ | |
| agentsview | 5 (14) | not checked | ? | |
| bd | 5 | beads | U | not added yet |
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
Candidates for `,` — or P for sbt. Harlequin covers mysql and psql.

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
| IntelliJ IDEA Ultimate | launcher alias | jetbrains.idea-ultimate | U (unfree) |
| CLion | launcher alias | jetbrains.clion | ? |
| Rider | installed | jetbrains.rider | ? |
| DataGrip | installed | jetbrains.datagrip | X — DBeaver replaced it |
| Thunderbird | dock favourite | thunderbird | U |
| Zoom | installed | zoom-us | U |
| Obsidian | installed | obsidian | U |
| Threema | installed | threema-desktop | U |
| LibreOffice | dock favourite | libreoffice | U |
| Zed, Cursor, VS Code | installed; `code` 2 runs | all present | ? |
| DBeaver | installed | dbeaver-bin | U ✓ |
| Google Chrome | installed | google-chrome | ? |
| Wireshark | installed | wireshark | S (capture group) |
| Altair, GitButler, Unity Hub | installed | all present | ? |
| OBS, GIMP | installed | both present | U ✓ |
| Flameshot | installed | present | X — X11; niri and DMS have screenshots |
| JupyterLab desktop | installed | missing | X — marimo is here |
| Emacs, WezTerm | installed | both present | X — nvim and ghostty won |

## System services on the host

| service | proposal |
|---|---|
| PostgreSQL 17 server | S (`services.postgresql`) or a container; a local alias targets it, with a local password that belongs in an env file, not here |
| libvirt, VirtualBox | X inside the VM; revisit on metal |
| Docker | ✓ rootless, `hosts/maxnix/containers.nix` |

## Shell configuration to port

- **Aliases:** `ll`/`la`/`l`, `kubectx`/`kubens`/`kubepo`, `jtop`, `clip`,
  `jsontidy`, `tp`, and launchers for IntelliJ and CLion. None ported; the
  `kubectx`/`kubens` aliases are moot now that the real tools are in.
- **Functions:** `rt`, `svim`. Not ported.
- **Hooks:** starship and atuin ✓ (Home Manager modules); mise and sdkman
  going; cargo and deno env; and a long run of `source <(… completion bash)`
  lines. Most of those completions come free once the package is in Home
  Manager.

## Unidentified

`pw`, `gi`, `dt`, `t`, `wt` (probably worktrunk), `cs` (probably coursier),
`rum`, and a set of personal PR-automation shell scripts. Where the scripts
live, and whether they belong in a repository, is open.
