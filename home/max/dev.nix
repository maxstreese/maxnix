# Development tools.
#
# User-level, like the rest of this directory: they are preferences, not
# something the machine needs in order to work. git is the exception and sits
# in environment.systemPackages — the guest needs it to clone and rebuild this
# repo before any user profile exists. Its *configuration* is still user-level,
# in ./git.nix.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # duckdb brings the `duckdb` CLI; the library rides along for anything
    # that links it. No server to run — it is in-process by design.
    duckdb

    kubectl

    # `scala` is Scala 3 (3.9 here; `scala_3` is the same derivation), and
    # brings scalac and scaladoc with it. No JDK alongside: the wrapper
    # carries OpenJDK 21. The `scala` command itself is scala-cli underneath
    # (it reports its own version 1.16), so a separate scala-cli is
    # redundant; sbt is not installed — add it here if a project wants it.
    scala
  ];
}
