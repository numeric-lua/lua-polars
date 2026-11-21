# lua-polars 0.9.0

- `polars.read_csv(path, { columns = ... })` reads only the requested columns
  and returns them in the requested order; one name or a list is accepted;
- the additive `pl_dataframe_read_csv_projected` C ABI carries the projection;
  `pl_dataframe_read_csv`, `pl_dataframe_read_csv_options`, and
  `pl_dataframe_read_csv_ex` keep their signatures and defaults;
- empty lists, empty or non-string entries, duplicate names, and unknown
  columns are rejected with a clear error;
- tests cover projection order, single-column selection, headerless and
  quote/comment combinations, all-column projection, and error paths; the
  installed-tree smoke test reads a projection from the LuaRocks/prefix layout;
- `scripts/check-version.sh` cross-checks `Cargo.toml`, `Cargo.lock`,
  `polars.lua`, the rockspec name/version/tag, README, API docs, and release
  notes; `scripts/rockspec.sh` runs it and supports `POLARS_LUA_ROCK_TREE` for
  incremental revalidation;
- 62 tests.
