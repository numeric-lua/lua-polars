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
check(polars.version() == "0.16.0", "unexpected bridge version")
check(polars._VERSION == "0.16.0", "unexpected Lua module version")

local df = polars.read_csv(fixture)
local rows, cols = df:shape()
check(rows == 5 and cols == 4, "unexpected fixture shape")
local columns = df:columns()
check(#columns == 4 and columns[1] == "name", "unexpected column order")
df:close()

local sliced = polars.read_csv(fixture)
local tail = sliced:tail(2)
check(tail:shape() == 2, "unexpected tail shape")
check(tail:to_table()[1].name == "duda", "unexpected tail row")
tail:close()
local window = sliced:slice(1, 2)
check(window:shape() == 2, "unexpected slice shape")
check(window:to_table()[1].name == "bia", "unexpected slice row")
window:close()
local indexed = sliced:with_row_index("row", 10)
check(indexed:columns()[1] == "row", "row index was not prepended")
check(indexed:to_table()[1].row == 10, "unexpected row index offset")
indexed:close()
sliced:close()

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

local per_column = polars.read_csv(fixture, {
  columns = { "score", "name" },
  dtypes = { score = "f64" },
  null_values = { score = "10", name = "eva" },
})
check(per_column:schema().score == "f64",
  "unexpected per-column null dtype")
local per_column_rows = per_column:to_table()
check(per_column_rows[1].score == polars.null,
  "per-column score marker mismatch")
check(per_column_rows[1].name == "ana", "per-column name changed")
check(per_column_rows[2].score == 7, "per-column unmatched score changed")
check(per_column_rows[5].name == polars.null,
  "per-column name marker mismatch")
per_column:close()

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

local renamed = polars.read_csv(fixture, {
  rename_columns = { "who", "squad", "points", "enabled" },
})
check(table.concat(renamed:columns(), ",") == "who,squad,points,enabled",
  "unexpected renamed columns")
check(renamed:schema().points == "i64", "unexpected renamed dtype")
check(renamed:to_table()[1].who == "ana", "unexpected renamed value")
renamed:close()

local lossy_path = os.tmpname()
local lossy_file = assert(io.open(lossy_path, "wb"))
lossy_file:write("name,note\nana,caf\233\n")
lossy_file:close()
local strict_ok = pcall(polars.read_csv, lossy_path)
check(strict_ok == false, "invalid UTF-8 accepted without lossy encoding")
local lossy = polars.read_csv(lossy_path, { encoding = "utf8-lossy" })
check(lossy:to_table()[1].note == "caf\239\191\189",
  "lossy replacement mismatch")
lossy:close()
os.remove(lossy_path)

local dated_path = os.tmpname()
local dated_file = assert(io.open(dated_path, "w"))
dated_file:write("id,day\n1,2024-01-02\n2,2024-12-31\n")
dated_file:close()
local dated = polars.read_csv(dated_path, { try_parse_dates = true })
check(dated:schema().day == "date", "unexpected inferred date dtype")
check(dated:to_table()[1].day == "2024-01-02", "unexpected inferred date value")
dated:close()
os.remove(dated_path)

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

local crlf_written = os.tmpname()
os.remove(crlf_written)
writer:write_csv(crlf_written, { line_terminator = "\r\n", null_value = "NA" })
handle = assert(io.open(crlf_written, "rb"))
raw = handle:read("*a")
handle:close()
check(raw:find("id,name,note\r\n", 1, true) ~= nil, "CRLF header mismatch")
check(raw:find("3,caio,NA\r\n", 1, true) ~= nil, "CRLF null record mismatch")
local bare = raw:gsub("\r\n", "")
check(not bare:find("[\r\n]"), "CRLF output has a lone separator")
local crlf_loaded = polars.read_csv(crlf_written)
check(crlf_loaded:shape() == 3, "unexpected CRLF round-trip shape")
check(crlf_loaded:to_table()[3].note == "NA", "CRLF round-trip mismatch")
crlf_loaded:close()
os.remove(crlf_written)

local quoted_csv = os.tmpname()
os.remove(quoted_csv)
writer:write_csv(quoted_csv, { quote_style = "always" })
handle = assert(io.open(quoted_csv, "rb"))
raw = handle:read("*a")
handle:close()
check(raw:find('"id","name","note"\n', 1, true) ~= nil,
  "quote_style header mismatch")
check(raw:find('"1","ana","hello, world"\n', 1, true) ~= nil,
  "quote_style record mismatch")
local quoted_loaded = polars.read_csv(quoted_csv)
check(quoted_loaded:shape() == 3, "unexpected quote_style round-trip shape")
quoted_loaded:close()
os.remove(quoted_csv)

local json_out = os.tmpname()
os.remove(json_out)
writer:write_json(json_out)
local json_loaded = polars.read_json(json_out)
check(json_loaded:shape() == 3, "unexpected JSON round-trip shape")
check(json_loaded:to_table()[3].note == polars.null,
  "unexpected JSON null round-trip")
json_loaded:close()
writer:write_json(json_out, { format = "lines" })
json_loaded = polars.read_json(json_out, { format = "lines" })
check(json_loaded:shape() == 3, "unexpected JSON Lines round-trip shape")
check(json_loaded:to_table()[1].name == "ana",
  "unexpected JSON Lines round-trip value")
json_loaded:close()
os.remove(json_out)

local parquet_out = os.tmpname()
os.remove(parquet_out)
writer:write_parquet(parquet_out, {
  compression = "snappy",
  statistics = false,
  row_group_size = 2,
  data_page_size = 1024,
})
local parquet = polars.read_parquet(parquet_out, {
  columns = { "note", "id" },
  skip_rows = 1,
  n_rows = 1,
})
check(parquet:shape() == 1, "unexpected Parquet window shape")
check(table.concat(parquet:columns(), ",") == "note,id",
  "unexpected Parquet column order")
check(parquet:to_table()[1].id == 2, "unexpected Parquet row value")
check(parquet:to_table()[1].note == 'say "hi"',
  "unexpected Parquet note value")
parquet:close()
local bad_compression = pcall(function()
  writer:write_parquet(parquet_out, { compression = "lzo" })
end)
check(bad_compression == false, "invalid Parquet compression accepted")
os.remove(parquet_out)

writer:close()
os.remove(written)

io.write("install smoke: ok\n")
