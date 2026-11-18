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

local function find_row(rows, fields)
  for _, row in ipairs(rows) do
    local matches = true
    for field, value in pairs(fields) do
      if row[field] ~= value then
        matches = false
        break
      end
    end
    if matches then
      return row
    end
  end
  error("no row matched the requested fields", 2)
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

current = "joins"
local join_left = root .. "/tests/fixtures/join_left.csv"
local join_right = root .. "/tests/fixtures/join_right.csv"

test("inner join on one key", function()
  local left = polars.read_csv(join_left)
  local right = polars.read_csv(join_right)
  local joined = left:join(right, { on = "id", how = "inner" })
  local rows, cols = joined:shape()
  eq(rows, 3)
  eq(cols, 5)
  local bia = find_row(joined:to_table(), { id = 2 })
  eq(bia.name, "bia")
  eq(bia.score, 20)
  eq(bia.active, true)
  eq(left:shape(), 5)
  eq(right:shape(), 4)
  left:close()
  right:close()
  joined:close()
end)
test("left join keeps unmatched rows and nulls right columns", function()
  local left = polars.read_csv(join_left)
  local right = polars.read_csv(join_right)
  local joined = left:join(right, { on = "id", how = "left" })
  local rows, cols = joined:shape()
  eq(rows, 5)
  eq(cols, 5)
  local table_rows = joined:to_table()
  local duda = find_row(table_rows, { id = 4 })
  eq(duda.name, "duda")
  eq(duda.team, polars.null)
  eq(duda.score, polars.null)
  eq(duda.active, polars.null)
  local eva = find_row(table_rows, { id = 6 })
  eq(eva.name, "eva")
  eq(eva.score, polars.null)
  left:close()
  right:close()
  joined:close()
end)
test("inner join on multiple keys", function()
  local left = polars.read_csv(root .. "/tests/fixtures/join_left_multi.csv")
  local right = polars.read_csv(root .. "/tests/fixtures/join_right_multi.csv")
  local joined = left:join(right, {
    on = { "region", "id" },
    how = "inner",
  })
  local rows, cols = joined:shape()
  eq(rows, 3)
  eq(cols, 4)
  local table_rows = joined:to_table()
  eq(find_row(table_rows, { region = "north", id = 2 }).price, 250)
  eq(find_row(table_rows, { region = "south", id = 1 }).price, 75)
  eq(find_row(table_rows, { region = "north", id = 1 }).qty, 5)
  left:close()
  right:close()
  joined:close()
end)
test("left join on multiple keys", function()
  local left = polars.read_csv(root .. "/tests/fixtures/join_left_multi.csv")
  local right = polars.read_csv(root .. "/tests/fixtures/join_right_multi.csv")
  local joined = left:join(right, {
    left_on = { "region", "id" },
    right_on = { "region", "id" },
    how = "left",
  })
  local rows, cols = joined:shape()
  eq(rows, 5)
  eq(cols, 4)
  local table_rows = joined:to_table()
  eq(find_row(table_rows, { region = "west", id = 1 }).price, polars.null)
  eq(find_row(table_rows, { region = "south", id = 3 }).price, polars.null)
  left:close()
  right:close()
  joined:close()
end)
test("join supports selecting columns afterwards", function()
  local left = polars.read_csv(join_left)
  local right = polars.read_csv(join_right)
  local joined = left:join(right, { on = "id", how = "inner" })
  local selected = joined:select("name", "score", "active")
  local rows, cols = selected:shape()
  eq(rows, 3)
  eq(cols, 3)
  local caio = find_row(selected:to_table(), { name = "caio" })
  eq(caio.score, 30)
  eq(caio.active, false)
  left:close()
  right:close()
  joined:close()
  selected:close()
end)
test("inner join excludes null keys by default", function()
  local left = polars.read_csv(root .. "/tests/fixtures/join_left_nulls.csv")
  local right = polars.read_csv(root .. "/tests/fixtures/join_right_nulls.csv")
  local joined = left:join(right, { on = "id", how = "inner" })
  eq(select(1, joined:shape()), 3)
  local matching = left:join(right, {
    on = "id",
    how = "inner",
    nulls_equal = true,
  })
  eq(select(1, matching:shape()), 4)
  eq(find_row(matching:to_table(), { label = "unknown" }).value, 99)
  left:close()
  right:close()
  joined:close()
  matching:close()
end)
test("left join preserves null-key rows and can match null keys", function()
  local left = polars.read_csv(root .. "/tests/fixtures/join_left_nulls.csv")
  local right = polars.read_csv(root .. "/tests/fixtures/join_right_nulls.csv")
  local joined = left:join(right, { on = "id", how = "left" })
  eq(select(1, joined:shape()), 4)
  eq(find_row(joined:to_table(), { label = "unknown" }).value, polars.null)
  local matching = left:join(right, {
    on = "id",
    how = "left",
    nulls_equal = true,
  })
  eq(select(1, matching:shape()), 4)
  eq(find_row(matching:to_table(), { label = "unknown" }).value, 99)
  left:close()
  right:close()
  joined:close()
  matching:close()
end)
test("join rejects an invalid join type", function()
  local left = polars.read_csv(join_left)
  local right = polars.read_csv(join_right)
  local ok, err = pcall(function()
    left:join(right, { on = "id", how = "outer" })
  end)
  eq(ok, false)
  truthy(tostring(err):find("invalid join type"), "invalid join type error")
  left:close()
  right:close()
end)
test("join reports missing key columns", function()
  local left = polars.read_csv(join_left)
  local right = polars.read_csv(join_right)
  local ok, err = pcall(function()
    left:join(right, { left_on = "missing", right_on = "id" })
  end)
  eq(ok, false)
  truthy(tostring(err):find("missing"), "missing left key error")
  ok, err = pcall(function()
    left:join(right, { left_on = "id", right_on = "missing" })
  end)
  eq(ok, false)
  truthy(tostring(err):find("missing"), "missing right key error")
  left:close()
  right:close()
end)
test("join rejects duplicate key names", function()
  local left = polars.read_csv(join_left)
  local right = polars.read_csv(join_right)
  local ok, err = pcall(function()
    left:join(right, { on = { "id", "id" } })
  end)
  eq(ok, false)
  truthy(tostring(err):find("duplicate"), "duplicate key error")
  left:close()
  right:close()
end)
test("join rejects mismatched key counts", function()
  local left = polars.read_csv(join_left)
  local right = polars.read_csv(join_right)
  local ok, err = pcall(function()
    left:join(right, { left_on = { "id" }, right_on = { "id", "score" } })
  end)
  eq(ok, false)
  truthy(tostring(err):find("key count mismatch"), "key count error")
  left:close()
  right:close()
end)
test("join requires an open DataFrame and valid options", function()
  local left = polars.read_csv(join_left)
  local right = polars.read_csv(join_right)
  local ok = pcall(function()
    left:join(right)
  end)
  eq(ok, false)
  right:close()
  ok = pcall(function()
    left:join(right, { on = "id" })
  end)
  eq(ok, false)
  left:close()
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
