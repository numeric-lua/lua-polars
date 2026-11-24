# lua-polars 0.22.0

Five DataFrame/IO additions, all additive over the 0.21.0 surface:

- `df:fill_null_forward([columns])` replaces each null with the previous
  non-null value in the same column. Leading nulls stay null; with no argument
  every column is filled, or a validated name/list restricts the fill. Column
  order, dtypes, and the input frame are preserved.
- `df:fill_null_backward([columns])` carries the next non-null value into each
  null, leaving trailing nulls in place. It uses the same all-column default
  and validated subset rules as the forward direction.
- `df:gather_every(n [, offset])` returns every `n`th row starting at the
  zero-based `offset` (default `0`). The schema is preserved, `n` must be
  positive, and an offset at or past the end returns an empty frame.
- `df:null_mask([name])` appends a Boolean column that is true when any column
  in the row is null. The default name is `has_nulls`; a custom name must be
  non-empty and must not collide with an existing column. A zero-column frame
  has no values to test and is rejected.
- `polars.read_json(..., { infer_schema_length = n })` controls schema
  inference for JSON Lines. The default remains Polars' 100-record window, `0`
  scans the whole stream, and a positive value limits the window. JSON arrays
  are read as a whole, so the option is accepted but has no effect there.

The additive C ABI entry points are `pl_dataframe_fill_null_forward`,
`pl_dataframe_fill_null_backward`, `pl_dataframe_gather_every`,
`pl_dataframe_null_mask`, and `pl_dataframe_read_json_inferred`; every earlier
entry point keeps its signature and defaults. Validation covers malformed,
empty, duplicate, unknown, or non-contiguous fill subsets, zero, negative,
fractional, non-numeric, or above-`2^53 - 1` gather counts and offsets,
empty, non-string, or colliding null-mask names, zero-column frames, invalid
JSON inference lengths, closed frames, and filesystem/parse errors. The test
suite covers all five additions, and the installed prefix and LuaRocks layouts
are exercised through `./scripts/test.sh`, `./scripts/smoke.sh`, and
`./scripts/rockspec.sh`.
This release is tagged `v0.22.0`.
