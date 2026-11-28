# lua-polars API — 0.24.0

## Modules

```lua
local polars = require("polars")
```

The native bridge is loaded from `POLARS_LUA_LIB`, then
`libpolars_lua.so` next to `polars.lua`, `target/release/...`,
`target/debug/...`, `build/...`, or the directories listed by
`package.cpath` (the LuaRocks layout).

## Top-level

### `polars.version() -> string`

Returns the bridge version (`"0.24.0"`).

### `polars.read_csv(path [, options]) -> DataFrame`

Reads a CSV file. UTF-8 is the default text encoding; invalid bytes fail the
read unless `encoding = "utf8-lossy"` asks Polars to substitute U+FFFD. With no
options it expects a header row and commas, as before. Type inference is
Polars' default.

`options` is an optional table:

- `delimiter`: a one-byte string, default `","`. Quote, newline, carriage
  return, and NUL bytes are rejected.
- `header`: a boolean, default `true`. With `header = false` the first row is
  data and Polars names the columns `column_1`, `column_2`, and so on.
- `skip_rows`: a non-negative integer, default `0`. Rows are skipped before the
  header is parsed, so leading metadata lines can be discarded; Polars respects
  CSV quoting and comments while skipping. The window counts CSV rows, not Lua
  indices, and must be at most `2^53 - 1`.
- `skip_rows_after_header`: a non-negative integer, default `0`. Drops that
  many data rows after the header before `n_rows` is applied, so it can skip a
  section of data without losing the header-derived schema. With
  `header = false` there is no header row, so it drops that many leading data
  rows instead. It composes with every other reader option and, like
  `skip_rows`, must be at most `2^53 - 1`.
- `n_rows`: a non-negative integer, default unlimited. Limits the number of
  data rows read after the header. `n_rows = 0` reads no data rows while
  keeping the header-derived schema; a limit larger than the file reads the
  remaining rows. Like `skip_rows`, it must be at most `2^53 - 1`.
- `infer_schema_length`: a non-negative integer limiting how many data rows
  Polars uses to infer dtypes. The default is Polars' 100-row window. `0`
  reads every column as `str` instead of inferring numeric, Boolean, or date
  types; a positive value narrows or widens the window. The whole requested
  row window is still read after inference, and explicit `dtypes` overrides
  still win. It composes with every other reader option and must be at most
  `2^53 - 1`.
- `raise_if_empty`: a boolean, default `true`. Polars treats a file with no
  header and no records as empty and raises. Set it to `false` to read such a
  file as an empty frame instead; the result has no columns because no header
  was available. A header-only file is not empty and keeps its header-derived
  schema in either mode. It composes with every other reader option. Non-boolean
  values are errors, and malformed or ragged files still fail the read.
- `decimal_comma`: a boolean, default `false`. When true, a comma is parsed as
  the decimal separator for numeric columns, which is useful with a semicolon
  or tab `delimiter`. It does not change the field delimiter; the delimiter
  still has to be one byte and differ from the quote and comment bytes.
  Non-boolean values are errors.
- `quote`: a one-byte string used to quote fields, default `"`. Set it to
  `false` or `""` to disable quote parsing. NUL, newline, and carriage-return
  bytes are rejected.
- `comment`: a one-byte line prefix, default disabled. Lines whose first byte
  matches are ignored, including comment lines before the header. Set it to
  `false` or `""` to disable comment skipping.
- `columns`: a column name or a list of names to read. The resulting frame
  keeps the requested order and contains only those columns. Unknown,
  duplicate, and empty names are errors.
- `rename_columns`: a non-empty, contiguous list of replacement names. Names
  are applied positionally to the columns of the frame that would otherwise be
  returned, so they compose with `columns`, `dtypes`, `null_values`, and the row
  window. Supplying fewer names renames only that prefix; supplying more names
  than the frame has columns, duplicate results, empty names, lists with holes,
  and non-string entries are errors. `dtypes` still names the file's original
  columns because it is applied before the rename.
- `encoding`: `"utf8"` (default) or `"utf8-lossy"`, matched
  case-insensitively. Strict UTF-8 raises on invalid bytes; lossy mode replaces
  each invalid byte sequence with `U+FFFD` (`"\239\191\189"` in Lua strings).
  Other values are errors.
- `try_parse_dates`: a boolean, default `false`. When true, Polars infers ISO
  date and datetime columns instead of leaving them as strings; without it an
  ISO-looking column still has dtype `str`. The option composes with projection,
  dtype overrides, null markers, renames, the row window, and the encoding.
  Non-boolean values are errors.
- `truncate_ragged_lines`: a boolean, default `false`. When true, rows with
  more fields than the header are truncated to the header width instead of
  failing the read. It composes with projection, dtype overrides, null markers,
  renames, the row window, encoding, and date inference.
- `ignore_errors`: a boolean, default `false`. When true, values Polars cannot
  parse for the inferred or overridden dtype become null and the remaining
  rows are kept instead of failing the whole read. The affected rows may have
  nulls in only the failed column; use a matching dtype override and
  `null_values` policy to make the recovery explicit. Both lenient options are
  rejected when non-boolean.
- `low_memory`: a boolean, default `false`. `true` selects Polars' lower-memory
  CSV reader path, trading read speed for a smaller peak footprint. It composes
  with projection, dtype overrides, inference, and the row window without
  changing the schema or values.
- `rechunk`: a boolean, default `false`. `true` consolidates the returned frame
  into single-chunk columns after reading. It composes with projection,
  inference, `low_memory`, and the row window without changing the schema or
  values.
- `dtypes`: a table mapping column names to dtype names, applied by name at
  read time instead of relying on inference. Supported dtypes are `bool` /
  `boolean`, `i32`, `i64`, `u32`, `u64`, `f32`, `f64`, and `str` / `string` /
  `utf8`; matching is case-insensitive and the `int32`, `uint32`, and
  `float32` long forms are accepted. The table must not be empty, and every key
  must be a read column: an override outside `columns` or absent from the file
  is an error. Parsing failures (for example `name = "i64"` on text) are
  reported by Polars.
- `null_values`: null markers, either a literal marker string or a non-empty
  list of markers applied to every column, or a table mapping column names to
  one marker each. Per-column markers are read as null only in their own
  column, while empty fields remain null in every column. Markers are compared
  after surrounding CSV quotes are removed, so a quoted `"NA"` field uses
  `null_values = "NA"`, not the quotes themselves. Empty strings, empty lists,
  non-string entries, lists with holes, duplicate list markers, mixed list and
  column keys, empty column names, and non-string or empty per-column markers
  are errors. A per-column marker outside `columns` is rejected before the
  read, and a marker column absent from the file is reported by Polars.
  Per-column markers name the file's original columns because they are applied
  before `rename_columns`.

`quote` and `comment` must differ from each other and from `delimiter`.

```lua
local semicolons = polars.read_csv("data.csv", { delimiter = ";" })
local headerless = polars.read_csv("data.tsv", {
  delimiter = "\t",
  header = false,
})
local quoted = polars.read_csv("notes.csv", {
  quote = "'",
  comment = "#",
})
local projected = polars.read_csv("data.csv", {
  columns = { "score", "name" },
})
local typed = polars.read_csv("data.csv", {
  columns = { "score", "name" },
  dtypes = { score = "f64" },
})
local null_markers = polars.read_csv("data.csv", {
  null_values = { "NA", "missing" },
})
local scoped_nulls = polars.read_csv("data.csv", {
  null_values = { note = "NA", score = "9" },
})
local window = polars.read_csv("export.csv", {
  skip_rows = 2,
  n_rows = 100,
})
local section = polars.read_csv("export.csv", {
  skip_rows_after_header = 10,
  n_rows = 25,
})
local european = polars.read_csv("prices.csv", {
  delimiter = ";",
  decimal_comma = true,
})
local renamed = polars.read_csv("headerless.csv", {
  header = false,
  rename_columns = { "id", "name", "score" },
})
local lossy = polars.read_csv("legacy.csv", { encoding = "utf8-lossy" })
local dated = polars.read_csv("events.csv", { try_parse_dates = true })
local ragged = polars.read_csv("export.csv", {
  truncate_ragged_lines = true,
})
local recovered = polars.read_csv("legacy.csv", {
  dtypes = { score = "i64" },
  ignore_errors = true,
})
local optional = polars.read_csv("maybe-empty.csv", {
  raise_if_empty = false,
})
local strings = polars.read_csv("wide.csv", { infer_schema_length = 0 })
```

Unknown option keys are errors so typos do not silently fall back to defaults.
Errors also cover invalid option types, invalid one-byte values, option
collisions, invalid projection names, unsupported or missing dtype overrides,
invalid or per-column null-value markers, invalid rename lists, unsupported
encodings, non-boolean lenient options, non-boolean `raise_if_empty`, invalid
post-header or pre-header row counts, invalid `infer_schema_length`,
non-boolean `decimal_comma`, a missing or unreadable path, and files that cannot
be parsed.

### `polars.read_parquet(path [, options]) -> DataFrame`

Reads a Parquet file. With no options it reads every row and column.

`options` is an optional table:

- `columns`: a column name or a non-empty list of names to read. The returned
  frame keeps the requested order and contains only those columns. Unknown,
  duplicate, and empty names are errors.
- `skip_rows`: a non-negative integer, default `0`. Drops that many leading
  data rows. Like `n_rows`, it must be at most `2^53 - 1`.
- `n_rows`: a non-negative integer, default unlimited. Limits the data rows
  read after `skip_rows`. `n_rows = 0` reads no rows while keeping the file
  schema; a window past the end returns an empty frame.
- `low_memory`: a boolean, default `false`. `true` selects Polars' lower-memory
  Parquet reader path, trading read speed for a smaller peak footprint. The
  returned schema and values are unchanged.
- `rechunk`: a boolean, default `false`. `true` consolidates the result into a
  single chunk per column. It composes with `low_memory`, projection, and the
  row window without changing the schema or values.

```lua
polars.read_parquet("data.parquet")
polars.read_parquet("data.parquet", {
  columns = { "score", "name" },
  skip_rows = 10,
  n_rows = 100,
  low_memory = true,
  rechunk = true,
})
```

Unknown option keys and invalid types are errors, as are a missing or
unreadable path, unknown projection names, and files that cannot be parsed.

### `polars.read_json(path [, options]) -> DataFrame`

Reads a JSON file whose top level is either a single array of row objects or
JSON Lines (one object per line). Columns and dtypes are inferred by Polars;
JSON `null` becomes `polars.null` in `to_table()`. With no options it expects a
single JSON array.

`options` is an optional table:

- `format`: `"array"` (default; aliases `"json"`) or `"lines"` (aliases
  `"ndjson"`, `"jsonl"`, `"json-lines"`, and `"jsonlines"`), matched
  case-insensitively. Other values are errors.
- `columns`: a column name or a non-empty list of names to read. The returned
  frame keeps the requested order and contains only those columns. Unknown,
  duplicate, and empty names are errors.
- `infer_schema_length`: a non-negative integer controlling JSON Lines schema
  inference. The default keeps Polars' 100-record window; `0` scans the whole
  stream, and a positive value limits inference to that many records. JSON
  arrays are read as a whole by Polars, so the option is accepted but has no
  effect there. It must be at most `2^53 - 1`.
- `ignore_errors`: a boolean, default `false`. For JSON Lines, `true` turns
  values that cannot be parsed under the inferred or narrowed schema into nulls
  and keeps the remaining records. It composes with `infer_schema_length` and
  projection. Polars does not support it for JSON arrays, so that combination
  is an error.

```lua
local rows = polars.read_json("rows.json")
local events = polars.read_json("events.jsonl", {
  format = "lines",
  columns = { "time", "event" },
  infer_schema_length = 0,
  ignore_errors = true,
})
```

Unknown option keys and invalid types are errors, as are a missing or
unreadable path, malformed JSON, unknown projection names, invalid
`infer_schema_length`, non-boolean `ignore_errors`, `ignore_errors` on an
array, and files whose top level is not a supported array or object stream.

### `polars.null`

Sentinel used by `to_table()` for JSON `null`. It stringifies as `null`.

## DataFrame

All methods require an open handle. Calling a method after `:close()` raises
an error.

### `df:shape() -> rows, cols`

### `df:estimated_size() -> bytes`

Returns Polars' approximate in-memory size for the frame in bytes. The value
excludes allocator overhead beyond the column buffers and is `0` for an empty
frame. Calling it on a closed frame is an error.

```lua
local bytes = df:estimated_size()
```

### `df:max_chunks() -> integer`

Returns the largest chunk count across the frame's columns. A fresh or
rechunked frame typically reports `1`.

```lua
local chunks = df:max_chunks()
```

### `df:rechunk() -> DataFrame`

Returns a new frame with a single chunk per column. The schema, values, and row
order are unchanged, and the input frame stays open. Calling it on a closed
frame is an error.

```lua
local compact = df:rechunk()
```

### `df:shrink_to_fit() -> DataFrame`

Returns a copy with excess allocation capacity released. Schema, values, and
row order are unchanged, and the input frame stays open.

```lua
local compact = df:shrink_to_fit()
```

### `df:schema() -> table`

Maps column names to Polars dtype names, e.g. `{ score = "i64" }`. The order
of keys in the returned Lua table is not significant.

### `df:columns() -> table`

Returns the column names as an array in frame order.

```lua
for _, name in ipairs(df:columns()) do
  print(name)
end
```

### `df:head(n) -> DataFrame`

Returns a new frame with at most `n` rows. Negative or non-integer values are
rejected.

### `df:tail(n) -> DataFrame`

Returns a new frame with at most the last `n` rows. `n` defaults to `5`, `0`
returns an empty frame with the same schema, and a count larger than the frame
returns every row. Negative, fractional, non-numeric, and above-`2^53 - 1`
counts are rejected.

```lua
local latest = df:tail(10)
```

### `df:slice(offset, length) -> DataFrame`

Returns `length` rows starting at `offset`. A negative offset counts from the
end, so `df:slice(-2, 2)` returns the last two rows; an offset outside the frame
returns an empty frame with the same schema. `length` must be a non-negative
integer. Both arguments must be integers and at most `2^53 - 1` in magnitude.

```lua
local page = df:slice(20, 10)
local last_two = df:slice(-2, 2)
```

### `df:take(indices) -> DataFrame`

Returns rows at the requested positions. `indices` is a non-empty contiguous
list of integers; positive values are 1-based and negative values count from
the end (`-1` is the last row). Order and duplicates are preserved, and the
result keeps the input schema. Every resolved position must be inside the
frame.

```lua
local picked = df:take({ 2, 4 })
local last_two = df:take({ -1, -2 })
local repeated = df:take({ 5, 1, 5 })
```

An empty, non-contiguous, or non-list argument, zero, fractional, non-numeric,
out-of-range, or above-`2^53 - 1` positions, and closed frames are errors.

### `df:with_row_index([name, offset]) -> DataFrame`

Returns a new frame with a row-index column prepended. `name` defaults to
`"index"` and must be a non-empty string that does not collide with an existing
column. `offset` is a non-negative integer, default `0`, added to the first row
index; indexes then increase by one per row. Offset values above `2^53 - 1`
are rejected.

```lua
local indexed = df:with_row_index("row_id", 100)
```

### `df:reverse() -> DataFrame`

Returns a new frame with the row order reversed. Column names, order, dtypes,
and nulls are preserved; the input frame is unchanged. An empty frame stays
empty. Calling it on a closed frame is an error.

```lua
local newest_first = df:reverse()
```

### `df:transpose([options]) -> DataFrame`

Transposes the frame so columns become rows and rows become columns. Polars
finds a common supertype across all values, so mixed dtypes are cast to that
type. Output columns are named `column_0`, `column_1`, and so on unless
`options.keep_names_as` supplies a non-empty column name for the original
column names. Empty frames cannot be transposed; the input frame is unchanged.

```lua
local swapped = df:transpose()
local named = df:transpose({ keep_names_as = "field" })
```

Unknown option keys, a non-table options argument, empty `keep_names_as`,
empty frames, and closed frames are errors.

### `df:shift(periods [, columns]) -> DataFrame`

Shifts column values by `periods` rows, keeping the column names, order, and
dtypes. Positive periods move values toward later rows and insert nulls at the
start; negative periods move values toward earlier rows and insert nulls at the
end; `0` returns an unchanged copy. With no `columns` every column shifts. A
single column name or a non-empty contiguous list limits the shift to those
columns and leaves the others untouched. The input frame is unchanged.

```lua
local lagged = df:shift(1)
local lead_score = df:shift(-1, "score")
local paired = df:shift(2, { "score", "bonus" })
```

Non-integer, non-numeric, or above-`2^53 - 1` periods, malformed, duplicate,
empty, or unknown column subsets, and closed frames are errors.

### `df:diff(periods [, columns]) -> DataFrame`

Computes each numeric value minus the value `periods` rows before it. The first
`periods` rows are null because no earlier value exists. With no `columns`
every primitive numeric column participates; a single name or a non-empty
contiguous list restricts the operation and must name numeric columns.
Unsigned inputs widen to `i64` through Polars' diff implementation, while nulls
stay null. Column order and the input frame are preserved.

```lua
local changes = df:diff(1, "score")
local wider = df:diff(2)
```

Zero, negative, fractional, non-numeric, or above-`2^53 - 1` periods,
malformed, duplicate, empty, unknown, or non-numeric column subsets, and closed
frames are errors.

### `df:cum_sum([columns]) -> DataFrame`

Computes a forward running sum over every primitive numeric column or a
validated numeric subset. Nulls remain null and a later value resumes the
running total. Column order, the input frame, and non-selected columns are
preserved.

```lua
local total = df:cum_sum("score")
local all_numeric = df:cum_sum()
```

### `df:cum_min([columns]) -> DataFrame`

Computes a forward running minimum with the same all-numeric default and
validated numeric subset rules as `cum_sum`.

```lua
local floor = df:cum_min("score")
```

### `df:cum_max([columns]) -> DataFrame`

Computes a forward running maximum with the same all-numeric default and
validated numeric subset rules as `cum_sum`.

```lua
local ceiling = df:cum_max("score")
```

### `df:cum_count([columns]) -> DataFrame`

Computes a forward running count of non-null values. The result is `u32`;
nulls do not advance the count. It uses the same all-numeric default and
validated numeric subset rules as the other cumulative operations.

```lua
local seen = df:cum_count("score")
```

### `df:cum_prod([columns]) -> DataFrame`

Computes a forward running product with the same all-numeric default and
validated numeric subset rules as the other cumulative operations.

```lua
local product = df:cum_prod("score")
```

Malformed, duplicate, empty, unknown, or non-numeric column subsets and closed
frames are errors for all five cumulative operations.

### `df:clip(min, max [, columns]) -> DataFrame`

Clamps numeric values to the inclusive `[min, max]` range. `min` and `max`
must be finite numbers with `min <= max`; a non-integral bound on an integer
column is an error instead of being silently truncated. With no `columns` every
primitive numeric column is clipped and string, Boolean, and other non-numeric
columns are left unchanged. A single name or a non-empty contiguous list
restricts the operation and must name only numeric columns. Nulls are
preserved, column order is preserved, and the input frame is unchanged.

```lua
local bounded = df:clip(0, 100)
local scored = df:clip(0, 10, "score")
local paired = df:clip(-1, 1, { "score", "bonus" })
```

NaN or infinite bounds, `min > max`, a fractional bound on an integer column,
unknown or non-numeric columns in an explicit subset, malformed or duplicate
subsets, and closed frames are errors.

### `df:cast(mapping) -> DataFrame`

Casts one or more columns to new dtypes. `mapping` is a non-empty table of
`column = dtype` pairs. Supported dtype names are `bool`/`boolean`, `i32`/
`int32`, `i64`/`int64`, `u32`/`uint32`, `u64`/`uint64`, `f32`/`float32`,
`f64`/`float64`, and `str`/`string`/`utf8`, matched case-insensitively.
Casting is strict: a value that cannot be converted fails the whole operation
instead of becoming null. The result keeps the original column order and the
input frame is unchanged.

```lua
local typed = df:cast({ score = "f64", active = "str" })
```

An empty mapping, non-table input, empty or non-string column/dtype names,
unsupported dtypes, unknown columns, unparsable values, and closed frames are
errors.

### `df:unique([columns, options]) -> DataFrame`

Returns distinct rows. With no column argument every column participates,
preserving the earlier `unique()` result. `columns` may be a single name or a
non-empty contiguous list to compare only those columns; unknown, duplicate,
empty, and malformed names are errors.

`options` is an optional table:

- `keep`: `"first"` (default), `"last"`, `"none"`, or `"any"`, matched
  case-insensitively. `first` and `last` keep that occurrence, `none` drops
  every row whose key repeats, and `any` allows Polars to choose.
- `maintain_order`: a boolean, default `true`. Keeps the first-seen row order
  for a stable result; `false` permits the faster unstable distinct.

```lua
local all_unique = df:unique()
local one_per_id = df:unique("id")
local last_per_id = df:unique("id", { keep = "last" })
local only_unrepeated = df:unique("id", { keep = "none" })
```

Unknown option keys, non-string or unsupported `keep` values, non-boolean
`maintain_order`, malformed column lists, and closed frames are errors.

### `df:explode(columns [, options]) -> DataFrame`

Flattens one or more list columns into long form, repeating the other columns
for each element. `columns` is a single name or a non-empty contiguous list,
and every named column must have a list dtype; a non-list column is an error.

`options` is an optional table:

- `keep_nulls`: a boolean, default `true`. Keeps one null row for a null list.
- `empty_as_null`: a boolean, default `true`. Keeps one null row for an empty
  list instead of dropping it.

```lua
local tagged = df:explode("tags")
local compact = df:explode("tags", {
  keep_nulls = false,
  empty_as_null = false,
})
```

Unknown option keys, non-boolean flags, empty or malformed column lists,
non-list columns, unknown columns, and closed frames are errors.

### `df:unnest([columns [, separator]]) -> DataFrame`

Expands one or more `Struct` columns into their field columns. With no
`columns` every struct column is expanded; an explicit name or contiguous list
must name struct columns. `separator` is an optional prefix: when set, each
output field is named `column{separator}field`. The input frame is unchanged
and the result keeps the non-struct columns in frame order.

```lua
local expanded = df:unnest("meta")
local prefixed = df:unnest({ "meta" }, "_")
```

Malformed, duplicate, empty, or unknown column subsets, non-struct columns, a
non-string separator, a frame with no struct columns, and closed frames are
errors.

### `df:drop_nulls([columns]) -> DataFrame`

Drops rows that contain a null in any selected column. With no argument every
column participates, preserving the earlier behavior. `columns` may be a single
column name or a non-empty contiguous list of names; unknown, empty, duplicate,
and malformed names are errors, and the result keeps the original schema and
column order.

```lua
local complete = df:drop_nulls()               -- any null
local scored = df:drop_nulls("score")          -- only null scores
local keyed = df:drop_nulls({ "id", "name" })  -- either key null
```

### `df:fill_null(value [, columns]) -> DataFrame`

Replaces nulls with a scalar, optionally only in the named columns. `value` may
be a finite number, a string, or a boolean; `nil` and the strings `"zero"` and
`"one"` keep the earlier strategy aliases for `0` and `1`. The value is
formatted as a SQL literal, so string content is escaped and `"O'Reilly"`
round-trips. `columns` is a single name or a non-empty contiguous list; when
omitted every column is filled, and when a subset is given the non-selected
columns keep their nulls.

```lua
local labeled = df:fill_null("unknown", "note")
local scored = df:fill_null(0, { "score", "bonus" })
local flagged = df:fill_null(false, "active")
```

Non-finite numbers, NUL in a fill string, tables/functions, and malformed,
unknown, or duplicate column subsets are errors. Type conflicts between the
fill value and a column are reported by Polars.

### `df:fill_null_forward([columns]) -> DataFrame`

Replaces each null with the previous non-null value in the same column. Leading
nulls stay null because no previous value exists. With no argument every column
is filled; a single name or a non-empty contiguous list restricts the fill and
leaves unselected columns untouched. The input frame is unchanged and column
order is preserved.

```lua
local ordered = df:fill_null_forward()
local note = df:fill_null_forward("note")
local paired = df:fill_null_forward({ "note", "score" })
```

### `df:fill_null_backward([columns]) -> DataFrame`

Replaces each null with the next non-null value in the same column. Trailing
nulls stay null because no following value exists. It uses the same optional
all-column default and validated subsets as `fill_null_forward`.

```lua
local ordered = df:fill_null_backward()
local note = df:fill_null_backward("note")
```

Malformed, duplicate, empty, or unknown column subsets and closed frames are
errors for both directions.

### `df:fill_nan(value [, columns]) -> DataFrame`

Replaces floating-point NaN values with a finite scalar. NaN is a separate
missing-value state from null: `fill_nan` leaves null values untouched, unlike
`fill_null`. With no column argument every `Float32`/`Float64` column is
targeted. `columns` is a single name or a non-empty contiguous list; each named
column must exist, and non-float columns in the subset are left unchanged
because they cannot contain NaN. The input frame is unchanged and column order
is preserved.

```lua
local cleaned = df:fill_nan(0)
local scored = df:fill_nan(2.5, "score")
```

`value` must be a finite number; strings, booleans, tables, NaN, and positive or
negative infinity are errors. Unknown, duplicate, empty, or non-contiguous
column subsets and closed frames are also errors.

### `df:drop_nans([columns]) -> DataFrame`

Drops rows that contain a NaN in any targeted float column. Nulls are kept
because they are a distinct missing-value state. With no argument every
`Float32`/`Float64` column participates. `columns` is a single name or a
non-empty contiguous list; every named column must exist, and non-float columns
in the subset are ignored because they cannot contain NaN. The result keeps the
original schema and column order, and the input frame is unchanged.

```lua
local finite = df:drop_nans()
local scored = df:drop_nans("score")
local paired = df:drop_nans({ "score", "bonus" })
```

Unknown, duplicate, empty, or non-contiguous column subsets and closed frames
are errors.

### `df:gather_every(n [, offset]) -> DataFrame`

Returns every `n`th row starting at the zero-based `offset`, which defaults to
`0`. The result keeps the column names, order, and dtypes of the input; an
offset at or past the frame height returns an empty frame with the same schema.
`n` must be a positive integer, and `offset` must be a non-negative integer.

```lua
local every_other = df:gather_every(2)
local odd_rows = df:gather_every(2, 1)
```

Zero, negative, fractional, non-numeric, or above-`2^53 - 1` counts and
offsets, and closed frames are errors.

### `df:null_mask([name]) -> DataFrame`

Returns a new frame with a Boolean row mask appended after the existing
columns. The mask is `true` when any column in that row is null. `name`
defaults to `"has_nulls"` and must be a non-empty string that does not collide
with an existing column. A zero-column frame has no values to test and is an
error; the input frame is unchanged.

```lua
local flagged = df:null_mask()
local custom = df:null_mask("has_holes")
```

Empty, non-string, or colliding names, zero-column frames, and closed frames
are errors.

### `df:is_duplicated([name]) -> DataFrame`

Returns a new frame with a Boolean marker column appended after the existing
columns. The marker is `true` for every row whose complete row value occurs
more than once; full-row values are compared, including nulls. `name` defaults
to `"duplicated"` and must be a non-empty string that does not collide with an
existing column. The input frame is unchanged.

```lua
local flagged = df:is_duplicated()
local custom = df:is_duplicated("repeat")
```

### `df:is_unique([name]) -> DataFrame`

The inverse of `is_duplicated`: appends a Boolean column that is `true` for rows
whose complete row value occurs exactly once. `name` defaults to `"unique"` and
follows the same non-empty, non-colliding rules. The input frame is unchanged.

```lua
local singles = df:is_unique()
local named = df:is_unique("only_row")
```

Empty, non-string, or colliding marker names and closed frames are errors.

### `df:sql(query) -> DataFrame`

Runs a Polars SQL query with the current frame registered as table `df`. The
result is collected eagerly.

### `df:select(...) -> DataFrame`

Accepts column names as varargs or a table. Builds a quoted `SELECT`; returns a
new frame.

```lua
df:select("name", "score")
df:select({ "name", "score" })
```

### `df:filter(condition) -> DataFrame`

Wraps a raw SQL condition:

```lua
df:filter('"score" >= 9 AND "active" = true')
```

The condition is SQL, not a Lua expression; only pass trusted strings.

### `df:sort(columns, descending [, options]) -> DataFrame`

`columns` is a name or list. `descending` is a boolean or a per-column list of
booleans. `options` may set `nulls_last` to a boolean or a per-column list of
booleans; `true` writes `NULLS LAST`, `false` writes `NULLS FIRST`, and omitting
the option keeps the previous SQL ordering exactly.

```lua
local ordered = df:sort("score", false, { nulls_last = true })
local keyed = df:sort({ "team", "score" }, { false, false },
  { nulls_last = { true, true } })
```

A non-table options argument, unknown option keys, a `nulls_last` list whose
length differs from the column count, non-boolean `nulls_last` entries, and
closed frames are errors.

### `df:is_sorted(columns [, descending [, nulls_last]]) -> boolean`

Reports whether the current row order is sorted by one or more columns.
`descending` is a boolean or a per-column list of booleans and defaults to
`false`; `nulls_last` is a single boolean applied to every key and defaults to
`false`. The input frame is unchanged.

```lua
local ordered = df:is_sorted("score")
local desc = df:is_sorted("score", true)
local keyed = df:is_sorted({ "team", "score" }, { false, false }, true)
```

Missing, malformed, duplicate, empty, or unknown key lists, a descending list
whose length differs from the key count, non-boolean descending or
`nulls_last` values, and closed frames are errors.

### `df:top_k(k, columns) -> DataFrame`

Returns the `k` largest rows ordered by one or more key columns, all descending,
with null keys placed last. `k` must be a non-negative integer; `k = 0` returns
an empty frame with the same schema, and a larger `k` returns every row. Ties
are left to Polars. `columns` is a single name or a non-empty contiguous list.

```lua
local highest = df:top_k(5, "score")
```

### `df:bottom_k(k, columns) -> DataFrame`

Returns the `k` smallest rows ordered by one or more key columns, all ascending,
with null keys placed last. It uses the same count and column validation as
`top_k`.

```lua
local lowest = df:bottom_k(5, { "score" })
```

Negative, fractional, non-numeric, or above-`2^53 - 1` counts, malformed,
duplicate, empty, or unknown key lists, and closed frames are errors.

### `df:group_by(keys, aggregates) -> DataFrame`

`keys` is a name or list; `aggregates` is a list of SQL aggregate expressions.

```lua
df:group_by("team", { 'sum("score") AS total' })
```

Aggregate expressions are trusted SQL strings.

### `df:value_counts(columns [, options]) -> DataFrame`

Counts the distinct combinations of one or more key columns. The result keeps
the keys in the requested order and appends a `count` column. By default rows
are sorted by count descending, with ties ordered by the key columns for stable
output. `columns` is a single name or a non-empty contiguous list and is
required.

`options` is an optional table:

- `sort`: a boolean, default `true`. `false` returns the groups without an
  `ORDER BY`.
- `name`: the count column name, default `"count"`. It must be non-empty and
  must not collide with a grouping key.

```lua
local by_team = df:value_counts("team")
local by_team_active = df:value_counts({ "team", "active" })
local unsorted = df:value_counts("team", { sort = false, name = "n" })
```

Unknown option keys, non-boolean `sort`, invalid or colliding names, empty,
duplicate, unknown, or non-contiguous key lists, and closed frames are errors.

### `df:sum(column) -> number|nil`

Returns the scalar sum of one numeric column. Nulls are ignored; an empty
column or a column with no non-null values returns `polars.null`. Summing an
unsupported dtype is reported by Polars.

```lua
local total = df:sum("score")
```

### `df:mean(column) -> number|nil`

Returns the scalar mean of one numeric column. Nulls are ignored; no values
returns `polars.null`.

```lua
local average = df:mean("score")
```

### `df:min(column) -> value|nil`

Returns the scalar minimum of one orderable column, including string columns.
No values returns `polars.null`.

```lua
local lowest = df:min("score")
local first_name = df:min("name")
```

### `df:max(column) -> value|nil`

Returns the scalar maximum of one orderable column, including string columns.
No values returns `polars.null`.

```lua
local highest = df:max("score")
local last_name = df:max("name")
```

### `df:count([column]) -> integer`

Without an argument returns the row count. With one column name returns the
number of non-null values in that column. An empty frame returns `0`.

```lua
local rows = df:count()
local scored = df:count("score")
```

### `df:std(column) -> number|nil`

Returns the sample standard deviation of one numeric column. Nulls are
ignored; no values returns `polars.null`.

```lua
local spread = df:std("score")
```

### `df:var(column) -> number|nil`

Returns the sample variance of one numeric column with the same null handling
as `std`.

```lua
local variance = df:var("score")
```

### `df:median(column) -> value|nil`

Returns the median of one orderable column. No values returns `polars.null`.

```lua
local middle = df:median("score")
```

### `df:quantile(column, probability) -> number|nil`

Returns the continuous quantile for a probability in `[0, 1]` for one numeric
column. `0` and `1` return the minimum and maximum; no values returns
`polars.null`.

```lua
local median = df:quantile("score", 0.5)
local upper = df:quantile("score", 0.9)
```

Non-string, empty, or unknown column names, non-numeric or out-of-range
probabilities, and closed frames are errors. A Polars type error is surfaced
when an aggregate is not supported for the column's dtype.

### `df:n_unique([column]) -> integer`

Without an argument returns the number of distinct full rows. With one column
name returns the number of distinct non-null values in that column.

```lua
local distinct_rows = df:n_unique()
local teams = df:n_unique("team")
```

### `df:first(column) -> value|nil`

Returns the first value in frame order for one column. An empty frame returns
`polars.null`.

```lua
local first_name = df:first("name")
```

### `df:last(column) -> value|nil`

Returns the last value in frame order for one column. An empty frame returns
`polars.null`.

```lua
local last_name = df:last("name")
```

### `df:corr(left, right) -> number|nil`

Returns the Pearson correlation between two numeric columns. Both columns must
exist and have a numeric dtype; insufficient data returns `polars.null`.

```lua
local perfect = df:corr("score", "score")
```

Non-string, empty, unknown, or non-numeric column names and closed frames are
errors.

### `df:covar(left, right) -> number|nil`

Returns the sample covariance between two numeric columns. Both columns must
exist and be numeric; insufficient data returns `polars.null`.

```lua
local covariance = df:covar("score", "score")
```

### `df:covar_pop(left, right) -> number|nil`

Returns the population covariance between two numeric columns with the same
validation and null behavior as `covar`.

```lua
local population = df:covar_pop("score", "score")
```

### `df:product(column) -> number|nil`

Returns the product of one numeric column. An empty or all-null column returns
`polars.null`.

```lua
local product = df:product("score")
```

Non-string, empty, unknown, or non-numeric columns and closed frames are
errors.

### `df:any(column) -> boolean`

Returns true when at least one non-null value in a `bool` column is true.
Nulls are ignored; an empty or all-null column returns false.

```lua
local has_active = df:any("active")
```

### `df:all(column) -> boolean`

Returns true when every non-null value in a `bool` column is true. Nulls are
ignored; an empty or all-null column returns true.

```lua
local all_active = df:all("active")
```

Non-string, empty, unknown, or non-boolean columns and closed frames are
errors.

### `df:replace(old, new, columns) -> DataFrame`

Replaces scalar `old` values with scalar `new` in the selected columns. Each
value must be a finite number, string, or boolean; strings are SQL-escaped and
NUL is rejected. `columns` is a required name or non-empty contiguous list.
Nulls are not matched; use `fill_null` for nulls. Unselected columns and the
input frame are preserved.

```lua
local renamed = df:replace("red", "RED", "team")
local rescored = df:replace(10, 0, { "score" })
```

A missing or malformed column list, a non-scalar value, a type mismatch
reported by Polars, and closed frames are errors.

### `df:filter_in(column, values) -> DataFrame`

Keeps rows whose column equals one of a non-empty contiguous list of scalar
values. Values may be finite numbers, strings, or booleans. Null column values
do not match. The input frame is unchanged.

```lua
local red_or_blue = df:filter_in("team", { "red", "blue" })
local middle = df:filter_in("score", { 7, 9 })
```

### `df:filter_not_in(column, values) -> DataFrame`

Drops rows whose column equals one of the listed scalar values, using the same
value validation as `filter_in`.

```lua
local other = df:filter_not_in("team", { "red" })
```

Malformed, empty, or non-contiguous value lists, non-scalar entries, unknown
columns, type mismatches reported by Polars, and closed frames are errors.

### `df:contains(column, needle [, name]) -> DataFrame`

Appends a Boolean marker named `name` (default `"contains"`) that is true when
the `str` column contains the non-empty literal `needle`. Null source values
produce false. The input frame is unchanged.

```lua
local marked = df:contains("name", "an")
```

### `df:starts_with(column, prefix [, name]) -> DataFrame`

Appends a Boolean marker named `name` (default `"starts_with"`) for a non-empty
literal prefix on a `str` column.

```lua
local marked = df:starts_with("name", "a")
```

### `df:ends_with(column, suffix [, name]) -> DataFrame`

Appends a Boolean marker named `name` (default `"ends_with"`) for a non-empty
literal suffix on a `str` column.

```lua
local marked = df:ends_with("name", "a")
```

### `df:is_in(column, values [, name]) -> DataFrame`

Appends a Boolean marker named `name` (default `"is_in"`) that is true when the
column equals one of a non-empty contiguous list of scalar values. Null source
values produce false.

```lua
local marked = df:is_in("team", { "red", "blue" })
```

### `df:between(column, lower, upper [, name]) -> DataFrame`

Appends a Boolean marker named `name` (default `"between"`) that is true when a
numeric column falls within the inclusive `[lower, upper]` range. Both bounds
must be finite numbers and `lower <= upper`; null source values produce false.

```lua
local marked = df:between("score", 7, 10)
```

Non-string or wrong-dtype source columns, empty match literals, malformed or
empty value lists, non-scalar membership values, non-numeric columns, invalid
range bounds, empty or colliding marker names, and closed frames are errors.

### `df:is_null(column [, name]) -> DataFrame`

Appends a Boolean marker named `name` (default `"is_null"`) that is true when
the column value is null. Any column dtype is accepted.

```lua
local missing = df:is_null("note")
```

### `df:is_not_null(column [, name]) -> DataFrame`

Appends a Boolean marker named `name` (default `"is_not_null"`) that is true
when the column value is not null. Any column dtype is accepted.

```lua
local present = df:is_not_null("note")
```

### `df:like(column, pattern [, name]) -> DataFrame`

Appends a Boolean marker named `name` (default `"like"`) that is true when a
`str` column matches the SQL `LIKE` `pattern`. `%` and `_` are wildcards; the
match follows Polars' case-sensitive `LIKE` semantics. A null value produces
false.

```lua
local marked = df:like("name", "a%")
```

### `df:not_like(column, pattern [, name]) -> DataFrame`

Appends a Boolean marker named `name` (default `"not_like"`) that is true when
a `str` column does not match the SQL `LIKE` `pattern`. A null value produces
false.

```lua
local marked = df:not_like("name", "a%")
```

### `df:is_blank(column [, name]) -> DataFrame`

Appends a Boolean marker named `name` (default `"is_blank"`) that is true when
a `str` column is empty or contains only whitespace. A null value produces
false.

```lua
local blank = df:is_blank("note")
```

Unknown or non-string columns, wrong dtypes for `like`/`not_like`/`is_blank`,
non-string or NUL patterns, empty or colliding marker names, and closed frames
are errors.

### `df:coalesce(columns [, name]) -> DataFrame`

Appends a column named `name` (default `"coalesce"`) with the first non-null
value across the selected columns for each row. `columns` is a name or
non-empty contiguous list. The input frame is unchanged.

```lua
local filled = df:coalesce({ "preferred_name", "name" }, "display_name")
```

All-selected-null rows produce null. Unknown or malformed column lists,
incompatible types reported by Polars, colliding names, and closed frames are
errors.

### `df:concat_str(columns, separator [, name]) -> DataFrame`

Appends a string column named `name` (default `"concat_str"`) containing the
selected columns joined by the literal `separator`. An empty separator is
allowed. `columns` is a name or non-empty contiguous list.

```lua
local label = df:concat_str({ "name", "team" }, "-", "label")
```

Null input values are treated as empty strings, so the separators still appear
in the result. Unknown or malformed column lists, non-string or NUL separators,
colliding names, and closed frames are errors.

### `df:lower(column [, name]) -> DataFrame`

Appends a lowercase copy of a `str` column named `name` (default `"lower"`).
Null values stay null.

```lua
local lowered = df:lower("name")
```

### `df:upper(column [, name]) -> DataFrame`

Appends an uppercase copy of a `str` column named `name` (default `"upper"`).

```lua
local uppercased = df:upper("name", "shout")
```

### `df:length(column [, name]) -> DataFrame`

Appends the character length of a `str` column named `name` (default
`"length"`). Null values stay null.

```lua
local lengths = df:length("name")
```

Non-string, empty, or unknown source columns, non-`str` dtypes, empty or
colliding output names, and closed frames are errors.

### `df:trim(column [, name]) -> DataFrame`

Appends whitespace-trimmed values from a `str` column named `name` (default
`"trim"`). Null values stay null.

```lua
local cleaned = df:trim("name")
```

### `df:ltrim(column [, name]) -> DataFrame`

Appends left-trimmed values from a `str` column named `name` (default
`"ltrim"`). Null values stay null.

```lua
local cleaned = df:ltrim("name")
```

### `df:rtrim(column [, name]) -> DataFrame`

Appends right-trimmed values from a `str` column named `name` (default
`"rtrim"`). Null values stay null.

```lua
local cleaned = df:rtrim("name")
```

### `df:replace_str(column, old, new [, name]) -> DataFrame`

Appends a `str` column named `name` (default `"replace_str"`) replacing every
literal occurrence of the non-empty `old` string with `new`. `new` may be
empty. Null source values stay null.

```lua
local renamed = df:replace_str("name", "a", "A")
```

### `df:substr(column, start, length [, name]) -> DataFrame`

Appends a `str` column named `name` (default `"substr"`) containing the
1-based character substring beginning at `start` with `length` characters.
`length` may be `0`; null source values stay null.

```lua
local middle = df:substr("name", 2, 2)
```

Non-string or unknown source columns, non-`str` dtypes, empty or non-string
replacement values, non-positive or fractional starts, negative lengths,
empty or colliding output names, and closed frames are errors.

### `df:pad_left(column, width [, fill [, name]]) -> DataFrame`

Appends a `str` column named `name` (default `"pad_left"`) padded on the left
to `width` characters using `fill` (default a space). `width` must be a
positive integer and `fill` a non-empty string.

```lua
local padded = df:pad_left("name", 5, "x")
```

### `df:pad_right(column, width [, fill [, name]]) -> DataFrame`

Appends a right-padded `str` column named `name` (default `"pad_right"`) with
the same validation as `pad_left`.

```lua
local padded = df:pad_right("name", 5)
```

### `df:repeat_str(column, count [, name]) -> DataFrame`

Appends a `str` column named `name` (default `"repeat_str"`) repeating the
source `count` times. `count` must be an integer from `0` through `1000`; zero
produces an empty string.

```lua
local repeated = df:repeat_str("name", 2)
```

### `df:reverse_str(column [, name]) -> DataFrame`

Appends a reversed `str` column named `name` (default `"reverse_str"`). Null
values stay null.

```lua
local reversed = df:reverse_str("name")
```

### `df:capitalize(column [, name]) -> DataFrame`

Appends a `str` column named `name` (default `"capitalize"`) with the first
character uppercased and the remaining characters lowercased. Null values stay
null.

```lua
local capitalized = df:capitalize("name")
```

Non-string or unknown source columns, non-`str` dtypes, non-positive or
fractional widths, empty fills, invalid repeat counts, empty or colliding
output names, and closed frames are errors.

### `df:left(column, count [, name]) -> DataFrame`

Appends the first `count` characters of a `str` column named `name` (default
`"left"`). `count` must be a non-negative integer.

```lua
local prefix = df:left("name", 2)
```

### `df:right(column, count [, name]) -> DataFrame`

Appends the last `count` characters of a `str` column named `name` (default
`"right"`).

```lua
local suffix = df:right("name", 2)
```

### `df:split_part(column, separator, index [, name]) -> DataFrame`

Appends the 1-based field `index` from splitting a `str` column by the
non-empty literal `separator`. The result is named `name` (default
`"split_part"`). Missing fields produce an empty string.

```lua
local field = df:split_part("name", "a", 2)
```

### `df:strpos(column, needle [, name]) -> DataFrame`

Appends the 1-based position of the non-empty literal `needle` in a `str`
column, or `0` when absent, named `name` (default `"strpos"`).

```lua
local position = df:strpos("name", "a")
```

### `df:char_at(column, index [, name]) -> DataFrame`

Appends the 1-based character at `index` from a `str` column, named `name`
(default `"char_at"`). `index` must be a positive integer.

```lua
local character = df:char_at("name", 2)
```

Non-string or unknown source columns, non-`str` dtypes, negative or fractional
counts and indexes, empty separators or needles, empty or colliding output
names, and closed frames are errors.

### `df:abs(column [, name]) -> DataFrame`

Appends the absolute value of a numeric column named `name` (default `"abs"`).
Null values stay null.

```lua
local magnitudes = df:abs("score")
```

### `df:round(column, decimals [, name]) -> DataFrame`

Appends a rounded numeric column named `name` (default `"round"`).
`decimals` must be a non-negative integer. Null values stay null.

```lua
local rounded = df:round("score", 1)
```

### `df:floor(column [, name]) -> DataFrame`

Appends the floor of a numeric column named `name` (default `"floor"`).

```lua
local floored = df:floor("score")
```

### `df:ceil(column [, name]) -> DataFrame`

Appends the ceiling of a numeric column named `name` (default `"ceil"`).

```lua
local ceiled = df:ceil("score")
```

### `df:sign(column [, name]) -> DataFrame`

Appends the sign (`-1`, `0`, or `1`) of a numeric column named `name` (default
`"sign"`).

```lua
local signed = df:sign("score")
```

Non-numeric or unknown source columns, negative or fractional decimal counts,
empty or colliding output names, and closed frames are errors.

### `df:add(column, value [, name]) -> DataFrame`

Appends a numeric column named `name` (default `"add"`) containing the source
column plus the finite scalar `value`.

```lua
local shifted = df:add("score", 5)
```

### `df:subtract(column, value [, name]) -> DataFrame`

Appends the source column minus a finite scalar, named `name` (default
`"subtract"`).

```lua
local shifted = df:subtract("score", 5)
```

### `df:multiply(column, value [, name]) -> DataFrame`

Appends the source column multiplied by a finite scalar, named `name` (default
`"multiply"`).

```lua
local scaled = df:multiply("score", 3)
```

### `df:divide(column, value [, name]) -> DataFrame`

Appends the source column divided by a finite, non-zero scalar, named `name`
(default `"divide"`). Integer columns may produce float results.

```lua
local halved = df:divide("score", 2)
```

### `df:modulo(column, value [, name]) -> DataFrame`

Appends the source column modulo a finite, non-zero scalar, named `name`
(default `"modulo"`).

```lua
local remainder = df:modulo("score", 4)
```

Non-numeric or unknown source columns, non-finite scalars, zero divisors,
empty or colliding output names, and closed frames are errors.

### `df:year(column [, name]) -> DataFrame`

Appends the year of a `date` or `datetime` column named `name` (default
`"year"`). Null values stay null.

```lua
local years = df:year("day")
```

### `df:month(column [, name]) -> DataFrame`

Appends the month of a `date` or `datetime` column named `name` (default
`"month"`).

```lua
local months = df:month("day")
```

### `df:day(column [, name]) -> DataFrame`

Appends the day of a `date` or `datetime` column named `name` (default
`"day"`).

```lua
local days = df:day("day")
```

### `df:hour(column [, name]) -> DataFrame`

Appends the hour of a `datetime` column named `name` (default `"hour"`).
Date-only columns are rejected.

```lua
local hours = df:hour("stamp")
```

### `df:minute(column [, name]) -> DataFrame`

Appends the minute of a `datetime` column named `name` (default `"minute"`).
Date-only columns are rejected.

```lua
local minutes = df:minute("stamp")
```

Non-temporal or unknown source columns, clock parts requested from date-only
columns, empty or colliding output names, and closed frames are errors.

### `df:quarter(column [, name]) -> DataFrame`

Appends the quarter (`1`–`4`) of a `date` or `datetime` column named `name`
(default `"quarter"`).

```lua
local quarters = df:quarter("day")
```

### `df:week(column [, name]) -> DataFrame`

Appends the week number of a `date` or `datetime` column named `name` (default
`"week"`). The value follows Polars' `DATE_PART('week', ...)` semantics.

```lua
local weeks = df:week("day")
```

### `df:weekday(column [, name]) -> DataFrame`

Appends the weekday number (`1` = Monday through `7` = Sunday) of a `date` or
`datetime` column named `name` (default `"weekday"`).

```lua
local weekdays = df:weekday("day")
```

### `df:day_of_year(column [, name]) -> DataFrame`

Appends the 1-based day-of-year number of a `date` or `datetime` column named
`name` (default `"day_of_year"`).

```lua
local ordinals = df:day_of_year("day")
```

### `df:second(column [, name]) -> DataFrame`

Appends the second (`0`–`59`) of a `datetime` column named `name` (default
`"second"`). Date-only columns are rejected.

```lua
local seconds = df:second("stamp")
```

Non-temporal or unknown source columns, second extraction from date-only
columns, empty or colliding output names, and closed frames are errors.

### `df:drop(...) -> DataFrame`

Returns a new frame without the named columns. Accepts one or more column-name
strings as varargs.

```lua
df:drop("unused", "debug")
```

Dropping every column is an error. The remaining columns keep their frame
order.

### `df:rename(mapping) -> DataFrame`

Renames columns whose names appear as keys in `mapping`; other columns are
kept. Values are the new column names. Column order is preserved.

```lua
df:rename({ score = "points" })
```

### `df:with_columns(...) -> DataFrame`

Appends trusted SQL expressions as new columns, keeping the existing columns
in their original order.

```lua
df:with_columns('"score" * 2 AS double_score')
```

### `df:join(other, options) -> DataFrame`

Eagerly joins `df` (the left frame) with `other` (the right frame). Both frames
stay open; the result is a new frame.

```lua
local joined = left:join(right, {
  on = { "region", "id" },  -- same keys on both sides
  how = "left",
})
```

`options` fields:

- `on`: a column name or list of names. Uses the same keys on both frames.
- `left_on`, `right_on`: column names or lists for each side. Use these instead
  of `on` when the key names differ.
- `how`: `"inner"` (default), `"left"`, `"full"`/`"outer"`, `"semi"`, `"anti"`,
  or `"cross"`.
- `nulls_equal`: optional boolean (default `false`). When false, null keys do
  not match; when true, null keys match null keys.

Join semantics:

- `inner` keeps rows whose keys match on both sides.
- `left` keeps every left row, with null right columns when no key matches.
- `full` and `outer` are aliases; they keep every row from both sides.
- `semi` keeps left rows that have a match and returns only left columns.
- `anti` keeps left rows without a match and returns only left columns.
- `cross` is a Cartesian product and does not accept `on`, `left_on`, or
  `right_on`.

Key lists must be non-empty, have the same length on both sides, contain no
duplicate names, and name columns that exist in the corresponding frame. The
result coalesces the join keys into one set of columns. Duplicate non-key column
names are suffixed by Polars (`_right`).

The error path covers missing keys, duplicate keys, mismatched key counts,
keys passed to a cross join, invalid join types, invalid options, and closed
handles.

### `df:concat(other) -> DataFrame`

Appends `other`'s rows below the receiver's rows. Both frames stay open, and
Polars validates the schema compatibility. The result is a new frame.

```lua
local all_rows = first:concat(second)
```

A non-DataFrame argument, incompatible schemas, and closed handles are errors.

### `df:hstack(other) -> DataFrame`

Appends `other`'s columns beside the receiver's columns. Both frames must have
the same height and both stay open. The result is a new frame.

```lua
local wider = left:hstack(right)
```

A non-DataFrame argument, a height mismatch, duplicate resulting column names,
and closed handles are errors.

### `df:write_csv(path [, options]) -> DataFrame`

Writes the frame as CSV and returns `df` for chaining. The file is created or
truncated. With no options it writes a comma-separated file with a header row
and empty fields for nulls, as before.

`options` is an optional table:

- `delimiter`: a one-byte field separator, default `","`. Quote, newline,
  carriage return, and NUL bytes are rejected.
- `header`: a boolean, default `true`. Set it to `false` to omit the header row.
- `null_value`: the literal placeholder written for null fields, default the
  empty string. Polars writes it without quoting, so a value containing the
  delimiter, `"`, NUL, newline, or carriage return is rejected.
- `line_terminator`: `"\n"` (default) or `"\r\n"`; the terminator is written
  after the header and every record. Other values are errors, keeping the
  output readable by the reader and by RFC 4180 consumers.
- `quote_style`: `"necessary"` (default; quote only fields that need it),
  `"always"` (quote every field), `"non_numeric"` (quote string fields even when
  quoting is not strictly needed; `"non-numeric"` is an alias), or `"never"`
  (never quote). Values are matched case-insensitively. `"never"` can produce
  invalid CSV when a field contains the delimiter, a quote, or a line break,
  matching Polars; use it only for controlled output.
- `float_precision`: a non-negative integer number of digits after the decimal
  point for float columns. `0` writes whole-number-rounded floats, `2` writes
  values such as `2.50`, and omitting the option keeps Polars' shortest
  round-trippable representation. It composes with every other writer option.
- `include_bom`: a boolean, default `false`. `true` prepends a UTF-8 byte-order
  mark (`"\239\187\191"`) before the header or first record, which helps some
  spreadsheet tools detect UTF-8. The reader accepts the BOM and keeps the
  header name clean. It composes with every other writer option.
- `decimal_comma`: a boolean, default `false`. `true` serializes float fields
  with a comma decimal separator, intended with a semicolon or tab `delimiter`.
  It changes only how floats are formatted; the field delimiter is still
  controlled by `delimiter`, and integers, strings, and nulls are unaffected.
  Read the result back with `read_csv(..., { delimiter = ";", decimal_comma =
  true })`.

```lua
df:write_csv("out.csv")
df:write_csv("out.tsv", {
  delimiter = "\t",
  header = false,
  null_value = "NA",
})
df:write_csv("crlf.csv", { line_terminator = "\r\n" })
df:write_csv("quoted.csv", { quote_style = "always" })
df:write_csv("rounded.csv", { float_precision = 2 })
df:write_csv("utf8.csv", { include_bom = true })
df:write_csv("european.csv", { delimiter = ";", decimal_comma = true })
```

Unknown option keys and invalid types are errors, as are negative, fractional,
non-numeric, or above-`2^53 - 1` float precision values, non-boolean
`include_bom`/`decimal_comma`, closed frames, non-string or empty paths, and
write failures.

### `df:to_csv([options]) -> string`

Returns the frame as CSV text. `options` is the same table accepted by
`write_csv`, including delimiter, header, null placeholder, line terminator,
quote style, float precision, BOM, and decimal-comma controls. With no options
the text is byte-identical to `write_csv`'s default comma/header/empty-null
output.

```lua
local text = df:to_csv()
local headerless = df:to_csv({ delimiter = ";", header = false })
```

Unknown option keys, invalid option values, and closed frames are errors.

### `df:write_json(path [, options]) -> DataFrame`

Writes the frame as JSON and returns `df` for chaining. The file is created or
truncated. With no options it writes one JSON array of row objects, matching
`to_json()` and `read_json`'s default.

`options` is an optional table:

- `format`: `"array"` (default; aliases `"json"`) or `"lines"` (aliases
  `"ndjson"`, `"jsonl"`, `"json-lines"`, and `"jsonlines"`), matched
  case-insensitively. JSON Lines writes one object per line and is not valid
  JSON as a whole, so read it back with `format = "lines"`. Other values are
  errors.
- `pretty`: a boolean, default `false`. `true` writes a pretty-printed JSON
  array with the same values as the compact form. Pretty output is not
  available for `format = "lines"` because indentation would break the
  one-object-per-line contract.

```lua
df:write_json("rows.json")
df:write_json("pretty.json", { pretty = true })
df:write_json("rows.jsonl", { format = "lines" })
```

Unknown option keys and invalid types are errors, as are `pretty` with JSON
Lines, closed frames, non-string or empty paths, and write failures.

### `df:write_parquet(path [, options]) -> DataFrame`

Writes the frame as Parquet and returns `df` for chaining. The file is created
or truncated. With no options it writes Zstd-compressed pages with Polars'
default statistics and chunk sizes.

`options` is an optional table:

- `compression`: `"zstd"` (default), `"snappy"`, `"gzip"`, `"brotli"`,
  `"lz4"` (alias `"lz4-raw"`), or `"uncompressed"` (alias `"none"`), matched
  case-insensitively.
- `compression_level`: a non-negative integer selecting the codec level.
  Zstd accepts `1..=22`, gzip `0..=9`, and brotli `0..=11`; omitting it keeps
  the codec default. Snappy, lz4, and uncompressed reject an explicit level.
- `statistics`: a boolean, default `true`. `false` skips the column statistics
  (min/max/null count) that predicate pushdown readers can use.
- `row_group_size`: a positive integer row count per row group. Omitted uses
  Polars' default 262144-row chunks; `1` writes one row per group.
- `data_page_size`: a positive integer maximum data-page size in bytes.
  Omitted uses Polars' default 1 MiB pages.

```lua
df:write_parquet("out.parquet")
df:write_parquet("out.parquet", {
  compression = "zstd",
  compression_level = 5,
  statistics = false,
  row_group_size = 1000,
  data_page_size = 65536,
})
```

Unknown option keys and invalid types are errors, as are unsupported codec
names, a non-positive or fractional chunk size, closed frames, non-string or
empty paths, and write failures.

### `df:to_json([options]) -> string`

Row-oriented JSON. With no options it returns a JSON array with one object per
row. `options` may set `format` to `"array"` (default; alias `"json"`) or
`"lines"` (aliases `"ndjson"`, `"jsonl"`, `"json-lines"`, and `"jsonlines"`),
matched case-insensitively. `pretty = true` returns an indented array; it
composes with the array format only. JSON Lines returns one object per line and
is not valid JSON as a whole; read it back with
`read_json(..., { format = "lines" })`. Non-JSON types are formatted by Polars'
Arrow JSON writer.

```lua
local array = df:to_json()
local pretty = df:to_json({ pretty = true })
local lines = df:to_json({ format = "lines" })
```

Unknown option keys, non-string or unsupported formats, non-boolean `pretty`,
`pretty` with JSON Lines, and closed frames are errors.

### `df:to_table() -> table`

Decodes `to_json()` into an array of row tables. JSON `null` becomes
`polars.null`. Large integers may lose precision as Lua doubles.

### `df:close()`

Frees the Rust handle. Idempotent. Also called by `__gc`.

## C ABI

The exported functions are:

```c
const char *pl_version(void);
PlFrame *pl_dataframe_read_csv(const char *path, char **err);
PlFrame *pl_dataframe_read_csv_options(
    const char *path, const char *delimiter, int32_t has_header, char **err);
PlFrame *pl_dataframe_read_csv_ex(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment, char **err);
PlFrame *pl_dataframe_read_csv_projected(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count, char **err);
PlFrame *pl_dataframe_read_csv_typed(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count, char **err);
PlFrame *pl_dataframe_read_csv_null_values(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count, char **err);
PlFrame *pl_dataframe_read_csv_row_window(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    uint64_t skip_rows, int64_t n_rows, char **err);
PlFrame *pl_dataframe_read_csv_encoded(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    uint64_t skip_rows, int64_t n_rows, const char *encoding, char **err);
PlFrame *pl_dataframe_read_csv_renamed(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    uint64_t skip_rows, int64_t n_rows,
    const char *const *rename_columns, uint64_t rename_column_count,
    const char *encoding, char **err);
PlFrame *pl_dataframe_read_csv_named_nulls(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_columns, const char *const *null_values,
    uint64_t null_value_count,
    uint64_t skip_rows, int64_t n_rows,
    const char *const *rename_columns, uint64_t rename_column_count,
    const char *encoding, char **err);
PlFrame *pl_dataframe_read_csv_parsed(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    const char *const *null_columns, const char *const *named_null_values,
    uint64_t named_null_value_count,
    uint64_t skip_rows, int64_t n_rows,
    const char *const *rename_columns, uint64_t rename_column_count,
    const char *encoding, int32_t try_parse_dates, char **err);
PlFrame *pl_dataframe_read_csv_lenient(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    const char *const *null_columns, const char *const *named_null_values,
    uint64_t named_null_value_count,
    uint64_t skip_rows, int64_t n_rows,
    const char *const *rename_columns, uint64_t rename_column_count,
    const char *encoding, int32_t try_parse_dates,
    int32_t truncate_ragged_lines, int32_t ignore_errors, char **err);
PlFrame *pl_dataframe_read_csv_extended(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    const char *const *null_columns, const char *const *named_null_values,
    uint64_t named_null_value_count,
    uint64_t skip_rows, uint64_t skip_rows_after_header, int64_t n_rows,
    const char *const *rename_columns, uint64_t rename_column_count,
    const char *encoding, int32_t try_parse_dates,
    int32_t decimal_comma, int32_t truncate_ragged_lines,
    int32_t ignore_errors, char **err);
PlFrame *pl_dataframe_read_csv_empty_policy(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    const char *const *null_columns, const char *const *named_null_values,
    uint64_t named_null_value_count,
    uint64_t skip_rows, uint64_t skip_rows_after_header, int64_t n_rows,
    const char *const *rename_columns, uint64_t rename_column_count,
    const char *encoding, int32_t try_parse_dates,
    int32_t decimal_comma, int32_t truncate_ragged_lines,
    int32_t ignore_errors, int32_t raise_if_empty, char **err);
PlFrame *pl_dataframe_read_csv_inferred(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    const char *const *null_columns, const char *const *named_null_values,
    uint64_t named_null_value_count,
    uint64_t skip_rows, uint64_t skip_rows_after_header, int64_t n_rows,
    const char *const *rename_columns, uint64_t rename_column_count,
    const char *encoding, int32_t try_parse_dates,
    int32_t decimal_comma, int32_t truncate_ragged_lines,
    int32_t ignore_errors, int32_t raise_if_empty,
    int64_t infer_schema_length, char **err);
PlFrame *pl_dataframe_read_csv_low_memory(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    const char *const *null_columns, const char *const *named_null_values,
    uint64_t named_null_value_count,
    uint64_t skip_rows, uint64_t skip_rows_after_header, int64_t n_rows,
    const char *const *rename_columns, uint64_t rename_column_count,
    const char *encoding, int32_t try_parse_dates,
    int32_t decimal_comma, int32_t truncate_ragged_lines,
    int32_t ignore_errors, int32_t raise_if_empty,
    int64_t infer_schema_length, int32_t low_memory, char **err);
PlFrame *pl_dataframe_read_parquet(const char *path, char **err);
PlFrame *pl_dataframe_read_parquet_options(
    const char *path, const char *const *columns, uint64_t column_count,
    uint64_t skip_rows, int64_t n_rows, char **err);
PlFrame *pl_dataframe_read_parquet_low_memory(
    const char *path, const char *const *columns, uint64_t column_count,
    uint64_t skip_rows, int64_t n_rows, int32_t low_memory, char **err);
PlFrame *pl_dataframe_read_parquet_full(
    const char *path, const char *const *columns, uint64_t column_count,
    uint64_t skip_rows, int64_t n_rows, int32_t low_memory, int32_t rechunk,
    char **err);
PlFrame *pl_dataframe_read_json(
    const char *path, int32_t json_lines,
    const char *const *columns, uint64_t column_count, char **err);
PlFrame *pl_dataframe_read_json_inferred(
    const char *path, int32_t json_lines,
    const char *const *columns, uint64_t column_count,
    int64_t infer_schema_length, char **err);
PlFrame *pl_dataframe_read_json_full(
    const char *path, int32_t json_lines,
    const char *const *columns, uint64_t column_count,
    int64_t infer_schema_length, int32_t ignore_errors, char **err);
void pl_dataframe_free(PlFrame *frame);
int pl_dataframe_shape(PlFrame *frame, uint64_t *rows, uint64_t *cols);
int pl_dataframe_estimated_size(
    PlFrame *frame, uint64_t *bytes, char **err);
int pl_dataframe_max_chunks(
    PlFrame *frame, uint64_t *out, char **err);
int pl_dataframe_is_sorted(
    PlFrame *frame, const char *const *columns, uint64_t column_count,
    const int32_t *descending, uint64_t descending_count,
    int32_t nulls_last, int32_t *out, char **err);
char *pl_dataframe_schema_json(PlFrame *frame, char **err);
char *pl_dataframe_columns_json(PlFrame *frame, char **err);
PlFrame *pl_dataframe_head(PlFrame *frame, int64_t n, char **err);
PlFrame *pl_dataframe_tail(PlFrame *frame, int64_t n, char **err);
PlFrame *pl_dataframe_slice(
    PlFrame *frame, int64_t offset, uint64_t length, char **err);
PlFrame *pl_dataframe_with_row_index(
    PlFrame *frame, const char *name, uint64_t offset, char **err);
PlFrame *pl_dataframe_reverse(PlFrame *frame, char **err);
PlFrame *pl_dataframe_rechunk(PlFrame *frame, char **err);
PlFrame *pl_dataframe_shrink_to_fit(PlFrame *frame, char **err);
PlFrame *pl_dataframe_unnest(
    PlFrame *frame, const char *const *columns, uint64_t column_count,
    const char *separator, char **err);
PlFrame *pl_dataframe_transpose(
    PlFrame *frame, const char *keep_names_as, char **err);
PlFrame *pl_dataframe_shift(
    PlFrame *frame, int64_t periods, const char *const *columns,
    uint64_t column_count, char **err);
PlFrame *pl_dataframe_clip(
    PlFrame *frame, double minimum, double maximum, const char *const *columns,
    uint64_t column_count, char **err);
PlFrame *pl_dataframe_diff(
    PlFrame *frame, int64_t periods, const char *const *columns,
    uint64_t column_count, char **err);
PlFrame *pl_dataframe_cumulative(
    PlFrame *frame, const char *operation, const char *const *columns,
    uint64_t column_count, char **err);
PlFrame *pl_dataframe_gather_every(
    PlFrame *frame, uint64_t n, uint64_t offset, char **err);
PlFrame *pl_dataframe_null_mask(
    PlFrame *frame, const char *name, char **err);
PlFrame *pl_dataframe_take(
    PlFrame *frame, const int64_t *indices, uint64_t count, char **err);
PlFrame *pl_dataframe_cast(
    PlFrame *frame, const char *const *pairs, uint64_t pair_count, char **err);
PlFrame *pl_dataframe_fill_nan(
    PlFrame *frame, double value, const char *const *columns,
    uint64_t column_count, char **err);
PlFrame *pl_dataframe_drop_nans(
    PlFrame *frame, const char *const *columns, uint64_t column_count,
    char **err);
PlFrame *pl_dataframe_fill_null_forward(
    PlFrame *frame, const char *const *columns, uint64_t column_count,
    char **err);
PlFrame *pl_dataframe_fill_null_backward(
    PlFrame *frame, const char *const *columns, uint64_t column_count,
    char **err);
PlFrame *pl_dataframe_is_duplicated(
    PlFrame *frame, const char *name, char **err);
PlFrame *pl_dataframe_is_unique(
    PlFrame *frame, const char *name, char **err);
PlFrame *pl_dataframe_unique(
    PlFrame *frame, const char *const *columns, uint64_t column_count,
    const char *keep, int32_t maintain_order, char **err);
PlFrame *pl_dataframe_explode(
    PlFrame *frame, const char *const *columns, uint64_t column_count,
    int32_t keep_nulls, int32_t empty_as_null, char **err);
PlFrame *pl_dataframe_join(
    PlFrame *left, PlFrame *right, const char *how,
    const char *const *left_on, uint64_t left_count,
    const char *const *right_on, uint64_t right_count,
    int32_t nulls_equal, char **err);
PlFrame *pl_dataframe_vstack(
    PlFrame *left, PlFrame *right, char **err);
PlFrame *pl_dataframe_hstack(
    PlFrame *left, PlFrame *right, char **err);
PlFrame *pl_dataframe_sql(PlFrame *frame, const char *query, char **err);
int pl_dataframe_write_csv(PlFrame *frame, const char *path, char **err);
int pl_dataframe_write_csv_options(
    PlFrame *frame, const char *path, const char *delimiter,
    int32_t has_header, const char *null_value, char **err);
int pl_dataframe_write_csv_full(
    PlFrame *frame, const char *path, const char *delimiter,
    int32_t has_header, const char *null_value,
    const char *line_terminator, char **err);
int pl_dataframe_write_csv_configured(
    PlFrame *frame, const char *path, const char *delimiter,
    int32_t has_header, const char *null_value,
    const char *line_terminator, const char *quote_style, char **err);
int pl_dataframe_write_csv_precise(
    PlFrame *frame, const char *path, const char *delimiter,
    int32_t has_header, const char *null_value,
    const char *line_terminator, const char *quote_style,
    int64_t float_precision, char **err);
int pl_dataframe_write_csv_complete(
    PlFrame *frame, const char *path, const char *delimiter,
    int32_t has_header, const char *null_value,
    const char *line_terminator, const char *quote_style,
    int64_t float_precision, int32_t include_bom, int32_t decimal_comma,
    char **err);
char *pl_dataframe_to_csv(
    PlFrame *frame, const char *delimiter, int32_t has_header,
    const char *null_value, const char *line_terminator,
    const char *quote_style, int64_t float_precision, int32_t include_bom,
    int32_t decimal_comma, char **err);
int pl_dataframe_write_parquet(PlFrame *frame, const char *path, char **err);
int pl_dataframe_write_parquet_options(
    PlFrame *frame, const char *path, const char *compression,
    int32_t statistics, uint64_t row_group_size, uint64_t data_page_size,
    char **err);
int pl_dataframe_write_parquet_leveled(
    PlFrame *frame, const char *path, const char *compression,
    int32_t statistics, uint64_t row_group_size, uint64_t data_page_size,
    int64_t compression_level, char **err);
int pl_dataframe_write_json(
    PlFrame *frame, const char *path, int32_t json_lines, char **err);
int pl_dataframe_write_json_pretty(
    PlFrame *frame, const char *path, int32_t json_lines, char **err);
char *pl_dataframe_to_json(PlFrame *frame, char **err);
char *pl_dataframe_to_json_format(
    PlFrame *frame, int32_t json_lines, char **err);
char *pl_dataframe_to_json_pretty(PlFrame *frame, char **err);
void pl_string_free(char *value);
```

`pl_dataframe_read_csv_lenient` is additive and carries every option from
`pl_dataframe_read_csv_parsed` plus two non-zero flags. `truncate_ragged_lines`
truncates rows wider than the header, and `ignore_errors` turns values that
cannot be parsed into nulls while keeping the rest of the rows. Both flags are
zero by default in every earlier reader entry point.

`pl_dataframe_read_csv_extended` is additive and carries every option from
`pl_dataframe_read_csv_lenient` plus `uint64_t skip_rows_after_header` and
`int32_t decimal_comma`. The post-header count drops data rows after the header
before `n_rows` applies; a non-zero `decimal_comma` parses a comma as the
decimal separator while the one-byte delimiter keeps its earlier rules. Both
default to zero in every earlier reader entry point.

`pl_dataframe_read_csv_empty_policy` is additive and carries every argument from
`pl_dataframe_read_csv_extended` plus `int32_t raise_if_empty`. A non-zero value
keeps Polars' default where an empty file with no header is an error; zero
returns an empty frame instead. The argument affects only the empty-file check,
so malformed content still fails. Earlier reader entry points keep
`raise_if_empty` enabled.

`pl_dataframe_read_csv_inferred` is additive and carries every argument from
`pl_dataframe_read_csv_empty_policy` plus `int64_t infer_schema_length`.
`-1` keeps Polars' default 100-row inference window, `0` infers every column as
`str`, and a non-negative value sets the row count used for inference. The
argument is a `usize` after conversion, so an out-of-range value is an error.
Explicit `dtypes` overrides still take precedence.

`pl_dataframe_read_csv_low_memory` is additive and carries every argument from
`pl_dataframe_read_csv_inferred` plus `int32_t low_memory`. Non-zero selects
Polars' lower-memory CSV reader path; the schema and values are unchanged.

`pl_dataframe_estimated_size` writes Polars' approximate in-memory byte count to
`uint64_t *bytes` and returns zero on success. `pl_dataframe_max_chunks` writes
the largest chunk count across columns to `uint64_t *out`.
`pl_dataframe_is_sorted` checks one or more keys with a parallel
descending-flag array and a single `nulls_last` flag, writing the Boolean result
to `int32_t *out`.

`pl_dataframe_reverse` returns a newly owned frame with the same columns and
reversed row order. `pl_dataframe_rechunk` returns a copy consolidated into
single-chunk columns, and `pl_dataframe_shrink_to_fit` returns a copy with
excess allocation capacity released. `pl_dataframe_unnest` expands borrowed
struct columns; a null/zero list targets every struct column, and an optional
non-empty separator prefixes each output field with its struct name.
`pl_dataframe_transpose` swaps rows and columns,
optionally naming the output column that receives the original column names;
Polars casts all values to a common supertype. `pl_dataframe_shift` borrows an
optional column list; a
null/zero count shifts every column, a positive `periods` inserts leading nulls,
and a negative value inserts trailing nulls. `pl_dataframe_clip` clamps every
numeric column (or only the borrowed explicit list) to the inclusive
`[minimum, maximum]` range, preserves nulls, and rejects non-integral bounds on
integer columns. `pl_dataframe_diff` computes the difference against the value
`periods` rows earlier for every numeric column or a borrowed numeric subset;
the first `periods` rows are null. `pl_dataframe_gather_every` returns rows
`offset`, `offset+n`,
and so on, with a positive `n` and a non-negative zero-based offset.
`pl_dataframe_take` resolves a borrowed array of signed indexes: negative
values count from the end and every position must be in bounds. Order and
duplicates are preserved, and a zero count returns an empty frame with the
input schema. `pl_dataframe_null_mask` appends a Boolean any-null row mask
named by the borrowed `name` (or `has_nulls` for a null pointer) and rejects
collisions and zero-column frames. `pl_dataframe_is_duplicated` and
`pl_dataframe_is_unique`
append a Boolean marker column whose name is the borrowed `name` (or
`duplicated`/`unique` for a null pointer) and reject collisions with existing
columns. `pl_dataframe_cast` borrows `pair_count` `column`, `dtype` string pairs
(a flat array of `2 * pair_count` names); casting is strict and preserves column
order. `pl_dataframe_unique` borrows an optional column list and a keep string
(`first`, `last`, `none`, or `any`), with a non-zero `maintain_order` selecting
the stable distinct. `pl_dataframe_explode` borrows a non-empty list of
list-typed columns; `keep_nulls` and `empty_as_null` control the null/empty-list
rows. All of these are additive and leave the input handle open.

`pl_dataframe_fill_nan` replaces NaN in Float32/Float64 columns with the finite
`double value`; a null/zero column count targets every float column, and a
non-empty list is validated against the frame. `pl_dataframe_drop_nans` filters
out rows with a NaN in any targeted float column and keeps nulls. Both ignore
non-float columns in a subset, borrow their name arrays for the call, and
return a newly owned frame while leaving the input open.
`pl_dataframe_fill_null_forward` and `pl_dataframe_fill_null_backward` carry
the previous or next non-null value into each null; leading/trailing nulls
remain null, an empty column list targets every column, and explicit subsets are
validated and applied independently while preserving column order.

`pl_dataframe_write_csv_precise` is additive and carries every option from
`pl_dataframe_write_csv_configured` plus `int64_t float_precision`, where `-1`
keeps Polars' default formatting and non-negative values set the number of
digits after the decimal point for float columns.

`pl_dataframe_write_csv_complete` is additive and carries every argument from
`pl_dataframe_write_csv_precise` plus `int32_t include_bom` and `int32_t
decimal_comma`. A non-zero `include_bom` prepends `EF BB BF`; a non-zero
`decimal_comma` formats float fields with a comma decimal separator. Both
default to zero in every earlier writer entry point.

`pl_dataframe_to_csv` takes the same writer configuration as
`pl_dataframe_write_csv_complete` and returns the CSV bytes as a
NUL-terminated string instead of writing a file. The returned string must be
freed with `pl_string_free`.

Returned `char *` values and error strings must be freed with
`pl_string_free`. A null frame pointer indicates an error when `err` is set.
`pl_dataframe_join` borrows both input handles, including the key-name arrays
for the duration of the call, and returns a newly owned frame.
`pl_dataframe_vstack` appends the right frame's rows below the left frame, and
`pl_dataframe_hstack` appends the right frame's columns beside the left frame;
both borrow their handles and return a newly owned frame. The write functions
return `0` on success and non-zero on error.

`pl_dataframe_read_csv_ex` is additive; the existing
`pl_dataframe_read_csv` and `pl_dataframe_read_csv_options` keep their
signatures and defaults. Both option entry points borrow their string
arguments for the duration of the call. A null `delimiter` means `","`;
`has_header` is zero for headerless input and non-zero for a header row. The
delimiter must be exactly one byte, and quote, newline, carriage-return, and
NUL bytes are rejected.

For `pl_dataframe_read_csv_ex`, a null `quote` keeps the `"` default while an
empty `quote` disables quote parsing. A null or empty `comment` disables
comment lines. Quote and comment values are one byte and may not equal the
delimiter or each other; NUL, newline, and carriage-return bytes are rejected.

`pl_dataframe_read_csv_projected` is additive and keeps the earlier reader
signatures and defaults. It borrows `column_count` UTF-8 column names for the
duration of the call and returns a frame containing only those columns in the
requested order. A null array or a zero count reads every column; empty,
duplicate, and unknown names are errors.

`pl_dataframe_read_csv_typed` is the superset entry point for projection and
dtype overrides. It borrows `dtype_count` `column`, `dtype` string pairs (a
flat array of `2 * dtype_count` names) in addition to the projection.
Overrides are applied by name after the header is known; `dtype_count` is zero
for inference only. A null array with a non-zero count is an error. The
supported dtype names match the Lua option, and a projection that omits an
overridden column is rejected. The earlier reader signatures and defaults are
unchanged.

`pl_dataframe_read_csv_null_values` is additive and combines the full reader
configuration with literal null markers. It borrows `null_value_count` UTF-8
strings beyond the typed-reader arguments; a null array or zero count keeps
Polars' default where only empty fields are null. One marker selects Polars'
single-value policy and several markers are all interpreted as null. Markers
are compared with unquoted field bytes, so a quoted `"NA"` field uses the
marker `NA`. Empty and duplicate markers are errors, as is a null array with a
non-zero count.

`pl_dataframe_read_csv_row_window` is additive and combines every earlier
reader option with a row window. `skip_rows` is the number of CSV rows skipped
before the header is parsed. `n_rows` limits the data rows read after the
header: `-1` reads every remaining row and any other negative value is an
error. `skip_rows = 0` with `n_rows = -1` matches the earlier defaults. Both
counts are `uint64_t`/`int64_t` at the ABI; the Lua wrapper restricts them to
non-negative safe integers and rejects fractional or non-numeric values before
the call.

`pl_dataframe_read_csv_encoded` is additive and combines every earlier reader
option with a text encoding. `encoding` is borrowed for the duration of the
call; a null or empty string keeps strict UTF-8, `utf8` selects it explicitly,
`utf8-lossy` substitutes U+FFFD for invalid bytes, and other names are errors.
The remaining arguments match `pl_dataframe_read_csv_row_window`.

`pl_dataframe_read_csv_renamed` is additive and combines every earlier reader
option with positionally applied replacement names. It borrows
`rename_column_count` UTF-8 names; a null array or zero count disables renaming.
Names replace the leading columns of the returned frame, so they apply after
projection and dtype overrides. Fewer names than columns renames only that
prefix; more names than columns, empty names, and duplicate resulting names are
errors. The encoding argument follows `pl_dataframe_read_csv_encoded`.

`pl_dataframe_read_csv_named_nulls` is additive and combines every earlier
reader option, including the encoding and positional renames, with per-column
null markers. `null_columns` and `null_values` are parallel arrays of
`null_value_count` UTF-8 strings: each named column gets exactly one marker,
and columns without an entry keep Polars' default where only empty fields are
null. Empty names or markers and duplicate columns are errors. A marker column
outside the projection is rejected, and a marker column absent from the file is
reported by Polars. Markers are applied before positional renames, so they name
the file's original columns, like dtype overrides.

`pl_dataframe_read_csv_parsed` is additive and combines every earlier reader
option with date inference. It accepts both the shared `null_values` array and
the parallel `null_columns`/`named_null_values` arrays; supplying both policies
is an error. `try_parse_dates` is zero for the string default and non-zero to
infer ISO date and datetime columns. All other arguments match
`pl_dataframe_read_csv_named_nulls` plus the shared null-marker array.

`pl_dataframe_write_csv_options` is additive; `pl_dataframe_write_csv` keeps
its signature and comma/header/empty-null defaults. A null `delimiter` means
`","`; `has_header` is zero to omit the header row. A null or empty
`null_value` writes empty fields for nulls. The placeholder is written
literally, so it may not contain the delimiter, `"`, NUL, newline, or
carriage-return bytes. All string arguments are borrowed for the duration of
the call.

`pl_dataframe_write_csv_full` is the superset writer entry point. It combines
the earlier delimiter, header, and null-value arguments with `line_terminator`:
a null or empty string keeps `"\n"`, `"\r\n"` writes CRLF records, and every
other value is an error. The terminator is written literally after the header
and each data row. Earlier writer signatures and defaults are unchanged.

`pl_dataframe_write_csv_configured` adds `quote_style` to the `_full` writer:
a null or empty string keeps `necessary`, and `always`, `non_numeric`
(alias `non-numeric`), and `never` are accepted case-insensitively. `never`
can produce invalid CSV for fields containing the delimiter, quote, or a line
break, matching Polars.

`pl_dataframe_read_parquet_options` is additive; `pl_dataframe_read_parquet`
keeps its signature and reads every row and column. It borrows
`column_count` UTF-8 column names; a null array or zero count reads every
column, while empty, duplicate, and unknown names are errors. `skip_rows`
drops that many leading data rows. `n_rows` limits the rows read after the
offset: `-1` reads every remaining row and any other negative value is an
error. `n_rows = 0` materializes an empty frame with the file schema.

`pl_dataframe_read_parquet_low_memory` is additive and carries the same
projection and row-window arguments as `pl_dataframe_read_parquet_options` plus
`int32_t low_memory`. Non-zero selects Polars' lower-memory reader path; zero
keeps the default. The schema and values are unchanged.

`pl_dataframe_read_parquet_full` is additive and carries both `int32_t
low_memory` and `int32_t rechunk`. A non-zero `rechunk` consolidates the result
into single-chunk columns after reading; both flags compose with projection and
the row window.

`pl_dataframe_write_parquet_options` is additive; `pl_dataframe_write_parquet`
keeps its signature and Zstd/statistics/default-chunking behavior. A null or
empty `compression` keeps Zstd; the accepted names are `zstd`, `snappy`,
`gzip`, `brotli`, `lz4`/`lz4-raw`, and `uncompressed`/`none`, matched
case-insensitively. `statistics` is zero to skip column statistics and
non-zero for the Polars defaults. A zero `row_group_size` or
`data_page_size` keeps the Polars default; non-zero values are row and byte
counts respectively. The compression string is borrowed for the duration of
the call.

`pl_dataframe_write_parquet_leveled` is additive and carries the same
arguments plus `int64_t compression_level`. A negative level keeps the codec
default; zstd, gzip, and brotli validate their codec-specific ranges, while
other codecs reject an explicit level.

`pl_dataframe_read_json` is additive and reads a JSON array (`json_lines` zero)
or JSON Lines (`json_lines` non-zero) with an optional projection. It borrows
`column_count` UTF-8 column names; a null array or zero count reads every
column, while empty and duplicate names are errors. The returned frame keeps
the requested order. `pl_dataframe_write_json` writes the same two formats from
an open frame and returns zero on success or non-zero with `err` set on
failure.

`pl_dataframe_write_json_pretty` writes an indented JSON array and returns zero
on success. A non-zero `json_lines` is rejected because pretty JSON Lines would
break the one-object-per-line format.

`pl_dataframe_read_json_inferred` is additive and carries every argument from
`pl_dataframe_read_json` plus `int64_t infer_schema_length`. For JSON Lines,
`-1` keeps Polars' default 100-record window, `0` scans the whole stream, and a
positive value limits inference to that many records. JSON arrays are read as
a whole, so the argument is validated but has no effect there.

`pl_dataframe_read_json_full` is additive and carries the inference window plus
`int32_t ignore_errors`. Non-zero keeps JSON Lines records whose values cannot
be parsed by substituting nulls; JSON arrays reject the flag. The remaining
arguments match `pl_dataframe_read_json_inferred`.

`pl_dataframe_to_json_format` is additive and serializes a frame as a JSON
array when `json_lines` is zero or as one object per line otherwise. The
returned string has the same Polars conventions as `pl_dataframe_to_json` and
must be freed with `pl_string_free`.

`pl_dataframe_cumulative` applies `sum`, `min`, `max`, `count`, or `prod`
forward over every numeric column or a borrowed validated subset. `count` is a
running count of non-null values and produces `u32`; the other operations
preserve their input dtypes.

`pl_dataframe_to_json_pretty` returns an indented JSON array string with the
same values as `pl_dataframe_to_json`. JSON Lines is not supported by this
entry point, and the returned string must be freed with `pl_string_free`.

## Install layouts

### LuaRocks source rock

`lua-polars-0.24.0-1.rockspec` uses a `command` build. Its build command runs
`scripts/ensure-bridge.sh`, which reuses a release bridge newer than the Rust
inputs and otherwise builds incrementally. LuaRocks then calls
`scripts/install-rock.sh` with `$(LUADIR)` and `$(LIBDIR)`, so Lua modules are
deployed under `share/lua/<version>/` and the native bridge under
`lib/lua/<version>/`. The loader searches `package.cpath` directories for
`libpolars_lua.<ext>`, so the rock works without `POLARS_LUA_LIB`:

```sh
luarocks make lua-polars-0.24.0-1.rockspec --tree=/tmp/lua-polars-rock
eval "$(luarocks path --tree=/tmp/lua-polars-rock)"
luajit -e 'print(require("polars").version())'
```

If `target/release/libpolars_lua.so` is absent or older than the Rust sources,
the bridge is built with `CARGO_BUILD_JOBS` defaulting to one. The `v0.24.0`
source tag referenced by the rockspec is created with the release; before that,
`luarocks make` from a checkout exercises the same build and install commands.
`scripts/rockspec.sh` runs `scripts/check-version.sh` first, so a mismatch
between `Cargo.toml`, `Cargo.lock`, `polars.lua`, the rockspec, README, API
docs, and release notes fails before a build. It then validates the install in
the ignored `.luarocks-tree/` directory, so repeated checks are incremental
without forcing a cold rebuild. A content stamp skips `luarocks make` while the
rockspec, Lua modules, install script, and native bridge are unchanged. Set
`POLARS_LUA_ROCK_TREE=/tmp/lua-polars-rock` to use another tree and
`POLARS_LUA_ROCK_FORCE=1` to force a reinstall into it.

### Prefix install

`scripts/install.sh PREFIX` installs `polars.lua`, `polars/json.lua`, and
`libpolars_lua.so` into `PREFIX/share/lua/5.1/`. The bridge sits beside
`polars.lua`, so a module loaded from that prefix finds it without
`POLARS_LUA_LIB`:

```sh
./scripts/install.sh /tmp/lua-polars
LUA_PATH='/tmp/lua-polars/share/lua/5.1/?.lua;;' \
  luajit -e 'print(require("polars").version())'
```

`scripts/smoke.sh` performs this install into a temporary prefix and runs
`tests/install_smoke.lua` against it.

## Roadmap

- [x] Eager inner/left/full/outer/semi/anti/cross DataFrame joins.
- [x] CSV/Parquet writers and drop/rename/with-columns helpers.
- [x] Ordered `columns()` and order-preserving column operations.
- [x] Prefix install and smoke test.
- [x] CSV reader delimiter and header options.
- [x] CSV reader quote and comment options.
- [x] CSV reader column projection and dtype overrides.
- [x] CSV reader null-value markers.
- [x] CSV reader per-column null-value markers.
- [x] CSV reader row windows (`skip_rows`, `n_rows`).
- [x] CSV reader positional column renaming and UTF-8 lossy decoding.
- [x] CSV reader post-header row windows and decimal-comma numbers.
- [x] CSV reader empty-file handling with `raise_if_empty = false`.
- [x] DataFrame NaN filling and dropping with column subsets.
- [x] DataFrame row reversal and strict column casting.
- [x] DataFrame row shifting and numeric clipping.
- [x] DataFrame row striding and null masks.
- [x] Forward and backward null filling.
- [x] DataFrame transpose, size estimates, and sortedness checks.
- [x] Lenient JSON Lines reads and Parquet rechunking.
- [x] Indexed row take and top/bottom k helpers.
- [x] Parquet low-memory reads and JSON Lines string output.
- [x] Duplicate and unique row markers.
- [x] CSV and JSON schema-inference length control.
- [x] Distinct rows with column subsets and keep strategies.
- [x] List-column explode with null/empty-list controls.
- [x] CSV writer delimiter, header, and null-value options.
- [x] CSV writer line terminator (`\n`, `\r\n`).
- [x] CSV writer UTF-8 BOM and decimal-comma output.
- [x] Parquet reader column projection and row windows.
- [x] Parquet writer compression, statistics, and chunk-size options.
- [x] LuaRocks source-rock packaging.
- [ ] LazyFrame/expressions.
- [ ] Arrow C Data Interface with `polars-ffi` and a numlua adapter.
- [ ] Streaming and scan APIs.
