# Changelog

## Unreleased

- five DataFrame/IO additions:
  - `df:diff(periods [, columns])` computes first differences over every
    numeric column or a validated numeric subset, leaving the first `periods`
    values null;
  - `df:sort(columns, descending [, options])` accepts a `nulls_last` option
    (boolean or per-column list) to place null keys first or last;
  - `df:rechunk()` returns a copy with one chunk per column while preserving
    schema, values, and row order;
  - `polars.read_csv(..., { low_memory = true })` selects Polars' lower-memory
    CSV reader path and composes with projection, inference, and row windows;
  - `df:write_json(..., { pretty = true })` writes an indented JSON array;
    JSON Lines remains unformatted and is rejected with `pretty`;
- the additive C ABI entry points are `pl_dataframe_diff`,
  `pl_dataframe_rechunk`, `pl_dataframe_read_csv_low_memory`, and
  `pl_dataframe_write_json_pretty`; `sort` null placement is built on the
  existing SQL entry point and every earlier signature and default is
  unchanged;
- validation covers non-positive/fractional/non-numeric diff periods,
  malformed or non-numeric diff subsets, invalid sort option tables and
  per-column null flags, non-boolean `low_memory`, `pretty` with JSON Lines,
  non-boolean `pretty`, and closed frames;
- tests cover integer and float differences at one- and two-row periods,
  null-first/null-last and per-column sort placement, rechunk data
  preservation, low-memory CSV reads with projection and row limits, pretty
  JSON round-trips, and every new error path;
- five additional DataFrame/IO additions:
  - `df:cum_sum([columns])`, `df:cum_min([columns])`, `df:cum_max([columns])`,
    and `df:cum_count([columns])` compute forward cumulative operations over
    every numeric column or a validated numeric subset;
  - `df:to_json({ pretty = true })` returns an indented JSON array string while
    the no-option call keeps the compact array and JSON Lines remains
    unformatted;
- the additional C ABI entry points are `pl_dataframe_cumulative` and
  `pl_dataframe_to_json_pretty`; every earlier signature and default is
  unchanged;
- validation covers malformed or non-numeric cumulative subsets, non-boolean
  `pretty`, `pretty` with JSON Lines, and closed frames;
- five more DataFrame/IO additions:
  - `df:cum_prod([columns])` adds the forward running product to the cumulative
    family;
  - `df:to_csv([options])` returns the CSV text for the same writer options as
    `write_csv`, with byte-identical default output;
  - `df:max_chunks()` reports the largest chunk count across columns;
  - `df:shrink_to_fit()` returns a copy with excess allocation capacity
    released;
  - `df:unnest([columns [, separator]])` expands struct columns into field
    columns, optionally prefixing each field with the struct name;
- the new C ABI entry points are `pl_dataframe_to_csv`,
  `pl_dataframe_max_chunks`, `pl_dataframe_shrink_to_fit`, and
  `pl_dataframe_unnest`; every earlier signature and default is unchanged;
- validation covers malformed or non-numeric cumulative subsets, unknown or
  non-struct unnest columns, non-string separators, unknown CSV writer options,
  and closed frames;
- five more DataFrame/IO additions:
  - `df:sum(column)`, `df:mean(column)`, `df:min(column)`, and `df:max(column)`
    return scalar aggregates for one column, with `polars.null` when no values
    remain;
  - `polars.read_csv(..., { rechunk = true })` rechunks the returned frame so
    every column has one chunk; it composes with projection, inference,
    low-memory reads, and row windows;
- these additions reuse existing SQL and frame entry points, so there are no
  new C ABI symbols or default changes;
- validation covers non-string and empty aggregate columns, unknown aggregate
  columns, unsupported aggregate input types, non-boolean `rechunk`, and closed
  frames;
- five more scalar aggregate additions:
  - `df:count([column])` returns the row count, or the non-null count for one
    column;
  - `df:std(column)` and `df:var(column)` return the sample standard deviation
    and variance;
  - `df:median(column)` returns the median;
  - `df:quantile(column, probability)` returns a continuous quantile in
    `[0, 1]`;
- these also reuse the existing SQL entry point, add no C ABI symbols, and
  preserve every earlier default;
- validation covers non-string, empty, or unknown columns, unsupported
  statistical input types, non-numeric or out-of-range quantile probabilities,
  and closed frames;
- `./scripts/test.sh` passes 207 tests; `./scripts/smoke.sh` and
  `./scripts/rockspec.sh` validate the installed layouts without a version or
  rockspec change.

## 0.24.0

- five DataFrame/IO additions:
  - `df:transpose([options])` swaps rows and columns, optionally storing the
    original column names in a `keep_names_as` column; Polars casts values to a
    common supertype;
  - `df:estimated_size()` reports the approximate in-memory byte footprint;
  - `df:is_sorted(columns [, descending [, nulls_last]])` checks the current
    row order against one or more keys, with per-column direction flags;
  - `polars.read_json(..., { ignore_errors = true })` keeps unparsable JSON
    Lines values as nulls and composes with `infer_schema_length` and
    projection;
  - `polars.read_parquet(..., { rechunk = true })` consolidates the result into
    single-chunk columns and composes with `low_memory`, projection, and the
    row window;
- the additive C ABI entry points are `pl_dataframe_transpose`,
  `pl_dataframe_estimated_size`, `pl_dataframe_is_sorted`,
  `pl_dataframe_read_json_full`, and `pl_dataframe_read_parquet_full`; every
  earlier signature and default is unchanged;
- validation covers unknown or empty transpose options, empty transpose inputs,
  malformed or unknown sortedness keys, mismatched or non-boolean descending
  lists, non-boolean `nulls_last`, non-boolean `ignore_errors`, `ignore_errors`
  on JSON arrays, non-boolean `rechunk`, and closed frames;
- tests cover numeric transpose with and without name retention, size and
  sortedness checks on ascending/descending/multi-key frames, lenient JSON
  Lines parsing with narrowing inference and projection, Parquet low-memory and
  rechunk combinations, and every new error path, including the
  installed-prefix smoke test;
- `./scripts/test.sh` passed 185 tests; `./scripts/smoke.sh` and
  `./scripts/rockspec.sh` validate the installed-prefix and LuaRocks layouts
  for 0.24.0-1;
- the 0.24.0 tag is created for this release.

## 0.23.0

- five DataFrame/IO additions:
  - `df:take(indices)` returns rows by a non-empty contiguous list of 1-based
    positions, with negative positions counting from the end; order and
    duplicates are preserved;
  - `df:top_k(k, columns)` keeps the `k` largest rows using descending key
    order with null keys last;
  - `df:bottom_k(k, columns)` keeps the `k` smallest rows using ascending key
    order with null keys last;
  - `polars.read_parquet(..., { low_memory = true })` selects Polars'
    lower-memory reader path without changing the schema or values;
  - `df:to_json({ format = "lines" })` returns JSON Lines text while the
    no-option call keeps the existing JSON array and `to_table()` contract;
- the additive C ABI entry points are `pl_dataframe_take`,
  `pl_dataframe_read_parquet_low_memory`, and
  `pl_dataframe_to_json_format`; every earlier signature and default is
  unchanged, and `top_k`/`bottom_k` are built on the existing SQL entry point;
- validation covers empty, non-contiguous, malformed, zero, fractional,
  non-numeric, out-of-range, and above-`2^53 - 1` take positions, invalid rank
  counts and key lists, non-boolean `low_memory`, unknown `to_json` options and
  formats, and closed frames;
- tests cover positive/negative/repeated take positions, top/bottom ordering
  with null keys and empty/past-end counts, JSON Lines output and array
  round-trips, Parquet low-memory projections and windows, and every new error
  path, including the installed-prefix smoke test;
- `./scripts/test.sh` passed 178 tests; `./scripts/smoke.sh` and
  `./scripts/rockspec.sh` validate the installed-prefix and LuaRocks layouts
  for 0.23.0-1;
- the 0.23.0 tag is created for this release.

## 0.22.0

- five DataFrame/IO additions:
  - `df:fill_null_forward([columns])` carries the previous non-null value into
    each null, leaves leading nulls in place, and supports every-column or
    validated-subset filling;
  - `df:fill_null_backward([columns])` carries the next non-null value into
    each null, leaves trailing nulls in place, and uses the same subset rules;
  - `df:gather_every(n [, offset])` returns the strided row window `offset`,
    `offset+n`, and so on, keeping the schema and returning an empty frame when
    the offset is past the end;
  - `df:null_mask([name])` appends a Boolean marker that is true when any
    column in the row is null, with a default `has_nulls` name;
  - `polars.read_json(..., { infer_schema_length = n })` controls JSON Lines
    schema inference, where `0` scans the whole stream and a positive value
    limits the record window; JSON arrays ignore the setting;
- the additive C ABI entry points are `pl_dataframe_fill_null_forward`,
  `pl_dataframe_fill_null_backward`, `pl_dataframe_gather_every`,
  `pl_dataframe_null_mask`, and `pl_dataframe_read_json_inferred`; every
  earlier signature and default is unchanged;
- validation covers malformed or duplicate fill subsets, closed frames,
  zero/negative/fractional/non-numeric/above-`2^53 - 1` gather counts and
  offsets, empty/colliding/non-string null-mask names, zero-column frames, and
  negative/fractional/non-numeric inference lengths;
- tests cover forward/backward propagation with leading and trailing nulls,
  subset isolation, odd/even/past-end striding, any-null masks with custom
  names and clean frames, JSON Lines inference with `0`, positive windows,
  projections and arrays, and every new error path, including the
  installed-prefix smoke test;
- `./scripts/test.sh` passed 172 tests; `./scripts/smoke.sh` and
  `./scripts/rockspec.sh` validate the installed-prefix and LuaRocks layouts
  for 0.22.0-1;
- the 0.22.0 tag is created for this release.

## 0.21.0

- five DataFrame/IO additions:
  - `df:shift(periods [, columns])` shifts values by a row count, inserting
    nulls at the start for positive periods and at the end for negative ones;
    every column shifts by default, and a validated subset leaves the other
    columns in place;
  - `df:clip(minimum, maximum [, columns])` clamps numeric values to an
    inclusive finite range while preserving nulls and column order; every
    numeric column is clipped by default, explicit subsets must be numeric, and
    non-integral bounds on integer columns are rejected;
  - `df:is_duplicated([name])` appends a Boolean marker that is true for rows
    whose full value repeats, with a default `duplicated` name;
  - `df:is_unique([name])` appends the inverse Boolean marker for rows that
    occur exactly once, with a default `unique` name;
  - `polars.read_csv(..., { infer_schema_length = n })` limits the rows used
    for dtype inference, with `0` forcing every column to `str`; it composes
    with projection, renames, dtypes, row windows, and every earlier option;
- the additive C ABI entry points are `pl_dataframe_shift`,
  `pl_dataframe_clip`, `pl_dataframe_is_duplicated`, `pl_dataframe_is_unique`,
  and `pl_dataframe_read_csv_inferred`; every earlier signature and default is
  unchanged;
- validation covers non-integer shift periods, malformed or duplicate column
  subsets, non-finite or reversed clip bounds, fractional integer clip bounds,
  non-numeric clip columns, empty/colliding/non-string marker names,
  negative/fractional/above-`2^53 - 1` inference lengths, and closed frames;
- tests cover shift direction and subset isolation, clip bounds and null
  preservation on integer and float columns, duplicate/unique marker values and
  custom names, schema inference with `0`, `1`, dtype overrides and combined
  reader options, and every new error path, including the installed-prefix
  smoke test;
- `./scripts/test.sh` passed 164 tests; `./scripts/smoke.sh` and
  `./scripts/rockspec.sh` validate the installed-prefix and LuaRocks layouts
  for 0.21.0-1;
- the 0.21.0 tag is created for this release.

## 0.20.0

- five DataFrame/IO additions:
  - `df:fill_nan(value [, columns])` replaces floating-point NaN values with a
    finite number while leaving nulls untouched, targeting every Float32/Float64
    column by default or a validated column subset;
  - `df:drop_nans([columns])` drops rows containing a NaN in any targeted float
    column while keeping nulls, with the same all-float default and validated
    column subsets;
  - `polars.read_csv(..., { raise_if_empty = false })` reads a file with no
    header and no records as an empty frame instead of raising, while malformed
    files still fail and header-only files keep their header-derived schema;
  - `df:write_csv(..., { include_bom = true })` prepends a UTF-8 byte-order mark
    and composes with the delimiter, header, null-value, line-terminator,
    quote-style, and float-precision options;
  - `df:write_csv(..., { decimal_comma = true })` serializes float fields with a
    comma decimal separator, intended with a semicolon or tab delimiter and
    round-tripping through the reader's existing `decimal_comma` option;
- the additive C ABI entry points are `pl_dataframe_fill_nan`,
  `pl_dataframe_drop_nans`, `pl_dataframe_read_csv_empty_policy`, and
  `pl_dataframe_write_csv_complete`; every earlier signature and default is
  unchanged, and non-float columns in a NaN subset are ignored;
- validation covers non-finite fill values, malformed or duplicate column
  subsets, unknown columns, closed frames, non-boolean `raise_if_empty`,
  `include_bom`, and `decimal_comma`, and malformed files that must still fail
  when empty-file handling is relaxed;
- tests cover NaN replacement and dropping with null preservation, subset
  isolation, empty and header-only CSV reads, UTF-8 BOM output with combined
  writer options, decimal-comma output and round-trips, and every new error
  path, including the installed-prefix smoke test;
- `./scripts/test.sh` passed 156 tests; `./scripts/smoke.sh` and
  `./scripts/rockspec.sh` validate the installed-prefix and LuaRocks layouts
  for 0.20.0-1;
- the 0.20.0 tag is created for this release.

## 0.19.0

- five DataFrame/IO additions:
  - `df:reverse()` returns the rows in reverse order while preserving the
    column names, order, dtypes, and nulls, leaving the input frame unchanged;
  - `df:cast({ column = dtype })` strictly casts one or more columns to the
    supported primitive dtypes, preserving column order; unparsable values fail
    the whole operation instead of becoming null;
  - `df:unique([columns, options])` compares every column by default, or only a
    named subset, and supports `keep = "first"`/`"last"`/`"none"`/`"any"` plus
    `maintain_order = false` for the unstable distinct; the earlier no-argument
    behavior is preserved;
  - `df:explode(columns [, options])` flattens list columns into long form, with
    `keep_nulls` and `empty_as_null` controlling the row produced for null and
    empty lists; non-list columns are rejected before Polars runs;
  - `polars.read_csv(..., { skip_rows_after_header = n, decimal_comma = true })`
    drops data rows after the header before `n_rows` applies and parses a comma
    as the decimal separator, composing with every earlier reader option;
- the additive C ABI entry points are `pl_dataframe_reverse`,
  `pl_dataframe_cast`, `pl_dataframe_unique`, `pl_dataframe_explode`, and
  `pl_dataframe_read_csv_extended`; every earlier signature and default is
  unchanged;
- validation covers empty and malformed cast mappings, unsupported dtypes,
  unknown or duplicate columns, strict conversion failures, invalid unique keep
  strategies and option types, non-contiguous subsets, non-list explode columns,
  invalid explode flags, negative or fractional post-header counts, and
  non-boolean `decimal_comma`;
- tests cover reversed row order and input immutability, dtype and value casts,
  keep strategies including `none` and unstable ordering, list explode with
  null/empty lists and both flags, post-header windows combined with `n_rows`,
  decimal-comma parsing with projection and windows, and every new error path;
- `./scripts/test.sh` passed 147 tests; `./scripts/smoke.sh` and
  `./scripts/rockspec.sh` validate the installed-prefix and LuaRocks layouts
  for 0.19.0-1;
- the 0.19.0 tag is created for this release.

## 0.18.0

- five DataFrame/IO additions:
  - `df:drop_nulls([columns])` accepts a single column or a non-empty list and
    drops rows whose nulls occur in those columns only; no argument keeps the
    earlier all-column behavior, and unknown, duplicate, empty, or malformed
    names and non-contiguous lists are rejected;
  - `df:fill_null(value [, columns])` fills nulls with a finite number, string,
    or boolean, optionally limited to selected columns; `nil`, `"zero"`, and
    `"one"` keep the earlier `0`/`1` aliases, while SQL-literal escaping makes
    strings containing quotes safe and non-finite numbers, NUL bytes, invalid
    types, and bad subsets explicit errors;
  - `df:value_counts(columns [, options])` counts distinct combinations of one
    or more key columns, appends a `count` column, sorts by count descending
    with deterministic key tie-breaks, and supports `sort = false` and a custom
    count-column `name`;
  - `polars.read_csv(..., { truncate_ragged_lines = true, ignore_errors = true })`
    truncates rows wider than the header and turns values Polars cannot parse
    into nulls instead of failing the whole read; both flags compose with every
    earlier reader option and reject non-boolean values;
  - `df:write_csv(..., { float_precision = n })` writes float columns with `n`
    digits after the decimal point, including `0`, and composes with the
    delimiter, header, null-value, line-terminator, and quote-style options;
- the additive C ABI entry points are `pl_dataframe_read_csv_lenient` and
  `pl_dataframe_write_csv_precise`; every earlier reader and writer signature
  and default is unchanged;
- validation covers non-contiguous and unknown column subsets, duplicate names,
  count-name collisions, non-boolean lenient flags, non-finite fill values, NUL
  fill strings, negative/fractional/non-numeric/above-`2^53 - 1` float
  precision, closed frames, and filesystem/parse failures;
- tests cover column-scoped null handling, literal and boolean fills, quoted
  fill strings, sorted and unsorted value counts, custom count names, truncated
  ragged rows, recovered parse errors, float precision including zero and
  combined writer options, and the installed-tree path through the prefix smoke
  test and LuaRocks check;
- `./scripts/test.sh` passed 137 tests; `./scripts/smoke.sh` and
  `./scripts/rockspec.sh` validate the installed-prefix and LuaRocks layouts
  for 0.18.0-1;
- the 0.18.0 tag is created for this release.

## 0.17.0

- five DataFrame/IO additions:
  - `df:tail(n)` returns the last `n` rows with the head defaults, and
    `df:slice(offset, length)` supports negative offsets from the end plus
    empty and past-end windows;
  - `df:with_row_index([name, offset])` prepends a zero-based row-index column,
    defaults to `index`/`0`, and rejects empty, colliding, or invalid names and
    offsets;
  - `polars.read_csv(..., { try_parse_dates = true })` lets Polars infer ISO
    date and datetime columns instead of strings, composing with projection,
    dtype overrides, null markers, renames, row windows, and encoding;
  - `df:write_csv(..., { quote_style = ... })` accepts `necessary`, `always`,
    `non_numeric`/`non-numeric`, and `never`, case-insensitively;
  - `polars.read_json(path, options)` and `df:write_json(path, options)` read
    and write JSON arrays or JSON Lines with `format = "array"`/`"lines"`
    aliases and an optional read-time `columns` projection;
- the additive C ABI entry points are `pl_dataframe_tail`,
  `pl_dataframe_slice`, `pl_dataframe_with_row_index`,
  `pl_dataframe_read_csv_parsed`, `pl_dataframe_write_csv_configured`,
  `pl_dataframe_read_json`, and `pl_dataframe_write_json`; every earlier
  signature and default is unchanged;
- the date/datetime Polars features are enabled so `try_parse_dates` produces
  real `date`/`datetime` dtypes; `QuoteStyle::Always` writes an empty null as
  `""`, which reads back as an empty string unless a `null_value` is used;
- validation covers non-integer and above-`2^53 - 1` counts/offsets, row-index
  collisions, non-boolean date inference, unknown quote styles and JSON
  formats, malformed projections, missing/malformed files, closed frames, and
  filesystem failures;
- tests cover tail/slice windows, row-index offsets and collisions, CSV date
  inference and its option combinations, every quote style and combined writer
  options, JSON array/JSON Lines reads and writes, projections, malformed
  options/files, and the installed-tree path through the prefix smoke test;
- `./scripts/test.sh` passed 125 tests; `./scripts/smoke.sh` and
  `./scripts/rockspec.sh` validated the installed-prefix and LuaRocks layouts
  for 0.17.0-1;
- the 0.17.0 tag is created for this release.

## 0.16.0

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
  installed-prefix check; `./scripts/rockspec.sh` built the local crate
  incrementally, installed the 0.16.0-1 rock through LuaRocks, and loaded it,
  and a repeated check reused the bridge and content stamp without a Cargo
  rebuild;
- no tag or package publish is performed for this release.

## 0.15.0

- `polars.read_csv(path, options)` accepts `null_values` as a table mapping
  column names to one marker each; named markers are read as null only in
  their own column, while empty fields remain null in every column, and the
  map composes with projection, dtype overrides, positional renames, the row
  window, and UTF-8 lossy decoding;
- the additive `pl_dataframe_read_csv_named_nulls` C ABI entry point combines
  every earlier reader option, including the encoding and positional rename
  list, with parallel `null_columns`/`null_values` arrays; earlier reader
  entry points keep their signatures and defaults;
- malformed per-column maps (mixed list and column keys, non-string keys,
  empty column names, and non-string or empty markers), markers outside the
  projection, and markers naming columns absent from the file are rejected
  with explicit Lua errors;
- tests cover per-column scoping, empty-field nulls, combinations with
  projection/dtypes/renames/row windows/lossy decoding, malformed maps, a
  marker outside the projection, and an unknown marker column; the
  installed-tree smoke test exercises per-column markers through both the
  prefix and LuaRocks layouts;
- `./scripts/test.sh`, `./scripts/smoke.sh`, and `./scripts/rockspec.sh` were
  run for the release; the LuaRocks check reused the native bridge, and a
  repeated check reused the installed tree without a Cargo rebuild;
- no tag or package publish was performed for this release;
- 99 tests.

## 0.14.0

- `polars.read_csv(path, options)` accepts `rename_columns`, a non-empty,
  contiguous list of replacement names applied positionally to the columns of
  the returned frame; it composes with projection, dtype overrides, null
  markers, and the row window, and fewer names rename only that prefix;
- `polars.read_csv(path, options)` accepts `encoding = "utf8"` (default) or
  `"utf8-lossy"`, matched case-insensitively; lossy mode replaces invalid UTF-8
  bytes with `U+FFFD` instead of failing the read;
- the additive `pl_dataframe_read_csv_encoded` C ABI entry point combines the
  row window and every earlier reader option with a text encoding, and the
  additive `pl_dataframe_read_csv_renamed` entry point adds the positional
  rename list; earlier reader entry points keep their signatures and defaults;
- `df:write_csv(path, options)` accepts `line_terminator`, either `"\n"` (the
  default) or `"\r\n"`; the additive `pl_dataframe_write_csv_full` C ABI entry
  point combines it with the delimiter, header, and null-value writer options,
  and earlier writer entry points keep their signatures and defaults;
- invalid encoding names, malformed rename lists, rename results that collide
  with an existing or duplicate column name, more names than the frame has
  columns, and unsupported line terminators are rejected before or just after
  the read, with explicit Lua errors for option-shape mistakes;
- tests cover positional renames on headed and headerless input, rename
  collisions and width errors, strict and lossy decoding with replacement-byte
  assertions, combinations with projection/dtypes/null markers/row windows, and
  CRLF output round-trips through the reader; the installed-tree smoke test
  exercises the new reader and writer options through both the prefix and
  LuaRocks layouts;
- `./scripts/test.sh`, `./scripts/smoke.sh`, and `./scripts/rockspec.sh` were
  run for the release; the first LuaRocks check repaired the changed content
  stamp, and a repeated check reused the installed tree without a Cargo
  rebuild;
- 95 tests.

## 0.13.0

- `polars.read_csv(path, options)` accepts `skip_rows` and `n_rows`, a
  non-negative row window: `skip_rows` drops CSV rows before the header is
  parsed and `n_rows` limits the data rows read after it; `n_rows = 0` keeps the
  header-derived schema and an absent `n_rows` reads the remaining rows;
- the additive `pl_dataframe_read_csv_row_window` C ABI entry point combines
  the full reader configuration (delimiter, header, quote, comment, projection,
  dtype overrides, and null markers) with `uint64_t skip_rows` and
  `int64_t n_rows`, where `-1` means all remaining rows; earlier reader entry
  points keep their signatures and defaults;
- negative, fractional, non-numeric, and above-`2^53 - 1` row-window values are
  rejected in Lua before the bridge is called, and the bridge rejects other
  negative `n_rows` sentinels;
- tests cover leading preamble rows, row limits, empty and past-end windows,
  headerless input, and combinations with projection, dtype overrides, and
  null markers; the installed-tree smoke test exercises a combined row-window
  read through both the prefix and LuaRocks layouts;
- `./scripts/test.sh`, `./scripts/smoke.sh`, and `./scripts/rockspec.sh` were
  run for the release; a repeated LuaRocks check reused the unchanged content
  stamp without a Cargo rebuild;
- 85 tests.

## 0.12.0

- `polars.read_csv(path, options)` accepts `null_values`, a literal marker
  string or a non-empty list of markers that are read as null in every column;
  markers are compared after surrounding CSV quotes are removed, and empty
  fields remain null by default;
- the additive `pl_dataframe_read_csv_null_values` C ABI entry point combines
  the existing projection and dtype overrides with the null markers; earlier
  reader entry points keep their signatures and defaults;
- markers are validated eagerly: an invalid option type, an empty string or
  list, non-string or empty entries, a list with holes, and duplicate markers
  are errors;
- tests cover single and multiple markers, quote/comment/delimiter/headerless
  combinations, projection and dtype overrides, writer round-trips, and the
  error paths; the installed-tree smoke test reads markers through both the
  prefix and LuaRocks layouts;
- 79 tests.

## 0.11.0

- `df:write_csv(path, options)` accepts a one-byte `delimiter`, a `header`
  boolean (default `true`; `false` omits the header row), and a literal
  `null_value` placeholder for null fields (default the empty string);
- the additive `pl_dataframe_write_csv_options` C ABI entry point carries the
  writer settings; `pl_dataframe_write_csv` keeps its comma/header/empty-null
  signature and defaults;
- writer options are validated eagerly: unknown fields, a non-boolean `header`,
  invalid one-byte delimiters, and a `null_value` containing the delimiter,
  `"`, NUL, newline, or carriage return are errors;
- tests cover semicolon and headerless round-trips, the literal null
  placeholder, unchanged default bytes, option validation, closed-frame and
  filesystem errors, and the installed-tree writer path;
- `scripts/rockspec.sh` now defaults to the ignored `.luarocks-tree/`
  directory, so repeated LuaRocks validation reuses the install stamp;
  `POLARS_LUA_ROCK_TREE` selects another tree and `POLARS_LUA_ROCK_FORCE=1`
  still forces a reinstall;
- 73 tests.

## 0.10.0

- `polars.read_csv(path, options)` accepts `dtypes`, a table that overrides
  inferred dtypes by column name; supported dtypes are `bool`, `i32`, `i64`,
  `u32`, `u64`, `f32`, `f64`, and `str`, with long aliases and
  case-insensitive matching;
- the additive `pl_dataframe_read_csv_typed` C ABI entry point carries both a
  column projection and `column`/`dtype` override pairs; earlier reader entry
  points keep their signatures and defaults;
- overrides are validated eagerly: unsupported dtype names, empty tables,
  non-string keys/values, an override outside the projection, a duplicate
  override, and an override for a column absent from the file are errors;
- tests cover dtype changes on inferred columns, string and numeric overrides,
  aliases and integer widths, projection and headerless combinations,
  quote/comment combinations, unknown/unprojected columns, and unparsable
  values;
- `scripts/rockspec.sh` records a content stamp in a reused
  `POLARS_LUA_ROCK_TREE` and skips `luarocks make` when the rockspec, Lua
  modules, install script, and native bridge are unchanged;
  `POLARS_LUA_ROCK_FORCE=1` forces a reinstall;
- the installed-tree smoke test exercises a projected dtype override;
- 68 tests.

## 0.9.0

- `polars.read_csv(path, options)` accepts `columns` as a single column name or
  a list of names; Polars applies the projection at read time and the returned
  frame keeps the requested order;
- the additive `pl_dataframe_read_csv_projected` C ABI entry point carries the
  projection; `pl_dataframe_read_csv`, `pl_dataframe_read_csv_options`, and
  `pl_dataframe_read_csv_ex` keep their signatures and defaults;
- projection validation rejects empty lists, non-string or empty entries,
  duplicate names, and unknown columns;
- tests cover projection order, single-column selection, headerless and
  quote/comment combinations, projecting every column, and the error paths;
- `scripts/check-version.sh` cross-checks `Cargo.toml`, `Cargo.lock`,
  `polars.lua`, the rockspec name/version/tag, README, API docs, and release
  notes; `scripts/rockspec.sh` runs it before installing and honors
  `POLARS_LUA_ROCK_TREE` for repeatable incremental validation;
- the installed-tree smoke test exercises a projected read;
- 62 tests.

## 0.8.0

- `polars.read_csv(path, options)` accepts a one-byte `quote` character and a
  one-byte `comment` prefix; `quote = false`/`quote = ""` disables quote
  parsing and `comment = false`/`comment = ""` disables comment skipping;
- the additive `pl_dataframe_read_csv_ex` C ABI entry point carries the quote
  and comment controls; `pl_dataframe_read_csv` and
  `pl_dataframe_read_csv_options` keep their signatures and defaults;
- option validation rejects multi-byte and control-byte quote/comment values,
  and rejects a quote or comment byte that collides with the delimiter or with
  each other;
- tests cover single-quote escaping, disabled quote parsing, comment lines
  before the header and between rows, combined delimiter/header/quote/comment
  options, invalid option values, and malformed CSV under the new options;
- `scripts/ensure-bridge.sh` reuses a release bridge newer than the Rust inputs
  and rebuilds only missing or stale bridges; `test.sh`, `rockspec.sh`,
  `install.sh`, and the rockspec build command share it, so LuaRocks
  validation is incremental instead of triggering repeated cold builds;
- `scripts/build.sh` now defaults to one Cargo job;
- 56 tests.

## 0.7.0

- `polars.read_csv(path, options)` accepts a one-byte `delimiter` and a
  `header` boolean; the new `pl_dataframe_read_csv_options` C ABI entry point
  keeps the old comma/header reader available;
- tests cover semicolon- and pipe-delimited reads, headerless input with
  Polars-generated column names, invalid options, and malformed CSV files;
- the LuaRocks source rockspec installs Lua modules through `$(LUADIR)` and the
  native bridge through `$(LIBDIR)` instead of staging everything under the
  rock metadata directory;
- the Lua loader also searches `package.cpath` directories for
  `libpolars_lua`, so a LuaRocks tree loads without `POLARS_LUA_LIB`;
- `scripts/install-rock.sh` stages the rock files and `scripts/rockspec.sh`
  validates the LuaRocks install path in a temporary tree;
- `drop_nulls()` and `fill_null()` SQL-backed null handling;
- `iter_rows()`, `column_names()`, and `is_empty()` frame helpers;
- `unique()` and `null_count()`;
- 50 tests.

## 0.6.0

- LuaRocks source rockspec and `make install` flow;
- install smoke covers the LuaRocks/prefix layout.

## 0.5.0

- ordered `df:columns()` and stable column order;
- writer round-trip and failure-path tests;
- prefix install/smoke workflow and default library discovery fix.

## 0.4.0

- CSV and Parquet writers;
- drop/rename/with_columns helpers;
- 32 tests.

## 0.3.0

- eager full/outer, semi, anti, and cross joins;
- join-type tests;
- 31 tests.

## 0.2.0

- eager inner/left joins.
