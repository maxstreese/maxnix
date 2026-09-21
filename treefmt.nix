# What `nix fmt` runs, and what `nix build .#checks.<system>.formatting` asserts.
#
# treefmt is a formatter multiplexer: one config, one command, every file type.
# The flake wires it in two places — as the `formatter` output, which is the
# conventional home for `nix fmt`, and as a check, so CI catches an unformatted
# tree without anyone remembering to run it.
#
# Only nixfmt is enabled today, and deliberately so:
#
#   nixfmt   the official Nix formatter (NixOS/nixfmt), RFC 166 style. This is
#            the style the repo was already written in by hand; turning it on
#            reformatted four files and changed nothing semantically.
#
#   shfmt    NOT enabled, though scripts/vm-keys is the obvious candidate.
#            shfmt cannot parse it: its parser reads an associative-array key
#            as an arithmetic expression, so the dconf paths in
#            `declare -A DISABLE=( [/org/gnome/mutter/overlay-key]=… )` fail
#            with "`/` must follow an expression". Reproduced on a three-line
#            file, so it is the key syntax and not this script. The shell code
#            inside flake.nix is already linted by writeShellApplication,
#            which runs shellcheck at build time.
#
#   markdown NOT enabled. README.md is hand-wrapped prose whose line breaks
#            carry meaning; a reflowing formatter would churn it every commit.
#
# Linters live in the separate `lint` check rather than here. treefmt-nix can
# run statix and deadnix, but only in *fix* mode — `nix fmt` would then delete
# an unused function argument as if that were whitespace. Reporting and
# rewriting are different acts and this repo keeps them apart.
{ ... }:
{
  # How treefmt finds the tree it is formatting.
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;
}
