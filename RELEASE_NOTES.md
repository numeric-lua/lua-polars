# lua-polars 0.7.0

- CSV reader `delimiter` and `header` options in Lua and the C ABI;
- tests for custom delimiters, headerless files, invalid options, and parse
  errors;
- LuaRocks source-rock install now deploys the bridge through `$(LIBDIR)` and
  the loader searches `package.cpath`;
- `scripts/install-rock.sh` and `scripts/rockspec.sh` cover the rock install
  path;
- `drop_nulls`/`fill_null`, row iteration helpers, and `unique`/`null_count`;
- 50 tests.
