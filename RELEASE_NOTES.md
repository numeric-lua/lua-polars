# lua-polars 0.19.0

Five DataFrame/IO additions, all additive over the 0.18.0 surface:

- `df:reverse()` returns the rows in reverse order. Column names, order,
  dtypes, and nulls are preserved, and the input frame is unchanged. Empty
  frames stay empty.
- `df:cast({ column = dtype })` strictly casts one or more columns to the
  supported primitive dtypes (`bool`, `i32`, `i64`, `u32`, `u64`, `f32`, `f64`,
  and `str`, with the usual aliases). Column order is preserved. A value that
  cannot be converted fails the operation instead of becoming null, and unknown
  columns or dtypes are errors.
- `df:unique([columns, options])` returns distinct rows. No argument compares
  every column and keeps the earlier behavior; a column name or contiguous list
  compares only that subset. `keep` accepts `first` (default), `last`, `none`,
  or `any`, and `maintain_order = false` selects the faster unstable distinct.
- `df:explode(columns [, options])` flattens list columns into long form.
  `keep_nulls` and `empty_as_null` both default to true and control the null row
  produced for a null or empty list. Every named column must have a list dtype;
  non-list columns are rejected before Polars runs.
- `polars.read_csv(..., { skip_rows_after_header = n, decimal_comma = true })`
  adds post-header row skipping and comma-decimal numbers. The skip is applied
  after the header and before `n_rows`, so it composes with projection, dtype
  overrides, null markers, renames, encoding, and the lenient flags. Decimal
  commas are intended with a semicolon or tab delimiter and do not change the
  field delimiter.

The additive C ABI entry points are `pl_dataframe_reverse`,
`pl_dataframe_cast`, `pl_dataframe_unique`, `pl_dataframe_explode`, and
`pl_dataframe_read_csv_extended`; every earlier entry point keeps its signature
and defaults. Validation covers malformed cast mappings, unsupported dtypes and
strict conversion failures, invalid unique keep strategies and option types,
malformed column subsets, non-list explode columns, invalid explode flags,
negative or fractional post-header counts, non-boolean `decimal_comma`, closed
frames, and filesystem/parse errors. The test suite covers all five additions,
and the installed prefix and LuaRocks layouts are exercised through
`./scripts/test.sh`, `./scripts/smoke.sh`, and `./scripts/rockspec.sh`.
This release is tagged `v0.19.0`.
