# lua-polars 0.12.0

- `polars.read_csv(path, options)` accepts `null_values`, a literal marker
  string or a non-empty list of markers that are read as null in every column;
  markers are compared after surrounding CSV quotes are removed, and empty
  fields stay null by default;
- the additive `pl_dataframe_read_csv_null_values` C ABI combines the full
  reader configuration (delimiter, header, quote, comment, projection, and
  dtype overrides) with the markers; earlier reader entry points keep their
  signatures and defaults;
- invalid option types, empty markers, empty lists, non-string entries, sparse
  lists, and duplicate markers are rejected before the file is read;
- tests cover single and multiple markers, quote/comment/delimiter/headerless
  combinations, projection and dtype overrides, writer round-trips, and error
  paths, including the installed-tree smoke test through both the prefix and
  LuaRocks layouts;
- `./scripts/test.sh`, `./scripts/smoke.sh`, and `./scripts/rockspec.sh` were
  run for the release; a repeated LuaRocks check reused the unchanged content
  stamp without a Cargo rebuild;
- 79 tests.
