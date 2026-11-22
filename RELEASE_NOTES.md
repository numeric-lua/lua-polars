# lua-polars 0.17.0

Five DataFrame/IO additions, all additive over the 0.16.0 surface:

- `df:tail(n)` returns the last `n` rows (default `5`, `0` for an empty schema
  window, larger counts return the whole frame); `df:slice(offset, length)`
  returns a row window, supports negative offsets from the end, and returns an
  empty frame for a past-end offset. Both reject negative, fractional,
  non-numeric, and above-`2^53 - 1` arguments.
- `df:with_row_index([name, offset])` prepends a zero-based index column. The
  name defaults to `"index"`, the offset defaults to `0`, and collisions with an
  existing column are errors.
- `polars.read_csv(..., { try_parse_dates = true })` infers ISO date and
  datetime columns instead of leaving them as strings. It composes with
  projection, dtype overrides, null markers, renames, the row window, and the
  encoding, and rejects non-boolean values.
- `df:write_csv(..., { quote_style = ... })` accepts `necessary` (default),
  `always`, `non_numeric`/`non-numeric`, and `never`, matched
  case-insensitively. `never` deliberately permits invalid CSV for fields that
  would need quoting; `always` writes an empty null as `""`, which reads back as
  an empty string unless a `null_value` placeholder is used.
- `polars.read_json(path, options)` and `df:write_json(path, options)` support a
  single JSON array (the default; alias `"json"`) or JSON Lines (`"lines"`,
  `"ndjson"`, `"jsonl"`, `"json-lines"`, `"jsonlines"`). Reads accept a
  `columns` projection in the requested order; JSON `null` round-trips through
  the `polars.null` sentinel in `to_table()`.

The additive C ABI entry points are `pl_dataframe_tail`,
`pl_dataframe_slice`, `pl_dataframe_with_row_index`,
`pl_dataframe_read_csv_parsed`, `pl_dataframe_write_csv_configured`,
`pl_dataframe_read_json`, and `pl_dataframe_write_json`. Every earlier entry
point keeps its signature and defaults. The `dtype-date`/`dtype-datetime`
Polars features are enabled so inferred dates are real logical dtypes.

Validation covers invalid counts and offsets, row-index collisions, non-boolean
date inference, unknown quote styles and JSON formats, invalid projections,
missing or malformed files, closed frames, and filesystem failures. The test
suite covers every new option and combination, and the installed prefix and
LuaRocks layouts are exercised through `./scripts/test.sh`, `./scripts/smoke.sh`,
and `./scripts/rockspec.sh`. This release is tagged `v0.17.0`.
