# lua-polars 0.13.0

- `polars.read_csv(path, options)` accepts `skip_rows` and `n_rows`, a
  non-negative row window: `skip_rows` skips CSV rows before the header is
  parsed and `n_rows` limits the data rows read after it; `n_rows = 0` keeps the
  header-derived schema and an absent `n_rows` reads the remaining rows;
- the additive `pl_dataframe_read_csv_row_window` C ABI combines the full
  reader configuration (delimiter, header, quote, comment, projection, dtype
  overrides, and null markers) with `uint64_t skip_rows` and `int64_t n_rows`,
  where `-1` reads all remaining rows; earlier reader entry points keep their
  signatures and defaults;
- negative, fractional, non-numeric, and above-`2^53 - 1` row-window values are
  rejected in Lua before the bridge is called, and the bridge rejects other
  negative `n_rows` sentinels;
- tests cover leading preamble rows, row limits, empty and past-end windows,
  headerless input, and combinations with projection, dtype overrides, and null
  markers, including the installed-tree smoke test through both the prefix and
  LuaRocks layouts;
- `./scripts/test.sh`, `./scripts/smoke.sh`, and `./scripts/rockspec.sh` were
  run for the release; a repeated LuaRocks check reused the unchanged content
  stamp without a Cargo rebuild;
- 85 tests.
