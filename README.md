# lua-polars

Unofficial **LuaJIT DataFrame bindings for the Rust [Polars](https://pola.rs)
engine**.

`lua-polars` is not a Lua reimplementation of Polars. It loads a small Rust
`cdylib` through LuaJIT FFI; every DataFrame operation runs in Polars.

```lua
local polars = require("polars")

local df = polars.read_csv("data.csv")
print(df:shape())                 -- rows, columns

local top = df:sql([[
  SELECT "team", sum("score") AS total
  FROM df
  GROUP BY "team"
  ORDER BY "total" DESC
]])

for _, row in ipairs(top:to_table()) do
  print(row.team, row.total)
end
```

## Status

`0.14.0` is an eager-first MVP:

- CSV and Parquet readers and writers
- CSV reader options: one-byte `delimiter`, `header = false` for headerless
  files, a one-byte `quote` character (or `false` to disable quote parsing),
  a one-byte `comment` prefix (or `false` to disable comment skipping), a
  `columns` name/list projection returned in the requested order, a
  `rename_columns` positional name list, a `dtypes` table that overrides
  inferred dtypes by column name (`bool`, `i32`, `i64`, `u32`, `u64`, `f32`,
  `f64`, `str`), `null_values` as a literal marker string or list of markers
  applied to every column, a `skip_rows`/`n_rows` window over the rows before
  and after the header, and `encoding = "utf8-lossy"` for invalid UTF-8 input
- CSV writer options: a one-byte `delimiter`, `header = false` to omit the
  header row, a literal `null_value` placeholder for null fields, and a
  `line_terminator` of `"\n"` or `"\r\n"`
- schema, shape, head, ordered columns
- SQL queries against the DataFrame registered as `df`
- helpers for select, filter, sort, group-by, drop, rename, and with-columns
  that preserve column order
- eager inner, left, full/outer, semi, anti, and cross joins on one or more keys
- row-oriented `to_table()` and raw `to_json()`
- `drop_nulls()`/`fill_null()`, `unique()`/`null_count()`, and row iteration
  helpers
- explicit `:close()` plus Lua GC finalization
- a LuaRocks source rockspec and a self-contained prefix install

Not implemented yet: LazyFrame expressions, Arrow zero-copy exchange, and
streaming/scan APIs.

## Requirements

- LuaJIT 2.1 (PUC Lua is not the target because the binding uses FFI)
- Rust 1.99+ and Cargo
- a C linker
- Linux or macOS
- LuaRocks 3.x for the source-rock install path (optional; the prefix install
  only needs LuaJIT)

Polars `0.55.2` is pinned. The build is large; on a 7 GB laptop use one Cargo
job:

```sh
CARGO_BUILD_JOBS=1 ./scripts/build.sh
```

## Build and test

```sh
./scripts/build.sh        # target/release/libpolars_lua.so
./scripts/test.sh         # reuses/rebuilds the bridge, then runs the suite
make test
./scripts/smoke.sh        # installs into a temporary prefix and loads it
make smoke
./scripts/rockspec.sh     # installs through LuaRocks and loads the rock
make rockspec
```

`scripts/ensure-bridge.sh` is shared by the test, prefix-install, and rockspec
checks. It reuses `target/release/libpolars_lua.so` when it is newer than the
Rust inputs and otherwise runs Cargo incrementally, so repeating an install
check does not restart the Polars build.

The test suite is dependency-free and covers CSV/Parquet parsing and writing,
custom CSV delimiters, quote characters, comment prefixes, headerless files,
read-time column projection, positional column renaming, dtype overrides,
literal null markers, UTF-8 lossy decoding, and skip-rows/row-limit windows,
writer delimiter/header/null/line-terminator options, schema, projection,
filtering, sorting, grouping, all eager join types, column operations, SQL,
JSON conversion, and error paths. The smoke test installs the module and bridge
into a prefix and verifies that `require("polars")` finds the bridge without
`POLARS_LUA_LIB`.
The rockspec check validates the release version references, installs the same
checkout through LuaRocks into the ignored `.luarocks-tree/` directory, and
requires it from there. A content stamp skips `luarocks make` while the rockspec, Lua
modules, install script, and native bridge are unchanged, so repeated checks are
incremental. Set `POLARS_LUA_ROCK_TREE=/path` to use another tree and
`POLARS_LUA_ROCK_FORCE=1` to force a reinstall. The native bridge itself is
reused whenever it is newer than the Rust sources.

## Install with LuaRocks

The repository ships a source rockspec. LuaRocks runs
`scripts/ensure-bridge.sh`, installs the Lua modules through `$(LUADIR)`, and
places the native bridge in `$(LIBDIR)`. A release library that is newer than
the Rust sources is reused; otherwise the bridge is built incrementally. The
Lua loader also searches the directories on `package.cpath`, so no
`POLARS_LUA_LIB` is needed.

```sh
luarocks make lua-polars-0.14.0-1.rockspec --tree=/tmp/lua-polars-rock
eval "$(luarocks path --tree=/tmp/lua-polars-rock)"
luajit -e 'print(require("polars").version())'
```

For a clean checkout the first command compiles Polars; set
`CARGO_BUILD_JOBS=1` on a memory-constrained machine (the rockspec and
`scripts/build.sh` default to one job). The source URL points at the `v0.14.0`
tag, which is created as part of the release: use `luarocks make` from a
checkout before the tag exists, and
`luarocks build lua-polars-0.14.0-1.rockspec` afterwards. Both use the same
build and install commands.

## Install into a prefix

`scripts/install.sh` copies the Lua module, its JSON helper, and the native
bridge into a self-contained prefix:

```sh
./scripts/install.sh /tmp/lua-polars
LUA_PATH='/tmp/lua-polars/share/lua/5.1/?.lua;;' \
  luajit -e 'local p = require("polars"); print(p.version())'
```

The bridge is installed beside `polars.lua`, which is the first default lookup
location after `POLARS_LUA_LIB`.

## API

See [`docs/api.md`](docs/api.md). In short:

```lua
polars.version()
polars.read_csv(path)
polars.read_csv(path, {
  delimiter = ";",
  header = false,
  quote = "'",
  comment = "#",
  columns = { "name", "score" },
  rename_columns = { "person", "points" },
  dtypes = { score = "f64" },
  null_values = { "NA", "missing" },
  encoding = "utf8-lossy",
  skip_rows = 1,
  n_rows = 100,
})
polars.read_parquet(path)

df:shape()                -- rows, cols
df:schema()               -- { column = "i64", ... }
df:columns()              -- ordered column names
df:head(n)
df:sql(query)
df:select("a", "b")
df:filter('"a" > 3')
df:sort("a", true)
df:group_by("team", { 'sum("score") AS total' })
df:join(other, { on = "id", how = "full" })
df:drop("unused")
df:rename({ old = "new" })
df:with_columns('"score" * 2 AS double_score')
df:write_csv("out.csv")
df:write_csv("out.tsv", {
  delimiter = "\t",
  header = false,
  null_value = "NA",
})
df:write_csv("out-crlf.csv", { line_terminator = "\r\n" })
df:write_parquet("out.parquet")
df:to_table()
df:to_json()
df:close()
```

JSON `null` becomes the `polars.null` sentinel so it is not confused with a
missing key. Numeric values pass through Lua numbers; large 64-bit integers
may lose precision in `to_table()`.

## Architecture

```text
LuaJIT FFI  →  extern "C" bridge (Rust)  →  polars 0.55
```

- The bridge catches Rust panics before they cross the C ABI.
- The bridge is discovered through `POLARS_LUA_LIB`, beside `polars.lua`, or in
  the directories listed by `package.cpath` (the LuaRocks layout).
- Opaque handles are owned by Lua tables with explicit close/GC cleanup.
- `polars-ffi` 0.55 is available for a later Arrow C Data exchange; it is not
  used in this eager MVP.
- The binding does not depend on luatorch or numlua.

## License

BSD-3-Clause. Polars is MIT-licensed; this repository is an independent,
unofficial binding.
