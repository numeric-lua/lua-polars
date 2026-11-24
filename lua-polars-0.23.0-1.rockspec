package = "lua-polars"
version = "0.23.0-1"

source = {
   url = "git+https://github.com/numeric-lua/lua-polars.git",
   tag = "v0.23.0",
}

description = {
   summary = "LuaJIT DataFrame bindings over Rust Polars",
   detailed = [[
Eager DataFrames over Polars: CSV/Parquet/JSON readers and writers with CSV
delimiter/header/quote/comment/columns/renames/dtypes/null-values reader
options, per-column null markers, skip-rows/row-limit windows, post-header row
skipping, CSV/JSON schema-inference length, decimal-comma numbers, date
inference, UTF-8 lossy decoding, truncation of ragged rows, recovery of
unparsable values, and empty-file handling; Parquet column projections, row
windows, and a low-memory read mode; Parquet compression/statistics/chunk-size
writer options; CSV
delimiter/header/null-value/line-terminator/quote-style/float-precision/BOM/
decimal-comma writer options; JSON array/JSON Lines formats with projections
and JSON Lines string output;
SQL, select, filter, sort, top/bottom k, group-by, value counts, joins,
head/tail/slice, indexed row take, row indexing, row reversal, shifting,
clipping, row striding, null masks, forward/backward null filling,
duplicate/unique markers, strict column casting, subset distinct rows,
list-column explode, column-scoped null dropping and filling, NaN filling and
dropping, ordered columns, and JSON/table conversion. Requires LuaJIT and a
Rust toolchain at build time.
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
