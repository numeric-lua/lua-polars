# lua-polars 0.18.0

Five DataFrame/IO additions, all additive over the 0.17.0 surface:

- `df:drop_nulls([columns])` drops rows with nulls only in a single named column
  or a non-empty list of columns. No argument keeps the earlier all-column
  behavior. Unknown, duplicate, empty, and non-contiguous names are rejected
  before the query runs.
- `df:fill_null(value [, columns])` fills nulls with a finite number, string,
  or boolean, optionally only in the selected columns. `nil`, `"zero"`, and
  `"one"` retain the earlier `0`/`1` aliases; strings are SQL-escaped so values
  such as `"O'Reilly"` round-trip. Non-finite numbers, NUL bytes, invalid types,
  and malformed subsets are errors.
- `df:value_counts(columns [, options])` counts distinct combinations of one or
  more key columns, appends a `count` column, and sorts by count descending.
  Ties are ordered by the key columns for deterministic output. `sort = false`
  omits the ordering and `name` renames the count column unless it collides
  with a grouping key.
- `polars.read_csv(..., { truncate_ragged_lines = true, ignore_errors = true })`
  handles imperfect exports: extra fields beyond the header are truncated, and
  values that cannot be parsed for the inferred or overridden dtype become
  nulls while the remaining rows are kept. Both options compose with
  projection, dtype overrides, null markers, renames, row windows, encoding,
  and date inference.
- `df:write_csv(..., { float_precision = n })` writes float columns with `n`
  digits after the decimal point. `0` writes whole-number-rounded floats, `2`
  writes values such as `2.50`, and omitting the option keeps Polars' shortest
  representation. It composes with every earlier writer option.

The additive C ABI entry points are `pl_dataframe_read_csv_lenient` and
`pl_dataframe_write_csv_precise`; every earlier entry point keeps its signature
and defaults. Validation covers malformed subsets, count-name collisions,
non-boolean lenient flags, invalid fill values, invalid precision counts,
closed frames, parse failures, and filesystem errors. The test suite covers all
five additions, and the installed prefix and LuaRocks layouts are exercised
through `./scripts/test.sh`, `./scripts/smoke.sh`, and `./scripts/rockspec.sh`.
This release is tagged `v0.18.0`.
