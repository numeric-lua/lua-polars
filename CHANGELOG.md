# Changelog

## Unreleased

- `polars.read_csv(path, options)` accepts `rename_columns`, a non-empty,
  contiguous list of replacement names applied positionally to the columns of
  the returned frame; it composes with projection, dtype overrides, null
  markers, and the row window, and fewer names rename only that prefix;
- `polars.read_csv(path, options)` accepts `encoding = "utf8"` (default) or
  `"utf8-lossy"`, matched case-insensitively; lossy mode replaces invalid UTF-8
  bytes with `U+FFFD` instead of failing the read;
- the additive `pl_dataframe_read_csv_encoded` C ABI entry point combines the
  row window and every earlier reader option with a text encoding, and the
  additive `pl_dataframe_read_csv_renamed` entry point adds the positional
  rename list; earlier reader entry points keep their signatures and defaults;
- `df:write_csv(path, options)` accepts `line_terminator`, either `"\n"` (the
  default) or `"\r\n"`; the additive `pl_dataframe_write_csv_full` C ABI entry
  point combines it with the delimiter, header, and null-value writer options,
  and earlier writer entry points keep their signatures and defaults;
- invalid encoding names, malformed rename lists, rename results that collide
  with an existing or duplicate column name, more names than the frame has
  columns, and unsupported line terminators are rejected before or just after
  the read, with explicit Lua errors for option-shape mistakes;
- tests cover positional renames on headed and headerless input, rename
  collisions and width errors, strict and lossy decoding with replacement-byte
  assertions, combinations with projection/dtypes/null markers/row windows, and
  CRLF output round-trips through the reader; the installed-tree smoke test
  exercises the new reader and writer options through both the prefix and
  LuaRocks layouts;
- 95 tests.

## 0.13.0

- `polars.read_csv(path, options)` accepts `skip_rows` and `n_rows`, a
  non-negative row window: `skip_rows` drops CSV rows before the header is
  parsed and `n_rows` limits the data rows read after it; `n_rows = 0` keeps the
  header-derived schema and an absent `n_rows` reads the remaining rows;
- the additive `pl_dataframe_read_csv_row_window` C ABI entry point combines
  the full reader configuration (delimiter, header, quote, comment, projection,
  dtype overrides, and null markers) with `uint64_t skip_rows` and
  `int64_t n_rows`, where `-1` means all remaining rows; earlier reader entry
  points keep their signatures and defaults;
- negative, fractional, non-numeric, and above-`2^53 - 1` row-window values are
  rejected in Lua before the bridge is called, and the bridge rejects other
  negative `n_rows` sentinels;
- tests cover leading preamble rows, row limits, empty and past-end windows,
  headerless input, and combinations with projection, dtype overrides, and
  null markers; the installed-tree smoke test exercises a combined row-window
  read through both the prefix and LuaRocks layouts;
- `./scripts/test.sh`, `./scripts/smoke.sh`, and `./scripts/rockspec.sh` were
  run for the release; a repeated LuaRocks check reused the unchanged content
  stamp without a Cargo rebuild;
- 85 tests.

## 0.12.0

- `polars.read_csv(path, options)` accepts `null_values`, a literal marker
  string or a non-empty list of markers that are read as null in every column;
  markers are compared after surrounding CSV quotes are removed, and empty
  fields remain null by default;
- the additive `pl_dataframe_read_csv_null_values` C ABI entry point combines
  the existing projection and dtype overrides with the null markers; earlier
  reader entry points keep their signatures and defaults;
- markers are validated eagerly: an invalid option type, an empty string or
  list, non-string or empty entries, a list with holes, and duplicate markers
  are errors;
- tests cover single and multiple markers, quote/comment/delimiter/headerless
  combinations, projection and dtype overrides, writer round-trips, and the
  error paths; the installed-tree smoke test reads markers through both the
  prefix and LuaRocks layouts;
- 79 tests.

## 0.11.0

- `df:write_csv(path, options)` accepts a one-byte `delimiter`, a `header`
  boolean (default `true`; `false` omits the header row), and a literal
  `null_value` placeholder for null fields (default the empty string);
- the additive `pl_dataframe_write_csv_options` C ABI entry point carries the
  writer settings; `pl_dataframe_write_csv` keeps its comma/header/empty-null
  signature and defaults;
- writer options are validated eagerly: unknown fields, a non-boolean `header`,
  invalid one-byte delimiters, and a `null_value` containing the delimiter,
  `"`, NUL, newline, or carriage return are errors;
- tests cover semicolon and headerless round-trips, the literal null
  placeholder, unchanged default bytes, option validation, closed-frame and
  filesystem errors, and the installed-tree writer path;
- `scripts/rockspec.sh` now defaults to the ignored `.luarocks-tree/`
  directory, so repeated LuaRocks validation reuses the install stamp;
  `POLARS_LUA_ROCK_TREE` selects another tree and `POLARS_LUA_ROCK_FORCE=1`
  still forces a reinstall;
- 73 tests.

## 0.10.0

- `polars.read_csv(path, options)` accepts `dtypes`, a table that overrides
  inferred dtypes by column name; supported dtypes are `bool`, `i32`, `i64`,
  `u32`, `u64`, `f32`, `f64`, and `str`, with long aliases and
  case-insensitive matching;
- the additive `pl_dataframe_read_csv_typed` C ABI entry point carries both a
  column projection and `column`/`dtype` override pairs; earlier reader entry
  points keep their signatures and defaults;
- overrides are validated eagerly: unsupported dtype names, empty tables,
  non-string keys/values, an override outside the projection, a duplicate
  override, and an override for a column absent from the file are errors;
- tests cover dtype changes on inferred columns, string and numeric overrides,
  aliases and integer widths, projection and headerless combinations,
  quote/comment combinations, unknown/unprojected columns, and unparsable
  values;
- `scripts/rockspec.sh` records a content stamp in a reused
  `POLARS_LUA_ROCK_TREE` and skips `luarocks make` when the rockspec, Lua
  modules, install script, and native bridge are unchanged;
  `POLARS_LUA_ROCK_FORCE=1` forces a reinstall;
- the installed-tree smoke test exercises a projected dtype override;
- 68 tests.

## 0.9.0

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
