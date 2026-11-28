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
check(polars.version() == "0.24.0", "unexpected bridge version")
check(polars._VERSION == "0.24.0", "unexpected Lua module version")

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

local transforms = polars.read_csv(fixture)
local reversed = transforms:reverse()
check(reversed:shape() == 5, "unexpected reversed shape")
check(reversed:to_table()[1].name == "eva", "unexpected reversed row")
reversed:close()
local casted = transforms:cast({ score = "f64" })
check(casted:schema().score == "f64", "unexpected cast dtype")
check(casted:to_table()[1].score == 10, "unexpected cast value")
casted:close()
local teams = transforms:unique("team")
check(teams:shape() == 2, "unexpected unique subset shape")
teams:close()
transforms:close()

local row_tools = polars.read_csv(fixture)
local shifted = row_tools:shift(1)
check(shifted:to_table()[1].score == polars.null,
  "shift did not insert a leading null")
check(shifted:to_table()[2].score == 10, "unexpected shifted value")
shifted:close()
local clipped = row_tools:clip(7, 10)
check(clipped:to_table()[3].score == 10, "unexpected clipped value")
check(clipped:to_table()[4].score == 7, "unexpected clipped lower bound")
clipped:close()
local differences = row_tools:diff(1, "score")
check(differences:to_table()[1].score == polars.null,
  "diff did not leave a leading null")
check(differences:to_table()[2].score == -3, "unexpected diff value")
differences:close()
local cumulative = row_tools:cum_sum("score")
check(cumulative:to_table()[5].score == 43,
  "unexpected cumulative sum")
cumulative:close()
local product = row_tools:cum_prod("score")
check(product:to_table()[5].score == 37800,
  "unexpected cumulative product")
product:close()
local compact = row_tools:rechunk()
check(compact:shape() == row_tools:shape(), "rechunk changed the shape")
check(compact:max_chunks() == 1, "rechunk did not produce one chunk")
compact:close()
local shrunk = row_tools:shrink_to_fit()
check(shrunk:shape() == row_tools:shape(), "shrink changed the shape")
shrunk:close()
check(row_tools:sum("score") == 43, "unexpected scalar sum")
check(row_tools:mean("score") == 8.6, "unexpected scalar mean")
check(row_tools:min("score") == 5, "unexpected scalar minimum")
check(row_tools:max("score") == 12, "unexpected scalar maximum")
check(row_tools:count() == 5, "unexpected row count")
check(row_tools:count("score") == 5, "unexpected non-null count")
check(row_tools:median("score") == 9, "unexpected median")
check(row_tools:quantile("score", 0.5) == 9, "unexpected quantile")
check(row_tools:var("score") == 7.3, "unexpected variance")
check(math.abs(row_tools:std("score") - 2.7018512172213) < 1e-9,
  "unexpected standard deviation")
check(row_tools:n_unique() == 5, "unexpected distinct row count")
check(row_tools:n_unique("team") == 2, "unexpected distinct team count")
check(row_tools:first("name") == "ana", "unexpected first value")
check(row_tools:last("name") == "eva", "unexpected last value")
check(row_tools:corr("score", "score") == 1, "unexpected correlation")
check(row_tools:covar("score", "score") == 7.3,
  "unexpected sample covariance")
check(row_tools:covar_pop("score", "score") == 5.84,
  "unexpected population covariance")
check(row_tools:product("score") == 37800, "unexpected product")
check(row_tools:any("active") == true, "unexpected any result")
check(row_tools:all("active") == false, "unexpected all result")
local replaced = row_tools:replace("red", "RED", "team")
check(replaced:to_table()[1].team == "RED", "unexpected replace value")
replaced:close()
local red_rows = row_tools:filter_in("team", { "red" })
check(red_rows:shape() == 3, "unexpected filter_in shape")
red_rows:close()
local not_red_rows = row_tools:filter_not_in("team", { "red" })
check(not_red_rows:shape() == 2, "unexpected filter_not_in shape")
not_red_rows:close()
local contains = row_tools:contains("name", "a")
check(contains:to_table()[1].contains == true,
  "unexpected contains marker")
contains:close()
local member = row_tools:is_in("team", { "red" })
check(member:to_table()[1].is_in == true, "unexpected is_in marker")
member:close()
local band = row_tools:between("score", 7, 10)
check(band:to_table()[1].between == true, "unexpected between marker")
band:close()
local nulls = row_tools:is_null("score")
check(nulls:to_table()[1].is_null == false, "unexpected is_null marker")
nulls:close()
local matching = row_tools:like("name", "a%")
check(matching:to_table()[1].like == true, "unexpected like marker")
matching:close()
local blanks = row_tools:is_blank("name")
check(blanks:to_table()[1].is_blank == false, "unexpected is_blank marker")
blanks:close()
local joined = row_tools:concat_str({ "name", "team" }, "-")
check(joined:to_table()[1].concat_str == "ana-red",
  "unexpected concat_str value")
joined:close()
local lowered = row_tools:lower("name")
check(lowered:to_table()[1].lower == "ana", "unexpected lower value")
lowered:close()
local uppered = row_tools:upper("name")
check(uppered:to_table()[1].upper == "ANA", "unexpected upper value")
uppered:close()
local lengths = row_tools:length("name")
check(lengths:to_table()[1].length == 3, "unexpected length value")
lengths:close()
local trimmed = row_tools:trim("name")
check(trimmed:to_table()[1].trim == "ana", "unexpected trim value")
trimmed:close()
local replaced_str = row_tools:replace_str("name", "a", "A")
check(replaced_str:to_table()[1].replace_str == "AnA",
  "unexpected replace_str value")
replaced_str:close()
local substring = row_tools:substr("name", 2, 2)
check(substring:to_table()[1].substr == "na", "unexpected substr value")
substring:close()
local absolute = row_tools:abs("score")
check(absolute:to_table()[1].abs == 10, "unexpected abs value")
absolute:close()
local rounded = row_tools:round("score", 1)
check(rounded:to_table()[1].round == 10, "unexpected round value")
rounded:close()
local floored = row_tools:floor("score")
check(floored:to_table()[1].floor == 10, "unexpected floor value")
floored:close()
local ceiled = row_tools:ceil("score")
check(ceiled:to_table()[1].ceil == 10, "unexpected ceil value")
ceiled:close()
local signed = row_tools:sign("score")
check(signed:to_table()[1].sign == 1, "unexpected sign value")
signed:close()
local added = row_tools:add("score", 5)
check(added:to_table()[1].add == 15, "unexpected add value")
added:close()
local subtracted = row_tools:subtract("score", 5)
check(subtracted:to_table()[1].subtract == 5, "unexpected subtract value")
subtracted:close()
local multiplied = row_tools:multiply("score", 3)
check(multiplied:to_table()[1].multiply == 30, "unexpected multiply value")
multiplied:close()
local divided = row_tools:divide("score", 2)
check(divided:to_table()[1].divide == 5, "unexpected divide value")
divided:close()
local modulo = row_tools:modulo("score", 4)
check(modulo:to_table()[1].modulo == 2, "unexpected modulo value")
modulo:close()
local padded = row_tools:pad_left("name", 5, "x")
check(padded:to_table()[1].pad_left == "xxana", "unexpected pad_left value")
padded:close()
local repeated = row_tools:repeat_str("name", 2)
check(repeated:to_table()[1].repeat_str == "anaana",
  "unexpected repeat_str value")
repeated:close()
local reversed_name = row_tools:reverse_str("team")
check(reversed_name:to_table()[1].reverse_str == "der",
  "unexpected reverse_str value")
reversed_name:close()
local capitalized = row_tools:capitalize("name")
check(capitalized:to_table()[1].capitalize == "Ana",
  "unexpected capitalize value")
capitalized:close()
local left_chars = row_tools:left("name", 2)
check(left_chars:to_table()[1].left == "an", "unexpected left value")
left_chars:close()
local right_chars = row_tools:right("name", 2)
check(right_chars:to_table()[1].right == "na", "unexpected right value")
right_chars:close()
local split_part = row_tools:split_part("name", "a", 2)
check(split_part:to_table()[1].split_part == "n",
  "unexpected split_part value")
split_part:close()
local position = row_tools:strpos("name", "a")
check(position:to_table()[1].strpos == 1, "unexpected strpos value")
position:close()
local character = row_tools:char_at("name", 2)
check(character:to_table()[1].char_at == "n", "unexpected char_at value")
character:close()
local coalesced = row_tools:coalesce({ "name", "team" })
check(coalesced:columns()[5] == "coalesce", "unexpected coalesce column")
coalesced:close()
local row_stack = row_tools:concat(row_tools)
check(row_stack:shape() == 10, "unexpected concat shape")
row_stack:close()
local right_columns = row_tools:sql('SELECT "score" AS "score2" FROM df')
local column_stack = row_tools:hstack(right_columns)
check(column_stack:shape() == 5, "unexpected hstack shape")
check(column_stack:columns()[5] == "score2", "unexpected hstack column")
column_stack:close()
right_columns:close()
local duplicated = row_tools:is_duplicated()
check(duplicated:columns()[5] == "duplicated",
  "duplicate marker was not appended")
check(duplicated:to_table()[1].duplicated == false,
  "unexpected duplicate marker value")
duplicated:close()
local unique_rows = row_tools:is_unique()
check(unique_rows:to_table()[1].unique == true,
  "unexpected unique marker value")
unique_rows:close()
local strided = row_tools:gather_every(2)
check(strided:shape() == 3, "unexpected gather_every shape")
check(strided:to_table()[1].name == "ana", "unexpected gather_every row")
strided:close()
local picked = row_tools:take({ 2, 4 })
check(picked:shape() == 2, "unexpected take shape")
check(picked:to_table()[1].name == "bia", "unexpected take row")
picked:close()
local top = row_tools:top_k(2, "score")
check(top:to_table()[1].name == "caio", "unexpected top_k row")
top:close()
local bottom = row_tools:bottom_k(2, "score")
check(bottom:to_table()[1].name == "duda", "unexpected bottom_k row")
bottom:close()
check(row_tools:estimated_size() > 0, "estimated_size was not positive")
check(row_tools:is_sorted("name"), "sorted names were not detected")
local sorted_rows = row_tools:sort("score", false)
check(sorted_rows:is_sorted("score"), "sorted scores were not detected")
sorted_rows:close()
local null_placed = row_tools:sort("score", false, { nulls_last = true })
check(null_placed:shape() == row_tools:shape(),
  "null-placed sort changed the shape")
null_placed:close()
local numeric = row_tools:sql('SELECT "score" FROM df')
local transposed = numeric:transpose()
local transpose_rows, transpose_cols = transposed:shape()
check(transpose_rows == 1 and transpose_cols == 5,
  "unexpected transpose shape")
check(transposed:to_table()[1].column_0 == 10,
  "unexpected transpose value")
transposed:close()
numeric:close()
local masked = row_tools:null_mask()
check(masked:columns()[5] == "has_nulls", "null mask was not appended")
check(masked:to_table()[1].has_nulls == false, "unexpected null mask value")
masked:close()
local nullable_path = os.tmpname()
local nullable_file = assert(io.open(nullable_path, "w"))
nullable_file:write("id,note\n1,one\n2,\n3,three\n")
nullable_file:close()
local nullable = polars.read_csv(nullable_path)
local forward_filled = nullable:fill_null_forward()
check(forward_filled:to_table()[2].note == "one",
  "unexpected forward fill value")
forward_filled:close()
local backward_filled = nullable:fill_null_backward()
check(backward_filled:to_table()[2].note == "three",
  "unexpected backward fill value")
backward_filled:close()
nullable:close()
os.remove(nullable_path)
row_tools:close()

local string_schema = polars.read_csv(fixture, { infer_schema_length = 0 })
check(string_schema:schema().score == "str",
  "infer_schema_length did not force string inference")
check(string_schema:to_table()[1].score == "10",
  "unexpected inferred string value")
string_schema:close()

local nan_source = polars.read_csv(fixture)
local nan = nan_source:sql([[
  SELECT "score",
         CASE WHEN "score" = 7 THEN NULL
              WHEN "score" = 10 THEN 0.0 / 0.0
              ELSE CAST("score" AS DOUBLE) END AS "x"
  FROM df
]])
local filled_nan = nan:fill_nan(2.5)
check(filled_nan:to_table()[1].x == 2.5, "unexpected fill_nan value")
check(filled_nan:to_table()[2].x == polars.null,
  "fill_nan replaced a null")
filled_nan:close()
local dropped_nan = nan:drop_nans()
check(dropped_nan:shape() == 4, "unexpected drop_nans shape")
check(dropped_nan:to_table()[1].x == polars.null,
  "drop_nans removed a null row")
dropped_nan:close()
nan:close()
nan_source:close()

local empty_path = os.tmpname()
local empty_file = assert(io.open(empty_path, "w"))
empty_file:close()
check(pcall(polars.read_csv, empty_path) == false,
  "empty CSV accepted without raise_if_empty = false")
local empty = polars.read_csv(empty_path, { raise_if_empty = false })
check(empty:shape() == 0 and #empty:columns() == 0,
  "unexpected empty CSV frame")
empty:close()
os.remove(empty_path)

local low_memory_csv = polars.read_csv(fixture, {
  low_memory = true,
  columns = { "score", "name" },
  n_rows = 2,
})
check(low_memory_csv:shape() == 2, "unexpected low-memory CSV shape")
check(low_memory_csv:to_table()[1].score == 10,
  "unexpected low-memory CSV value")
low_memory_csv:close()

local rechunked_csv = polars.read_csv(fixture, {
  rechunk = true,
  columns = { "score", "name" },
})
check(rechunked_csv:max_chunks() == 1,
  "read_csv rechunk did not consolidate chunks")
check(rechunked_csv:shape() == 5, "unexpected rechunked CSV shape")
rechunked_csv:close()

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
dated_file:write("id,day,stamp\n" ..
  "1,2024-01-02,2024-01-02 03:04:05\n" ..
  "2,2024-12-31,2024-12-31 23:59:59\n")
dated_file:close()
local dated = polars.read_csv(dated_path, { try_parse_dates = true })
check(dated:schema().day == "date", "unexpected inferred date dtype")
check(dated:to_table()[1].day == "2024-01-02", "unexpected inferred date value")
local years = dated:year("day")
check(years:to_table()[1].year == 2024, "unexpected year value")
years:close()
local months = dated:month("day")
check(months:to_table()[1].month == 1, "unexpected month value")
months:close()
local days = dated:day("day", "day_value")
check(days:to_table()[1].day_value == 2, "unexpected day value")
days:close()
local hours = dated:hour("stamp")
check(hours:to_table()[1].hour == 3, "unexpected hour value")
hours:close()
local minutes = dated:minute("stamp")
check(minutes:to_table()[1].minute == 4, "unexpected minute value")
minutes:close()
local quarters = dated:quarter("day")
check(quarters:to_table()[1].quarter == 1, "unexpected quarter value")
quarters:close()
local weeks = dated:week("day")
check(weeks:to_table()[1].week == 1, "unexpected week value")
weeks:close()
local weekdays = dated:weekday("day")
check(weekdays:to_table()[1].weekday == 2, "unexpected weekday value")
weekdays:close()
local ordinals = dated:day_of_year("day")
check(ordinals:to_table()[1].day_of_year == 2, "unexpected ordinal value")
ordinals:close()
local seconds = dated:second("stamp")
check(seconds:to_table()[1].second == 5, "unexpected second value")
seconds:close()
dated:close()
os.remove(dated_path)

local roundtrip_fixture = fixture:gsub("sample%.csv$", "roundtrip.csv")
local written = os.tmpname()
os.remove(written)
local writer = polars.read_csv(roundtrip_fixture)
local csv_text = writer:to_csv({
  delimiter = ";",
  header = false,
  null_value = "NA",
})
check(csv_text:find("1;ana;", 1, true) ~= nil,
  "unexpected to_csv first row")
check(csv_text:find("3;caio;NA\n", 1, true) ~= nil,
  "unexpected to_csv null placeholder")

local bom_path = os.tmpname()
os.remove(bom_path)
writer:write_csv(bom_path, { include_bom = true })
local bom_handle = assert(io.open(bom_path, "rb"))
local bom_raw = bom_handle:read("*a")
bom_handle:close()
check(bom_raw:sub(1, 3) == "\239\187\191", "missing UTF-8 BOM")
local bom_loaded = polars.read_csv(bom_path)
check(bom_loaded:shape() == 3, "unexpected BOM round-trip shape")
bom_loaded:close()
os.remove(bom_path)

local complete = writer:drop_nulls("note")
check(complete:shape() == 2, "unexpected drop_nulls subset shape")
complete:close()
local filled = writer:fill_null("missing", "note")
check(filled:to_table()[3].note == "missing",
  "unexpected fill_null subset value")
filled:close()
local counts = polars.read_csv(fixture):value_counts("team")
check(counts:shape() == 2 and counts:columns()[2] == "count",
  "unexpected value_counts shape")
check(counts:to_table()[1].team == "red" and counts:to_table()[1].count == 3,
  "unexpected value_counts result")
counts:close()

local lenient_path = os.tmpname()
local lenient_file = assert(io.open(lenient_path, "w"))
lenient_file:write("name,team,score\nana,red,10\nbia,blue,20,extra\n" ..
  "caio,red,30\n")
lenient_file:close()
local strict_ragged = pcall(polars.read_csv, lenient_path)
check(strict_ragged == false, "ragged CSV accepted without truncation")
local ragged = polars.read_csv(lenient_path, { truncate_ragged_lines = true })
check(ragged:shape() == 3, "unexpected truncated ragged shape")
check(ragged:to_table()[2].score == 20, "unexpected truncated ragged value")
ragged:close()
os.remove(lenient_path)

local errors_path = os.tmpname()
local errors_file = assert(io.open(errors_path, "w"))
errors_file:write("id,score\n1,10\n2,oops\n3,30\n")
errors_file:close()
local recovered = polars.read_csv(errors_path, {
  dtypes = { score = "i64" },
  ignore_errors = true,
})
check(recovered:shape() == 3, "unexpected ignore_errors shape")
check(recovered:to_table()[2].score == polars.null,
  "unexpected ignore_errors null")
recovered:close()
os.remove(errors_path)

local float_path = os.tmpname()
local float_file = assert(io.open(float_path, "w"))
float_file:write("id,ratio\n1,1.23456\n2,2.5\n")
float_file:close()
local floats = polars.read_csv(float_path)
local rounded_path = os.tmpname()
os.remove(rounded_path)
floats:write_csv(rounded_path, { float_precision = 2 })
local rounded_file = assert(io.open(rounded_path, "rb"))
local rounded_raw = rounded_file:read("*a")
rounded_file:close()
check(rounded_raw:find("1,1.23\n", 1, true) ~= nil,
  "unexpected float precision output")
check(rounded_raw:find("2,2.50\n", 1, true) ~= nil,
  "unexpected float precision padding")
local comma_path = os.tmpname()
os.remove(comma_path)
floats:write_csv(comma_path, { delimiter = ";", decimal_comma = true })
local comma_handle = assert(io.open(comma_path, "rb"))
local comma_raw = comma_handle:read("*a")
comma_handle:close()
check(comma_raw:find("1;1,23456\n", 1, true) ~= nil,
  "unexpected decimal comma output")
local comma_loaded = polars.read_csv(comma_path, {
  delimiter = ";",
  decimal_comma = true,
})
check(comma_loaded:to_table()[2].ratio == 2.5,
  "unexpected decimal comma round-trip")
comma_loaded:close()
os.remove(comma_path)
floats:close()
os.remove(float_path)
os.remove(rounded_path)

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
json_loaded = polars.read_json(json_out, {
  format = "lines",
  infer_schema_length = 0,
})
check(json_loaded:shape() == 3, "unexpected JSON Lines round-trip shape")
check(json_loaded:to_table()[1].name == "ana",
  "unexpected JSON Lines round-trip value")
json_loaded:close()
local json_lines_string = writer:to_json({ format = "lines" })
check(json_lines_string:sub(1, 1) == "{",
  "to_json lines output does not start with an object")
local json_array_string = writer:to_json()
check(json_array_string:sub(1, 1) == "[",
  "default to_json output does not start with an array")
local pretty_string = writer:to_json({ pretty = true })
check(pretty_string:sub(1, 1) == "[", "pretty to_json is not an array")
check(pretty_string:find("\n", 1, true) ~= nil,
  "pretty to_json has no line breaks")
local pretty_json = os.tmpname()
os.remove(pretty_json)
writer:write_json(pretty_json, { pretty = true })
local pretty_handle = assert(io.open(pretty_json, "rb"))
local pretty_raw = pretty_handle:read("*a")
pretty_handle:close()
check(pretty_raw:sub(1, 1) == "[", "pretty JSON is not an array")
check(pretty_raw:find("\n", 1, true) ~= nil,
  "pretty JSON has no line breaks")
local pretty_loaded = polars.read_json(pretty_json)
check(pretty_loaded:shape() == 3, "unexpected pretty JSON round-trip shape")
pretty_loaded:close()
os.remove(pretty_json)
os.remove(json_out)

local lenient_json = os.tmpname()
local lenient_json_file = assert(io.open(lenient_json, "w"))
lenient_json_file:write('{"x":1}\n{"x":2}\n{"x":"oops"}\n')
lenient_json_file:close()
local lenient = polars.read_json(lenient_json, {
  format = "lines",
  infer_schema_length = 2,
  ignore_errors = true,
})
check(lenient:shape() == 3, "unexpected lenient JSON shape")
check(lenient:to_table()[3].x == polars.null,
  "unexpected lenient JSON null")
lenient:close()
os.remove(lenient_json)

local nested_json = os.tmpname()
local nested_json_file = assert(io.open(nested_json, "w"))
nested_json_file:write('[{"id":1,"meta":{"a":1,"b":"x"}}]')
nested_json_file:close()
local nested = polars.read_json(nested_json)
local expanded = nested:unnest()
check(table.concat(expanded:columns(), ",") == "id,a,b",
  "unexpected unnest column order")
check(expanded:to_table()[1].b == "x", "unexpected unnest value")
expanded:close()
nested:close()
os.remove(nested_json)

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
local low_memory = polars.read_parquet(parquet_out, { low_memory = true })
check(low_memory:shape() == 3, "unexpected low-memory Parquet shape")
check(low_memory:to_table()[3].note == polars.null,
  "unexpected low-memory Parquet null")
low_memory:close()
local rechunked = polars.read_parquet(parquet_out, {
  low_memory = true,
  rechunk = true,
})
check(rechunked:shape() == 3, "unexpected rechunked Parquet shape")
check(rechunked:to_table()[3].note == polars.null,
  "unexpected rechunked Parquet null")
rechunked:close()
writer:write_parquet(parquet_out, {
  compression = "zstd",
  compression_level = 3,
})
local leveled = polars.read_parquet(parquet_out)
check(leveled:shape() == 3, "unexpected leveled Parquet shape")
leveled:close()
local bad_compression = pcall(function()
  writer:write_parquet(parquet_out, { compression = "lzo" })
end)
check(bad_compression == false, "invalid Parquet compression accepted")
os.remove(parquet_out)

writer:close()
os.remove(written)

io.write("install smoke: ok\n")
