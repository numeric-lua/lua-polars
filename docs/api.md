# lua-polars API — 0.1.0

## Modules

```lua
local polars = require("polars")
```

The native bridge is loaded from `POLARS_LUA_LIB`, then
`target/release/libpolars_lua.so`, `target/debug/...`, or `build/...`.

## Top-level

### `polars.version() -> string`

Returns the bridge version (`"0.1.0"`).

### `polars.read_csv(path) -> DataFrame`

Reads a UTF-8 CSV file with a header row. Type inference is Polars' default.

Errors if the path is missing, unreadable, or cannot be parsed.

### `polars.read_parquet(path) -> DataFrame`

Reads a Parquet file.

### `polars.null`

Sentinel used by `to_table()` for JSON `null`. It stringifies as `null`.

## DataFrame

All methods require an open handle. Calling a method after `:close()` raises
an error.

### `df:shape() -> rows, cols`

### `df:schema() -> table`

Maps column names to Polars dtype names, e.g. `{ score = "i64" }`.

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
PlFrame *pl_dataframe_sql(PlFrame *frame, const char *query, char **err);
char *pl_dataframe_to_json(PlFrame *frame, char **err);
void pl_string_free(char *value);
```

Returned `char *` values and error strings must be freed with
`pl_string_free`. A null frame pointer indicates an error when `err` is set.

## Roadmap

1. LazyFrame/expressions and joins.
2. Arrow C Data Interface with `polars-ffi` and a numlua adapter.
3. CSV/Parquet writers and scan APIs.
4. LuaRocks packaging and CI with a cached Polars build.
