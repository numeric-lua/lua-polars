--
-- Dependency-free lua-polars test suite.
--
local script = arg and arg[0] or "tests/run.lua"
local root = script:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
if root == "" then root = "." end
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local polars = require("polars")
local fixture = root .. "/tests/fixtures/sample.csv"

local passed, failed = 0, 0
local failures = {}
local current = "?"

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    io.write(".")
  else
    failed = failed + 1
    failures[#failures + 1] = string.format("[%s] %s\n  %s", current, name,
      tostring(err))
    io.write("F")
  end
  io.flush()
end

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label or "value",
      tostring(expected), tostring(actual)), 2)
  end
end

local function truthy(value, label)
  if not value then
    error((label or "value") .. " should be truthy", 2)
  end
end

current = "module"
test("version is exposed", function()
  eq(polars.version(), "0.1.0")
end)
test("package version", function()
  eq(polars._VERSION, "0.1.0")
end)

current = "csv"
test("reads a CSV file", function()
  local df = polars.read_csv(fixture)
  local rows, cols = df:shape()
  eq(rows, 5)
  eq(cols, 4)
  df:close()
end)
test("schema lists columns and dtypes", function()
  local df = polars.read_csv(fixture)
  local schema = df:schema()
  eq(schema.name, "str")
  eq(schema.score, "i64")
  eq(schema.active, "bool")
  df:close()
end)
test("head limits rows", function()
  local df = polars.read_csv(fixture):head(2)
  local rows = df:shape()
  eq(rows, 2)
  df:close()
end)
test("select returns chosen columns in order", function()
  local df = polars.read_csv(fixture):select("name", "score")
  local rows, cols = df:shape()
  eq(rows, 5)
  eq(cols, 2)
  local table_rows = df:to_table()
  eq(table_rows[1].name, "ana")
  eq(table_rows[1].score, 10)
  df:close()
end)
test("SQL filter and projection", function()
  local df = polars.read_csv(fixture)
  local result = df:sql([[
    SELECT "name", "score" FROM df WHERE "score" >= 9 ORDER BY "score" DESC
  ]])
  local rows = result:to_table()
  eq(#rows, 3)
  eq(rows[1].name, "caio")
  eq(rows[2].name, "ana")
  eq(rows[3].name, "eva")
  df:close()
  result:close()
end)
test("SQL group by aggregation", function()
  local df = polars.read_csv(fixture)
  local result = df:sql([[
    SELECT "team", sum("score") AS total FROM df
    GROUP BY "team" ORDER BY "team"
  ]])
  local rows = result:to_table()
  eq(#rows, 2)
  eq(rows[1].team, "blue")
  eq(rows[1].total, 17)
  eq(rows[2].team, "red")
  eq(rows[2].total, 26)
  df:close()
  result:close()
end)
test("filter helper builds a WHERE clause", function()
  local df = polars.read_csv(fixture)
  local result = df:filter('"active" = true')
  eq(result:shape(), 3)
  df:close()
  result:close()
end)
test("sort helper orders rows", function()
  local df = polars.read_csv(fixture)
  local result = df:sort("score", true)
  local rows = result:to_table()
  eq(rows[1].score, 12)
  eq(rows[5].score, 5)
  df:close()
  result:close()
end)
test("group_by helper", function()
  local df = polars.read_csv(fixture)
  local result = df:group_by("team", { 'sum("score") AS total' })
  local rows = result:to_table()
  eq(#rows, 2)
  df:close()
  result:close()
end)

current = "parquet"
test("reads a Parquet file", function()
  local parquet = root .. "/tests/fixtures/sample.parquet"
  local f = io.open(parquet, "rb")
  if f == nil then
    error("sample.parquet is missing; run examples/make_parquet.rs")
  end
  f:close()
  local df = polars.read_parquet(parquet)
  eq(df:shape(), 5)
  df:close()
end)

current = "errors"
test("missing file is an error", function()
  local ok, err = pcall(polars.read_csv, root .. "/tests/fixtures/missing.csv")
  eq(ok, false)
  truthy(tostring(err):find("No such file") or tostring(err):find("os error"),
    "missing-file error")
end)
test("invalid SQL is an error", function()
  local df = polars.read_csv(fixture)
  local ok = pcall(function()
    df:sql("SELECT nope FROM df")
  end)
  eq(ok, false)
  df:close()
end)
test("closed handle cannot be used", function()
  local df = polars.read_csv(fixture)
  df:close()
  df:close()
  local ok = pcall(function()
    return df:shape()
  end)
  eq(ok, false)
end)
test("head rejects negative counts", function()
  local df = polars.read_csv(fixture)
  local ok = pcall(function()
    df:head(-1)
  end)
  eq(ok, false)
  df:close()
end)

current = "json"
test("to_json returns a JSON array", function()
  local df = polars.read_csv(fixture):head(1)
  local encoded = df:to_json()
  truthy(encoded:find('^%['), "JSON array start")
  truthy(encoded:find('"name"'), "column name")
  df:close()
end)
test("null sentinel is available", function()
  truthy(polars.null ~= nil, "null sentinel")
  eq(tostring(polars.null), "null")
end)

io.write(string.format("\n\n%d tests, %d passed, %d failed\n", passed + failed,
  passed, failed))
if failed > 0 then
  for _, failure in ipairs(failures) do
    io.write("\n" .. failure .. "\n")
  end
  os.exit(1)
end
