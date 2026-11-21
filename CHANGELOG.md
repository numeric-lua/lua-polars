# Changelog

## Unreleased

- `polars.read_csv(path, options)` accepts `columns` as a single column name or
  a list of names; Polars applies the projection at read time and the returned
  frame keeps the requested order;
- the additive `pl_dataframe_read_csv_projected` C ABI entry point carries the
  projection; `pl_dataframe_read_csv`, `pl_dataframe_read_csv_options`, and
  `pl_dataframe_read_csv_ex` keep their signatures and defaults;
- projection validation rejects empty lists, non-string or empty entries,
  duplicate names, and unknown columns;
- tests cover projection order, single-column selection, headerless and
  quote/comment combinations, projecting every column, and the error paths;
- `scripts/check-version.sh` cross-checks `Cargo.toml`, `Cargo.lock`,
  `polars.lua`, the rockspec name/version/tag, README, API docs, and release
  notes; `scripts/rockspec.sh` runs it before installing and honors
  `POLARS_LUA_ROCK_TREE` for repeatable incremental validation;
- the installed-tree smoke test exercises a projected read;
- 62 tests.

## 0.8.0

- `polars.read_csv(path, options)` accepts a one-byte `quote` character and a
  one-byte `comment` prefix; `quote = false`/`quote = ""` disables quote
  parsing and `comment = false`/`comment = ""` disables comment skipping;
- the additive `pl_dataframe_read_csv_ex` C ABI entry point carries the quote
  and comment controls; `pl_dataframe_read_csv` and
  `pl_dataframe_read_csv_options` keep their signatures and defaults;
- option validation rejects multi-byte and control-byte quote/comment values,
  and rejects a quote or comment byte that collides with the delimiter or with
  each other;
- tests cover single-quote escaping, disabled quote parsing, comment lines
  before the header and between rows, combined delimiter/header/quote/comment
  options, invalid option values, and malformed CSV under the new options;
- `scripts/ensure-bridge.sh` reuses a release bridge newer than the Rust inputs
  and rebuilds only missing or stale bridges; `test.sh`, `rockspec.sh`,
  `install.sh`, and the rockspec build command share it, so LuaRocks
  validation is incremental instead of triggering repeated cold builds;
- `scripts/build.sh` now defaults to one Cargo job;
- 56 tests.

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
