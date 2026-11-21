# Changelog

## 0.7.0

- `polars.read_csv(path, options)` accepts a one-byte `delimiter` and a
  `header` boolean; the new `pl_dataframe_read_csv_options` C ABI entry point
  keeps the old comma/header reader available;
- tests cover semicolon- and pipe-delimited reads, headerless input with
  Polars-generated column names, invalid options, and malformed CSV files;
- the LuaRocks source rockspec installs Lua modules through `$(LUADIR)` and the
  native bridge through `$(LIBDIR)` instead of staging everything under the
  rock metadata directory;
- the Lua loader also searches `package.cpath` directories for
  `libpolars_lua`, so a LuaRocks tree loads without `POLARS_LUA_LIB`;
- `scripts/install-rock.sh` stages the rock files and `scripts/rockspec.sh`
  validates the LuaRocks install path in a temporary tree;
- `drop_nulls()` and `fill_null()` SQL-backed null handling;
- `iter_rows()`, `column_names()`, and `is_empty()` frame helpers;
- `unique()` and `null_count()`;
- 50 tests.

## 0.6.0

- LuaRocks source rockspec and `make install` flow;
- install smoke covers the LuaRocks/prefix layout.

## 0.5.0

- ordered `df:columns()` and stable column order;
- writer round-trip and failure-path tests;
- prefix install/smoke workflow and default library discovery fix.

## 0.4.0

- CSV and Parquet writers;
- drop/rename/with_columns helpers;
- 32 tests.

## 0.3.0

- eager full/outer, semi, anti, and cross joins;
- join-type tests;
- 31 tests.

## 0.2.0

- eager inner/left joins.
