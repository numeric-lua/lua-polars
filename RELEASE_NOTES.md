# lua-polars 0.15.0

- `polars.read_csv(path, options)` accepts `null_values` as a table mapping
  column names to one marker each; a named marker is read as null only in its
  own column, empty fields remain null in every column, and the map composes
  with projection, dtype overrides, positional renames, the row window, and
  UTF-8 lossy decoding;
- the additive `pl_dataframe_read_csv_named_nulls` C ABI entry point combines
  every earlier reader option, including the encoding and positional rename
  list, with parallel `null_columns`/`null_values` arrays; earlier reader entry
  points keep their signatures and defaults;
- malformed per-column maps (mixed list and column keys, non-string keys,
  empty column names, and non-string or empty markers), markers outside the
  projection, and markers naming columns absent from the file are rejected
  with explicit errors; markers name the file's original columns because they
  are applied before positional renames;
- tests cover per-column scoping, empty-field nulls, combinations with
  projection/dtypes/renames/row windows/lossy decoding, malformed maps, a
  marker outside the projection, and an unknown marker column; the
  installed-tree smoke test exercises per-column markers through both the
  prefix and LuaRocks layouts;
- `./scripts/test.sh` passed 99 tests, `./scripts/smoke.sh` passed the
  installed-prefix check, and `./scripts/rockspec.sh` installed the checkout
  through LuaRocks and loaded it; a repeated LuaRocks check reused the
  unchanged content stamp without a Cargo rebuild;
- no tag or package publish was performed for this release.
