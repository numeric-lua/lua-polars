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

`0.3.0` is an eager-first MVP:

- CSV and Parquet readers
- schema, shape, head
- SQL queries against the DataFrame registered as `df`
- helpers for select, filter, sort, and group-by
- eager inner and left joins on one or more keys
- row-oriented `to_table()` and raw `to_json()`
- explicit `:close()` plus Lua GC finalization

Not implemented yet: LazyFrame expressions, Arrow
zero-copy exchange, writes, streaming, and a LuaRocks package.

## Requirements

- LuaJIT 2.1 (PUC Lua is not the target because the binding uses FFI)
- Rust 1.99+ and Cargo
- a C linker
- Linux or macOS

Polars `0.55.2` is pinned. The build is large; on a 7 GB laptop use one Cargo
job:

```sh
CARGO_BUILD_JOBS=1 ./scripts/build.sh
```

## Build and test

```sh
./scripts/build.sh        # target/release/libpolars_lua.so
./scripts/test.sh         # builds if needed, then runs the Lua suite
make test
```

The test suite is dependency-free and covers CSV parsing, schema, projection,
filtering, sorting, grouping, inner/left joins, SQL, JSON conversion, and error
paths.

## API

See [`docs/api.md`](docs/api.md). In short:

```lua
polars.version()
polars.read_csv(path)
polars.read_parquet(path)

df:shape()                -- rows, cols
df:schema()               -- { column = "i64", ... }
df:head(n)
df:sql(query)
df:select("a", "b")
df:filter('"a" > 3')
df:sort("a", true)
df:group_by("team", { 'sum("score") AS total' })
df:join(other, { on = "id", how = "left" })
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
- Opaque handles are owned by Lua tables with explicit close/GC cleanup.
- `polars-ffi` 0.55 is available for a later Arrow C Data exchange; it is not
  used in this eager MVP.
- The binding does not depend on luatorch or numlua.

## License

BSD-3-Clause. Polars is MIT-licensed; this repository is an independent,
unofficial binding.
