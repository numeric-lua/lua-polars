# lua-polars 0.10.0

- `polars.read_csv(path, { dtypes = { column = "f64" } })` overrides inferred
  CSV dtypes by column name; `bool`, `i32`, `i64`, `u32`, `u64`, `f32`, `f64`,
  and `str` are supported, with long aliases and case-insensitive matching;
- the additive `pl_dataframe_read_csv_typed` C ABI carries both the column
  projection and `column`/`dtype` override pairs; `pl_dataframe_read_csv`,
  `pl_dataframe_read_csv_options`, `pl_dataframe_read_csv_ex`, and
  `pl_dataframe_read_csv_projected` keep their signatures and defaults;
- empty dtype tables, non-string keys or values, unsupported dtype names,
  duplicate overrides, overrides outside the projection, and overrides for
  columns absent from the file are rejected with a clear error;
- tests cover numeric and string overrides, aliases and integer widths,
  projection and headerless combinations, quote/comment combinations, and the
  error paths; the installed-tree smoke test exercises a projected dtype
  override;
- `scripts/rockspec.sh` writes a content stamp into a reused
  `POLARS_LUA_ROCK_TREE` and skips `luarocks make` while the rockspec, Lua
  modules, install script, and native bridge are unchanged;
  `POLARS_LUA_ROCK_FORCE=1` forces a reinstall;
- `scripts/check-version.sh` cross-checks `Cargo.toml`, `Cargo.lock`,
  `polars.lua`, the rockspec name/version/tag, README, API docs, and release
  notes; `scripts/rockspec.sh` runs it before installing;
- 68 tests.
