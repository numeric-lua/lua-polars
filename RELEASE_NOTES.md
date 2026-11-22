# lua-polars 0.14.0

- `polars.read_csv(path, options)` accepts `rename_columns`, a non-empty,
  contiguous list of replacement names applied positionally to the columns of
  the returned frame; fewer names rename a prefix, and the option composes with
  projection, dtype overrides, null markers, and the row window;
- `polars.read_csv(path, options)` accepts `encoding = "utf8"` (default) or
  `"utf8-lossy"`, matched case-insensitively; lossy mode replaces invalid UTF-8
  bytes with `U+FFFD` instead of failing the read;
- the additive `pl_dataframe_read_csv_encoded` C ABI entry point combines the
  row window and every earlier reader option with the encoding, and the
  additive `pl_dataframe_read_csv_renamed` entry point adds the positional
  rename list; earlier reader entry points keep their signatures and defaults;
- `df:write_csv(path, options)` accepts `line_terminator`, either `"\n"` (the
  default) or `"\r\n"`; the additive `pl_dataframe_write_csv_full` C ABI entry
  point combines it with the delimiter, header, and null-value writer options,
  and earlier writer entry points keep their signatures and defaults;
- invalid encodings, malformed rename lists, rename results that collide with
  an existing or duplicate column name, more rename names than the frame has
  columns, and unsupported line terminators are rejected with explicit errors;
- tests cover positional renames on headed and headerless input, rename
  collisions and width errors, strict and lossy decoding with replacement-byte
  assertions, combinations with projection/dtypes/null markers/row windows, and
  CRLF output round-trips through the reader; the installed-tree smoke test
  exercises the new options through both the prefix and LuaRocks layouts;
- `./scripts/test.sh` passed 95 tests, `./scripts/smoke.sh` passed the
  installed-prefix check, and `./scripts/rockspec.sh` installed the checkout
  through LuaRocks and loaded it; a repeated LuaRocks check reused the unchanged
  content stamp without a Cargo rebuild;
- no tag or package publish was performed for this release.
