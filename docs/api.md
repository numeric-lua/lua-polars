# lua-polars API — 0.4.0

## Modules

```lua
local polars = require("polars")
```

The native bridge is loaded from `POLARS_LUA_LIB`, then
`target/release/libpolars_lua.so`, `target/debug/...`, or `build/...`.

## Top-level

### `polars.version() -> string`

Returns the bridge version (`"0.4.0"`).

### `polars.read_csv(path) -> DataFrame`

Reads a UTF-8 CSV file with a header row. Type inference is Polars' default.

Errors if the path is missing, unreadable, or cannot be parsed.

### `polars.read_parquet(path) -> DataFrame`

Reads a Parquet file.

Errors if the path is missing, unreadable, or cannot be parsed.

### `polars.null`

Sentinel used by `to_table()` for JSON `null`. It stringifies as `null`.

## DataFrame

All methods require an open handle. Calling a method after `:close()` raises
an error.

### `df:shape() -> rows, cols`

### `df:schema() -> table`

Maps column names to Polars dtype names, e.g. `{ score = "i64" }`. The order
of keys in the returned Lua table is not significant.

### `df:head(n) -> DataFrame`

Returns a new frame with at most `n` rows. Negative or non-integer values are
rejected.

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

Dropping every column is an error.

### `df:rename(mapping) -> DataFrame`

Renames columns whose names appear as keys in `mapping`; other columns are
kept. Values are the new column names.

```lua
df:rename({ score = "points" })
```

### `df:with_columns(...) -> DataFrame`

Appends trusted SQL expressions as new columns, keeping the existing columns.

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

### `df:write_csv(path) -> DataFrame`

Writes the frame as CSV with a header row and returns `df` for chaining.
The file is created or truncated. Errors when the frame is closed, the path is
not a non-empty string, or the write fails.

### `df:write_parquet(path) -> DataFrame`

Writes the frame as Parquet and returns `df` for chaining. The file is created
or truncated. Errors when the frame is closed, the path is not a non-empty
string, or the write fails.

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
PlFrame *pl_dataframe_read_parquet(const char *path, char **err);
void pl_dataframe_free(PlFrame *frame);
int pl_dataframe_shape(PlFrame *frame, uint64_t *rows, uint64_t *cols);
char *pl_dataframe_schema_json(PlFrame *frame, char **err);
PlFrame *pl_dataframe_head(PlFrame *frame, int64_t n, char **err);
PlFrame *pl_dataframe_join(
    PlFrame *left, PlFrame *right, const char *how,
    const char *const *left_on, uint64_t left_count,
    const char *const *right_on, uint64_t right_count,
    int32_t nulls_equal, char **err);
PlFrame *pl_dataframe_sql(PlFrame *frame, const char *query, char **err);
int pl_dataframe_write_csv(PlFrame *frame, const char *path, char **err);
int pl_dataframe_write_parquet(PlFrame *frame, const char *path, char **err);
char *pl_dataframe_to_json(PlFrame *frame, char **err);
void pl_string_free(char *value);
```

Returned `char *` values and error strings must be freed with
`pl_string_free`. A null frame pointer indicates an error when `err` is set.
`pl_dataframe_join` borrows both input handles, including the key-name arrays
for the duration of the call, and returns a newly owned frame. The write
functions return `0` on success and non-zero on error.

## Roadmap

- [x] Eager inner/left/full/outer/semi/anti/cross DataFrame joins.
- [x] CSV/Parquet writers and drop/rename/with-columns helpers.
- [ ] LazyFrame/expressions.
- [ ] Arrow C Data Interface with `polars-ffi` and a numlua adapter.
- [ ] Streaming and scan APIs.
- [ ] LuaRocks packaging.
