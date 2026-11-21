# lua-polars API — 0.10.0

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

Returns the bridge version (`"0.10.0"`).

### `polars.read_csv(path [, options]) -> DataFrame`

Reads a UTF-8 CSV file. With no options it expects a header row and commas, as
before. Type inference is Polars' default.

`options` is an optional table:

- `delimiter`: a one-byte string, default `","`. Quote, newline, carriage
  return, and NUL bytes are rejected.
- `header`: a boolean, default `true`. With `header = false` the first row is
  data and Polars names the columns `column_1`, `column_2`, and so on.
- `quote`: a one-byte string used to quote fields, default `"`. Set it to
  `false` or `""` to disable quote parsing. NUL, newline, and carriage-return
  bytes are rejected.
- `comment`: a one-byte line prefix, default disabled. Lines whose first byte
  matches are ignored, including comment lines before the header. Set it to
  `false` or `""` to disable comment skipping.
- `columns`: a column name or a list of names to read. The resulting frame
  keeps the requested order and contains only those columns. Unknown,
  duplicate, and empty names are errors.
- `dtypes`: a table mapping column names to dtype names, applied by name at
  read time instead of relying on inference. Supported dtypes are `bool` /
  `boolean`, `i32`, `i64`, `u32`, `u64`, `f32`, `f64`, and `str` / `string` /
  `utf8`; matching is case-insensitive and the `int32`, `uint32`, and
  `float32` long forms are accepted. The table must not be empty, and every key
  must be a read column: an override outside `columns` or absent from the file
  is an error. Parsing failures (for example `name = "i64"` on text) are
  reported by Polars.

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
```

Unknown option keys are errors so typos do not silently fall back to defaults.
Errors also cover invalid option types, invalid one-byte values, option
collisions, invalid projection names, unsupported or missing dtype overrides,
a missing or unreadable path, and files that cannot be parsed.

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
PlFrame *pl_dataframe_read_parquet(const char *path, char **err);
void pl_dataframe_free(PlFrame *frame);
int pl_dataframe_shape(PlFrame *frame, uint64_t *rows, uint64_t *cols);
char *pl_dataframe_schema_json(PlFrame *frame, char **err);
char *pl_dataframe_columns_json(PlFrame *frame, char **err);
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

`pl_dataframe_read_csv_typed` is the superset entry point. It borrows
`dtype_count` `column`, `dtype` string pairs (a flat array of
`2 * dtype_count` names) in addition to the projection. Overrides are applied
by name after the header is known; `dtype_count` is zero for inference only.
A null array with a non-zero count is an error. The supported dtype names match
the Lua option, and a projection that omits an overridden column is rejected.
The earlier reader signatures and defaults are unchanged.

## Install layouts

### LuaRocks source rock

`lua-polars-0.10.0-1.rockspec` uses a `command` build. Its build command runs
`scripts/ensure-bridge.sh`, which reuses a release bridge newer than the Rust
inputs and otherwise builds incrementally. LuaRocks then calls
`scripts/install-rock.sh` with `$(LUADIR)` and `$(LIBDIR)`, so Lua modules are
deployed under `share/lua/<version>/` and the native bridge under
`lib/lua/<version>/`. The loader searches `package.cpath` directories for
`libpolars_lua.<ext>`, so the rock works without `POLARS_LUA_LIB`:

```sh
luarocks make lua-polars-0.10.0-1.rockspec --tree=/tmp/lua-polars-rock
eval "$(luarocks path --tree=/tmp/lua-polars-rock)"
luajit -e 'print(require("polars").version())'
```

If `target/release/libpolars_lua.so` is absent or older than the Rust sources,
the bridge is built with `CARGO_BUILD_JOBS` defaulting to one. The `v0.10.0`
source tag referenced by the rockspec is created with the release; before that,
`luarocks make` from a checkout exercises the same build and install commands.
`scripts/rockspec.sh` runs `scripts/check-version.sh` first, so a mismatch
between `Cargo.toml`, `Cargo.lock`, `polars.lua`, the rockspec, README, API
docs, and release notes fails before a build. It then validates the install in
a temporary tree without forcing a cold rebuild. Set
`POLARS_LUA_ROCK_TREE=/tmp/lua-polars-rock` to reuse a tree across repeated
checks; a content stamp skips `luarocks make` while the rockspec, Lua modules,
install script, and native bridge are unchanged. Set
`POLARS_LUA_ROCK_FORCE=1` to force a reinstall into that tree.

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
- [x] CSV reader column projection.
- [x] LuaRocks source-rock packaging.
- [ ] LazyFrame/expressions.
- [ ] Arrow C Data Interface with `polars-ffi` and a numlua adapter.
- [ ] Streaming and scan APIs.
