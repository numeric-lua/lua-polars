# lua-polars 0.20.0

Five DataFrame/IO additions, all additive over the 0.19.0 surface:

- `df:fill_nan(value [, columns])` replaces floating-point NaN values with a
  finite number. NaN is treated separately from null, so nulls stay null. With
  no column argument every Float32/Float64 column is targeted; a name or
  contiguous list restricts the replacement, and non-float columns in the subset
  are left unchanged. The input frame is unchanged.
- `df:drop_nans([columns])` drops rows containing a NaN in any targeted float
  column. Nulls are kept because they are a distinct missing-value state. It
  uses the same all-float default and validated column subsets as `fill_nan`.
- `polars.read_csv(..., { raise_if_empty = false })` reads a file with no header
  and no records as an empty frame instead of raising. Malformed or ragged files
  still fail, and a header-only file keeps its header-derived schema in either
  mode. The default stays `true` for every earlier reader entry point.
- `df:write_csv(..., { include_bom = true })` prepends a UTF-8 byte-order mark
  (`EF BB BF`) and composes with delimiter, header, null-value,
  line-terminator, quote-style, and float-precision options. The default output
  still has no BOM.
- `df:write_csv(..., { decimal_comma = true })` serializes float fields with a
  comma decimal separator, intended with a semicolon or tab delimiter. It
  round-trips through the existing reader `decimal_comma` option, leaves the
  field delimiter to `delimiter`, and does not affect integers, strings, or
  nulls.

The additive C ABI entry points are `pl_dataframe_fill_nan`,
`pl_dataframe_drop_nans`, `pl_dataframe_read_csv_empty_policy`, and
`pl_dataframe_write_csv_complete`; every earlier entry point keeps its signature
and defaults. Validation covers non-finite fill values, malformed, empty,
duplicate, unknown, or non-contiguous column subsets, non-boolean
`raise_if_empty`/`include_bom`/`decimal_comma`, closed frames, and
filesystem/parse errors, including malformed files read with
`raise_if_empty = false`. The test suite covers all five additions, and the
installed prefix and LuaRocks layouts are exercised through `./scripts/test.sh`,
`./scripts/smoke.sh`, and `./scripts/rockspec.sh`.
This release is tagged `v0.20.0`.
