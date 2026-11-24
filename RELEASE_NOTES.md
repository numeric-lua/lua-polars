# lua-polars 0.21.0

Five DataFrame/IO additions, all additive over the 0.20.0 surface:

- `df:shift(periods [, columns])` shifts values by a row count. Positive
  periods move values toward later rows and insert nulls at the start; negative
  periods move them toward earlier rows and insert nulls at the end. Every
  column shifts by default, or a validated name/list restricts the operation
  and leaves the other columns untouched. Column names, order, dtypes, and the
  input frame are preserved.
- `df:clip(minimum, maximum [, columns])` clamps numeric values to an inclusive
  finite range. Nulls are preserved, and column order is unchanged. With no
  column argument every primitive numeric column is clipped; an explicit subset
  must name numeric columns. Non-integral bounds on integer columns are
  rejected instead of being silently truncated.
- `df:is_duplicated([name])` appends a Boolean column that is true for every
  full row value that occurs more than once. The default name is `duplicated`;
  a custom name must be non-empty and must not collide with an existing column.
- `df:is_unique([name])` appends the inverse Boolean marker for rows that occur
  exactly once. The default name is `unique`, with the same collision rules.
- `polars.read_csv(..., { infer_schema_length = n })` controls how many data
  rows are used to infer dtypes. The default remains Polars' 100-row window;
  `0` reads every column as a string, and a positive value sets a different
  window. Explicit `dtypes` overrides still win, and the option composes with
  every earlier reader option.

The additive C ABI entry points are `pl_dataframe_shift`,
`pl_dataframe_clip`, `pl_dataframe_is_duplicated`, `pl_dataframe_is_unique`,
and `pl_dataframe_read_csv_inferred`; every earlier entry point keeps its
signature and defaults. Validation covers non-integer shift periods, malformed,
empty, duplicate, unknown, or non-contiguous subsets, non-finite or reversed
clip bounds, fractional integer clip bounds, non-numeric explicit clip columns,
empty, non-string, or colliding marker names, invalid inference lengths, closed
frames, and filesystem/parse errors. The test suite covers all five additions,
and the installed prefix and LuaRocks layouts are exercised through
`./scripts/test.sh`, `./scripts/smoke.sh`, and `./scripts/rockspec.sh`.
This release is tagged `v0.21.0`.
