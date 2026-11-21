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
check(polars.version() == "0.9.0", "unexpected bridge version")
check(polars._VERSION == "0.9.0", "unexpected Lua module version")

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

io.write("install smoke: ok\n")
