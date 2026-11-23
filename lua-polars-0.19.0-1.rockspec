package = "lua-polars"
version = "0.19.0-1"

source = {
   url = "git+https://github.com/numeric-lua/lua-polars.git",
   tag = "v0.19.0",
}

description = {
   summary = "LuaJIT DataFrame bindings over Rust Polars",
   detailed = [[
Eager DataFrames over Polars: CSV/Parquet/JSON readers and writers with CSV
delimiter/header/quote/comment/columns/renames/dtypes/null-values reader
options, per-column null markers, skip-rows/row-limit windows, post-header row
skipping, decimal-comma numbers, date inference, UTF-8 lossy decoding,
truncation of ragged rows, and recovery of unparsable values; Parquet column
projections and row windows; Parquet compression/statistics/chunk-size writer
options; CSV delimiter/header/null-value/line-terminator/quote-style and
float-precision writer options; JSON array/JSON Lines formats with projections;
SQL, select, filter, sort, group-by, value counts, joins, head/tail/slice, row
indexing, row reversal, strict column casting, subset distinct rows, list-column
explode, column-scoped null dropping and filling, ordered columns, and
JSON/table conversion. Requires LuaJIT and a Rust toolchain at build time.
]],
   homepage = "https://github.com/numeric-lua/lua-polars",
   license = "BSD-3-Clause",
}

dependencies = {
   "lua >= 5.1",
}

build = {
   type = "command",
   build_command = "sh scripts/ensure-bridge.sh",
   install_command = "sh scripts/install-rock.sh \"$(LUADIR)\" \"$(LIBDIR)\"",
}
