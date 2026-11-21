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

local function temp_path(suffix)
  local path = os.tmpname()
  os.remove(path)
  return path .. (suffix or "")
end

local temp_files = {}
local function new_temp_path(suffix)
  local path = temp_path(suffix)
  temp_files[#temp_files + 1] = path
  return path
end

local function cleanup_temp_files()
  for _, path in ipairs(temp_files) do
    os.remove(path)
  end
  temp_files = {}
end

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local data = file:read("*a")
  file:close()
  return data
end

current = "module"
test("version is exposed", function()
  eq(polars.version(), "0.10.0")
end)
test("package version", function()
  eq(polars._VERSION, "0.10.0")
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
local semicolon_fixture = root .. "/tests/fixtures/semicolon.csv"
local pipe_fixture = root .. "/tests/fixtures/pipe_no_header.csv"
test("reads a CSV with a custom delimiter", function()
  local df = polars.read_csv(semicolon_fixture, { delimiter = ";" })
  eq(df:shape(), 5)
  eq(table.concat(df:columns(), ","), "name,team,score,active")
  local rows = df:to_table()
  eq(rows[1].name, "ana")
  eq(rows[1].score, 10)
  eq(rows[5].team, "red")
  df:close()
end)
test("reads a headerless CSV with generated column names", function()
  local df = polars.read_csv(fixture, { header = false })
  local rows, cols = df:shape()
  eq(rows, 6)
  eq(cols, 4)
  eq(table.concat(df:columns(), ","), "column_1,column_2,column_3,column_4")
  local table_rows = df:to_table()
  eq(table_rows[1].column_1, "name")
  eq(table_rows[1].column_2, "team")
  eq(table_rows[2].column_1, "ana")
  eq(table_rows[2].column_2, "red")
  df:close()
  local headed = polars.read_csv(fixture, { header = true })
  eq(headed:shape(), 5)
  headed:close()
end)
test("custom delimiter and header options combine", function()
  local df = polars.read_csv(pipe_fixture, { delimiter = "|", header = false })
  local rows, cols = df:shape()
  eq(rows, 3)
  eq(cols, 3)
  local schema = df:schema()
  eq(schema.column_1, "i64")
  eq(schema.column_2, "str")
  eq(schema.column_3, "i64")
  local table_rows = df:to_table()
  eq(table_rows[1].column_1, 1)
  eq(table_rows[1].column_2, "ana")
  eq(table_rows[1].column_3, 10)
  eq(table_rows[3].column_2, "caio")
  df:close()
end)
local single_quote_fixture = root .. "/tests/fixtures/single_quote.csv"
local commented_fixture = root .. "/tests/fixtures/commented.csv"
local quoted_literal_fixture = root .. "/tests/fixtures/quoted_literal.csv"
local quoted_comments_fixture = root .. "/tests/fixtures/quoted_comments.txt"
local comment_rows_fixture = root .. "/tests/fixtures/comment_rows.csv"
local ragged_quoted_fixture = root .. "/tests/fixtures/ragged_quoted.csv"

test("reads a CSV with a custom quote character", function()
  local df = polars.read_csv(single_quote_fixture, { quote = "'" })
  local rows, cols = df:shape()
  eq(rows, 3)
  eq(cols, 3)
  local table_rows = df:to_table()
  eq(table_rows[1].note, "hello, world")
  eq(table_rows[2].note, "say 'hi'")
  eq(table_rows[3].note, polars.null)
  eq(table_rows[2].score, 20)
  df:close()
end)
test("disables quote parsing with quote = false", function()
  local quoted = polars.read_csv(quoted_literal_fixture)
  eq(quoted:to_table()[1].note, "hello")
  quoted:close()
  local literal = polars.read_csv(quoted_literal_fixture, { quote = false })
  local table_rows = literal:to_table()
  eq(table_rows[1].note, '"hello"')
  eq(table_rows[2].note, '"hi"')
  literal:close()
end)
test("skips comment lines with a custom comment prefix", function()
  local df = polars.read_csv(commented_fixture, { comment = "#" })
  local rows, cols = df:shape()
  eq(rows, 2)
  eq(cols, 3)
  eq(table.concat(df:columns(), ","), "name,team,score")
  local table_rows = df:to_table()
  eq(table_rows[1].name, "ana")
  eq(table_rows[2].team, "blue")
  df:close()
end)
test("combines quote, comment, delimiter, and header options", function()
  local df = polars.read_csv(quoted_comments_fixture, {
    delimiter = "|",
    header = false,
    quote = "'",
    comment = "#",
  })
  local rows, cols = df:shape()
  eq(rows, 2)
  eq(cols, 3)
  eq(table.concat(df:columns(), ","), "column_1,column_2,column_3")
  local table_rows = df:to_table()
  eq(table_rows[1].column_2, "ana, a")
  eq(table_rows[2].column_2, "bia")
  eq(table_rows[2].column_3, 20)
  df:close()
end)
test("comment = false keeps comment-looking rows as data", function()
  local data = polars.read_csv(comment_rows_fixture, { comment = false })
  local rows, cols = data:shape()
  eq(rows, 2)
  eq(cols, 3)
  eq(data:to_table()[1].name, "#skip")
  data:close()
  local skipped = polars.read_csv(comment_rows_fixture, { comment = "#" })
  eq(skipped:shape(), 1)
  eq(skipped:to_table()[1].name, "ana")
  skipped:close()
end)
test("malformed CSV still errors with quote and comment options", function()
  local ok, err = pcall(polars.read_csv, ragged_quoted_fixture, {
    quote = "'",
    comment = "#",
  })
  eq(ok, false, "ragged CSV with options accepted")
  truthy(tostring(err):find("fields", 1, true) or
    tostring(err):find("CSV", 1, true), "CSV parse error: " .. tostring(err))
end)
test("projects selected CSV columns in requested order", function()
  local df = polars.read_csv(fixture, { columns = { "score", "name" } })
  local rows, cols = df:shape()
  eq(rows, 5)
  eq(cols, 2)
  eq(table.concat(df:columns(), ","), "score,name")
  local table_rows = df:to_table()
  eq(table_rows[1].score, 10)
  eq(table_rows[1].name, "ana")
  eq(table_rows[1].team, nil)
  eq(table_rows[5].score, 9)
  df:close()
end)
test("accepts a single projected column name", function()
  local df = polars.read_csv(fixture, { columns = "name" })
  eq(df:shape(), 5)
  eq(table.concat(df:columns(), ","), "name")
  eq(df:to_table()[5].name, "eva")
  df:close()
end)
test("projection combines with headerless and delimiter options", function()
  local df = polars.read_csv(pipe_fixture, {
    delimiter = "|",
    header = false,
    columns = { "column_3", "column_1" },
  })
  eq(df:shape(), 3)
  eq(table.concat(df:columns(), ","), "column_3,column_1")
  local table_rows = df:to_table()
  eq(table_rows[1].column_1, 1)
  eq(table_rows[1].column_3, 10)
  eq(table_rows[3].column_3, 30)
  df:close()
end)
test("projection combines with quote and comment options", function()
  local df = polars.read_csv(quoted_comments_fixture, {
    delimiter = "|",
    header = false,
    quote = "'",
    comment = "#",
    columns = { "column_3", "column_2" },
  })
  eq(df:shape(), 2)
  eq(table.concat(df:columns(), ","), "column_3,column_2")
  local table_rows = df:to_table()
  eq(table_rows[1].column_2, "ana, a")
  eq(table_rows[2].column_3, 20)
  df:close()
end)
test("projecting every column matches the full frame", function()
  local full = polars.read_csv(fixture)
  local projected = polars.read_csv(fixture, { columns = full:columns() })
  eq(projected:shape(), full:shape())
  eq(table.concat(projected:columns(), ","),
    table.concat(full:columns(), ","))
  eq(projected:to_table()[1].name, full:to_table()[1].name)
  projected:close()
  full:close()
end)
test("projection rejects unknown and duplicate columns", function()
  local ok, err = pcall(polars.read_csv, fixture, { columns = { "nope" } })
  eq(ok, false, "unknown projected column accepted")
  truthy(tostring(err):find("nope", 1, true),
    "unknown projected column error: " .. tostring(err))
  ok, err = pcall(polars.read_csv, fixture, { columns = { "name", "name" } })
  eq(ok, false, "duplicate projected column accepted")
  truthy(tostring(err):find("duplicate", 1, true),
    "duplicate projected column error: " .. tostring(err))
end)
test("dtype override changes the inferred schema and values", function()
  local numeric = polars.read_csv(fixture, { dtypes = { score = "f64" } })
  local schema = numeric:schema()
  eq(schema.score, "f64")
  eq(schema.name, "str")
  eq(schema.active, "bool")
  eq(numeric:to_table()[1].score, 10)
  numeric:close()
  local text = polars.read_csv(fixture, { dtypes = { score = "str" } })
  eq(text:schema().score, "str")
  eq(text:to_table()[1].score, "10")
  eq(text:to_table()[5].score, "9")
  text:close()
end)
test("dtype override accepts aliases and integer widths", function()
  local df = polars.read_csv(fixture, {
    dtypes = { score = "UINT32", active = "Boolean" },
  })
  local schema = df:schema()
  eq(schema.score, "u32")
  eq(schema.active, "bool")
  eq(df:to_table()[1].active, true)
  df:close()
end)
test("dtype override combines with projection and headerless input", function()
  local projected = polars.read_csv(fixture, {
    columns = { "score", "name" },
    dtypes = { score = "f32" },
  })
  eq(table.concat(projected:columns(), ","), "score,name")
  eq(projected:schema().score, "f32")
  eq(projected:schema().name, "str")
  eq(projected:to_table()[1].score, 10)
  projected:close()

  local headerless = polars.read_csv(pipe_fixture, {
    delimiter = "|",
    header = false,
    dtypes = { column_1 = "str", column_3 = "f32" },
  })
  local schema = headerless:schema()
  eq(schema.column_1, "str")
  eq(schema.column_2, "str")
  eq(schema.column_3, "f32")
  local rows = headerless:to_table()
  eq(rows[1].column_1, "1")
  eq(rows[1].column_3, 10)
  eq(rows[3].column_3, 30)
  headerless:close()
end)
test("dtype override combines with quote and comment options", function()
  local df = polars.read_csv(quoted_comments_fixture, {
    delimiter = "|",
    header = false,
    quote = "'",
    comment = "#",
    dtypes = { column_3 = "f64" },
  })
  eq(df:shape(), 2)
  eq(df:schema().column_3, "f64")
  local rows = df:to_table()
  eq(rows[1].column_2, "ana, a")
  eq(rows[2].column_3, 20)
  df:close()
end)
test("dtype override rejects invalid values", function()
  local cases = {
    { { dtypes = 42 }, "dtypes must be" },
    { { dtypes = {} }, "must not be empty" },
    { { dtypes = { [1] = "f64" } }, "keys must be" },
    { { dtypes = { score = 42 } }, "values must be" },
    { { dtypes = { score = "" } }, "values must be" },
    { { dtypes = { score = "decimal" } }, "unsupported CSV dtype" },
    { { dtypes = { score = "date" } }, "unsupported CSV dtype" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(polars.read_csv, fixture, case[1])
    eq(ok, false, "invalid dtype options accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
end)
test("dtype override rejects unknown columns and unparsable values", function()
  local ok, err = pcall(polars.read_csv, fixture, { dtypes = { missing = "f64" } })
  eq(ok, false, "dtype override for a missing column accepted")
  truthy(tostring(err):find("not a column in the file", 1, true),
    "missing dtype column error: " .. tostring(err))

  ok, err = pcall(polars.read_csv, fixture, {
    columns = { "name" },
    dtypes = { score = "f64" },
  })
  eq(ok, false, "dtype override outside the projection accepted")
  truthy(tostring(err):find("not in the projection", 1, true),
    "unprojected dtype column error: " .. tostring(err))

  ok, err = pcall(polars.read_csv, fixture, { dtypes = { name = "i64" } })
  eq(ok, false, "unparsable dtype override accepted")
  truthy(tostring(err):find("parse", 1, true) or
    tostring(err):find("conversion", 1, true),
    "dtype parse error: " .. tostring(err))
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

current = "columns"
test("columns returns the frame's column order", function()
  local df = polars.read_csv(fixture)
  local columns = df:columns()
  eq(#columns, 4)
  eq(columns[1], "name")
  eq(columns[2], "team")
  eq(columns[3], "score")
  eq(columns[4], "active")
  df:close()
end)
test("drop preserves the remaining column order", function()
  local df = polars.read_csv(fixture)
  local dropped = df:drop("team")
  eq(table.concat(dropped:columns(), ","), "name,score,active")
  eq(find_row(dropped:to_table(), { name = "ana" }).score, 10)
  dropped:close()
  df:close()
end)
test("rename preserves column order", function()
  local df = polars.read_csv(fixture)
  local renamed = df:rename({ name = "person" })
  eq(table.concat(renamed:columns(), ","), "person,team,score,active")
  eq(find_row(renamed:to_table(), { person = "ana" }).score, 10)
  renamed:close()
  df:close()
end)
test("with_columns appends expressions in order", function()
  local df = polars.read_csv(fixture)
  local extended = df:with_columns('"score" * 2 AS double_score')
  eq(table.concat(extended:columns(), ","),
    "name,team,score,active,double_score")
  eq(find_row(extended:to_table(), { name = "ana" }).double_score, 20)
  extended:close()
  df:close()
end)
test("drop rejects dropping every column", function()
  local df = polars.read_csv(fixture)
  local ok, err = pcall(function()
    df:drop("name", "team", "score", "active")
  end)
  eq(ok, false)
  truthy(tostring(err):find("at least one column"), "drop-all error")
  df:close()
end)
test("columns rejects a closed frame", function()
  local df = polars.read_csv(fixture)
  df:close()
  local ok, err = pcall(function()
    return df:columns()
  end)
  eq(ok, false)
  truthy(tostring(err):find("closed"), "closed-frame error")
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
    left:join(right, { on = "id", how = "bad" })
  end)
  eq(ok, false)
  truthy(tostring(err):find("invalid join type"), "invalid join type error")
  left:close()
  right:close()
end)
test("full, semi, anti, and cross joins execute", function()
  local left = polars.read_csv(join_left)
  local right = polars.read_csv(join_right)
  local lrows = select(1, left:shape())
  local rrows = select(1, right:shape())
  local full = left:join(right, { on = "id", how = "full" })
  eq(select(1, full:shape()), 6)
  local semi = left:join(right, { on = "id", how = "semi" })
  eq(select(1, semi:shape()), 3)
  local anti = left:join(right, { on = "id", how = "anti" })
  eq(select(1, anti:shape()), 2)
  local cross = left:join(right, { how = "cross" })
  eq(select(1, cross:shape()), lrows * rrows)
  cross:close(); anti:close(); semi:close(); full:close()
  left:close(); right:close()
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

current = "writers"
local roundtrip_fixture = root .. "/tests/fixtures/roundtrip.csv"

local function check_roundtrip_frame(df)
  eq(select(1, df:shape()), 3)
  eq(select(2, df:shape()), 3)
  local schema = df:schema()
  eq(schema.id, "i64")
  eq(schema.name, "str")
  eq(schema.note, "str")
  local rows = df:to_table()
  eq(find_row(rows, { id = 1 }).note, "hello, world")
  eq(find_row(rows, { id = 2 }).note, 'say "hi"')
  eq(find_row(rows, { id = 3 }).name, "caio")
  eq(find_row(rows, { id = 3 }).note, polars.null)
end

test("CSV writer round-trips quoted strings, nulls, and schema", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".csv")
  eq(df:write_csv(out), df, "write_csv return value")
  local loaded = polars.read_csv(out)
  check_roundtrip_frame(loaded)
  loaded:close()
  df:close()
end)
test("Parquet writer round-trips quoted strings, nulls, and schema", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".parquet")
  eq(df:write_parquet(out), df, "write_parquet return value")
  local loaded = polars.read_parquet(out)
  check_roundtrip_frame(loaded)
  loaded:close()
  df:close()
end)
test("CSV writer options round-trip delimiter and null value", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".csv")
  eq(df:write_csv(out, { delimiter = ";", null_value = "NA" }), df,
    "write_csv options return value")
  local raw = read_file(out)
  truthy(raw:find("id;name;note\n", 1, true), "semicolon header")
  truthy(raw:find("3;caio;NA\n", 1, true), "null placeholder")
  local loaded = polars.read_csv(out, { delimiter = ";" })
  eq(select(1, loaded:shape()), 3)
  eq(select(2, loaded:shape()), 3)
  local rows = loaded:to_table()
  eq(find_row(rows, { id = 1 }).note, "hello, world")
  eq(find_row(rows, { id = 2 }).note, 'say "hi"')
  eq(find_row(rows, { id = 3 }).note, "NA")
  loaded:close()
  df:close()
end)
test("CSV writer header option writes headerless output", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".csv")
  df:write_csv(out, { header = false })
  local raw = read_file(out)
  truthy(not raw:find("id,name,note", 1, true), "header row omitted")
  truthy(raw:find('1,ana,"hello, world"\n', 1, true), "headerless first row")
  local loaded = polars.read_csv(out, { header = false })
  eq(select(1, loaded:shape()), 3)
  eq(select(2, loaded:shape()), 3)
  local rows = loaded:to_table()
  eq(rows[1].column_2, "ana")
  eq(rows[3].column_3, polars.null)
  loaded:close()
  df:close()
end)
test("CSV writer defaults stay comma, header, and empty null", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".csv")
  df:write_csv(out, {})
  local raw = read_file(out)
  truthy(raw:find("id,name,note\n", 1, true), "comma header")
  truthy(raw:find("3,caio,\n", 1, true), "empty null field")
  df:close()
end)
test("CSV writer rejects invalid options", function()
  local df = polars.read_csv(fixture)
  local path = new_temp_path(".csv")
  local cases = {
    { 42, "options must be a table" },
    { { separator = ";" }, "unknown field 'separator'" },
    { { delimiter = 59 }, "delimiter must be a one-byte string" },
    { { delimiter = "" }, "delimiter" },
    { { delimiter = ";;" }, "delimiter" },
    { { delimiter = "\n" }, "delimiter" },
    { { delimiter = '"' }, "delimiter" },
    { { header = 0 }, "header must be a boolean" },
    { { null_value = 1 }, "null_value must be a string" },
    { { null_value = "a\nb" }, "null_value" },
    { { null_value = "a\0b" }, "null_value" },
    { { delimiter = ";", null_value = "a;b" }, "null_value" },
    { { null_value = '"' }, "null_value" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function()
      df:write_csv(path, case[1])
    end)
    eq(ok, false, "invalid write_csv options accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  df:close()
end)
test("CSV writer options report invalid paths, closed frames, and IO errors", function()
  local df = polars.read_csv(fixture)
  local ok, err = pcall(function()
    df:write_csv("", { delimiter = ";" })
  end)
  eq(ok, false, "empty options path accepted")
  truthy(tostring(err):find("path must be a string"), "options path error")
  local base = temp_path()
  ok, err = pcall(function()
    df:write_csv(base .. "/missing/out.csv", { header = false })
  end)
  eq(ok, false, "missing directory accepted")
  truthy(tostring(err):find("No such file") or tostring(err):find("os error"),
    "options filesystem error")
  df:close()
  ok, err = pcall(function()
    df:write_csv(new_temp_path(".csv"), { delimiter = ";" })
  end)
  eq(ok, false, "closed frame with options accepted")
  truthy(tostring(err):find("closed"), "options closed-frame error")
end)
test("writers reject empty and non-string paths", function()
  local df = polars.read_csv(fixture)
  for _, method in ipairs({ "write_csv", "write_parquet" }) do
    for _, value in ipairs({ "", 42 }) do
      local ok, err = pcall(function()
        df[method](df, value)
      end)
      eq(ok, false, method .. " invalid path")
      truthy(tostring(err):find("path must be a string"),
        method .. " path error")
    end
  end
  df:close()
end)
test("writers report filesystem errors", function()
  local df = polars.read_csv(fixture)
  local base = temp_path()
  for _, suffix in ipairs({ ".csv", ".parquet" }) do
    local method = suffix == ".csv" and "write_csv" or "write_parquet"
    local ok, err = pcall(function()
      df[method](df, base .. "/missing/out" .. suffix)
    end)
    eq(ok, false, method .. " missing directory")
    local message = tostring(err)
    truthy(message:find("No such file") or message:find("os error"),
      method .. " filesystem error")
  end
  df:close()
end)
test("writers reject a closed frame", function()
  local df = polars.read_csv(fixture)
  df:close()
  for _, method in ipairs({ "write_csv", "write_parquet" }) do
    local ok, err = pcall(function()
      df[method](df, new_temp_path(".out"))
    end)
    eq(ok, false, method .. " closed frame")
    truthy(tostring(err):find("closed"), method .. " closed-frame error")
  end
end)

current = "errors"
test("missing file is an error", function()
  local ok, err = pcall(polars.read_csv, root .. "/tests/fixtures/missing.csv")
  eq(ok, false)
  truthy(tostring(err):find("No such file") or tostring(err):find("os error"),
    "missing-file error")
end)
test("read_csv rejects invalid options", function()
  local cases = {
    { 42, "options must be a table" },
    { { separator = ";" }, "unknown field 'separator'" },
    { { delimiter = 59 }, "delimiter must be a string" },
    { { header = 0 }, "header must be a boolean" },
    { { delimiter = "" }, "delimiter" },
    { { delimiter = ";;" }, "delimiter" },
    { { delimiter = "\n" }, "delimiter" },
    { { delimiter = '"' }, "delimiter" },
    { { quote = 39 }, "quote must be" },
    { { quote = true }, "quote must be" },
    { { quote = "''" }, "quote" },
    { { quote = "\n" }, "quote" },
    { { quote = "\r" }, "quote" },
    { { quote = "\0" }, "quote" },
    { { comment = 35 }, "comment must be" },
    { { comment = "##" }, "comment" },
    { { comment = "\r" }, "comment" },
    { { columns = 42 }, "columns must be" },
    { { columns = {} }, "must not be empty" },
    { { columns = { 1 } }, "entries must be" },
    { { columns = { "" } }, "entries must be" },
    { { columns = { "name", 42 } }, "entries must be" },
    { { columns = { "name", "name" } }, "duplicate" },
    { { delimiter = "'", quote = "'" }, "quote" },
    { { delimiter = "#", comment = "#" }, "comment" },
    { { quote = "'", comment = "'" }, "quote" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(polars.read_csv, fixture, case[1])
    eq(ok, false, "invalid options accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
end)
test("read_csv reports a CSV parse error", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("a,b\n1,2\n3,4,5\n")
  file:close()
  local ok, err = pcall(polars.read_csv, path)
  eq(ok, false, "ragged CSV accepted")
  truthy(tostring(err):find("fields", 1, true) or
    tostring(err):find("CSV", 1, true), "CSV parse error: " .. tostring(err))
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

cleanup_temp_files()

test("drop_nulls and fill_null work on CSV nulls", function()
  local df = polars.read_csv(roundtrip_fixture)
  local dropped = df:drop_nulls()
  eq(select(1, dropped:shape()), 2)
  dropped:close()
  local filled = df:fill_null("zero")
  local rows = filled:to_table()
  eq(tostring(find_row(rows, { id = 3 }).note), "0")
  filled:close(); df:close()
  local bad = polars.read_csv(roundtrip_fixture)
  local ok = pcall(function() bad:fill_null("nope") end)
  eq(ok, false); bad:close()
end)

test("row iteration and emptiness helpers", function()
  local df = polars.read_csv(fixture)
  local count = 0
  for row in df:iter_rows() do count = count + 1 end
  eq(count, select(1, df:shape()))
  eq(df:is_empty(), false)
  eq(#df:column_names(), select(2, df:shape()))
  df:close()
end)

test("unique and null_count", function()
  local df = polars.read_csv(roundtrip_fixture)
  local counts = df:null_count()
  eq(counts.note, 1)
  eq(counts.id, 0)
  local unique = df:unique()
  eq(select(1, unique:shape()), 3)
  unique:close(); df:close()
end)

io.write(string.format("\n\n%d tests, %d passed, %d failed\n", passed + failed,
  passed, failed))
if failed > 0 then
  for _, failure in ipairs(failures) do
    io.write("\n" .. failure .. "\n")
  end
  os.exit(1)
end
