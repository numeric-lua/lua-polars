# lua-polars 0.23.0

Five DataFrame/IO additions, all additive over the 0.22.0 surface:

- `df:take(indices)` selects rows by a non-empty contiguous list of 1-based
  positions. Negative positions count from the end (`-1` is the last row),
  order and duplicates are preserved, and the result keeps the input schema.
  Every resolved position must be inside the frame.
- `df:top_k(k, columns)` returns the `k` largest rows ordered by one or more
  keys in descending order, with null keys last. `k = 0` returns an empty frame
  and a larger `k` returns every row.
- `df:bottom_k(k, columns)` returns the `k` smallest rows ordered by ascending
  keys, again with null keys last, using the same count and column validation.
- `polars.read_parquet(..., { low_memory = true })` uses Polars' lower-memory
  reader path. It composes with projection and the `skip_rows`/`n_rows`
  window, and the resulting schema and values are unchanged.
- `df:to_json({ format = "lines" })` returns JSON Lines text; the no-option
  call keeps returning the existing JSON array, so `to_table()` is unchanged.

The additive C ABI entry points are `pl_dataframe_take`,
`pl_dataframe_read_parquet_low_memory`, and `pl_dataframe_to_json_format`;
every earlier entry point keeps its signature and defaults. `top_k` and
`bottom_k` are implemented over the existing SQL entry point. Validation covers
empty, non-contiguous, malformed, zero, fractional, non-numeric, out-of-range,
and above-`2^53 - 1` take positions, invalid rank counts and key lists,
non-boolean `low_memory`, unknown `to_json` options and formats, closed frames,
and filesystem/parse errors. The test suite covers all five additions, and the
installed prefix and LuaRocks layouts are exercised through
`./scripts/test.sh`, `./scripts/smoke.sh`, and `./scripts/rockspec.sh`.
This release is tagged `v0.23.0`.
