--
-- Installed-layout smoke test, run by scripts/smoke.sh.
--
local prefix, fixture = arg[1], arg[2]
if prefix == nil or fixture == nil then
  error("usage: install_smoke.lua PREFIX FIXTURE", 2)
end

local function check(condition, message)
  if not condition then
    error(message, 2)
  end
end

local polars = require("polars")
local source = debug.getinfo(polars.read_csv, "S").source
check(source:sub(1, 1) == "@", "module source is not a file path")
local module_path = source:sub(2)
check(module_path:sub(1, #prefix) == prefix,
  "loaded polars from outside the installed prefix: " .. module_path)
check(polars.version() == "0.13.0", "unexpected bridge version")
check(polars._VERSION == "0.13.0", "unexpected Lua module version")

local df = polars.read_csv(fixture)
local rows, cols = df:shape()
check(rows == 5 and cols == 4, "unexpected fixture shape")
local columns = df:columns()
check(#columns == 4 and columns[1] == "name", "unexpected column order")
df:close()

local projected = polars.read_csv(fixture, { columns = { "score", "name" } })
local projected_rows, projected_cols = projected:shape()
check(projected_rows == 5 and projected_cols == 2,
  "unexpected projected fixture shape")
check(table.concat(projected:columns(), ",") == "score,name",
  "unexpected projected column order")
check(projected:to_table()[1].score == 10, "unexpected projected value")
projected:close()

local typed = polars.read_csv(fixture, {
  columns = { "score", "name" },
  dtypes = { score = "f64" },
})
check(typed:schema().score == "f64", "unexpected dtype override")
check(table.concat(typed:columns(), ",") == "score,name",
  "unexpected typed column order")
check(typed:to_table()[1].score == 10, "unexpected typed value")
typed:close()

local nulled = polars.read_csv(fixture, {
  columns = { "score", "name" },
  null_values = { "10", "7" },
})
check(nulled:schema().score == "i64", "unexpected null_values schema")
local nulled_rows = nulled:to_table()
check(nulled_rows[1].score == polars.null, "10 was not read as null")
check(nulled_rows[2].score == polars.null, "7 was not read as null")
check(nulled_rows[3].score == 12, "unmatched score changed")
nulled:close()

local windowed = polars.read_csv(fixture, {
  columns = { "score", "name" },
  dtypes = { score = "f64" },
  null_values = "10",
  skip_rows = 0,
  n_rows = 2,
})
check(windowed:shape() == 2, "unexpected row-window shape")
check(table.concat(windowed:columns(), ",") == "score,name",
  "unexpected row-window column order")
check(windowed:schema().score == "f64", "unexpected row-window dtype")
local windowed_rows = windowed:to_table()
check(windowed_rows[1].score == polars.null, "row-window null marker mismatch")
check(windowed_rows[2].score == 7, "row-window value mismatch")
windowed:close()

local skipped = polars.read_csv(fixture, {
  header = false,
  skip_rows = 2,
  n_rows = 1,
})
check(skipped:to_table()[1].column_1 == "bia", "skip_rows mismatch")
skipped:close()

local roundtrip_fixture = fixture:gsub("sample%.csv$", "roundtrip.csv")
local written = os.tmpname()
os.remove(written)
local writer = polars.read_csv(roundtrip_fixture)
writer:write_csv(written, {
  delimiter = ";",
  header = false,
  null_value = "NA",
})
local handle = assert(io.open(written, "rb"))
local raw = handle:read("*a")
handle:close()
check(raw:find("1;ana;", 1, true) ~= nil, "headerless writer output mismatch")
check(raw:find("3;caio;NA\n", 1, true) ~= nil, "null placeholder mismatch")
local reloaded = polars.read_csv(written, { delimiter = ";", header = false })
check(select(1, reloaded:shape()) == 3, "unexpected writer round-trip rows")
check(reloaded:to_table()[3].column_3 == "NA",
  "null placeholder did not read back literally")
reloaded:close()
local nulled_writer = polars.read_csv(written, {
  delimiter = ";",
  header = false,
  null_values = "NA",
})
check(nulled_writer:to_table()[3].column_3 == polars.null,
  "null placeholder did not read back as null")
nulled_writer:close()
writer:close()
os.remove(written)

io.write("install smoke: ok\n")
