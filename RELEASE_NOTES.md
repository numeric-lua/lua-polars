# lua-polars 0.16.0

- `polars.read_parquet(path, options)` accepts `columns` as a single name or a
  non-empty list of names, applied as a read-time projection in the requested
  order, and `skip_rows`/`n_rows` as a non-negative row window over the data
  rows; `n_rows = 0` keeps the file schema and a window past the end returns an
  empty frame;
- the additive `pl_dataframe_read_parquet_options` C ABI entry point carries
  the projection and row window; `pl_dataframe_read_parquet` keeps its
  signature and reads every row and column;
- `df:write_parquet(path, options)` accepts `compression` (`zstd` default,
  `snappy`, `gzip`, `brotli`, `lz4`/`lz4-raw`, `uncompressed`/`none`, matched
  case-insensitively), `statistics = false` to skip column statistics, and
  positive `row_group_size`/`data_page_size` chunk controls in rows and bytes;
- the additive `pl_dataframe_write_parquet_options` C ABI entry point carries
  the compression codec, statistics flag, and chunk sizes; the earlier writer
  keeps its Zstd/statistics/default-chunking signature and defaults;
- option validation rejects unknown keys, non-string or empty projections,
  duplicate and missing columns, negative or fractional row windows, unknown
  codec names, non-boolean statistics, and non-positive or fractional chunk
  sizes; closed frames and filesystem failures keep their explicit errors;
- tests cover projection order, empty and past-end windows, every compression
  codec plus aliases/case folding, statistics and chunk-size combinations,
  malformed reader/writer options, missing files, closed frames, filesystem
  failures, and the installed-tree path through the prefix smoke test;
- `./scripts/test.sh` passed 107 tests and `./scripts/smoke.sh` passed the
  installed-prefix check; the LuaRocks source-rock check installed the 0.16.0
  checkout and loaded it, and a repeated check reused the content stamp
  without a Cargo rebuild;
- no tag or package publish was performed for this release.
