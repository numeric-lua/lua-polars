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
  eq(polars.version(), "0.23.0")
end)
test("package version", function()
  eq(polars._VERSION, "0.23.0")
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
test("tail limits rows from the end", function()
  local df = polars.read_csv(fixture)
  local tail = df:tail(2)
  eq(tail:shape(), 2)
  eq(table.concat(tail:columns(), ","), table.concat(df:columns(), ","))
  local rows = tail:to_table()
  eq(rows[1].name, "duda")
  eq(rows[1].score, 5)
  eq(rows[2].name, "eva")
  eq(rows[2].score, 9)
  tail:close()

  local default = df:tail()
  eq(default:shape(), 5)
  default:close()
  local empty = df:tail(0)
  eq(empty:shape(), 0)
  eq(#empty:columns(), 4)
  empty:close()
  local over = df:tail(100)
  eq(over:shape(), 5)
  over:close()
  df:close()
end)
test("slice returns a row window and supports negative offsets", function()
  local df = polars.read_csv(fixture)
  local window = df:slice(1, 2)
  eq(window:shape(), 2)
  local rows = window:to_table()
  eq(rows[1].name, "bia")
  eq(rows[1].score, 7)
  eq(rows[2].name, "caio")
  eq(rows[2].score, 12)
  window:close()

  local from_end = df:slice(-2, 2)
  eq(from_end:shape(), 2)
  rows = from_end:to_table()
  eq(rows[1].name, "duda")
  eq(rows[2].name, "eva")
  from_end:close()

  local empty = df:slice(0, 0)
  eq(empty:shape(), 0)
  eq(#empty:columns(), 4)
  empty:close()
  local past = df:slice(100, 2)
  eq(past:shape(), 0)
  eq(#past:columns(), 4)
  past:close()
  df:close()
end)
test("tail and slice reject invalid counts", function()
  local df = polars.read_csv(fixture)
  local cases = {
    { "tail", -1, "tail count" },
    { "tail", 1.5, "tail count" },
    { "tail", "2", "tail count" },
    { "tail", true, "tail count" },
    { "tail", math.huge, "tail count" },
    { "tail", 2 ^ 53, "tail count" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function() df[case[1]](df, case[2]) end)
    eq(ok, false, "invalid " .. case[1] .. " count accepted")
    truthy(tostring(err):find(case[3], 1, true),
      "expected '" .. case[3] .. "' in: " .. tostring(err))
  end
  local offset_cases = {
    { 1.5, 1, "offset" },
    { "0", 1, "offset" },
    { 0, -1, "length" },
    { 0, 1.5, "length" },
    { 0, "1", "length" },
    { 0, math.huge, "length" },
    { 0, 2 ^ 53, "length" },
  }
  for _, case in ipairs(offset_cases) do
    local ok, err = pcall(function()
      df:slice(case[1], case[2])
    end)
    eq(ok, false, "invalid slice arguments accepted")
    truthy(tostring(err):find(case[3], 1, true),
      "expected '" .. case[3] .. "' in: " .. tostring(err))
  end
  df:close()
  local ok, err = pcall(function() df:tail(1) end)
  eq(ok, false, "closed tail accepted")
  truthy(tostring(err):find("closed", 1, true), "closed tail error")
end)
test("with_row_index prepends a zero-based index column", function()
  local df = polars.read_csv(fixture)
  local indexed = df:with_row_index("row")
  eq(indexed:shape(), 5)
  eq(table.concat(indexed:columns(), ","),
    "row,name,team,score,active")
  local rows = indexed:to_table()
  eq(rows[1].row, 0)
  eq(rows[1].name, "ana")
  eq(rows[5].row, 4)
  eq(rows[5].name, "eva")
  indexed:close()

  local default = df:with_row_index()
  eq(default:columns()[1], "index")
  eq(default:to_table()[1].index, 0)
  default:close()
  df:close()
end)
test("with_row_index honors an offset and composes with a row window", function()
  local df = polars.read_csv(fixture)
  local indexed = df:with_row_index("row", 10)
  local rows = indexed:to_table()
  eq(rows[1].row, 10)
  eq(rows[5].row, 14)
  local windowed = indexed:slice(2, 2)
  eq(windowed:shape(), 2)
  rows = windowed:to_table()
  eq(rows[1].row, 12)
  eq(rows[1].name, "caio")
  eq(rows[2].row, 13)
  windowed:close()
  indexed:close()
  df:close()
end)
test("with_row_index rejects invalid names, offsets, and collisions", function()
  local df = polars.read_csv(fixture)
  local cases = {
    { "", 0, "name" },
    { 42, 0, "name" },
    { "row", -1, "offset" },
    { "row", 1.5, "offset" },
    { "row", "1", "offset" },
    { "row", true, "offset" },
    { "row", math.huge, "offset" },
    { "row", 2 ^ 53, "offset" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function()
      df:with_row_index(case[1], case[2])
    end)
    eq(ok, false, "invalid with_row_index arguments accepted")
    truthy(tostring(err):find(case[3], 1, true),
      "expected '" .. case[3] .. "' in: " .. tostring(err))
  end
  local ok, err = pcall(function() df:with_row_index("name") end)
  eq(ok, false, "colliding row-index name accepted")
  truthy(tostring(err):lower():find("name", 1, true),
    "row-index collision error: " .. tostring(err))
  df:close()
  ok, err = pcall(function() df:with_row_index("row") end)
  eq(ok, false, "closed with_row_index accepted")
  truthy(tostring(err):find("closed", 1, true), "closed with_row_index error")
end)
local semicolon_fixture = root .. "/tests/fixtures/semicolon.csv"
local pipe_fixture = root .. "/tests/fixtures/pipe_no_header.csv"
local null_fixture = root .. "/tests/fixtures/null_values.csv"
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
test("null_values marks matching fields null", function()
  local default = polars.read_csv(null_fixture)
  local default_rows = default:to_table()
  eq(default_rows[1].note, "NA")
  eq(default_rows[3].note, polars.null)
  default:close()

  local df = polars.read_csv(null_fixture, { null_values = "NA" })
  eq(df:schema().note, "str")
  local rows = df:to_table()
  eq(rows[1].note, polars.null)
  eq(rows[2].note, "missing")
  eq(rows[3].note, polars.null)
  eq(rows[4].note, "N/A")
  eq(rows[5].note, "ok")
  df:close()
end)
test("null_values accepts multiple markers", function()
  local df = polars.read_csv(null_fixture, {
    null_values = { "NA", "missing", "N/A" },
  })
  local rows = df:to_table()
  eq(rows[1].note, polars.null)
  eq(rows[2].note, polars.null)
  eq(rows[3].note, polars.null)
  eq(rows[4].note, polars.null)
  eq(rows[5].note, "ok")
  df:close()

  local single = polars.read_csv(null_fixture, { null_values = { "NA" } })
  eq(single:to_table()[1].note, polars.null)
  eq(single:to_table()[2].note, "missing")
  single:close()
end)
test("per-column null_values mark only their column", function()
  local df = polars.read_csv(null_fixture, {
    null_values = { note = "NA" },
  })
  eq(df:schema().note, "str")
  local rows = df:to_table()
  eq(rows[1].note, polars.null)
  eq(rows[1].name, "ana")
  eq(rows[2].note, "missing")
  eq(rows[3].note, polars.null)
  eq(rows[4].note, "N/A")
  eq(rows[5].note, "ok")
  df:close()

  local scoped = polars.read_csv(null_fixture, {
    null_values = { name = "NA" },
  })
  rows = scoped:to_table()
  eq(rows[1].name, "ana")
  eq(rows[1].note, "NA")
  eq(scoped:schema().note, "str")
  scoped:close()
end)
test("per-column null_values combine with projection, dtypes, renames, and row windows", function()
  local df = polars.read_csv(null_fixture, {
    columns = { "score", "note" },
    dtypes = { score = "f64" },
    null_values = { score = "9", note = "NA" },
    n_rows = 5,
    rename_columns = { "points", "label" },
  })
  eq(df:shape(), 5)
  eq(table.concat(df:columns(), ","), "points,label")
  eq(df:schema().points, "f64")
  local rows = df:to_table()
  eq(rows[1].label, polars.null)
  eq(rows[1].points, 10)
  eq(rows[2].label, "missing")
  eq(rows[3].label, polars.null)
  eq(rows[4].label, "N/A")
  eq(rows[5].label, "ok")
  eq(rows[5].points, polars.null)
  df:close()
end)
test("per-column null_values combine with lossy decoding", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "wb"))
  file:write("id,note,score\n1,caf\233,10\n2,NA,20\n3,ok,NA\n")
  file:close()
  local df = polars.read_csv(path, {
    encoding = "utf8-lossy",
    null_values = { note = "NA" },
  })
  eq(df:shape(), 3)
  local rows = df:to_table()
  eq(rows[1].note, "caf\239\191\189")
  eq(rows[2].note, polars.null)
  eq(rows[3].note, "ok")
  eq(rows[3].score, "NA")
  df:close()
end)
test("per-column null_values reject malformed maps and unknown columns", function()
  local cases = {
    { { [1] = "NA", note = "NA" }, "either a list of markers or a table" },
    { { [0] = "NA" }, "positive integers" },
    { { [1.5] = "NA" }, "positive integers" },
    { { [true] = "NA" }, "keys must be column names or list indices" },
    { { [""] = "NA" }, "column names must be non-empty strings" },
    { { note = 42 }, "markers must be non-empty strings" },
    { { note = "" }, "markers must be non-empty strings" },
    { { note = { "NA" } }, "markers must be non-empty strings" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(polars.read_csv, null_fixture, { null_values = case[1] })
    eq(ok, false, "invalid named null_values accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end

  local ok, err = pcall(polars.read_csv, null_fixture, {
    columns = { "score" },
    null_values = { note = "NA" },
  })
  eq(ok, false, "null marker outside the projection accepted")
  truthy(tostring(err):find("not in the projection", 1, true),
    "projected null marker error: " .. tostring(err))

  ok, err = pcall(polars.read_csv, null_fixture, {
    null_values = { nope = "NA" },
  })
  eq(ok, false, "null marker for an unknown column accepted")
  truthy(tostring(err):find("unable to find column", 1, true),
    "unknown null marker error: " .. tostring(err))
end)
test("null_values combines with projection and dtype overrides", function()
  local df = polars.read_csv(null_fixture, {
    columns = { "score", "note" },
    dtypes = { score = "f64" },
    null_values = { "NA", "9" },
  })
  eq(table.concat(df:columns(), ","), "score,note")
  eq(df:schema().score, "f64")
  local rows = df:to_table()
  eq(rows[1].score, 10)
  eq(rows[1].note, polars.null)
  eq(rows[5].score, polars.null)
  eq(rows[5].note, "ok")
  df:close()
end)
test("null_values combines with quote, comment, delimiter, and headerless input", function()
  local path = new_temp_path(".txt")
  local file = assert(io.open(path, "w"))
  file:write("# comment\n1|'NA'|10\n# skip\n2|'bia'|20\n3|'say | hi'|30\n")
  file:close()
  local df = polars.read_csv(path, {
    delimiter = "|",
    header = false,
    quote = "'",
    comment = "#",
    null_values = "NA",
  })
  eq(df:shape(), 3)
  local rows = df:to_table()
  eq(rows[1].column_1, 1)
  eq(rows[1].column_2, polars.null)
  eq(rows[2].column_2, "bia")
  eq(rows[3].column_2, "say | hi")
  df:close()
end)
test("null_values rejects invalid values", function()
  local cases = {
    { 42, "null_values must be a non-empty string or a list" },
    { true, "null_values must be a non-empty string or a list" },
    { "", "null_values must not be empty" },
    { {}, "null_values must not be empty" },
    { { [1] = "NA", [3] = "missing" }, "contiguous list" },
    { { 42 }, "entries must be non-empty strings" },
    { { "" }, "entries must be non-empty strings" },
    { { "NA", "" }, "entries must be non-empty strings" },
    { { "NA", "NA" }, "duplicate read_csv null value 'NA'" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(polars.read_csv, null_fixture, { null_values = case[1] })
    eq(ok, false, "invalid null_values accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
end)
test("skip_rows skips leading rows before the header", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("preamble row\nname,team,score\nana,red,10\nbia,blue,20\n" ..
    "caio,red,30\n")
  file:close()
  local df = polars.read_csv(path, { skip_rows = 1 })
  eq(df:shape(), 3)
  eq(table.concat(df:columns(), ","), "name,team,score")
  local rows = df:to_table()
  eq(rows[1].name, "ana")
  eq(rows[1].score, 10)
  eq(rows[2].team, "blue")
  eq(rows[3].score, 30)
  df:close()
end)
test("n_rows limits rows and preserves the inferred schema", function()
  local full = polars.read_csv(fixture)
  local df = polars.read_csv(fixture, { n_rows = 2 })
  eq(df:shape(), 2)
  eq(table.concat(df:columns(), ","), table.concat(full:columns(), ","))
  local schema = df:schema()
  for name, dtype in pairs(full:schema()) do
    eq(schema[name], dtype, "schema." .. name)
  end
  local rows = df:to_table()
  eq(rows[1].name, "ana")
  eq(rows[1].score, 10)
  eq(rows[2].name, "bia")
  eq(rows[2].score, 7)
  full:close()
  df:close()
end)
test("row window handles empty and past-end ranges", function()
  local empty = polars.read_csv(fixture, { n_rows = 0 })
  eq(empty:shape(), 0)
  eq(table.concat(empty:columns(), ","), "name,team,score,active")
  eq(empty:schema().score, "i64")
  empty:close()

  local over = polars.read_csv(fixture, { skip_rows = 0, n_rows = 100 })
  eq(over:shape(), 5)
  over:close()

  -- The last row becomes the header, so no data rows remain.
  local past = polars.read_csv(fixture, { skip_rows = 5 })
  eq(past:shape(), 0)
  eq(table.concat(past:columns(), ","), "eva,red,9,false")
  past:close()
end)
test("row window combines with headerless input", function()
  local df = polars.read_csv(fixture, {
    header = false,
    skip_rows = 2,
    n_rows = 2,
  })
  eq(df:shape(), 2)
  eq(table.concat(df:columns(), ","), "column_1,column_2,column_3,column_4")
  local rows = df:to_table()
  eq(rows[1].column_1, "bia")
  eq(rows[1].column_3, 7)
  eq(rows[2].column_1, "caio")
  eq(rows[2].column_3, 12)
  df:close()
end)
test("row window combines with projection, dtype overrides, and null markers", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("metadata\nid,name,note,score\n1,ana,NA,10\n2,bia,missing,20\n" ..
    "3,caio,,30\n4,duda,N/A,40\n")
  file:close()
  local df = polars.read_csv(path, {
    skip_rows = 1,
    n_rows = 3,
    columns = { "score", "note", "name" },
    dtypes = { score = "f64" },
    null_values = { "NA", "missing" },
  })
  eq(df:shape(), 3)
  eq(table.concat(df:columns(), ","), "score,note,name")
  eq(df:schema().score, "f64")
  local rows = df:to_table()
  eq(rows[1].name, "ana")
  eq(rows[1].note, polars.null)
  eq(rows[1].score, 10)
  eq(rows[2].name, "bia")
  eq(rows[2].note, polars.null)
  eq(rows[2].score, 20)
  eq(rows[3].name, "caio")
  eq(rows[3].note, polars.null)
  df:close()
end)
test("row window rejects invalid values", function()
  local cases = {
    { { skip_rows = -1 }, "skip_rows" },
    { { skip_rows = 1.5 }, "skip_rows" },
    { { skip_rows = "1" }, "skip_rows" },
    { { skip_rows = true }, "skip_rows" },
    { { skip_rows = math.huge }, "skip_rows" },
    { { skip_rows = 2 ^ 53 }, "skip_rows" },
    { { n_rows = -2 }, "n_rows" },
    { { n_rows = 0.5 }, "n_rows" },
    { { n_rows = "2" }, "n_rows" },
    { { n_rows = false }, "n_rows" },
    { { n_rows = math.huge }, "n_rows" },
    { { n_rows = 2 ^ 53 }, "n_rows" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(polars.read_csv, fixture, case[1])
    eq(ok, false, "invalid row window options accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
    truthy(tostring(err):find("non-negative integer", 1, true),
      "expected integer guidance in: " .. tostring(err))
  end
end)
test("rename_columns replaces leading column names positionally", function()
  local df = polars.read_csv(fixture, {
    rename_columns = { "who", "squad", "points", "enabled" },
  })
  eq(df:shape(), 5)
  eq(table.concat(df:columns(), ","), "who,squad,points,enabled")
  local schema = df:schema()
  eq(schema.who, "str")
  eq(schema.points, "i64")
  eq(schema.enabled, "bool")
  local rows = df:to_table()
  eq(rows[1].who, "ana")
  eq(rows[1].points, 10)
  eq(rows[5].squad, "red")
  df:close()
end)
test("rename_columns renames a prefix and works with headerless input", function()
  local df = polars.read_csv(pipe_fixture, {
    delimiter = "|",
    header = false,
    rename_columns = { "id", "who" },
  })
  eq(df:shape(), 3)
  eq(table.concat(df:columns(), ","), "id,who,column_3")
  local rows = df:to_table()
  eq(rows[1].id, 1)
  eq(rows[1].who, "ana")
  eq(rows[1].column_3, 10)
  eq(rows[3].who, "caio")
  df:close()
end)
test("rename_columns combines with projection, dtype overrides, null markers, and a row window", function()
  local df = polars.read_csv(null_fixture, {
    columns = { "score", "note" },
    dtypes = { score = "f64" },
    null_values = { "NA", "9" },
    skip_rows = 0,
    n_rows = 3,
    rename_columns = { "points", "label" },
  })
  eq(df:shape(), 3)
  eq(table.concat(df:columns(), ","), "points,label")
  eq(df:schema().points, "f64")
  local rows = df:to_table()
  eq(rows[1].points, 10)
  eq(rows[1].label, polars.null)
  eq(rows[2].label, "missing")
  eq(rows[3].points, 30)
  eq(rows[3].label, polars.null)
  df:close()
end)
test("rename_columns rejects invalid values", function()
  local cases = {
    { "who", "non-empty list" },
    { 42, "non-empty list" },
    { true, "non-empty list" },
    { {}, "must not be empty" },
    { { who = "x" }, "non-empty list" },
    { { [1] = "a", [3] = "c" }, "contiguous" },
    { { 42 }, "entries must be non-empty strings" },
    { { "" }, "entries must be non-empty strings" },
    { { "a", "a" }, "duplicate read_csv column name 'a'" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(polars.read_csv, fixture, { rename_columns = case[1] })
    eq(ok, false, "invalid rename_columns accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  local ok, err = pcall(polars.read_csv, fixture, {
    rename_columns = { "a", "b", "c", "d", "e" },
  })
  eq(ok, false, "too many rename_columns accepted")
  truthy(tostring(err):find("frame has 4 columns", 1, true),
    "rename width error: " .. tostring(err))
  ok, err = pcall(polars.read_csv, fixture, { rename_columns = { "team" } })
  eq(ok, false, "rename collision accepted")
  truthy(tostring(err):find("duplicate CSV column name 'team'", 1, true),
    "rename collision error: " .. tostring(err))
end)
test("encoding stays strict UTF-8 by default", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "wb"))
  file:write("name,note\nana,caf\233\n")
  file:close()
  local ok, err = pcall(polars.read_csv, path)
  eq(ok, false, "invalid UTF-8 accepted by default")
  truthy(tostring(err):lower():find("utf", 1, true),
    "strict encoding error: " .. tostring(err))
  ok, err = pcall(polars.read_csv, path, { encoding = "utf8" })
  eq(ok, false, "explicit strict encoding accepted invalid bytes")
  truthy(tostring(err):lower():find("utf", 1, true),
    "explicit strict encoding error: " .. tostring(err))
end)
test("encoding utf8-lossy replaces invalid bytes", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "wb"))
  file:write("name,note\nana,caf\233\n")
  file:close()
  local df = polars.read_csv(path, { encoding = "utf8-lossy" })
  eq(df:shape(), 1)
  eq(df:schema().note, "str")
  eq(df:to_table()[1].note, "caf\239\191\189")
  df:close()
  local upper = polars.read_csv(path, { encoding = "UTF8-LOSSY" })
  eq(upper:to_table()[1].note, "caf\239\191\189")
  upper:close()
end)
test("encoding combines with projection, null markers, rename_columns, and row limits", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "wb"))
  file:write("id,note,score\n1,caf\233,10\n2,ok,20\n3,na\255,30\n")
  file:close()
  local df = polars.read_csv(path, {
    encoding = "utf8-lossy",
    columns = { "note", "score" },
    dtypes = { score = "f64" },
    null_values = "ok",
    n_rows = 2,
    rename_columns = { "label", "points" },
  })
  eq(df:shape(), 2)
  eq(table.concat(df:columns(), ","), "label,points")
  eq(df:schema().points, "f64")
  local rows = df:to_table()
  eq(rows[1].label, "caf\239\191\189")
  eq(rows[1].points, 10)
  eq(rows[2].label, polars.null)
  eq(rows[2].points, 20)
  df:close()
end)
test("encoding rejects unsupported values", function()
  local cases = { 42, true, "", "latin1", "utf-16", "lossy", {} }
  for _, value in ipairs(cases) do
    local ok, err = pcall(polars.read_csv, fixture, { encoding = value })
    eq(ok, false, "invalid encoding accepted")
    truthy(tostring(err):find("encoding", 1, true),
      "encoding error: " .. tostring(err))
    truthy(tostring(err):find("utf8", 1, true),
      "encoding guidance: " .. tostring(err))
  end
end)
local date_fixture = root .. "/tests/fixtures/dates.csv"
test("try_parse_dates infers date and datetime columns", function()
  local plain = polars.read_csv(date_fixture)
  eq(plain:schema().day, "str")
  eq(plain:schema().stamp, "str")
  eq(plain:to_table()[1].day, "2024-01-02")
  plain:close()

  local dated = polars.read_csv(date_fixture, { try_parse_dates = true })
  eq(dated:shape(), 3)
  eq(dated:schema().day, "date")
  truthy(dated:schema().stamp:find("datetime", 1, true),
    "datetime dtype: " .. tostring(dated:schema().stamp))
  local rows = dated:to_table()
  eq(rows[1].day, "2024-01-02")
  eq(rows[3].day, "2025-06-15")
  eq(rows[1].note, "ok")
  truthy(rows[1].stamp ~= nil, "parsed datetime value")
  dated:close()

  local explicit = polars.read_csv(date_fixture, {
    try_parse_dates = false,
  })
  eq(explicit:schema().day, "str")
  explicit:close()
end)
test("try_parse_dates combines with projection, dtypes, nulls, renames, and windows", function()
  local df = polars.read_csv(date_fixture, {
    try_parse_dates = true,
    columns = { "day", "id", "note" },
    dtypes = { id = "f64" },
    null_values = { note = "NA" },
    n_rows = 2,
    rename_columns = { "when", "id", "label" },
  })
  eq(df:shape(), 2)
  eq(table.concat(df:columns(), ","), "when,id,label")
  eq(df:schema().when, "date")
  eq(df:schema().id, "f64")
  local rows = df:to_table()
  eq(rows[1].when, "2024-01-02")
  eq(rows[1].id, 1)
  eq(rows[1].label, "ok")
  eq(rows[2].label, polars.null)
  df:close()
end)
test("try_parse_dates rejects non-boolean values", function()
  local cases = { 1, 0, "true", {}, function() end }
  for _, value in ipairs(cases) do
    local ok, err = pcall(polars.read_csv, date_fixture, {
      try_parse_dates = value,
    })
    eq(ok, false, "invalid try_parse_dates accepted")
    truthy(tostring(err):find("try_parse_dates", 1, true),
      "try_parse_dates error: " .. tostring(err))
    truthy(tostring(err):find("boolean", 1, true),
      "try_parse_dates guidance: " .. tostring(err))
  end
end)
test("truncate_ragged_lines keeps rows with extra fields", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("name,team,score\nana,red,10\nbia,blue,20,extra\n" ..
    "caio,red,30\n")
  file:close()

  local ok, err = pcall(polars.read_csv, path)
  eq(ok, false, "ragged CSV accepted by default")
  truthy(tostring(err):find("fields", 1, true) or
    tostring(err):find("Schema", 1, true), "ragged CSV error: " .. tostring(err))

  local df = polars.read_csv(path, { truncate_ragged_lines = true })
  eq(df:shape(), 3)
  eq(table.concat(df:columns(), ","), "name,team,score")
  eq(df:schema().score, "i64")
  local rows = df:to_table()
  eq(rows[1].name, "ana")
  eq(rows[2].name, "bia")
  eq(rows[2].score, 20)
  eq(rows[3].team, "red")
  df:close()

  local combined = polars.read_csv(path, {
    truncate_ragged_lines = true,
    columns = { "score", "name" },
    dtypes = { score = "f64" },
    n_rows = 2,
    rename_columns = { "points", "who" },
  })
  eq(combined:shape(), 2)
  eq(table.concat(combined:columns(), ","), "points,who")
  eq(combined:schema().points, "f64")
  rows = combined:to_table()
  eq(rows[1].who, "ana")
  eq(rows[1].points, 10)
  eq(rows[2].points, 20)
  combined:close()
end)
test("ignore_errors keeps parsable rows and nulls failures", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("id,score,note\n1,10,ok\n2,oops,NA\n3,30,keep\n")
  file:close()

  local ok, err = pcall(polars.read_csv, path, {
    dtypes = { score = "i64" },
  })
  eq(ok, false, "unparsable value accepted by default")
  truthy(tostring(err):find("parse", 1, true),
    "unparsable value error: " .. tostring(err))

  local df = polars.read_csv(path, {
    dtypes = { score = "i64" },
    null_values = { note = "NA" },
    ignore_errors = true,
  })
  eq(df:shape(), 3)
  local rows = df:to_table()
  eq(rows[1].score, 10)
  eq(rows[2].id, 2)
  eq(rows[2].score, polars.null)
  eq(rows[2].note, polars.null)
  eq(rows[3].score, 30)
  df:close()

  local combined = polars.read_csv(path, {
    ignore_errors = true,
    columns = { "score", "id" },
    dtypes = { score = "i64" },
    n_rows = 3,
    rename_columns = { "points", "row_id" },
  })
  eq(table.concat(combined:columns(), ","), "points,row_id")
  rows = combined:to_table()
  eq(rows[2].row_id, 2)
  eq(rows[2].points, polars.null)
  eq(rows[3].points, 30)
  combined:close()
end)
test("lenient CSV options reject non-boolean values", function()
  for _, key in ipairs({ "truncate_ragged_lines", "ignore_errors" }) do
    for _, value in ipairs({ 1, 0, "true", {}, function() end }) do
      local ok, err = pcall(polars.read_csv, fixture, { [key] = value })
      eq(ok, false, key .. " accepted a non-boolean value")
      truthy(tostring(err):find(key, 1, true),
        "expected option name in: " .. tostring(err))
      truthy(tostring(err):find("boolean", 1, true),
        "expected boolean guidance in: " .. tostring(err))
    end
  end
  local df = polars.read_csv(fixture, {
    truncate_ragged_lines = false,
    ignore_errors = false,
  })
  eq(df:shape(), 5)
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

test("value_counts counts keys and sorts by count", function()
  local df = polars.read_csv(fixture)
  local counts = df:value_counts("team")
  eq(counts:shape(), 2)
  eq(table.concat(counts:columns(), ","), "team,count")
  local rows = counts:to_table()
  eq(rows[1].team, "red")
  eq(rows[1].count, 3)
  eq(rows[2].team, "blue")
  eq(rows[2].count, 2)
  counts:close()

  local pair = df:value_counts({ "team", "active" })
  eq(pair:shape(), 4)
  eq(table.concat(pair:columns(), ","), "team,active,count")
  rows = pair:to_table()
  local red_true = find_row(rows, { team = "red", active = true })
  eq(red_true.count, 2)
  eq(find_row(rows, { team = "red", active = false }).count, 1)
  eq(find_row(rows, { team = "blue", active = false }).count, 1)
  eq(find_row(rows, { team = "blue", active = true }).count, 1)
  pair:close()

  local renamed = df:value_counts("active", { name = "n" })
  eq(table.concat(renamed:columns(), ","), "active,n")
  rows = renamed:to_table()
  eq(rows[1].active, true)
  eq(rows[1].n, 3)
  renamed:close()
  df:close()
end)
test("value_counts supports unsorted output", function()
  local df = polars.read_csv(fixture)
  local counts = df:value_counts("team", { sort = false })
  eq(counts:shape(), 2)
  local rows = counts:to_table()
  eq(find_row(rows, { team = "red" }).count, 3)
  eq(find_row(rows, { team = "blue" }).count, 2)
  counts:close()
  df:close()
end)
test("value_counts rejects invalid columns and options", function()
  local df = polars.read_csv(fixture)
  local column_cases = {
    { nil, "columns must be a column name or a list of names" },
    { 42, "columns must be a column name or a list of names" },
    { {}, "columns must not be empty" },
    { { [1] = "team", [3] = "active" }, "contiguous list" },
    { { "team", "team" }, "duplicate value_counts column 'team'" },
    { { "missing" }, "is not a column in the DataFrame" },
  }
  for _, case in ipairs(column_cases) do
    local ok, err = pcall(function() df:value_counts(case[1]) end)
    eq(ok, false, "invalid value_counts columns accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  local option_cases = {
    { 42, "options must be a table" },
    { { sorted = true }, "unknown field 'sorted'" },
    { { sort = 1 }, "sort must be a boolean" },
    { { name = 42 }, "name must be a non-empty string" },
    { { name = "" }, "name must be a non-empty string" },
    { { name = "team" }, "collides with a grouping column" },
  }
  for _, case in ipairs(option_cases) do
    local ok, err = pcall(function()
      df:value_counts("team", case[1])
    end)
    eq(ok, false, "invalid value_counts options accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  df:close()
  local ok, err = pcall(function() df:value_counts("team") end)
  eq(ok, false, "closed value_counts accepted")
  truthy(tostring(err):find("closed", 1, true), "closed value_counts error")
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
local sample_parquet = root .. "/tests/fixtures/sample.parquet"
test("reads a Parquet file", function()
  local parquet = sample_parquet
  local f = io.open(parquet, "rb")
  if f == nil then
    error("sample.parquet is missing; run examples/make_parquet.rs")
  end
  f:close()
  local df = polars.read_parquet(parquet)
  eq(df:shape(), 5)
  df:close()
end)
test("Parquet reader projects columns in the requested order", function()
  local df = polars.read_parquet(sample_parquet, {
    columns = { "score", "name" },
  })
  eq(df:shape(), 5)
  eq(table.concat(df:columns(), ","), "score,name")
  eq(df:schema().score, "i64")
  eq(df:schema().name, "str")
  local rows = df:to_table()
  eq(rows[1].name, "ana")
  eq(rows[1].score, 10)
  df:close()

  local single = polars.read_parquet(sample_parquet, { columns = "team" })
  eq(table.concat(single:columns(), ","), "team")
  eq(select(2, single:shape()), 1)
  single:close()
end)
test("Parquet reader applies a row window", function()
  local df = polars.read_parquet(sample_parquet, { skip_rows = 1, n_rows = 2 })
  eq(df:shape(), 2)
  local rows = df:to_table()
  eq(rows[1].name, "bia")
  eq(rows[1].score, 7)
  eq(rows[2].name, "caio")
  eq(rows[2].score, 12)
  df:close()

  local limited = polars.read_parquet(sample_parquet, {
    columns = { "name", "score" },
    skip_rows = 2,
    n_rows = 2,
  })
  eq(limited:shape(), 2)
  eq(table.concat(limited:columns(), ","), "name,score")
  eq(limited:to_table()[2].name, "duda")
  limited:close()

  local empty = polars.read_parquet(sample_parquet, { n_rows = 0 })
  eq(empty:shape(), 0)
  eq(#empty:columns(), 4)
  empty:close()

  local past = polars.read_parquet(sample_parquet, {
    skip_rows = 99,
    n_rows = 2,
  })
  eq(past:shape(), 0)
  eq(#past:columns(), 4)
  past:close()
end)
test("Parquet reader rejects malformed options", function()
  local cases = {
    { 42, "options must be a table" },
    { { rows = 1 }, "unknown field 'rows'" },
    { { columns = {} }, "must not be empty" },
    { { columns = 42 }, "columns must be" },
    { { columns = { 42 } }, "entries must be" },
    { { columns = { "" } }, "entries must be" },
    { { columns = { "name", "name" } }, "duplicate" },
    { { columns = { "missing" } }, "missing" },
    { { skip_rows = -1 }, "skip_rows must be" },
    { { skip_rows = 1.5 }, "skip_rows must be" },
    { { skip_rows = "1" }, "skip_rows must be" },
    { { n_rows = -1 }, "n_rows must be" },
    { { n_rows = 1.5 }, "n_rows must be" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(polars.read_parquet, sample_parquet, case[1])
    eq(ok, false, "invalid Parquet reader options accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
end)
test("missing Parquet file is an error", function()
  local ok, err = pcall(polars.read_parquet,
    root .. "/tests/fixtures/missing.parquet")
  eq(ok, false)
  truthy(tostring(err):find("No such file") or tostring(err):find("os error"),
    "missing Parquet file error")
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
test("Parquet writer accepts every compression codec", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".parquet")
  for _, codec in ipairs({
    "zstd", "snappy", "gzip", "brotli", "lz4", "uncompressed",
  }) do
    eq(df:write_parquet(out, { compression = codec }), df,
      codec .. " return value")
    local loaded = polars.read_parquet(out)
    check_roundtrip_frame(loaded)
    loaded:close()
  end
  for _, alias in ipairs({ "ZSTD", "lz4-raw", "None" }) do
    df:write_parquet(out, { compression = alias })
    local loaded = polars.read_parquet(out)
    check_roundtrip_frame(loaded)
    loaded:close()
  end
  df:close()
end)
test("Parquet writer options control statistics and chunk sizes", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".parquet")
  eq(df:write_parquet(out, {
    compression = "snappy",
    statistics = false,
    row_group_size = 1,
    data_page_size = 64,
  }), df, "write_parquet options return value")
  local loaded = polars.read_parquet(out)
  check_roundtrip_frame(loaded)
  loaded:close()

  df:write_parquet(out, {
    statistics = true,
    row_group_size = 3,
    data_page_size = 4096,
  })
  loaded = polars.read_parquet(out)
  check_roundtrip_frame(loaded)
  loaded:close()
  df:close()
end)
test("Parquet writer rejects malformed options", function()
  local df = polars.read_csv(roundtrip_fixture)
  local cases = {
    { 42, "options must be a table" },
    { { level = 3 }, "unknown field 'level'" },
    { { compression = 42 }, "compression must be" },
    { { compression = "" }, "compression must be" },
    { { compression = "lzo" }, "compression must be one of" },
    { { statistics = 0 }, "statistics must be a boolean" },
    { { row_group_size = 0 }, "row_group_size must be a positive integer" },
    { { row_group_size = -1 }, "row_group_size must be a positive integer" },
    { { row_group_size = 1.5 }, "row_group_size must be a positive integer" },
    { { row_group_size = "2" }, "row_group_size must be a positive integer" },
    { { data_page_size = 0 }, "data_page_size must be a positive integer" },
    { { data_page_size = 1.5 }, "data_page_size must be a positive integer" },
  }
  for _, case in ipairs(cases) do
    local out = new_temp_path(".parquet")
    local ok, err = pcall(function() df:write_parquet(out, case[1]) end)
    eq(ok, false, "invalid Parquet writer options accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  df:close()
end)
test("Parquet writer options reject closed frames and bad paths", function()
  local df = polars.read_csv(roundtrip_fixture)
  df:close()
  local ok, err = pcall(function()
    df:write_parquet(new_temp_path(".parquet"), { compression = "snappy" })
  end)
  eq(ok, false)
  truthy(tostring(err):find("closed"), "closed-frame error")

  local live = polars.read_csv(roundtrip_fixture)
  ok, err = pcall(function()
    live:write_parquet(root .. "/tests/fixtures/missing-dir/out.parquet",
      { compression = "snappy" })
  end)
  eq(ok, false)
  truthy(tostring(err):find("No such file") or tostring(err):find("os error"),
    "filesystem error")
  live:close()
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
test("CSV writer null placeholder reads back as null with null_values", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".csv")
  df:write_csv(out, { null_value = "NA" })

  local literal = polars.read_csv(out)
  eq(find_row(literal:to_table(), { id = 3 }).note, "NA")
  literal:close()

  local nulled = polars.read_csv(out, { null_values = "NA" })
  eq(find_row(nulled:to_table(), { id = 3 }).note, polars.null)
  eq(find_row(nulled:to_table(), { id = 1 }).note, "hello, world")
  nulled:close()
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
test("CSV writer line_terminator writes CRLF records", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".csv")
  eq(df:write_csv(out, { line_terminator = "\r\n" }), df,
    "write_csv CRLF return value")
  local raw = read_file(out)
  truthy(raw:find("id,name,note\r\n", 1, true), "CRLF header")
  truthy(raw:find("3,caio,\r\n", 1, true), "CRLF null record")
  local bare = raw:gsub("\r\n", "")
  truthy(not bare:find("\r", 1, true) and not bare:find("\n", 1, true),
    "lone record separator in CRLF output")
  local loaded = polars.read_csv(out)
  check_roundtrip_frame(loaded)
  loaded:close()
  df:close()
end)
test("CSV writer line_terminator combines with delimiter, header, and null_value", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".csv")
  df:write_csv(out, {
    delimiter = ";",
    header = false,
    null_value = "NA",
    line_terminator = "\r\n",
  })
  local raw = read_file(out)
  truthy(raw:find("1;ana;hello, world\r\n", 1, true),
    "CRLF quoted record")
  truthy(raw:find("3;caio;NA\r\n", 1, true), "CRLF null placeholder")
  truthy(not raw:gsub("\r\n", ""):find("[\r\n]"),
    "lone record separator in combined CRLF output")
  local loaded = polars.read_csv(out, { delimiter = ";", header = false })
  eq(loaded:shape(), 3)
  local rows = loaded:to_table()
  eq(rows[1].column_2, "ana")
  eq(rows[3].column_3, "NA")
  loaded:close()
  df:close()
end)
test("CSV writer quote_style controls quoting", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".csv")
  eq(df:write_csv(out, { quote_style = "always" }), df,
    "always quote_style return value")
  local raw = read_file(out)
  truthy(raw:find('"id","name","note"\n', 1, true), "always header")
  truthy(raw:find('"1","ana","hello, world"\n', 1, true),
    "always quoted string record")
  local loaded = polars.read_csv(out)
  eq(loaded:shape(), 3)
  local always_rows = loaded:to_table()
  eq(find_row(always_rows, { id = 1 }).note, "hello, world")
  -- QuoteStyle.Always writes the empty null as `""`, which Polars reads back as
  -- an empty string rather than null; use a null_value to preserve nulls.
  eq(find_row(always_rows, { id = 3 }).note, "")
  loaded:close()

  df:write_csv(out, { quote_style = "non_numeric" })
  raw = read_file(out)
  truthy(raw:find('"id","name","note"\n', 1, true),
    "non_numeric quoted header")
  truthy(raw:find('1,"ana","hello, world"\n', 1, true),
    "non_numeric quoted strings")
  truthy(raw:find('3,"caio",\n', 1, true), "non_numeric empty null")
  loaded = polars.read_csv(out)
  check_roundtrip_frame(loaded)
  loaded:close()

  df:write_csv(out, { quote_style = "never" })
  raw = read_file(out)
  truthy(raw:find("id,name,note\n", 1, true), "never unquoted header")
  truthy(raw:find('1,ana,hello, world\n', 1, true),
    "never unquoted comma field")
  truthy(raw:find('2,bia,say "hi"\n', 1, true),
    "never preserves literal quotes in data")
  df:write_csv(out, { quote_style = "NECESSARY" })
  raw = read_file(out)
  truthy(raw:find("id,name,note\n", 1, true), "necessary header")
  truthy(raw:find('1,ana,"hello, world"\n', 1, true),
    "necessary quoted string record")
  df:close()
end)
test("CSV writer quote_style combines with other writer options", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".csv")
  df:write_csv(out, {
    delimiter = ";",
    header = false,
    null_value = "NA",
    line_terminator = "\r\n",
    quote_style = "always",
  })
  local raw = read_file(out)
  truthy(raw:find('"1";"ana";"hello, world"\r\n', 1, true),
    "always combined string record")
  truthy(raw:find('"3";"caio";"NA"\r\n', 1, true),
    "always combined null record")
  local loaded = polars.read_csv(out, { delimiter = ";", header = false })
  eq(loaded:shape(), 3)
  local rows = loaded:to_table()
  eq(rows[1].column_2, "ana")
  eq(rows[3].column_3, "NA")
  loaded:close()
  df:close()
end)
test("CSV writer float_precision controls float digits", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("id,ratio\n1,1.23456\n2,2.5\n3,3.14159\n")
  file:close()
  local df = polars.read_csv(path)
  eq(df:schema().ratio, "f64")
  local out = new_temp_path(".csv")

  eq(df:write_csv(out, { float_precision = 2 }), df,
    "float_precision return value")
  local raw = read_file(out)
  truthy(raw:find("1,1.23\n", 1, true), "two-digit first row")
  truthy(raw:find("2,2.50\n", 1, true), "two-digit padding")
  truthy(raw:find("3,3.14\n", 1, true), "two-digit rounding")
  local loaded = polars.read_csv(out)
  eq(loaded:schema().ratio, "f64")
  eq(loaded:to_table()[2].ratio, 2.5)
  loaded:close()

  df:write_csv(out, { float_precision = 0 })
  raw = read_file(out)
  truthy(raw:find("1,1\n", 1, true), "zero-digit first row")
  truthy(raw:find("2,2\n", 1, true), "zero-digit rounding")
  truthy(raw:find("3,3\n", 1, true), "zero-digit third row")

  df:write_csv(out, { float_precision = 6 })
  raw = read_file(out)
  truthy(raw:find("1,1.234560\n", 1, true), "six-digit padding")

  df:write_csv(out, {
    delimiter = ";",
    header = false,
    line_terminator = "\r\n",
    quote_style = "always",
    float_precision = 1,
  })
  raw = read_file(out)
  truthy(raw:find('"1";"1.2"\r\n', 1, true),
    "precision combined with writer options")
  truthy(raw:find('"3";"3.1"\r\n', 1, true),
    "precision combined rounding")
  loaded = polars.read_csv(out, {
    delimiter = ";",
    header = false,
    rename_columns = { "id", "ratio" },
  })
  eq(loaded:shape(), 3)
  eq(loaded:to_table()[1].ratio, 1.2)
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
    { { quote_style = 42 }, "quote_style must be a non-empty string" },
    { { quote_style = "" }, "quote_style must be a non-empty string" },
    { { quote_style = "sometimes" }, "quote_style must be one of" },
    { { float_precision = -1 }, "float_precision must be a non-negative integer" },
    { { float_precision = 1.5 }, "float_precision must be a non-negative integer" },
    { { float_precision = "2" }, "float_precision must be a non-negative integer" },
    { { float_precision = true }, "float_precision must be a non-negative integer" },
    { { float_precision = math.huge }, "float_precision must be a non-negative integer" },
    { { float_precision = 2 ^ 53 }, "float_precision must be a non-negative integer" },
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
    { { line_terminator = 42 }, "line_terminator must be a string" },
    { { line_terminator = "" }, "line_terminator" },
    { { line_terminator = "\r" }, "line_terminator" },
    { { line_terminator = "\n\n" }, "line_terminator" },
    { { line_terminator = "x" }, "line_terminator" },
    { { line_terminator = "\0" }, "line_terminator" },
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

current = "json io"
local json_array_fixture = root .. "/tests/fixtures/sample.json"
local json_lines_fixture = root .. "/tests/fixtures/sample.jsonl"
test("read_json reads a JSON array and infers the schema", function()
  local df = polars.read_json(json_array_fixture)
  eq(df:shape(), 3)
  eq(table.concat(df:columns(), ","), "id,name,score,active")
  local schema = df:schema()
  eq(schema.id, "i64")
  eq(schema.name, "str")
  eq(schema.score, "i64")
  eq(schema.active, "bool")
  local rows = df:to_table()
  eq(rows[1].id, 1)
  eq(rows[1].name, "ana")
  eq(rows[1].active, true)
  eq(rows[3].name, "caio")
  eq(rows[3].score, 12)
  df:close()
end)
test("read_json reads JSON Lines with aliases", function()
  local df = polars.read_json(json_lines_fixture, { format = "lines" })
  eq(df:shape(), 3)
  eq(df:to_table()[2].name, "bia")
  df:close()
  local alias = polars.read_json(json_lines_fixture, { format = "NDJSON" })
  eq(alias:shape(), 3)
  eq(alias:to_table()[3].score, 12)
  alias:close()
  local json_alias = polars.read_json(json_array_fixture, { format = "json" })
  eq(json_alias:shape(), 3)
  json_alias:close()
end)
test("read_json projects columns in the requested order", function()
  local df = polars.read_json(json_array_fixture, {
    columns = { "score", "name" },
  })
  eq(df:shape(), 3)
  eq(table.concat(df:columns(), ","), "score,name")
  local rows = df:to_table()
  eq(rows[1].score, 10)
  eq(rows[1].name, "ana")
  eq(rows[1].id, nil)
  eq(rows[3].score, 12)
  df:close()

  local single = polars.read_json(json_lines_fixture, {
    format = "lines",
    columns = "name",
  })
  eq(table.concat(single:columns(), ","), "name")
  eq(single:to_table()[1].name, "ana")
  single:close()
end)
test("read_json rejects malformed options, missing files, and invalid JSON", function()
  local cases = {
    { { format = 42 }, "format must be a non-empty string" },
    { { format = "" }, "format must be a non-empty string" },
    { { format = "xml" }, "format must be 'array' or 'lines'" },
    { { columns = {} }, "columns must not be empty" },
    { { columns = 42 }, "columns must be a column name or a list" },
    { { columns = { 42 } }, "entries must be non-empty strings" },
    { { columns = { "name", "name" } }, "duplicate" },
    { { columns = { "missing" } }, "missing" },
    { { rows = 1 }, "unknown field 'rows'" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(polars.read_json, json_array_fixture, case[1])
    eq(ok, false, "invalid read_json options accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  local ok, err = pcall(polars.read_json, 42)
  eq(ok, false, "non-string read_json path accepted")
  truthy(tostring(err):find("path", 1, true), "read_json path error")

  ok, err = pcall(polars.read_json, root .. "/tests/fixtures/missing.json")
  eq(ok, false, "missing JSON file accepted")
  truthy(tostring(err):find("No such file") or tostring(err):find("os error"),
    "missing JSON file error")

  local malformed = new_temp_path(".json")
  local file = assert(io.open(malformed, "w"))
  file:write('{"id": 1')
  file:close()
  ok, err = pcall(polars.read_json, malformed)
  eq(ok, false, "malformed JSON accepted")
  truthy(tostring(err):find("JSON", 1, true) or
    tostring(err):find("json", 1, true) or
    tostring(err):find("Syntax", 1, true) or
    tostring(err):find("EOF", 1, true), "malformed JSON error: " .. tostring(err))
end)
test("write_json writes an array that read_json round-trips", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".json")
  eq(df:write_json(out), df, "write_json return value")
  local raw = read_file(out)
  truthy(raw:find("^%s*%["), "JSON array output")
  truthy(raw:find('"id"', 1, true), "JSON column name")
  local loaded = polars.read_json(out)
  eq(loaded:shape(), 3)
  eq(table.concat(loaded:columns(), ","), "id,name,note")
  local rows = loaded:to_table()
  eq(find_row(rows, { id = 1 }).note, "hello, world")
  eq(find_row(rows, { id = 2 }).note, 'say "hi"')
  eq(find_row(rows, { id = 3 }).note, polars.null)
  loaded:close()
  df:close()
end)
test("write_json writes JSON Lines with aliases", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".jsonl")
  df:write_json(out, { format = "lines" })
  local raw = read_file(out)
  truthy(raw:find("^%s*%{"), "JSON Lines output starts with an object")
  truthy(not raw:find("%[", 1), "JSON Lines output has an array bracket")
  local loaded = polars.read_json(out, { format = "lines" })
  eq(loaded:shape(), 3)
  eq(find_row(loaded:to_table(), { id = 3 }).note, polars.null)
  loaded:close()
  df:write_json(out, { format = "ndjson" })
  loaded = polars.read_json(out, { format = "jsonl" })
  eq(loaded:shape(), 3)
  loaded:close()
  df:close()
end)
test("write_json rejects malformed options and failures", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".json")
  local cases = {
    { 42, "options must be a table" },
    { { rows = 1 }, "unknown field 'rows'" },
    { { format = 42 }, "format must be a non-empty string" },
    { { format = "" }, "format must be a non-empty string" },
    { { format = "xml" }, "format must be 'array' or 'lines'" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function() df:write_json(out, case[1]) end)
    eq(ok, false, "invalid write_json options accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  local ok, err = pcall(function() df:write_json("") end)
  eq(ok, false, "empty write_json path accepted")
  truthy(tostring(err):find("path must be a string", 1, true),
    "write_json path error")
  ok, err = pcall(function()
    df:write_json(temp_path() .. "/missing/out.json")
  end)
  eq(ok, false, "missing JSON directory accepted")
  truthy(tostring(err):find("No such file") or tostring(err):find("os error"),
    "write_json filesystem error")
  df:close()
  ok, err = pcall(function() df:write_json(out) end)
  eq(ok, false, "closed write_json accepted")
  truthy(tostring(err):find("closed", 1, true), "write_json closed-frame error")
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

current = "dataframe transforms"
test("reverse returns rows in reverse order", function()
  local df = polars.read_csv(fixture)
  local reversed = df:reverse()
  eq(reversed:shape(), 5)
  eq(table.concat(reversed:columns(), ","), "name,team,score,active")
  local rows = reversed:to_table()
  eq(rows[1].name, "eva")
  eq(rows[1].score, 9)
  eq(rows[5].name, "ana")
  eq(rows[5].score, 10)
  eq(df:to_table()[1].name, "ana", "reverse must not change the input")
  reversed:close()

  local empty = df:head(0):reverse()
  eq(empty:shape(), 0)
  eq(#empty:columns(), 4)
  empty:close()
  df:close()
  local ok, err = pcall(function() df:reverse() end)
  eq(ok, false, "closed reverse accepted")
  truthy(tostring(err):find("closed", 1, true), "reverse closed-frame error")
end)

test("cast changes selected dtypes and preserves column order", function()
  local df = polars.read_csv(fixture)
  local casted = df:cast({ score = "f64", active = "str" })
  local schema = casted:schema()
  eq(schema.score, "f64")
  eq(schema.active, "str")
  eq(schema.name, "str")
  eq(table.concat(casted:columns(), ","), table.concat(df:columns(), ","))
  local rows = casted:to_table()
  eq(rows[1].score, 10)
  eq(rows[1].active, "true")
  eq(rows[3].active, "false")
  casted:close()

  local text = df:cast({ score = "str" })
  eq(text:schema().score, "str")
  eq(text:to_table()[1].score, "10")
  text:close()

  local narrow = df:cast({ score = "i32" })
  eq(narrow:schema().score, "i32")
  eq(narrow:to_table()[1].score, 10)
  narrow:close()
  eq(df:schema().score, "i64", "cast must not change the input")
  df:close()
end)

test("cast rejects invalid mappings and conversions", function()
  local df = polars.read_csv(fixture)
  local cases = {
    { 42, "cast expects a table" },
    { {}, "cast requires at least one column" },
    { { [1] = "f64" }, "keys must be non-empty column names" },
    { { score = 42 }, "cast dtypes must be non-empty dtype names" },
    { { score = "" }, "cast dtypes must be non-empty dtype names" },
    { { score = "blob" }, "unsupported cast dtype" },
    { { missing = "f64" }, "not a column in the DataFrame" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function() df:cast(case[1]) end)
    eq(ok, false, "invalid cast mapping accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  local ok, err = pcall(function() df:cast({ name = "i64" }) end)
  eq(ok, false, "unparsable cast accepted")
  truthy(tostring(err):find("could not cast", 1, true),
    "cast conversion error: " .. tostring(err))
  df:close()
  ok, err = pcall(function() df:cast({ score = "f64" }) end)
  eq(ok, false, "closed cast accepted")
  truthy(tostring(err):find("closed", 1, true), "cast closed-frame error")
end)

test("unique supports a column subset and keep strategies", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("id,name\n1,ana\n2,bia\n1,ana\n1,last\n2,bia\n3,caio\n")
  file:close()
  local df = polars.read_csv(path)
  eq(df:shape(), 6)

  local all = df:unique()
  eq(all:shape(), 4)
  all:close()

  local by_id = df:unique("id")
  eq(by_id:shape(), 3)
  local rows = by_id:to_table()
  eq(rows[1].id, 1)
  eq(rows[1].name, "ana")
  eq(rows[2].id, 2)
  eq(rows[3].id, 3)
  by_id:close()

  local last = df:unique("id", { keep = "LAST" })
  eq(last:shape(), 3)
  eq(find_row(last:to_table(), { id = 1 }).name, "last")
  eq(find_row(last:to_table(), { id = 2 }).name, "bia")
  last:close()

  local none = df:unique("id", { keep = "none" })
  eq(none:shape(), 1)
  eq(none:to_table()[1].id, 3)
  none:close()

  local unordered = df:unique("id", {
    keep = "any",
    maintain_order = false,
  })
  eq(unordered:shape(), 3)
  unordered:close()

  local pair = df:unique({ "id", "name" })
  eq(pair:shape(), 4)
  pair:close()
  df:close()
end)

test("unique rejects invalid columns, keep strategies, and options", function()
  local df = polars.read_csv(fixture)
  local cases = {
    { 42, nil, "columns must be a column name or a list of names" },
    { {}, nil, "columns must not be empty" },
    { { [1] = "name", [3] = "score" }, nil, "contiguous list" },
    { { "name", "name" }, nil, "duplicate unique column 'name'" },
    { "missing", nil, "is not a column in the DataFrame" },
    { "name", "first", "unique options must be a table" },
    { "name", { keep = 42 }, "unique keep must be a non-empty string" },
    { "name", { keep = "" }, "unique keep must be a non-empty string" },
    { "name", { keep = "middle" }, "unique keep must be one of" },
    { "name", { maintain_order = 1 }, "unique maintain_order must be a boolean" },
    { "name", { sort = true }, "unknown field 'sort'" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function() df:unique(case[1], case[2]) end)
    eq(ok, false, "invalid unique arguments accepted")
    truthy(tostring(err):find(case[3], 1, true),
      "expected '" .. case[3] .. "' in: " .. tostring(err))
  end
  df:close()
  local ok, err = pcall(function() df:unique() end)
  eq(ok, false, "closed unique accepted")
  truthy(tostring(err):find("closed", 1, true), "unique closed-frame error")
end)

test("explode flattens list columns and handles nulls", function()
  local path = new_temp_path(".json")
  local file = assert(io.open(path, "w"))
  file:write('[{"id":1,"tag":["a","b"]},' ..
    '{"id":2,"tag":[]},{"id":3,"tag":null},' ..
    '{"id":4,"tag":["c"]}]')
  file:close()
  local df = polars.read_json(path)
  eq(df:schema().tag, "list[str]")

  local exploded = df:explode("tag")
  eq(exploded:shape(), 5)
  eq(table.concat(exploded:columns(), ","), "id,tag")
  local rows = exploded:to_table()
  eq(rows[1].id, 1)
  eq(rows[1].tag, "a")
  eq(rows[2].id, 1)
  eq(rows[2].tag, "b")
  eq(find_row(rows, { id = 2 }).tag, polars.null)
  eq(find_row(rows, { id = 3 }).tag, polars.null)
  eq(find_row(rows, { id = 4 }).tag, "c")
  exploded:close()

  local empty_dropped = df:explode("tag", { empty_as_null = false })
  eq(empty_dropped:shape(), 4)
  for _, row in ipairs(empty_dropped:to_table()) do
    truthy(row.id ~= 2, "empty list should be dropped")
  end
  empty_dropped:close()

  local null_dropped = df:explode("tag", { keep_nulls = false })
  eq(null_dropped:shape(), 4)
  for _, row in ipairs(null_dropped:to_table()) do
    truthy(row.id ~= 3, "null list should be dropped")
  end
  null_dropped:close()

  local listed = df:explode({ "tag" })
  eq(listed:shape(), 5)
  listed:close()
  df:close()
end)

test("explode rejects non-list columns and malformed options", function()
  local path = new_temp_path(".json")
  local file = assert(io.open(path, "w"))
  file:write('[{"id":1,"tag":["a"]},{"id":2,"tag":["b"]}]')
  file:close()
  local df = polars.read_json(path)
  local cases = {
    { nil, nil, "columns must be a column name or a list of names" },
    { {}, nil, "columns must not be empty" },
    { { "tag", "tag" }, nil, "duplicate explode column 'tag'" },
    { "missing", nil, "is not a column in the DataFrame" },
    { "id", nil, "expected a list" },
    { "tag", "yes", "explode options must be a table" },
    { "tag", { keep_nulls = 1 }, "keep_nulls must be a boolean" },
    { "tag", { empty_as_null = "yes" }, "empty_as_null must be a boolean" },
    { "tag", { flatten = true }, "unknown field 'flatten'" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function() df:explode(case[1], case[2]) end)
    eq(ok, false, "invalid explode arguments accepted")
    truthy(tostring(err):find(case[3], 1, true),
      "expected '" .. case[3] .. "' in: " .. tostring(err))
  end
  df:close()
  local ok, err = pcall(function() df:explode("tag") end)
  eq(ok, false, "closed explode accepted")
  truthy(tostring(err):find("closed", 1, true), "explode closed-frame error")
end)

test("read_csv skips rows after the header and composes with n_rows", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("metadata\nid,value\n1,10\n2,20\n3,30\n4,40\n")
  file:close()

  local window = polars.read_csv(path, {
    skip_rows = 1,
    skip_rows_after_header = 1,
    n_rows = 2,
  })
  eq(window:shape(), 2)
  eq(window:schema().id, "i64")
  local rows = window:to_table()
  eq(rows[1].id, 2)
  eq(rows[1].value, 20)
  eq(rows[2].id, 3)
  eq(rows[2].value, 30)
  window:close()

  local tail = polars.read_csv(path, {
    skip_rows = 1,
    skip_rows_after_header = 3,
  })
  eq(tail:shape(), 1)
  eq(tail:to_table()[1].id, 4)
  tail:close()

  local unchanged = polars.read_csv(path, {
    skip_rows = 1,
    skip_rows_after_header = 0,
  })
  eq(unchanged:shape(), 4)
  unchanged:close()

  local headerless_path = new_temp_path(".csv")
  local headerless_file = assert(io.open(headerless_path, "w"))
  headerless_file:write("1,10\n2,20\n3,30\n")
  headerless_file:close()
  local headerless = polars.read_csv(headerless_path, {
    header = false,
    skip_rows_after_header = 1,
  })
  eq(headerless:shape(), 2)
  eq(headerless:to_table()[1].column_1, 2)
  headerless:close()
end)

test("read_csv decimal_comma parses comma decimals", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("id;price\n1;1,5\n2;2,25\n3;3,75\n")
  file:close()

  local df = polars.read_csv(path, {
    delimiter = ";",
    decimal_comma = true,
  })
  eq(df:schema().price, "f64")
  local rows = df:to_table()
  eq(rows[1].price, 1.5)
  eq(rows[2].price, 2.25)
  eq(rows[3].price, 3.75)
  df:close()

  local combined = polars.read_csv(path, {
    delimiter = ";",
    decimal_comma = true,
    columns = { "price" },
    skip_rows_after_header = 1,
    n_rows = 1,
  })
  eq(combined:shape(), 1)
  eq(table.concat(combined:columns(), ","), "price")
  eq(combined:to_table()[1].price, 2.25)
  combined:close()

  local plain = polars.read_csv(path, { delimiter = ";" })
  eq(plain:schema().price, "str")
  eq(plain:to_table()[1].price, "1,5")
  plain:close()
end)

test("read_csv rejects invalid extended dialect options", function()
  local cases = {
    { { skip_rows_after_header = -1 },
      "skip_rows_after_header must be a non-negative integer" },
    { { skip_rows_after_header = 1.5 },
      "skip_rows_after_header must be a non-negative integer" },
    { { skip_rows_after_header = "2" },
      "skip_rows_after_header must be a non-negative integer" },
    { { skip_rows_after_header = true },
      "skip_rows_after_header must be a non-negative integer" },
    { { skip_rows_after_header = math.huge },
      "skip_rows_after_header must be a non-negative integer" },
    { { skip_rows_after_header = 2 ^ 53 },
      "skip_rows_after_header must be a non-negative integer" },
    { { decimal_comma = 1 }, "decimal_comma must be a boolean" },
    { { decimal_comma = "yes" }, "decimal_comma must be a boolean" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(polars.read_csv, fixture, case[1])
    eq(ok, false, "invalid extended CSV option accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
end)

test("fill_nan replaces NaN values and preserves nulls", function()
  local source = polars.read_csv(fixture)
  local df = source:sql([[
    SELECT "score",
           CASE WHEN "score" = 7 THEN NULL
                WHEN "score" = 10 THEN 0.0 / 0.0
                ELSE CAST("score" AS DOUBLE) END AS "x"
    FROM df
  ]])
  local filled = df:fill_nan(2.5)
  eq(filled:schema().x, "f64")
  eq(table.concat(filled:columns(), ","), "score,x")
  local rows = filled:to_table()
  eq(rows[1].score, 10)
  eq(rows[1].x, 2.5)
  eq(rows[2].score, 7)
  eq(rows[2].x, polars.null)
  eq(rows[3].x, 12)
  local out = new_temp_path(".csv")
  df:write_csv(out)
  truthy(read_file(out):find(",NaN\n", 1, true),
    "fill_nan changed the input frame")
  filled:close()
  df:close()
  source:close()
end)

test("fill_nan scopes columns and rejects invalid values", function()
  local source = polars.read_csv(fixture)
  local df = source:sql([[
    SELECT "score",
           CASE WHEN "score" = 10 THEN 0.0 / 0.0
                ELSE CAST("score" AS DOUBLE) END AS "x",
           CASE WHEN "score" = 10 THEN 0.0 / 0.0
                ELSE CAST("score" AS DOUBLE) END AS "y"
    FROM df
  ]])
  local filled = df:fill_nan(3, "x")
  local out = new_temp_path(".csv")
  filled:write_csv(out)
  local raw = read_file(out)
  local x_value, y_value = raw:match("\n10,([^,\n]+),([^\n]+)")
  truthy(x_value ~= nil, "missing first data row in fill_nan output")
  eq(tonumber(x_value), 3)
  eq(y_value, "NaN", "unselected column changed")

  local untouched = df:fill_nan(1, "score")
  eq(untouched:to_table()[1].score, 10, "non-float column changed")
  untouched:close()

  local text_only = source:sql('SELECT "name", "team" FROM df')
  local unchanged = text_only:fill_nan(1)
  eq(unchanged:shape(), text_only:shape())
  eq(table.concat(unchanged:columns(), ","), "name,team")
  unchanged:close()
  text_only:close()

  local value_cases = {
    { "2", "finite number" },
    { 0 / 0, "finite number" },
    { math.huge, "finite number" },
    { -math.huge, "finite number" },
    { true, "finite number" },
    { {}, "finite number" },
  }
  for _, case in ipairs(value_cases) do
    local ok, err = pcall(function() df:fill_nan(case[1]) end)
    eq(ok, false, "invalid fill_nan value accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  local subset_cases = {
    { 42, "columns must be a column name or a list of names" },
    { {}, "columns must not be empty" },
    { { [1] = "score", [3] = "x" }, "contiguous list" },
    { { "score", "score" }, "duplicate fill_nan column 'score'" },
    { { "missing" }, "is not a column in the DataFrame" },
  }
  for _, case in ipairs(subset_cases) do
    local ok, err = pcall(function() df:fill_nan(0, case[1]) end)
    eq(ok, false, "invalid fill_nan subset accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  filled:close()
  df:close()
  source:close()
  local ok, err = pcall(function() df:fill_nan(0) end)
  eq(ok, false, "closed fill_nan accepted")
  truthy(tostring(err):find("closed", 1, true), "closed fill_nan error")
end)

test("drop_nans removes NaN rows and keeps nulls", function()
  local source = polars.read_csv(fixture)
  local df = source:sql([[
    SELECT "score",
           CASE WHEN "score" = 7 THEN NULL
                WHEN "score" = 10 THEN 0.0 / 0.0
                ELSE CAST("score" AS DOUBLE) END AS "x"
    FROM df
  ]])
  local dropped = df:drop_nans()
  eq(dropped:shape(), 4)
  eq(dropped:schema().x, "f64")
  local rows = dropped:to_table()
  eq(rows[1].score, 7)
  eq(rows[1].x, polars.null, "null row was dropped")
  eq(rows[2].score, 12)
  dropped:close()

  local pair = source:sql([[
    SELECT "score",
           CASE WHEN "score" = 10 THEN 0.0 / 0.0
                ELSE CAST("score" AS DOUBLE) END AS "x",
           CASE WHEN "score" = 7 THEN 0.0 / 0.0
                ELSE CAST("score" AS DOUBLE) END AS "y"
    FROM df
  ]])
  local by_x = pair:drop_nans("x")
  eq(by_x:shape(), 4)
  eq(by_x:to_table()[1].score, 7,
    "subset should ignore NaN in an unselected column")
  by_x:close()

  local both = pair:drop_nans({ "x", "y" })
  eq(both:shape(), 3)
  eq(both:to_table()[1].score, 12)
  both:close()

  local by_score = pair:drop_nans("score")
  eq(by_score:shape(), 5, "non-float subset should keep every row")
  by_score:close()

  local text_only = source:sql('SELECT "name", "team" FROM df')
  local unchanged = text_only:drop_nans()
  eq(unchanged:shape(), text_only:shape())
  unchanged:close()
  text_only:close()
  pair:close()
  df:close()
  source:close()
end)

test("drop_nans rejects invalid subsets", function()
  local df = polars.read_csv(fixture)
  local cases = {
    { 42, "columns must be a column name or a list of names" },
    { true, "columns must be a column name or a list of names" },
    { {}, "columns must not be empty" },
    { { [1] = "name", [3] = "score" }, "contiguous list" },
    { { "" }, "entries must be non-empty strings" },
    { { 42 }, "entries must be non-empty strings" },
    { { "name", "name" }, "duplicate drop_nans column 'name'" },
    { { "missing" }, "is not a column in the DataFrame" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function() df:drop_nans(case[1]) end)
    eq(ok, false, "invalid drop_nans subset accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  df:close()
  local ok, err = pcall(function() df:drop_nans() end)
  eq(ok, false, "closed drop_nans accepted")
  truthy(tostring(err):find("closed", 1, true), "closed drop_nans error")
end)

test("read_csv raise_if_empty allows an empty file", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:close()

  local ok, err = pcall(polars.read_csv, path)
  eq(ok, false, "empty CSV accepted by default")
  truthy(tostring(err):lower():find("empty", 1, true),
    "empty CSV error: " .. tostring(err))

  local df = polars.read_csv(path, { raise_if_empty = false })
  eq(df:shape(), 0)
  eq(#df:columns(), 0)
  df:close()

  local custom = polars.read_csv(path, {
    raise_if_empty = false,
    delimiter = ";",
  })
  eq(custom:shape(), 0)
  custom:close()

  local header_path = new_temp_path(".csv")
  local header_file = assert(io.open(header_path, "w"))
  header_file:write("id,name\n")
  header_file:close()
  local headed = polars.read_csv(header_path, { raise_if_empty = false })
  eq(headed:shape(), 0)
  eq(table.concat(headed:columns(), ","), "id,name")
  headed:close()

  ok, err = pcall(polars.read_csv, path, { raise_if_empty = true })
  eq(ok, false, "explicit raise_if_empty = true accepted an empty file")
  truthy(tostring(err):lower():find("empty", 1, true),
    "explicit empty CSV error: " .. tostring(err))
end)

test("read_csv raise_if_empty rejects non-booleans and keeps parse errors", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("a,b\n1,2\n3,4,5\n")
  file:close()
  for _, value in ipairs({ 1, 0, "false", {}, function() end }) do
    local ok, err = pcall(polars.read_csv, path, { raise_if_empty = value })
    eq(ok, false, "invalid raise_if_empty accepted")
    truthy(tostring(err):find("raise_if_empty", 1, true),
      "raise_if_empty option name: " .. tostring(err))
    truthy(tostring(err):find("boolean", 1, true),
      "raise_if_empty boolean guidance: " .. tostring(err))
  end
  local ok, err = pcall(polars.read_csv, path, { raise_if_empty = false })
  eq(ok, false, "malformed CSV accepted with raise_if_empty = false")
  truthy(tostring(err):find("fields", 1, true) or
    tostring(err):find("CSV", 1, true), "malformed CSV error: " .. tostring(err))
end)

test("CSV writer include_bom writes and reads a UTF-8 BOM", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".csv")
  eq(df:write_csv(out, { include_bom = true }), df,
    "include_bom return value")
  local raw = read_file(out)
  eq(raw:sub(1, 3), "\239\187\191", "UTF-8 BOM")
  truthy(raw:find("\239\187\191id,name,note\n", 1, true), "BOM header")
  local loaded = polars.read_csv(out)
  check_roundtrip_frame(loaded)
  loaded:close()

  df:write_csv(out, {
    include_bom = true,
    delimiter = ";",
    header = false,
    null_value = "NA",
  })
  raw = read_file(out)
  eq(raw:sub(1, 3), "\239\187\191", "combined UTF-8 BOM")
  truthy(raw:find("1;ana;hello, world\n", 1, true),
    "BOM headerless record")
  truthy(raw:find("3;caio;NA\n", 1, true), "BOM combined null placeholder")
  loaded = polars.read_csv(out, { delimiter = ";", header = false })
  eq(loaded:shape(), 3)
  eq(loaded:to_table()[1].column_2, "ana")
  loaded:close()

  df:write_csv(out, {})
  truthy(read_file(out):sub(1, 3) ~= "\239\187\191",
    "default CSV output should not have a BOM")
  df:close()
end)

test("CSV writer decimal_comma writes comma decimals and round-trips", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("id;price\n1;1.5\n2;2.25\n3;3\n")
  file:close()
  local df = polars.read_csv(path, { delimiter = ";" })
  eq(df:schema().price, "f64")
  local out = new_temp_path(".csv")

  eq(df:write_csv(out, {
    delimiter = ";",
    decimal_comma = true,
  }), df, "decimal_comma return value")
  local raw = read_file(out)
  truthy(raw:find("id;price\n", 1, true), "decimal_comma header")
  truthy(raw:find("1;1,5\n", 1, true), "comma decimal first row")
  truthy(raw:find("2;2,25\n", 1, true), "comma decimal second row")
  local loaded = polars.read_csv(out, {
    delimiter = ";",
    decimal_comma = true,
  })
  eq(loaded:schema().price, "f64")
  local rows = loaded:to_table()
  eq(rows[1].price, 1.5)
  eq(rows[2].price, 2.25)
  eq(rows[3].price, 3)
  loaded:close()

  df:write_csv(out, { delimiter = ";" })
  raw = read_file(out)
  truthy(raw:find("1;1.5\n", 1, true), "default decimal separator")
  truthy(not raw:find("1;1,5\n", 1, true),
    "decimal_comma leaked into the default writer")

  df:write_csv(out, {
    delimiter = ";",
    header = false,
    decimal_comma = true,
    float_precision = 1,
  })
  raw = read_file(out)
  truthy(raw:find("1;1,5\n", 1, true),
    "decimal_comma combined with header and precision")
  loaded = polars.read_csv(out, {
    delimiter = ";",
    header = false,
    decimal_comma = true,
    rename_columns = { "id", "price" },
  })
  eq(loaded:to_table()[1].price, 1.5)
  loaded:close()
  df:close()
end)

test("CSV writer BOM and decimal options reject non-booleans", function()
  local df = polars.read_csv(roundtrip_fixture)
  local out = new_temp_path(".csv")
  for _, key in ipairs({ "include_bom", "decimal_comma" }) do
    for _, value in ipairs({ 1, 0, "true", {}, function() end }) do
      local ok, err = pcall(function()
        df:write_csv(out, { [key] = value })
      end)
      eq(ok, false, key .. " accepted a non-boolean value")
      truthy(tostring(err):find(key, 1, true),
        "expected option name in: " .. tostring(err))
      truthy(tostring(err):find("boolean", 1, true),
        "expected boolean guidance in: " .. tostring(err))
    end
  end
  df:close()
  local ok, err = pcall(function()
    df:write_csv(out, { include_bom = true })
  end)
  eq(ok, false, "closed include_bom accepted")
  truthy(tostring(err):find("closed", 1, true), "closed include_bom error")
end)

test("shift moves values and preserves the schema", function()
  local df = polars.read_csv(fixture)
  local shifted = df:shift(1)
  eq(shifted:shape(), df:shape())
  eq(table.concat(shifted:columns(), ","), "name,team,score,active")
  eq(shifted:schema().score, "i64")
  local rows = shifted:to_table()
  eq(rows[1].name, polars.null)
  eq(rows[1].team, polars.null)
  eq(rows[1].score, polars.null)
  eq(rows[1].active, polars.null)
  eq(rows[2].name, "ana")
  eq(rows[2].score, 10)
  eq(rows[5].name, "duda")
  shifted:close()

  local subset = df:shift(-1, { "score" })
  eq(table.concat(subset:columns(), ","), "name,team,score,active")
  rows = subset:to_table()
  eq(rows[1].name, "ana")
  eq(rows[1].score, 7)
  eq(rows[2].score, 12)
  eq(rows[4].score, 9)
  eq(rows[5].score, polars.null)
  subset:close()

  local unchanged = df:shift(0)
  eq(unchanged:to_table()[1].name, "ana")
  eq(unchanged:to_table()[5].score, 9)
  unchanged:close()
  eq(df:to_table()[1].name, "ana", "shift changed the input frame")
  df:close()
end)

test("shift rejects invalid periods and subsets", function()
  local df = polars.read_csv(fixture)
  for _, period in ipairs({ 1.5, "1", true, {}, math.huge,
      9007199254740992 }) do
    local ok, err = pcall(function() df:shift(period) end)
    eq(ok, false, "invalid shift period accepted")
    truthy(tostring(err):find("integer", 1, true),
      "shift period error: " .. tostring(err))
  end
  local cases = {
    { 42, "columns must be a column name or a list of names" },
    { {}, "columns must not be empty" },
    { { [1] = "score", [3] = "active" }, "contiguous list" },
    { { "score", "score" }, "duplicate shift column 'score'" },
    { { "missing" }, "is not a column in the DataFrame" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function() df:shift(1, case[1]) end)
    eq(ok, false, "invalid shift subset accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  df:close()
  local ok, err = pcall(function() df:shift(1) end)
  eq(ok, false, "closed shift accepted")
  truthy(tostring(err):find("closed", 1, true), "closed shift error")
end)

test("clip clamps numeric columns and preserves nulls", function()
  local df = polars.read_csv(fixture)
  local clipped = df:clip(7, 10)
  eq(clipped:shape(), df:shape())
  eq(table.concat(clipped:columns(), ","), "name,team,score,active")
  eq(clipped:schema().score, "i64")
  local rows = clipped:to_table()
  eq(rows[1].score, 10)
  eq(rows[2].score, 7)
  eq(rows[3].score, 10)
  eq(rows[4].score, 7)
  eq(rows[5].score, 9)
  eq(rows[1].name, "ana")
  eq(rows[4].active, true)
  clipped:close()

  local floated = df:sql([[
    SELECT "score",
           CASE WHEN "score" = 5 THEN NULL
                ELSE CAST("score" AS DOUBLE) END AS "f"
    FROM df
  ]])
  local finite = floated:clip(8, 10, "f")
  eq(finite:schema().f, "f64")
  rows = finite:to_table()
  eq(rows[1].f, 10)
  eq(rows[2].f, 8)
  eq(rows[3].f, 10)
  eq(rows[4].f, polars.null, "clip replaced a null")
  eq(rows[5].f, 9)
  finite:close()

  local only_numbers = df:sql('SELECT "name", "score" FROM df')
  local unchanged = only_numbers:clip(0, 100)
  eq(unchanged:to_table()[1].name, "ana")
  eq(unchanged:to_table()[3].score, 12)
  unchanged:close()
  only_numbers:close()
  floated:close()
  eq(df:to_table()[3].score, 12, "clip changed the input frame")
  df:close()
end)

test("clip rejects invalid bounds and subsets", function()
  local df = polars.read_csv(fixture)
  local value_cases = {
    { "7", 10, "finite number" },
    { 0 / 0, 10, "finite number" },
    { math.huge, 10, "finite number" },
    { 0, -math.huge, "finite number" },
    { 10, 7, "must not be greater than maximum" },
    { 2.5, 8, "must be an integer" },
  }
  for _, case in ipairs(value_cases) do
    local ok, err = pcall(function() df:clip(case[1], case[2]) end)
    eq(ok, false, "invalid clip bound accepted")
    truthy(tostring(err):find(case[3], 1, true),
      "expected '" .. case[3] .. "' in: " .. tostring(err))
  end
  local subset_cases = {
    { 42, "columns must be a column name or a list of names" },
    { {}, "columns must not be empty" },
    { { [1] = "score", [3] = "active" }, "contiguous list" },
    { { "score", "score" }, "duplicate clip column 'score'" },
    { { "missing" }, "is not a column in the DataFrame" },
    { { "name" }, "expected a numeric column" },
  }
  for _, case in ipairs(subset_cases) do
    local ok, err = pcall(function() df:clip(0, 10, case[1]) end)
    eq(ok, false, "invalid clip subset accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  df:close()
  local ok, err = pcall(function() df:clip(0, 10) end)
  eq(ok, false, "closed clip accepted")
  truthy(tostring(err):find("closed", 1, true), "closed clip error")
end)

test("is_duplicated and is_unique append Boolean markers", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("id,team\n1,red\n1,red\n2,blue\n3,green\n2,blue\n")
  file:close()
  local df = polars.read_csv(path)

  local duplicated = df:is_duplicated()
  eq(table.concat(duplicated:columns(), ","), "id,team,duplicated")
  local rows = duplicated:to_table()
  eq(rows[1].duplicated, true)
  eq(rows[2].duplicated, true)
  eq(rows[3].duplicated, true)
  eq(rows[4].duplicated, false)
  eq(rows[5].duplicated, true)
  duplicated:close()

  local unique = df:is_unique("only")
  eq(table.concat(unique:columns(), ","), "id,team,only")
  rows = unique:to_table()
  eq(rows[1].only, false)
  eq(rows[3].only, false)
  eq(rows[4].only, true)
  unique:close()

  local renamed = df:is_duplicated("repeat")
  eq(renamed:columns()[3], "repeat")
  renamed:close()
  eq(table.concat(df:columns(), ","), "id,team",
    "duplicate marker changed the input frame")
  df:close()

  local single = polars.read_csv(path):head(1)
  eq(single:is_unique():to_table()[1].unique, true)
  single:close()
end)

test("is_duplicated and is_unique reject names and closed frames", function()
  local df = polars.read_csv(fixture)
  local ok, err = pcall(function() df:is_duplicated("score") end)
  eq(ok, false, "colliding duplicate marker name accepted")
  truthy(tostring(err):find("already exists", 1, true),
    "duplicate marker collision error: " .. tostring(err))
  ok, err = pcall(function() df:is_unique("team") end)
  eq(ok, false, "colliding unique marker name accepted")
  truthy(tostring(err):find("already exists", 1, true),
    "unique marker collision error: " .. tostring(err))
  for _, value in ipairs({ "", 42, true, {} }) do
    ok, err = pcall(function() df:is_duplicated(value) end)
    eq(ok, false, "invalid duplicate marker name accepted")
    truthy(tostring(err):find("non-empty string", 1, true),
      "duplicate marker name error: " .. tostring(err))
    ok, err = pcall(function() df:is_unique(value) end)
    eq(ok, false, "invalid unique marker name accepted")
    truthy(tostring(err):find("non-empty string", 1, true),
      "unique marker name error: " .. tostring(err))
  end
  df:close()
  ok, err = pcall(function() df:is_duplicated() end)
  eq(ok, false, "closed is_duplicated accepted")
  truthy(tostring(err):find("closed", 1, true), "closed is_duplicated error")
  ok, err = pcall(function() df:is_unique() end)
  eq(ok, false, "closed is_unique accepted")
  truthy(tostring(err):find("closed", 1, true), "closed is_unique error")
end)

test("read_csv infer_schema_length controls dtype inference", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("id,score\n1,10\n2,20\n3,30\n")
  file:close()

  local default = polars.read_csv(path)
  eq(default:schema().score, "i64")
  eq(default:to_table()[1].score, 10)
  default:close()

  local strings = polars.read_csv(path, { infer_schema_length = 0 })
  eq(strings:schema().id, "str")
  eq(strings:schema().score, "str")
  eq(strings:to_table()[1].score, "10")
  strings:close()

  local first_row = polars.read_csv(path, { infer_schema_length = 1 })
  eq(first_row:schema().score, "i64")
  eq(first_row:to_table()[3].score, 30)
  first_row:close()

  local typed = polars.read_csv(path, {
    infer_schema_length = 0,
    dtypes = { score = "i64" },
  })
  eq(typed:schema().score, "i64")
  eq(typed:to_table()[1].score, 10)
  typed:close()

  local combined = polars.read_csv(path, {
    infer_schema_length = 0,
    columns = { "score", "id" },
    rename_columns = { "points", "key" },
    n_rows = 2,
  })
  eq(table.concat(combined:columns(), ","), "points,key")
  eq(combined:schema().points, "str")
  eq(combined:shape(), 2)
  eq(combined:to_table()[1].points, "10")
  combined:close()

  local headerless_path = new_temp_path(".csv")
  local headerless_file = assert(io.open(headerless_path, "w"))
  headerless_file:write("1;10\n2;20\n")
  headerless_file:close()
  local headerless = polars.read_csv(headerless_path, {
    delimiter = ";",
    header = false,
    infer_schema_length = 0,
    n_rows = 1,
  })
  eq(headerless:schema().column_1, "str")
  eq(headerless:schema().column_2, "str")
  eq(headerless:shape(), 1)
  headerless:close()

  local empty_path = new_temp_path(".csv")
  local empty_file = assert(io.open(empty_path, "w"))
  empty_file:close()
  local relaxed = polars.read_csv(empty_path, {
    infer_schema_length = 0,
    raise_if_empty = false,
  })
  eq(relaxed:shape(), 0)
  relaxed:close()
end)

test("read_csv infer_schema_length rejects invalid values", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("id,score\n1,10\n")
  file:close()
  for _, value in ipairs({ -1, 1.5, "1", true, {}, math.huge, 0 / 0,
      9007199254740992 }) do
    local ok, err = pcall(polars.read_csv, path, {
      infer_schema_length = value,
    })
    eq(ok, false, "invalid infer_schema_length accepted")
    truthy(tostring(err):find("infer_schema_length", 1, true),
      "infer_schema_length option name: " .. tostring(err))
    truthy(tostring(err):find("non-negative integer", 1, true),
      "infer_schema_length guidance: " .. tostring(err))
  end
end)

test("fill_null_forward and fill_null_backward carry values", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("id,note\n1,one\n2,\n3,\n4,four\n5,\n")
  file:close()
  local df = polars.read_csv(path)

  local forward = df:fill_null_forward()
  eq(forward:shape(), df:shape())
  eq(table.concat(forward:columns(), ","), "id,note")
  eq(forward:schema().note, "str")
  local rows = forward:to_table()
  eq(rows[1].note, "one")
  eq(rows[2].note, "one")
  eq(rows[3].note, "one")
  eq(rows[4].note, "four")
  eq(rows[5].note, "four")
  forward:close()

  local backward = df:fill_null_backward()
  rows = backward:to_table()
  eq(rows[1].note, "one")
  eq(rows[2].note, "four")
  eq(rows[3].note, "four")
  eq(rows[4].note, "four")
  eq(rows[5].note, polars.null)
  backward:close()

  local scoped = df:fill_null_forward("id")
  eq(scoped:to_table()[2].note, polars.null,
    "forward fill touched an unselected column")
  scoped:close()
  local scoped_back = df:fill_null_backward({ "id" })
  eq(scoped_back:to_table()[3].note, polars.null,
    "backward fill touched an unselected column")
  scoped_back:close()
  eq(df:to_table()[2].note, polars.null, "fill direction changed the input")
  df:close()
end)

test("fill_null direction rejects invalid subsets and closed frames", function()
  local df = polars.read_csv(fixture)
  local cases = {
    { 42, "columns must be a column name or a list of names" },
    { true, "columns must be a column name or a list of names" },
    { {}, "columns must not be empty" },
    { { [1] = "score", [3] = "active" }, "contiguous list" },
    { { "score", "score" }, "duplicate fill_null_" },
    { { "missing" }, "is not a column in the DataFrame" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function() df:fill_null_forward(case[1]) end)
    eq(ok, false, "invalid fill_null_forward subset accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
    ok, err = pcall(function() df:fill_null_backward(case[1]) end)
    eq(ok, false, "invalid fill_null_backward subset accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  df:close()
  local ok, err = pcall(function() df:fill_null_forward() end)
  eq(ok, false, "closed fill_null_forward accepted")
  truthy(tostring(err):find("closed", 1, true),
    "closed fill_null_forward error")
  ok, err = pcall(function() df:fill_null_backward() end)
  eq(ok, false, "closed fill_null_backward accepted")
  truthy(tostring(err):find("closed", 1, true),
    "closed fill_null_backward error")
end)

test("gather_every returns a strided row window", function()
  local df = polars.read_csv(fixture)
  local even = df:gather_every(2)
  eq(even:shape(), 3)
  eq(table.concat(even:columns(), ","), "name,team,score,active")
  eq(even:schema().score, "i64")
  local rows = even:to_table()
  eq(rows[1].name, "ana")
  eq(rows[2].name, "caio")
  eq(rows[3].name, "eva")
  even:close()

  local odd = df:gather_every(2, 1)
  eq(odd:shape(), 2)
  rows = odd:to_table()
  eq(rows[1].name, "bia")
  eq(rows[2].name, "duda")
  odd:close()

  local all = df:gather_every(1)
  eq(all:shape(), df:shape())
  eq(all:to_table()[1].name, "ana")
  all:close()

  local past = df:gather_every(2, 6)
  eq(past:shape(), 0)
  eq(table.concat(past:columns(), ","), "name,team,score,active")
  past:close()

  local sparse = df:gather_every(10)
  eq(sparse:shape(), 1)
  eq(sparse:to_table()[1].name, "ana")
  sparse:close()
  eq(df:to_table()[1].name, "ana", "gather_every changed the input frame")
  df:close()
end)

test("gather_every rejects invalid counts and offsets", function()
  local df = polars.read_csv(fixture)
  for _, value in ipairs({ 0, -1, 1.5, "2", true, {}, math.huge,
      9007199254740992 }) do
    local ok, err = pcall(function() df:gather_every(value) end)
    eq(ok, false, "invalid gather_every n accepted")
    truthy(tostring(err):find("positive integer", 1, true),
      "gather_every n error: " .. tostring(err))
  end
  for _, value in ipairs({ -1, 1.5, "0", true, {}, math.huge,
      9007199254740992 }) do
    local ok, err = pcall(function() df:gather_every(2, value) end)
    eq(ok, false, "invalid gather_every offset accepted")
    truthy(tostring(err):find("non-negative integer", 1, true),
      "gather_every offset error: " .. tostring(err))
  end
  df:close()
  local ok, err = pcall(function() df:gather_every(2) end)
  eq(ok, false, "closed gather_every accepted")
  truthy(tostring(err):find("closed", 1, true), "closed gather_every error")
end)

test("null_mask marks rows with any null", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("id,note,score\n1,one,10\n2,,20\n3,three,\n,four,40\n")
  file:close()
  local df = polars.read_csv(path)
  local masked = df:null_mask()
  eq(table.concat(masked:columns(), ","), "id,note,score,has_nulls")
  eq(masked:shape(), df:shape())
  local rows = masked:to_table()
  eq(rows[1].has_nulls, false)
  eq(rows[2].has_nulls, true)
  eq(rows[3].has_nulls, true)
  eq(rows[4].has_nulls, true)
  masked:close()

  local custom = df:null_mask("missing")
  eq(custom:columns()[4], "missing")
  eq(custom:to_table()[2].missing, true)
  custom:close()

  local clean = polars.read_csv(fixture):null_mask()
  for _, row in ipairs(clean:to_table()) do
    eq(row.has_nulls, false)
  end
  clean:close()
  eq(table.concat(df:columns(), ","), "id,note,score",
    "null_mask changed the input frame")
  df:close()
end)

test("null_mask rejects names, empty frames, and closed handles", function()
  local df = polars.read_csv(fixture)
  local ok, err = pcall(function() df:null_mask("score") end)
  eq(ok, false, "colliding null mask name accepted")
  truthy(tostring(err):find("already exists", 1, true),
    "null mask collision error: " .. tostring(err))
  for _, value in ipairs({ "", 42, true, {} }) do
    ok, err = pcall(function() df:null_mask(value) end)
    eq(ok, false, "invalid null mask name accepted")
    truthy(tostring(err):find("non-empty string", 1, true),
      "null mask name error: " .. tostring(err))
  end
  df:close()
  ok, err = pcall(function() df:null_mask() end)
  eq(ok, false, "closed null_mask accepted")
  truthy(tostring(err):find("closed", 1, true), "closed null_mask error")

  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:close()
  local empty = polars.read_csv(path, { raise_if_empty = false })
  ok, err = pcall(function() empty:null_mask() end)
  eq(ok, false, "null_mask accepted a zero-column frame")
  truthy(tostring(err):find("at least one column", 1, true),
    "zero-column null_mask error: " .. tostring(err))
  empty:close()
end)

test("read_json infer_schema_length controls JSON Lines inference", function()
  local path = new_temp_path(".jsonl")
  local file = assert(io.open(path, "w"))
  file:write('{"x":1}\n{"x":2}\n{"x":3}\n')
  file:close()
  local positive = polars.read_json(path, {
    format = "lines",
    infer_schema_length = 2,
  })
  eq(positive:schema().x, "i64")
  eq(positive:shape(), 3)
  eq(positive:to_table()[3].x, 3)
  positive:close()

  local mixed = new_temp_path(".jsonl")
  local mixed_file = assert(io.open(mixed, "w"))
  mixed_file:write('{"x":1}\n{"x":2.5}\n{"x":3}\n')
  mixed_file:close()
  local full = polars.read_json(mixed, {
    format = "lines",
    infer_schema_length = 0,
  })
  eq(full:schema().x, "f64")
  local rows = full:to_table()
  eq(rows[1].x, 1)
  eq(rows[2].x, 2.5)
  eq(rows[3].x, 3)
  full:close()

  local projected = polars.read_json(path, {
    format = "lines",
    infer_schema_length = 0,
    columns = { "x" },
  })
  eq(table.concat(projected:columns(), ","), "x")
  eq(projected:to_table()[1].x, 1)
  projected:close()

  local array_path = new_temp_path(".json")
  local array_file = assert(io.open(array_path, "w"))
  array_file:write('[{"x":1},{"x":2}]')
  array_file:close()
  local array = polars.read_json(array_path, { infer_schema_length = 1 })
  eq(array:shape(), 2)
  eq(array:schema().x, "i64")
  array:close()
end)

test("read_json infer_schema_length rejects invalid values and mismatches", function()
  local path = new_temp_path(".jsonl")
  local file = assert(io.open(path, "w"))
  file:write('{"x":1}\n{"x":2.5}\n')
  file:close()
  for _, value in ipairs({ -1, 1.5, "1", true, {}, math.huge, 0 / 0,
      9007199254740992 }) do
    local ok, err = pcall(polars.read_json, path, {
      format = "lines",
      infer_schema_length = value,
    })
    eq(ok, false, "invalid JSON infer_schema_length accepted")
    truthy(tostring(err):find("infer_schema_length", 1, true),
      "JSON infer_schema_length option name: " .. tostring(err))
    truthy(tostring(err):find("non-negative integer", 1, true),
      "JSON infer_schema_length guidance: " .. tostring(err))
  end

  local ok, err = pcall(polars.read_json, path, {
    format = "lines",
    infer_schema_length = 1,
  })
  eq(ok, false, "inference window too small did not fail the read")
  truthy(tostring(err):find("parse", 1, true) or
    tostring(err):find("Int64", 1, true),
    "inference mismatch error: " .. tostring(err))
end)

test("take selects rows in the requested order", function()
  local df = polars.read_csv(fixture)
  local picked = df:take({ 2, 4 })
  eq(picked:shape(), 2)
  eq(table.concat(picked:columns(), ","), "name,team,score,active")
  eq(picked:schema().score, "i64")
  local rows = picked:to_table()
  eq(rows[1].name, "bia")
  eq(rows[1].score, 7)
  eq(rows[2].name, "duda")
  picked:close()

  local negative = df:take({ -1, -2 })
  eq(negative:shape(), 2)
  rows = negative:to_table()
  eq(rows[1].name, "eva")
  eq(rows[2].name, "duda")
  negative:close()

  local repeated = df:take({ 5, 1, 5 })
  eq(repeated:shape(), 3)
  rows = repeated:to_table()
  eq(rows[1].name, "eva")
  eq(rows[2].name, "ana")
  eq(rows[3].name, "eva")
  repeated:close()
  eq(df:to_table()[1].name, "ana", "take changed the input frame")
  df:close()
end)

test("take rejects invalid index lists", function()
  local df = polars.read_csv(fixture)
  local cases = {
    { 42, "non-empty contiguous list" },
    { "1", "non-empty contiguous list" },
    { {}, "must not be empty" },
    { { [1] = 1, [3] = 3 }, "contiguous list" },
    { { 1, 1.5 }, "non-zero integers" },
    { { "1" }, "non-zero integers" },
    { { 0 }, "non-zero integers" },
    { { 6 }, "out of bounds" },
    { { -6 }, "out of bounds" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function() df:take(case[1]) end)
    eq(ok, false, "invalid take index list accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  df:close()
  local ok, err = pcall(function() df:take({ 1 }) end)
  eq(ok, false, "closed take accepted")
  truthy(tostring(err):find("closed", 1, true), "closed take error")
end)

test("top_k and bottom_k keep ordered extremes", function()
  local df = polars.read_csv(fixture)
  local top = df:top_k(3, "score")
  eq(top:shape(), 3)
  eq(table.concat(top:columns(), ","), "name,team,score,active")
  local rows = top:to_table()
  eq(rows[1].name, "caio")
  eq(rows[2].name, "ana")
  eq(rows[3].name, "eva")
  top:close()

  local bottom = df:bottom_k(3, { "score" })
  eq(bottom:shape(), 3)
  rows = bottom:to_table()
  eq(rows[1].name, "duda")
  eq(rows[2].name, "bia")
  eq(rows[3].name, "eva")
  bottom:close()

  local empty = df:top_k(0, "score")
  eq(empty:shape(), 0)
  eq(table.concat(empty:columns(), ","), "name,team,score,active")
  empty:close()

  local all = df:bottom_k(100, "score")
  eq(all:shape(), df:shape())
  all:close()

  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("id,score\n1,\n2,5\n3,9\n")
  file:close()
  local nullable = polars.read_csv(path)
  local high = nullable:top_k(3, "score")
  rows = high:to_table()
  eq(rows[1].score, 9)
  eq(rows[2].score, 5)
  eq(rows[3].score, polars.null)
  high:close()
  local low = nullable:bottom_k(3, "score")
  rows = low:to_table()
  eq(rows[1].score, 5)
  eq(rows[2].score, 9)
  eq(rows[3].score, polars.null)
  low:close()
  nullable:close()
  eq(df:to_table()[1].name, "ana", "rank helper changed the input frame")
  df:close()
end)

test("top_k and bottom_k reject invalid counts and keys", function()
  local df = polars.read_csv(fixture)
  for _, value in ipairs({ -1, 1.5, "1", true, {}, math.huge,
      9007199254740992 }) do
    local ok, err = pcall(function() df:top_k(value, "score") end)
    eq(ok, false, "invalid top_k count accepted")
    truthy(tostring(err):find("non-negative integer", 1, true),
      "top_k count error: " .. tostring(err))
    ok, err = pcall(function() df:bottom_k(value, "score") end)
    eq(ok, false, "invalid bottom_k count accepted")
    truthy(tostring(err):find("non-negative integer", 1, true),
      "bottom_k count error: " .. tostring(err))
  end
  local key_cases = {
    { 42, "columns must be a column name" },
    { {}, "columns must not be empty" },
    { { [1] = "score", [3] = "active" }, "contiguous list" },
    { { "score", "score" }, "duplicate" },
    { { "missing" }, "is not a column in the DataFrame" },
  }
  for _, case in ipairs(key_cases) do
    local ok, err = pcall(function() df:top_k(1, case[1]) end)
    eq(ok, false, "invalid top_k keys accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
    ok, err = pcall(function() df:bottom_k(1, case[1]) end)
    eq(ok, false, "invalid bottom_k keys accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  local ok, err = pcall(function() df:top_k(1) end)
  eq(ok, false, "top_k accepted missing keys")
  truthy(tostring(err):find("columns must be a column name", 1, true),
    "top_k missing keys error: " .. tostring(err))
  ok, err = pcall(function() df:bottom_k(1) end)
  eq(ok, false, "bottom_k accepted missing keys")
  truthy(tostring(err):find("columns must be a column name", 1, true),
    "bottom_k missing keys error: " .. tostring(err))
  df:close()
  local ok, err = pcall(function() df:top_k(1, "score") end)
  eq(ok, false, "closed top_k accepted")
  truthy(tostring(err):find("closed", 1, true), "closed top_k error")
  ok, err = pcall(function() df:bottom_k(1, "score") end)
  eq(ok, false, "closed bottom_k accepted")
  truthy(tostring(err):find("closed", 1, true), "closed bottom_k error")
end)

test("to_json supports JSON Lines output", function()
  local df = polars.read_csv(fixture)
  local array = df:to_json()
  truthy(array:sub(1, 1) == "[", "default to_json is not an array")
  truthy(array:find('"name":"ana"', 1, true), "default to_json row")

  local lines = df:to_json({ format = "lines" })
  truthy(lines:sub(1, 1) == "{", "JSON Lines output starts with an object")
  truthy(not lines:find("[", 1, true), "JSON Lines output has an array bracket")
  local count = 0
  for line in lines:gmatch("[^\n]+") do
    count = count + 1
    truthy(line:sub(1, 1) == "{", "JSON Lines record is not an object")
  end
  eq(count, 5)

  local alias = df:to_json({ format = "ndjson" })
  eq(alias, lines, "ndjson alias differs from lines output")
  local empty_options = df:to_json({})
  eq(empty_options, array, "empty to_json options changed the format")

  local path = new_temp_path(".jsonl")
  local file = assert(io.open(path, "w"))
  file:write(lines)
  file:close()
  local loaded = polars.read_json(path, { format = "lines" })
  eq(loaded:shape(), df:shape())
  eq(loaded:to_table()[1].name, "ana")
  loaded:close()

  local ok, err = pcall(function() df:to_json({ format = 42 }) end)
  eq(ok, false, "non-string to_json format accepted")
  truthy(tostring(err):find("format", 1, true), "to_json format error")
  ok, err = pcall(function() df:to_json({ rows = 1 }) end)
  eq(ok, false, "unknown to_json option accepted")
  truthy(tostring(err):find("unknown field", 1, true), "to_json option error")
  df:close()
  ok, err = pcall(function() df:to_json() end)
  eq(ok, false, "closed to_json accepted")
  truthy(tostring(err):find("closed", 1, true), "closed to_json error")
end)

test("read_parquet low_memory preserves results", function()
  local df = polars.read_csv(fixture)
  local path = new_temp_path(".parquet")
  df:write_parquet(path, { compression = "snappy" })
  local default = polars.read_parquet(path)
  local low = polars.read_parquet(path, { low_memory = true })
  eq(low:shape(), default:shape())
  eq(table.concat(low:columns(), ","), table.concat(default:columns(), ","))
  eq(low:schema().score, default:schema().score)
  eq(low:to_table()[1].name, default:to_table()[1].name)
  eq(low:to_table()[3].score, default:to_table()[3].score)
  low:close()
  default:close()

  local windowed = polars.read_parquet(path, {
    low_memory = false,
    columns = { "score", "name" },
    skip_rows = 1,
    n_rows = 2,
  })
  eq(windowed:shape(), 2)
  eq(table.concat(windowed:columns(), ","), "score,name")
  eq(windowed:to_table()[1].name, "bia")
  windowed:close()

  local ok, err = pcall(polars.read_parquet, path, { low_memory = "true" })
  eq(ok, false, "non-boolean low_memory accepted")
  truthy(tostring(err):find("low_memory", 1, true),
    "low_memory option error: " .. tostring(err))
  df:close()
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
  local ok = pcall(function() bad:fill_null({}) end)
  eq(ok, false); bad:close()
end)

test("drop_nulls accepts a column subset", function()
  local df = polars.read_csv(roundtrip_fixture)
  local by_id = df:drop_nulls("id")
  eq(by_id:shape(), 3)
  by_id:close()

  local by_note = df:drop_nulls("note")
  eq(by_note:shape(), 2)
  local rows = by_note:to_table()
  eq(rows[1].id, 1)
  eq(rows[2].id, 2)
  eq(table.concat(by_note:columns(), ","), "id,name,note")
  by_note:close()

  local by_pair = df:drop_nulls({ "name", "note" })
  eq(by_pair:shape(), 2)
  by_pair:close()

  local all = df:drop_nulls()
  eq(all:shape(), 2)
  all:close()

  local no_nulls = polars.read_csv(fixture):drop_nulls({ "team", "score" })
  eq(no_nulls:shape(), 5)
  no_nulls:close()
  df:close()
end)
test("drop_nulls rejects invalid subsets", function()
  local df = polars.read_csv(roundtrip_fixture)
  local cases = {
    { 42, "columns must be a column name or a list of names" },
    { true, "columns must be a column name or a list of names" },
    { {}, "columns must not be empty" },
    { { id = true }, "columns must be a column name or a list of names" },
    { { [1] = "id", [3] = "note" }, "contiguous list" },
    { { "" }, "entries must be non-empty strings" },
    { { 42 }, "entries must be non-empty strings" },
    { { "id", "id" }, "duplicate drop_nulls column 'id'" },
    { { "missing" }, "is not a column in the DataFrame" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function() df:drop_nulls(case[1]) end)
    eq(ok, false, "invalid drop_nulls subset accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  df:close()
  local ok, err = pcall(function() df:drop_nulls("id") end)
  eq(ok, false, "closed drop_nulls accepted")
  truthy(tostring(err):find("closed", 1, true), "closed drop_nulls error")
end)

test("fill_null accepts literal values and a column subset", function()
  local df = polars.read_csv(roundtrip_fixture)
  local quoted = df:fill_null("O'Reilly", "note")
  local rows = quoted:to_table()
  eq(find_row(rows, { id = 3 }).note, "O'Reilly")
  eq(find_row(rows, { id = 1 }).note, "hello, world")
  eq(find_row(rows, { id = 2 }).note, 'say "hi"')
  quoted:close()

  local empty = df:fill_null("", "note")
  eq(find_row(empty:to_table(), { id = 3 }).note, "")
  empty:close()

  local numeric = df:fill_null(42.5, { "id", "note" })
  rows = numeric:to_table()
  eq(find_row(rows, { id = 3 }).note, "42.5")
  eq(find_row(rows, { id = 1 }).note, "hello, world")
  eq(find_row(rows, { id = 1 }).id, 1)
  numeric:close()

  local scoped = polars.read_csv(null_fixture, {
    null_values = { score = "9" },
  })
  local scored = scoped:fill_null(0, "score")
  rows = scored:to_table()
  eq(find_row(rows, { id = 5 }).score, 0)
  eq(find_row(rows, { id = 1 }).score, 10)
  eq(find_row(rows, { id = 3 }).note, polars.null)
  scored:close()

  local aliased = scoped:fill_null("zero", { "score" })
  eq(find_row(aliased:to_table(), { id = 5 }).score, 0)
  aliased:close()
  scoped:close()
  df:close()
end)
test("fill_null fills booleans and keeps unselected columns", function()
  local path = new_temp_path(".csv")
  local file = assert(io.open(path, "w"))
  file:write("id,active\n1,true\n2,\n3,false\n")
  file:close()
  local df = polars.read_csv(path)
  eq(df:schema().active, "bool")
  eq(df:to_table()[2].active, polars.null)
  local filled = df:fill_null(false, "active")
  local rows = filled:to_table()
  eq(rows[1].active, true)
  eq(rows[2].active, false)
  eq(rows[3].active, false)
  filled:close()
  df:close()
end)
test("fill_null rejects invalid values and subsets", function()
  local df = polars.read_csv(roundtrip_fixture)
  local cases = {
    { {}, "value must be zero, one, a finite number, a string, or a boolean" },
    { function() end, "value must be zero, one" },
    { 0 / 0, "must not be NaN" },
    { math.huge, "must be finite" },
    { -math.huge, "must be finite" },
    { "a\0b", "must not contain NUL" },
  }
  for _, case in ipairs(cases) do
    local ok, err = pcall(function() df:fill_null(case[1]) end)
    eq(ok, false, "invalid fill_null value accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  local subset_cases = {
    { 42, "columns must be a column name or a list of names" },
    { {}, "columns must not be empty" },
    { { [1] = "id", [3] = "note" }, "contiguous list" },
    { { "id", "id" }, "duplicate fill_null column 'id'" },
    { { "missing" }, "is not a column in the DataFrame" },
  }
  for _, case in ipairs(subset_cases) do
    local ok, err = pcall(function() df:fill_null(0, case[1]) end)
    eq(ok, false, "invalid fill_null subset accepted")
    truthy(tostring(err):find(case[2], 1, true),
      "expected '" .. case[2] .. "' in: " .. tostring(err))
  end
  df:close()
  local ok, err = pcall(function() df:fill_null(0) end)
  eq(ok, false, "closed fill_null accepted")
  truthy(tostring(err):find("closed", 1, true), "closed fill_null error")
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
