# lua-polars 0.24.0

Five DataFrame/IO additions, all additive over the 0.23.0 surface:

- `df:transpose([options])` swaps rows and columns. Polars finds a common
  supertype across all values, so mixed dtypes are cast to that type. Output
  columns are `column_0`, `column_1`, and so on unless
  `options.keep_names_as` supplies a non-empty column name for the original
  column names. Empty frames cannot be transposed.
- `df:estimated_size()` reports Polars' approximate in-memory byte footprint
  for the frame, excluding allocator overhead beyond the column buffers.
- `df:is_sorted(columns [, descending [, nulls_last]])` checks the current row
  order against one or more keys. `descending` may be a boolean or per-column
  list; `nulls_last` applies to every key and defaults to `false`.
- `polars.read_json(..., { ignore_errors = true })` keeps JSON Lines records
  whose values cannot be parsed by substituting nulls. It composes with
  `infer_schema_length` and projection; JSON arrays reject the flag.
- `polars.read_parquet(..., { rechunk = true })` consolidates the result into
  single-chunk columns. It composes with `low_memory`, projection, and the
  `skip_rows`/`n_rows` window without changing the schema or values.

The additive C ABI entry points are `pl_dataframe_transpose`,
`pl_dataframe_estimated_size`, `pl_dataframe_is_sorted`,
`pl_dataframe_read_json_full`, and `pl_dataframe_read_parquet_full`; every
earlier entry point keeps its signature and defaults. Validation covers unknown
or empty transpose options, empty transpose inputs, malformed or unknown
sortedness keys, mismatched or non-boolean descending lists, non-boolean
`nulls_last`, non-boolean `ignore_errors`, `ignore_errors` on arrays,
non-boolean `rechunk`, closed frames, and filesystem/parse errors. The test
suite covers all five additions, and the installed prefix and LuaRocks layouts
are exercised through `./scripts/test.sh`, `./scripts/smoke.sh`, and
`./scripts/rockspec.sh`.
This release is tagged `v0.24.0`.
