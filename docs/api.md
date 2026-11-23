# lua-polars API — 0.17.0

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

Returns the bridge version (`"0.17.0"`).

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
- `n_rows`: a non-negative integer, default unlimited. Limits the number of
  data rows read after the header. `n_rows = 0` reads no data rows while
  keeping the header-derived schema; a limit larger than the file reads the
  remaining rows. Like `skip_rows`, it must be at most `2^53 - 1`.
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
local renamed = polars.read_csv("headerless.csv", {
  header = false,
  rename_columns = { "id", "name", "score" },
})
local lossy = polars.read_csv("legacy.csv", { encoding = "utf8-lossy" })
local dated = polars.read_csv("events.csv", { try_parse_dates = true })
```

Unknown option keys are errors so typos do not silently fall back to defaults.
Errors also cover invalid option types, invalid one-byte values, option
collisions, invalid projection names, unsupported or missing dtype overrides,
invalid or per-column null-value markers, invalid rename lists, unsupported encodings,
negative or fractional row-window counts, a missing or unreadable path, and
files that cannot be parsed.

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

```lua
polars.read_parquet("data.parquet")
polars.read_parquet("data.parquet", {
  columns = { "score", "name" },
  skip_rows = 10,
  n_rows = 100,
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

```lua
local rows = polars.read_json("rows.json")
local events = polars.read_json("events.jsonl", {
  format = "lines",
  columns = { "time", "event" },
})
```

Unknown option keys and invalid types are errors, as are a missing or
unreadable path, malformed JSON, unknown projection names, and files whose top
level is not a supported array or object stream.

### `polars.null`

Sentinel used by `to_table()` for JSON `null`. It stringifies as `null`.

## DataFrame

All methods require an open handle. Calling a method after `:close()` raises
an error.

### `df:shape() -> rows, cols`

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

### `df:with_row_index([name, offset]) -> DataFrame`

Returns a new frame with a row-index column prepended. `name` defaults to
`"index"` and must be a non-empty string that does not collide with an existing
column. `offset` is a non-negative integer, default `0`, added to the first row
index; indexes then increase by one per row. Offset values above `2^53 - 1`
are rejected.

```lua
local indexed = df:with_row_index("row_id", 100)
```

### `df:drop_nulls([columns]) -> DataFrame`

Drops rows that contain a null in any selected column. With no argument every
column participates, preserving the earlier behavior. `columns` may be a single
column name or a non-empty contiguous list of names; unknown, empty, duplicate,
and malformed names are errors, and the result keeps the original schema and
column order.

```lua
local complete = df:drop_nulls()              -- any null
local scored = df:drop_nulls("score")        -- only null scores
local keyed = df:drop_nulls({ "id", "name" }) -- either key null
```

### `df:fill_null(value [, columns]) -> DataFrame`

Replaces nulls with a scalar, optionally only in the named columns. `value` may
be a finite number, a string, or a boolean; `nil` and the strings `"zero"` and
`"one"` keep the earlier strategy aliases for `0` and `1`. The value is
formatted as a SQL literal, so string content is escaped and `"O'Reilly"`
round-trips. `columns` is a single name or a non-empty contiguous list; when
omitted every column is filled and unselected columns keep their nulls.

```lua
local labeled = df:fill_null("unknown", "note")
local scored = df:fill_null(0, { "score", "bonus" })
local flagged = df:fill_null(false, "active")
```

Non-finite numbers, NUL in a fill string, tables/functions, and malformed,
unknown, or duplicate column subsets are errors. Type conflicts between the
fill value and a column are reported by Polars.

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

### `df:sort(columns, descending) -> DataFrame`

`columns` is a name or list. `descending` is a boolean or a per-column list of
booleans.

### `df:group_by(keys, aggregates) -> DataFrame`

`keys` is a name or list; `aggregates` is a list of SQL aggregate expressions.

```lua
df:group_by("team", { 'sum("score") AS total' })
```

Aggregate expressions are trusted SQL strings.

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

```lua
df:write_csv("out.csv")
df:write_csv("out.tsv", {
  delimiter = "\t",
  header = false,
  null_value = "NA",
})
df:write_csv("crlf.csv", { line_terminator = "\r\n" })
df:write_csv("quoted.csv", { quote_style = "always" })
```

Unknown option keys and invalid types are errors, as are closed frames,
non-string or empty paths, and write failures.

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

```lua
df:write_json("rows.json")
df:write_json("rows.jsonl", { format = "lines" })
```

Unknown option keys and invalid types are errors, as are closed frames,
non-string or empty paths, and write failures.

### `df:write_parquet(path [, options]) -> DataFrame`

Writes the frame as Parquet and returns `df` for chaining. The file is created
or truncated. With no options it writes Zstd-compressed pages with Polars'
default statistics and chunk sizes.

`options` is an optional table:

- `compression`: `"zstd"` (default), `"snappy"`, `"gzip"`, `"brotli"`,
  `"lz4"` (alias `"lz4-raw"`), or `"uncompressed"` (alias `"none"`), matched
  case-insensitively. The pinned Polars writer uses each codec's default
  level; there is no separate level option yet.
- `statistics`: a boolean, default `true`. `false` skips the column statistics
  (min/max/null count) that predicate pushdown readers can use.
- `row_group_size`: a positive integer row count per row group. Omitted uses
  Polars' default 262144-row chunks; `1` writes one row per group.
- `data_page_size`: a positive integer maximum data-page size in bytes.
  Omitted uses Polars' default 1 MiB pages.

```lua
df:write_parquet("out.parquet")
df:write_parquet("out.parquet", {
  compression = "snappy",
  statistics = false,
  row_group_size = 1000,
  data_page_size = 65536,
})
```

Unknown option keys and invalid types are errors, as are unsupported codec
names, a non-positive or fractional chunk size, closed frames, non-string or
empty paths, and write failures.

### `df:to_json() -> string`

Row-oriented JSON array, one object per row. Non-JSON types are formatted by
Polars' Arrow JSON writer.

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
PlFrame *pl_dataframe_read_parquet(const char *path, char **err);
PlFrame *pl_dataframe_read_parquet_options(
    const char *path, const char *const *columns, uint64_t column_count,
    uint64_t skip_rows, int64_t n_rows, char **err);
PlFrame *pl_dataframe_read_json(
    const char *path, int32_t json_lines,
    const char *const *columns, uint64_t column_count, char **err);
void pl_dataframe_free(PlFrame *frame);
int pl_dataframe_shape(PlFrame *frame, uint64_t *rows, uint64_t *cols);
char *pl_dataframe_schema_json(PlFrame *frame, char **err);
char *pl_dataframe_columns_json(PlFrame *frame, char **err);
PlFrame *pl_dataframe_head(PlFrame *frame, int64_t n, char **err);
PlFrame *pl_dataframe_tail(PlFrame *frame, int64_t n, char **err);
PlFrame *pl_dataframe_slice(
    PlFrame *frame, int64_t offset, uint64_t length, char **err);
PlFrame *pl_dataframe_with_row_index(
    PlFrame *frame, const char *name, uint64_t offset, char **err);
PlFrame *pl_dataframe_join(
    PlFrame *left, PlFrame *right, const char *how,
    const char *const *left_on, uint64_t left_count,
    const char *const *right_on, uint64_t right_count,
    int32_t nulls_equal, char **err);
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
int pl_dataframe_write_parquet(PlFrame *frame, const char *path, char **err);
int pl_dataframe_write_parquet_options(
    PlFrame *frame, const char *path, const char *compression,
    int32_t statistics, uint64_t row_group_size, uint64_t data_page_size,
    char **err);
int pl_dataframe_write_json(
    PlFrame *frame, const char *path, int32_t json_lines, char **err);
char *pl_dataframe_to_json(PlFrame *frame, char **err);
void pl_string_free(char *value);
```

Returned `char *` values and error strings must be freed with
`pl_string_free`. A null frame pointer indicates an error when `err` is set.
`pl_dataframe_join` borrows both input handles, including the key-name arrays
for the duration of the call, and returns a newly owned frame. The write
functions return `0` on success and non-zero on error.

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

`pl_dataframe_write_parquet_options` is additive; `pl_dataframe_write_parquet`
keeps its signature and Zstd/statistics/default-chunking behavior. A null or
empty `compression` keeps Zstd; the accepted names are `zstd`, `snappy`,
`gzip`, `brotli`, `lz4`/`lz4-raw`, and `uncompressed`/`none`, matched
case-insensitively. `statistics` is zero to skip column statistics and
non-zero for the Polars defaults. A zero `row_group_size` or
`data_page_size` keeps the Polars default; non-zero values are row and byte
counts respectively. The compression string is borrowed for the duration of
the call.

`pl_dataframe_read_json` is additive and reads a JSON array (`json_lines` zero)
or JSON Lines (`json_lines` non-zero) with an optional projection. It borrows
`column_count` UTF-8 column names; a null array or zero count reads every
column, while empty and duplicate names are errors. The returned frame keeps
the requested order. `pl_dataframe_write_json` writes the same two formats from
an open frame and returns zero on success or non-zero with `err` set on
failure.

## Install layouts

### LuaRocks source rock

`lua-polars-0.17.0-1.rockspec` uses a `command` build. Its build command runs
`scripts/ensure-bridge.sh`, which reuses a release bridge newer than the Rust
inputs and otherwise builds incrementally. LuaRocks then calls
`scripts/install-rock.sh` with `$(LUADIR)` and `$(LIBDIR)`, so Lua modules are
deployed under `share/lua/<version>/` and the native bridge under
`lib/lua/<version>/`. The loader searches `package.cpath` directories for
`libpolars_lua.<ext>`, so the rock works without `POLARS_LUA_LIB`:

```sh
luarocks make lua-polars-0.17.0-1.rockspec --tree=/tmp/lua-polars-rock
eval "$(luarocks path --tree=/tmp/lua-polars-rock)"
luajit -e 'print(require("polars").version())'
```

If `target/release/libpolars_lua.so` is absent or older than the Rust sources,
the bridge is built with `CARGO_BUILD_JOBS` defaulting to one. The `v0.17.0`
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
- [x] CSV writer delimiter, header, and null-value options.
- [x] CSV writer line terminator (`\n`, `\r\n`).
- [x] Parquet reader column projection and row windows.
- [x] Parquet writer compression, statistics, and chunk-size options.
- [x] LuaRocks source-rock packaging.
- [ ] LazyFrame/expressions.
- [ ] Arrow C Data Interface with `polars-ffi` and a numlua adapter.
- [ ] Streaming and scan APIs.
