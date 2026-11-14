# Harlequin, with the adapters nixpkgs does not carry.
#
# `harlequin` is a SQL IDE in the terminal, and `hsql` its headless twin: one
# psql-like interface over every database it has an adapter for, with
# csv/json/parquet output, so an agent learns one tool rather than one per
# database. Both read connection profiles from
# ~/.config/harlequin/harlequin.toml, whose values may name environment
# variables (`password = "${PGPASSWORD}"`), so credentials come from `op run`
# rather than the file.
#
# DuckDB and SQLite are built in, and nixpkgs' harlequin already bundles the
# Postgres and BigQuery adapters. Trino and MySQL are packaged here from PyPI.
# An adapter is a plug-in found through Python entry points, so it has to sit
# in harlequin's own environment — installing it beside harlequin does
# nothing. Hence the override rather than two more home.packages entries.
#
# Both adapters pin their database client below what nixpkgs ships (trino
# <0.328, mysql-connector-python <10). The pins are relaxed rather than the
# clients downgraded; if a query ever fails inside the client, look here
# first. When nixpkgs gains either adapter, delete it from this file.
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  py = pkgs.python3Packages;

  # The adapters' PyPI versions and sdist hashes, keyed by distribution name.
  # A JSON file rather than Nix so Renovate can maintain it: it bumps a
  # version through a regex manager, then scripts/renovate-pypi-rehash
  # rewrites the hashes to match (see renovate.jsonc).
  pins = builtins.fromJSON (builtins.readFile ./harlequin-adapters.json);
  fromPypi =
    name:
    pkgs.fetchPypi {
      pname = name;
      inherit (pins.${name}) version hash;
    };

  # nixpkgs' trino client fails its own build at the pinned revision, so it
  # is not in the binary cache. The newer pythonMetadataCheckPhase looks the
  # distribution up by pname, "trino-python-client", while the package calls
  # itself "trino" — a naming mismatch, not a broken client. Skip that one
  # check; drop this once nixpkgs fixes the package.
  trino-python-client = py.trino-python-client.overridePythonAttrs {
    dontCheckPythonMetadata = true;
  };

  harlequin-trino = py.buildPythonPackage {
    pname = "harlequin-trino";
    inherit (pins.harlequin_trino) version;
    pyproject = true;

    src = fromPypi "harlequin_trino";

    build-system = [ py.poetry-core ];

    dependencies = [
      trino-python-client
      py.google-auth
      py.numpy
    ];

    pythonRelaxDeps = [ "trino" ];

    # harlequin requires its adapters and they require harlequin. As in
    # nixpkgs' harlequin-postgres, the cycle is cut here and closed by the
    # override below; the import check moves there too, since importing an
    # adapter imports harlequin.
    pythonRemoveDeps = [ "harlequin" ];
    doCheck = false;

    meta = {
      description = "Harlequin adapter for Trino";
      homepage = "https://github.com/tconbeer/harlequin-trino";
      license = pkgs.lib.licenses.mit;
    };
  };

  harlequin-mysql = py.buildPythonPackage {
    pname = "harlequin-mysql";
    inherit (pins.harlequin_mysql) version;
    pyproject = true;

    src = fromPypi "harlequin_mysql";

    build-system = [ py.hatchling ];

    # duckdb is a Python >= 3.14 requirement of the adapter, as in nixpkgs'
    # harlequin-postgres.
    dependencies = [
      py.mysql-connector
    ]
    ++ pkgs.lib.optional (py.pythonAtLeast "3.14") py.duckdb;

    pythonRelaxDeps = [ "mysql-connector-python" ];

    pythonRemoveDeps = [ "harlequin" ];
    doCheck = false;

    meta = {
      description = "Harlequin adapter for MySQL";
      homepage = "https://github.com/tconbeer/harlequin-mysql";
      license = pkgs.lib.licenses.mit;
    };
  };

  harlequin = pkgs.harlequin.overridePythonAttrs (old: {
    dependencies = old.dependencies ++ [
      harlequin-trino
      harlequin-mysql
    ];
    pythonImportsCheck = old.pythonImportsCheck ++ [
      "harlequin_trino"
      "harlequin_mysql"
    ];

    # Harlequin's own test suite is not run again here. This override only
    # adds two adapters to its environment, which that suite does not touch,
    # and nixpkgs' unmodified harlequin is on cache.nixos.org, so Hydra has
    # already run all of it on the same source. Re-running it cost about 2.5
    # minutes a build (1,935 tests) and made every build of the machine
    # depend on tests that wait on real clocks: on 2026-11-14 one of them,
    # an `hsql --timeout 0.1` case, failed on a busy runner and took the
    # closure-diff job with it, while the same derivation built in `checks`
    # beside it. The import check above still runs, and is what covers the
    # two adapters.
    doCheck = false;
  });
in
{
  home.packages = [ harlequin ];

  # The connection profiles. Their hosts and users are sops secrets, so the
  # file is rendered at activation by the system layer
  # (../../../hosts/t14s/secrets.nix) into /run/secrets, outside the store,
  # and only linked from here. Read-only as a result: change a profile there
  # and rebuild, not with `hsql --config init`.
  xdg.configFile."harlequin/config.toml" = lib.mkIf osConfig.maxnix.harlequin.profiles.enable {
    source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.templates."harlequin.toml".path;
  };
}
