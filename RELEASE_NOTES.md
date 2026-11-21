# lua-polars 0.8.0

- CSV reader `quote` and `comment` options in Lua and the additive
  `pl_dataframe_read_csv_ex` C ABI; `false` or an empty string disables either
  feature;
- validation rejects multi-byte/control bytes and quote/comment/delimiter
  collisions; malformed input still reports a parse error;
- tests for custom quotes, disabled quoting, comment lines, combined reader
  options, and invalid options;
- `scripts/ensure-bridge.sh` reuses a fresh release bridge and rebuilds only
  when it is missing or stale, keeping LuaRocks install validation incremental;
- `scripts/build.sh` defaults to `CARGO_BUILD_JOBS=1`;
- 56 tests.
