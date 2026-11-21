# lua-polars 0.11.0

- `df:write_csv(path, options)` accepts a one-byte `delimiter`, omits the
  header row with `header = false`, and writes a literal `null_value`
  placeholder for null fields; the default stays comma/header/empty null;
- the additive `pl_dataframe_write_csv_options` C ABI carries the writer
  settings; `pl_dataframe_write_csv` keeps its signature and defaults;
- unknown fields, a non-boolean `header`, invalid one-byte delimiters, and a
  `null_value` containing the delimiter, `"`, NUL, newline, or carriage return
  are rejected before the file is written;
- tests cover semicolon and headerless round-trips, the literal null
  placeholder, unchanged default bytes, option validation, closed-frame and
  filesystem errors, and the installed-tree writer path;
- `scripts/rockspec.sh` now validates against the ignored `.luarocks-tree/`
  directory by default and skips `luarocks make` while the content stamp
  matches; `POLARS_LUA_ROCK_TREE` selects another tree and
  `POLARS_LUA_ROCK_FORCE=1` forces a reinstall;
- `scripts/check-version.sh` cross-checks `Cargo.toml`, `Cargo.lock`,
  `polars.lua`, the rockspec name/version/tag, README, API docs, and release
  notes; `scripts/rockspec.sh` runs it before installing;
- 73 tests.
