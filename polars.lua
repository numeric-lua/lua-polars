--
-- lua-polars: eager DataFrame bindings over the Rust Polars engine.
--
-- The module loads a small C ABI bridge (libpolars_lua.so / .dylib).  LuaJIT
-- never calls Rust directly; every handle crossing the boundary is opaque.
--
local ffi = require("ffi")
local json = require("polars.json")

ffi.cdef[[
typedef struct PlFrame PlFrame;

const char *pl_version(void);

PlFrame *pl_dataframe_read_csv(const char *path, char **err);
PlFrame *pl_dataframe_read_csv_options(
    const char *path, const char *delimiter, int32_t has_header, char **err);
PlFrame *pl_dataframe_read_csv_ex(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment, char **err);
PlFrame *pl_dataframe_read_csv_projected(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count, char **err);
PlFrame *pl_dataframe_read_csv_typed(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count, char **err);
PlFrame *pl_dataframe_read_csv_null_values(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count, char **err);
PlFrame *pl_dataframe_read_csv_row_window(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    uint64_t skip_rows, int64_t n_rows, char **err);
PlFrame *pl_dataframe_read_csv_encoded(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    uint64_t skip_rows, int64_t n_rows, const char *encoding, char **err);
PlFrame *pl_dataframe_read_csv_renamed(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    uint64_t skip_rows, int64_t n_rows,
    const char *const *rename_columns, uint64_t rename_column_count,
    const char *encoding, char **err);
PlFrame *pl_dataframe_read_csv_named_nulls(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_columns, const char *const *null_values,
    uint64_t null_value_count,
    uint64_t skip_rows, int64_t n_rows,
    const char *const *rename_columns, uint64_t rename_column_count,
    const char *encoding, char **err);
PlFrame *pl_dataframe_read_csv_parsed(
    const char *path, const char *delimiter, int32_t has_header,
    const char *quote, const char *comment,
    const char *const *columns, uint64_t column_count,
    const char *const *dtypes, uint64_t dtype_count,
    const char *const *null_values, uint64_t null_value_count,
    const char *const *null_columns, const char *const *named_null_values,
    uint64_t named_null_value_count,
    uint64_t skip_rows, int64_t n_rows,
    const char *const *rename_columns, uint64_t rename_column_count,
    const char *encoding, int32_t try_parse_dates, char **err);
PlFrame *pl_dataframe_read_parquet(const char *path, char **err);
PlFrame *pl_dataframe_read_parquet_options(
    const char *path, const char *const *columns, uint64_t column_count,
    uint64_t skip_rows, int64_t n_rows, char **err);
PlFrame *pl_dataframe_read_json(
    const char *path, int32_t json_lines,
    const char *const *columns, uint64_t column_count, char **err);
void pl_dataframe_free(PlFrame *frame);
int pl_dataframe_shape(PlFrame *frame, uint64_t *rows, uint64_t *cols);
char *pl_dataframe_schema_json(PlFrame *frame, char **err);
char *pl_dataframe_columns_json(PlFrame *frame, char **err);
PlFrame *pl_dataframe_head(PlFrame *frame, int64_t n, char **err);
PlFrame *pl_dataframe_tail(PlFrame *frame, int64_t n, char **err);
PlFrame *pl_dataframe_slice(
    PlFrame *frame, int64_t offset, uint64_t length, char **err);
PlFrame *pl_dataframe_with_row_index(
    PlFrame *frame, const char *name, uint64_t offset, char **err);
PlFrame *pl_dataframe_join(
    PlFrame *left, PlFrame *right, const char *how,
    const char *const *left_on, uint64_t left_count,
    const char *const *right_on, uint64_t right_count,
    int32_t nulls_equal, char **err);
PlFrame *pl_dataframe_sql(PlFrame *frame, const char *query, char **err);
int pl_dataframe_write_csv(PlFrame *frame, const char *path, char **err);
int pl_dataframe_write_csv_options(
    PlFrame *frame, const char *path, const char *delimiter,
    int32_t has_header, const char *null_value, char **err);
int pl_dataframe_write_csv_full(
    PlFrame *frame, const char *path, const char *delimiter,
    int32_t has_header, const char *null_value,
    const char *line_terminator, char **err);
int pl_dataframe_write_csv_configured(
    PlFrame *frame, const char *path, const char *delimiter,
    int32_t has_header, const char *null_value,
    const char *line_terminator, const char *quote_style, char **err);
int pl_dataframe_write_parquet(PlFrame *frame, const char *path, char **err);
int pl_dataframe_write_parquet_options(
    PlFrame *frame, const char *path, const char *compression,
    int32_t statistics, uint64_t row_group_size, uint64_t data_page_size,
    char **err);
int pl_dataframe_write_json(
    PlFrame *frame, const char *path, int32_t json_lines, char **err);
char *pl_dataframe_to_json(PlFrame *frame, char **err);
void pl_string_free(char *value);
]]

local function module_root()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    local path = source:sub(2)
    return path:match("^(.*)[/\\][^/\\]+$") or "."
  end
  return "."
end

local function cpath_candidates(suffix)
  local result = {}
  local seen = {}
  for entry in package.cpath:gmatch("[^;]+") do
    -- An installed LuaRocks tree keeps native modules in lib/lua/<version>;
    -- look for the bridge in the same directories C modules come from.
    local directory = entry:match("^(.*)[/\\][^/\\]+$")
    if directory then
      local candidate = directory .. "/libpolars_lua" .. suffix
      if not seen[candidate] then
        seen[candidate] = true
        result[#result + 1] = candidate
      end
    end
  end
  return result
end

local function library_candidates()
  local root = module_root()
  local suffix = jit.os == "OSX" and ".dylib" or ".so"
  local result = {
    root .. "/libpolars_lua" .. suffix,
    root .. "/target/release/libpolars_lua" .. suffix,
    root .. "/target/debug/libpolars_lua" .. suffix,
    root .. "/build/libpolars_lua" .. suffix,
  }
  for _, candidate in ipairs(cpath_candidates(suffix)) do
    result[#result + 1] = candidate
  end
  local configured = os.getenv("POLARS_LUA_LIB")
  if configured and configured ~= "" then
    table.insert(result, 1, configured)
  end
  return result
end

local lib
local load_errors = {}
for _, candidate in ipairs(library_candidates()) do
  local ok, loaded = pcall(ffi.load, candidate)
  if ok then
    lib = loaded
    break
  end
  load_errors[#load_errors + 1] = candidate .. ": " .. tostring(loaded)
end
if lib == nil then
  local ok, loaded = pcall(ffi.load, "polars_lua")
  if ok then
    lib = loaded
  else
    load_errors[#load_errors + 1] = "polars_lua: " .. tostring(loaded)
  end
end
if lib == nil then
  error("lua-polars: could not load the native bridge; tried\n  " ..
    table.concat(load_errors, "\n  "), 2)
end

local function take_error(err)
  local pointer = err[0]
  if pointer == nil then
    return "unknown Polars error"
  end
  local message = ffi.string(pointer)
  lib.pl_string_free(pointer)
  err[0] = nil
  return message
end

local function string_result(pointer, err)
  if pointer == nil then
    error(take_error(err), 3)
  end
  local value = ffi.string(pointer)
  lib.pl_string_free(pointer)
  return value
end

local DataFrame = {}
DataFrame.__index = DataFrame

local function new_frame(pointer, err)
  if pointer == nil then
    error(take_error(err), 3)
  end
  return setmetatable({ _ptr = pointer }, DataFrame)
end

function DataFrame:_require_open()
  if self._ptr == nil then
    error("DataFrame is closed", 2)
  end
  return self._ptr
end

function DataFrame:close()
  local pointer = self._ptr
  if pointer ~= nil then
    self._ptr = nil
    lib.pl_dataframe_free(pointer)
  end
end

DataFrame.__gc = DataFrame.close

function DataFrame:shape()
  local rows = ffi.new("uint64_t[1]")
  local cols = ffi.new("uint64_t[1]")
  local status = lib.pl_dataframe_shape(self:_require_open(), rows, cols)
  if status ~= 0 then
    error("could not read DataFrame shape (status " .. status .. ")", 2)
  end
  return tonumber(rows[0]), tonumber(cols[0])
end

function DataFrame:schema()
  local err = ffi.new("char *[1]")
  local pointer = lib.pl_dataframe_schema_json(self:_require_open(), err)
  return json.decode(string_result(pointer, err))
end

function DataFrame:columns()
  local err = ffi.new("char *[1]")
  local pointer = lib.pl_dataframe_columns_json(self:_require_open(), err)
  return json.decode(string_result(pointer, err))
end

function DataFrame:head(count)
  count = count == nil and 5 or count
  if type(count) ~= "number" or count < 0 or count % 1 ~= 0 or
      count > 9007199254740991 then
    error("head count must be a non-negative integer", 2)
  end
  local err = ffi.new("char *[1]")
  local pointer = lib.pl_dataframe_head(self:_require_open(), count, err)
  return new_frame(pointer, err)
end

function DataFrame:tail(count)
  count = count == nil and 5 or count
  if type(count) ~= "number" or count < 0 or count % 1 ~= 0 or
      count > 9007199254740991 then
    error("tail count must be a non-negative integer", 2)
  end
  local err = ffi.new("char *[1]")
  local pointer = lib.pl_dataframe_tail(self:_require_open(), count, err)
  return new_frame(pointer, err)
end

-- A negative offset counts from the end, matching Polars' eager slice. The
-- length is a row count and never negative; an offset past either end yields
-- an empty frame with the same schema instead of an error.
function DataFrame:slice(offset, length)
  if type(offset) ~= "number" or offset % 1 ~= 0 or
      offset < -9007199254740991 or offset > 9007199254740991 then
    error("slice offset must be an integer", 2)
  end
  if type(length) ~= "number" or length < 0 or length % 1 ~= 0 or
      length > 9007199254740991 then
    error("slice length must be a non-negative integer", 2)
  end
  local err = ffi.new("char *[1]")
  local pointer = lib.pl_dataframe_slice(self:_require_open(), offset, length,
    err)
  return new_frame(pointer, err)
end

-- The row index is prepended, matching Polars' with_row_index. An offset
-- shifts the first value; the default is zero. The bridge and Polars reject
-- an empty name or one that collides with an existing column.
function DataFrame:with_row_index(name, offset)
  name = name == nil and "index" or name
  if type(name) ~= "string" or name == "" then
    error("with_row_index name must be a non-empty string", 2)
  end
  offset = offset == nil and 0 or offset
  if type(offset) ~= "number" or offset < 0 or offset % 1 ~= 0 or
      offset > 9007199254740991 then
    error("with_row_index offset must be a non-negative integer", 2)
  end
  local err = ffi.new("char *[1]")
  local pointer = lib.pl_dataframe_with_row_index(self:_require_open(), name,
    offset, err)
  return new_frame(pointer, err)
end

function DataFrame:sql(query)
  if type(query) ~= "string" or query == "" then
    error("sql query must be a non-empty string", 2)
  end
  local err = ffi.new("char *[1]")
  local pointer = lib.pl_dataframe_sql(self:_require_open(), query, err)
  return new_frame(pointer, err)
end

local function quote_ident(name)
  return '"' .. tostring(name):gsub('"', '""') .. '"'
end

function DataFrame:sql_select(columns, suffix)
  local parts = {}
  for _, column in ipairs(columns) do parts[#parts + 1] = quote_ident(column) end
  if suffix and #suffix > 0 then
    for _, expression in ipairs(suffix) do parts[#parts + 1] = expression end
  end
  return self:sql("SELECT " .. table.concat(parts, ", ") .. " FROM df")
end

function DataFrame:drop(...)
  local drop = {}
  for _, name in ipairs({ ... }) do drop[name] = true end
  local columns = {}
  for _, name in ipairs(self:columns()) do
    if not drop[name] then columns[#columns + 1] = name end
  end
  if #columns == 0 then
    error("drop must leave at least one column", 2)
  end
  return self:sql_select(columns)
end

function DataFrame:rename(mapping)
  if type(mapping) ~= "table" then error("rename expects a table", 2) end
  local parts = {}
  for _, name in ipairs(self:columns()) do
    if mapping[name] ~= nil then
      parts[#parts + 1] = quote_ident(name) .. " AS " .. quote_ident(mapping[name])
    else parts[#parts + 1] = quote_ident(name) end
  end
  return self:sql("SELECT " .. table.concat(parts, ", ") .. " FROM df")
end

function DataFrame:with_columns(...)
  local expressions = { ... }
  local parts = {}
  for _, name in ipairs(self:columns()) do parts[#parts + 1] = quote_ident(name) end
  for _, expression in ipairs(expressions) do parts[#parts + 1] = expression end
  return self:sql("SELECT " .. table.concat(parts, ", ") .. " FROM df")
end

local function write_frame(self, path, method)
  if type(path) ~= "string" or path == "" then error(method .. " path must be a string", 2) end
  local err = ffi.new("char *[1]")
  local status = lib[method](self:_require_open(), path, err)
  if status ~= 0 then
    error(take_error(err), 2)
  end
  return self
end

local WRITE_CSV_OPTION_KEYS = {
  delimiter = true,
  header = true,
  null_value = true,
  line_terminator = true,
  quote_style = true,
}

local CSV_QUOTE_STYLES = {
  necessary = "necessary",
  always = "always",
  non_numeric = "non_numeric",
  ["non-numeric"] = "non_numeric",
  never = "never",
}

-- The default is Necessary, so an absent option keeps the earlier writer ABI
-- path. Never deliberately permits invalid CSV when a field needs quoting; the
-- other styles preserve a readable file.
local function write_csv_quote_style(value)
  if value == nil then
    return nil
  end
  if type(value) ~= "string" or value == "" then
    error("write_csv quote_style must be a non-empty string", 3)
  end
  local canonical = CSV_QUOTE_STYLES[value:lower()]
  if canonical == nil then
    error("write_csv quote_style must be one of necessary, always, " ..
      "non_numeric, or never", 3)
  end
  return canonical
end

local function write_csv_delimiter(value)
  if value == nil then
    return ","
  end
  if type(value) ~= "string" then
    error("write_csv delimiter must be a one-byte string", 3)
  end
  if #value ~= 1 then
    error("write_csv delimiter must be exactly one byte", 3)
  end
  if value == "\n" or value == "\r" or value == "\0" or value == '"' then
    error("write_csv delimiter byte is not allowed", 3)
  end
  return value
end

-- Polars writes the placeholder literally, so a value containing structure
-- bytes would make the output ambiguous instead of quoted.
local function write_csv_null_value(value, delimiter)
  if value == nil then
    return ""
  end
  if type(value) ~= "string" then
    error("write_csv null_value must be a string", 3)
  end
  if value:find("\0", 1, true) or value:find("\n", 1, true) or
      value:find("\r", 1, true) then
    error("write_csv null_value must not contain NUL, newline, or carriage return", 3)
  end
  if value:find(delimiter, 1, true) then
    error("write_csv null_value must not contain the delimiter", 3)
  end
  if value:find('"', 1, true) then
    error("write_csv null_value must not contain the quote character", 3)
  end
  return value
end

local function write_csv_options(options)
  if type(options) ~= "table" then
    error("write_csv options must be a table", 3)
  end
  for key in pairs(options) do
    if not WRITE_CSV_OPTION_KEYS[key] then
      error("write_csv options: unknown field '" .. tostring(key) .. "'", 3)
    end
  end
  local delimiter = write_csv_delimiter(options.delimiter)
  local header = options.header
  if header == nil then
    header = true
  end
  if type(header) ~= "boolean" then
    error("write_csv header must be a boolean", 3)
  end
  local line_terminator = options.line_terminator
  if line_terminator == nil then
    line_terminator = "\n"
  end
  if type(line_terminator) ~= "string" then
    error("write_csv line_terminator must be a string", 3)
  end
  if line_terminator ~= "\n" and line_terminator ~= "\r\n" then
    error("write_csv line_terminator must be \"\\n\" or \"\\r\\n\"", 3)
  end
  return delimiter, header,
    write_csv_null_value(options.null_value, delimiter), line_terminator,
    write_csv_quote_style(options.quote_style)
end

local function quote_identifier(name)
  return '"' .. tostring(name):gsub('"', '""') .. '"'
end

local MAX_SAFE_INTEGER = 9007199254740991

local PARQUET_WRITE_OPTION_KEYS = {
  compression = true,
  statistics = true,
  row_group_size = true,
  data_page_size = true,
}

-- The ABI accepts these names case-insensitively; `none`/`lz4-raw` are
-- readability aliases and map to the same Polars codec.
local PARQUET_COMPRESSION_ALIASES = {
  zstd = "zstd",
  snappy = "snappy",
  gzip = "gzip",
  brotli = "brotli",
  lz4 = "lz4",
  ["lz4-raw"] = "lz4",
  uncompressed = "uncompressed",
  none = "uncompressed",
}

-- Zero is the ABI sentinel for "use the Polars default", so Lua only accepts
-- an explicit positive integer. Row group sizes are row counts and data page
-- sizes are byte counts.
local function parquet_size_option(options, key)
  local value = options[key]
  if value == nil then
    return 0
  end
  if type(value) ~= "number" or value < 1 or value % 1 ~= 0 or
      value > MAX_SAFE_INTEGER then
    error("write_parquet " .. key .. " must be a positive integer", 3)
  end
  return value
end

local function write_parquet_options(options)
  if type(options) ~= "table" then
    error("write_parquet options must be a table", 3)
  end
  for key in pairs(options) do
    if not PARQUET_WRITE_OPTION_KEYS[key] then
      error("write_parquet options: unknown field '" .. tostring(key) .. "'", 3)
    end
  end
  local compression = options.compression
  if compression == nil then
    compression = "zstd"
  end
  if type(compression) ~= "string" or compression == "" then
    error("write_parquet compression must be a non-empty string", 3)
  end
  local canonical = PARQUET_COMPRESSION_ALIASES[compression:lower()]
  if canonical == nil then
    error("write_parquet compression must be one of zstd, snappy, gzip, " ..
      "brotli, lz4, or uncompressed", 3)
  end
  local statistics = options.statistics
  if statistics == nil then
    statistics = true
  end
  if type(statistics) ~= "boolean" then
    error("write_parquet statistics must be a boolean", 3)
  end
  return canonical, statistics,
    parquet_size_option(options, "row_group_size"),
    parquet_size_option(options, "data_page_size")
end

local JSON_FORMAT_ALIASES = {
  array = "array",
  json = "array",
  lines = "lines",
  ndjson = "lines",
  jsonl = "lines",
  ["json-lines"] = "lines",
  jsonlines = "lines",
}

-- Both JSON readers and writers default to a single JSON array. JSON Lines is
-- opt-in because the whole-file result is not valid JSON and needs the matching
-- read format to round-trip.
local function json_format(value, label)
  if value == nil then
    return "array"
  end
  if type(value) ~= "string" or value == "" then
    error(label .. " format must be a non-empty string", 3)
  end
  local canonical = JSON_FORMAT_ALIASES[value:lower()]
  if canonical == nil then
    error(label .. " format must be 'array' or 'lines'", 3)
  end
  return canonical
end

function DataFrame:unique()
  return self:sql("SELECT DISTINCT * FROM df")
end

function DataFrame:null_count()
  local counts = {}
  for _, name in ipairs(self:columns()) do
    local query = string.format("SELECT COUNT(*) AS n FROM df WHERE %s IS NULL",
      quote_identifier(name))
    local frame = self:sql(query)
    local rows = frame:to_table()
    counts[name] = rows[1] and rows[1].n or 0
    frame:close()
  end
  return counts
end

-- Accepts a column name or a contiguous list of names and checks it against
-- the live frame. The helpers that take an optional subset use this to report
-- typos before Polars sees the SQL, while a nil subset keeps the all-column
-- behavior of the earlier API.
local function subset_columns(frame, value, label)
  if value == nil then
    return nil
  end
  local columns
  if type(value) == "string" then
    columns = { value }
  elseif type(value) == "table" then
    columns = value
  else
    error(label .. " columns must be a column name or a list of names", 3)
  end
  local keys = {}
  for key in pairs(columns) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      error(label .. " columns must be a column name or a list of names", 3)
    end
    keys[#keys + 1] = key
  end
  if #keys == 0 then
    error(label .. " columns must not be empty", 3)
  end
  table.sort(keys)
  for index, key in ipairs(keys) do
    if key ~= index then
      error(label .. " columns must be a contiguous list of names", 3)
    end
  end
  local available = {}
  for _, name in ipairs(frame:columns()) do
    available[name] = true
  end
  local seen = {}
  local result = {}
  for index = 1, #keys do
    local name = columns[index]
    if type(name) ~= "string" or name == "" then
      error(label .. " columns entries must be non-empty strings", 3)
    end
    if seen[name] then
      error("duplicate " .. label .. " column '" .. name .. "'", 3)
    end
    seen[name] = true
    if not available[name] then
      error(label .. " column '" .. name ..
        "' is not a column in the DataFrame", 3)
    end
    result[index] = name
  end
  return result
end

-- With no argument every column participates, matching the earlier behavior.
-- A name or list limits the null check to those columns; rows with a null in
-- any selected column are dropped and the schema is unchanged.
function DataFrame:drop_nulls(columns)
  local selected = subset_columns(self, columns, "drop_nulls")
  if selected == nil then
    selected = self:columns()
  end
  local conditions = {}
  for _, name in ipairs(selected) do
    conditions[#conditions + 1] = quote_identifier(name) .. " IS NOT NULL"
  end
  return self:sql("SELECT * FROM df WHERE " .. table.concat(conditions, " AND "))
end

-- Formats a Lua scalar as a SQL literal for COALESCE. Strings are escaped by
-- doubling single quotes, booleans use SQL true/false, and numbers must be
-- finite so a typo cannot emit NaN or infinity into the query. `zero` and
-- `one` stay reserved strategy aliases for backward compatibility.
local function fill_null_literal(value)
  if value == nil or value == "zero" then
    return "0"
  end
  if value == "one" then
    return "1"
  end
  if type(value) == "boolean" then
    return value and "true" or "false"
  end
  if type(value) == "number" then
    if value ~= value then
      error("fill_null value must not be NaN", 3)
    end
    if value == math.huge or value == -math.huge then
      error("fill_null value must be finite", 3)
    end
    return string.format("%.17g", value)
  end
  if type(value) == "string" then
    if value:find("\0", 1, true) then
      error("fill_null string must not contain NUL", 3)
    end
    return "'" .. value:gsub("'", "''") .. "'"
  end
  error("fill_null value must be zero, one, a finite number, a string, " ..
    "or a boolean", 3)
end

-- With no columns every column is filled, matching the earlier behavior.
-- A name or list limits the replacement to those columns. The scalar may be a
-- finite number, string, or boolean; `zero` and `one` remain strategy aliases.
function DataFrame:fill_null(value, columns)
  local literal = fill_null_literal(value)
  local selected = subset_columns(self, columns, "fill_null")
  local wanted
  if selected ~= nil then
    wanted = {}
    for _, name in ipairs(selected) do
      wanted[name] = true
    end
  end
  local projections = {}
  for _, name in ipairs(self:columns()) do
    local quoted = quote_identifier(name)
    if wanted == nil or wanted[name] then
      projections[#projections + 1] = "COALESCE(" .. quoted .. ", " ..
        literal .. ") AS " .. quoted
    else
      projections[#projections + 1] = quoted
    end
  end
  return self:sql("SELECT " .. table.concat(projections, ", ") .. " FROM df")
end

function DataFrame:write_csv(path, options)
  if options == nil then
    return write_frame(self, path, "pl_dataframe_write_csv")
  end
  if type(path) ~= "string" or path == "" then
    error("write_csv path must be a string", 2)
  end
  local delimiter, header, null_value, line_terminator, quote_style =
    write_csv_options(options)
  local err = ffi.new("char *[1]")
  local status
  if quote_style ~= nil then
    status = lib.pl_dataframe_write_csv_configured(self:_require_open(), path,
      delimiter, header and 1 or 0, null_value, line_terminator, quote_style,
      err)
  else
    status = lib.pl_dataframe_write_csv_full(self:_require_open(), path,
      delimiter, header and 1 or 0, null_value, line_terminator, err)
  end
  if status ~= 0 then
    error(take_error(err), 2)
  end
  return self
end
function DataFrame:write_parquet(path, options)
  if options == nil then
    return write_frame(self, path, "pl_dataframe_write_parquet")
  end
  if type(path) ~= "string" or path == "" then
    error("write_parquet path must be a string", 2)
  end
  local compression, statistics, row_group_size, data_page_size =
    write_parquet_options(options)
  local err = ffi.new("char *[1]")
  local status = lib.pl_dataframe_write_parquet_options(self:_require_open(),
    path, compression, statistics and 1 or 0, row_group_size, data_page_size,
    err)
  if status ~= 0 then
    error(take_error(err), 2)
  end
  return self
end

local JSON_WRITE_OPTION_KEYS = {
  format = true,
}

function DataFrame:write_json(path, options)
  if type(path) ~= "string" or path == "" then
    error("write_json path must be a string", 2)
  end
  local format = "array"
  if options ~= nil then
    if type(options) ~= "table" then
      error("write_json options must be a table", 2)
    end
    for key in pairs(options) do
      if not JSON_WRITE_OPTION_KEYS[key] then
        error("write_json options: unknown field '" .. tostring(key) .. "'", 2)
      end
    end
    format = json_format(options.format, "write_json")
  end
  local err = ffi.new("char *[1]")
  local status = lib.pl_dataframe_write_json(self:_require_open(), path,
    format == "lines" and 1 or 0, err)
  if status ~= 0 then
    error(take_error(err), 2)
  end
  return self
end

function DataFrame:to_json()
  local err = ffi.new("char *[1]")
  local pointer = lib.pl_dataframe_to_json(self:_require_open(), err)
  return string_result(pointer, err)
end

function DataFrame:column_names()
  return self:columns()
end

function DataFrame:is_empty()
  local rows = self:shape()
  return rows == 0
end

function DataFrame:iter_rows()
  local rows = self:to_table()
  local index = 0
  return function()
    index = index + 1
    return rows[index]
  end
end

function DataFrame:to_table()
  return json.decode(self:to_json())
end

local function as_list(value, label)
  if type(value) == "table" then
    return value
  end
  if type(value) == "string" and value ~= "" then
    return { value }
  end
  error(label .. " must be a column name or a list of names", 3)
end

local function key_list(value, label)
  local keys = as_list(value, label)
  if #keys == 0 then
    error(label .. " must not be empty", 3)
  end
  local seen = {}
  local result = {}
  for index, key in ipairs(keys) do
    if type(key) ~= "string" or key == "" then
      error(label .. " entries must be non-empty strings", 3)
    end
    if seen[key] then
      error("duplicate " .. label .. " '" .. key .. "'", 3)
    end
    seen[key] = true
    result[index] = key
  end
  return result
end

local function quote_identifier(name)
  if type(name) ~= "string" or name == "" then
    error("column names must be non-empty strings", 3)
  end
  return '"' .. name:gsub('"', '""') .. '"'
end

function DataFrame:select(...)
  local columns = { ... }
  if #columns == 1 and type(columns[1]) == "table" then
    columns = columns[1]
  end
  if #columns == 0 then
    error("select expects at least one column", 2)
  end
  local quoted = {}
  for index, name in ipairs(columns) do
    quoted[index] = quote_identifier(name)
  end
  return self:sql("SELECT " .. table.concat(quoted, ", ") .. " FROM df")
end

function DataFrame:filter(condition)
  if type(condition) ~= "string" or condition == "" then
    error("filter condition must be a non-empty SQL expression", 2)
  end
  return self:sql("SELECT * FROM df WHERE " .. condition)
end

function DataFrame:sort(columns, descending)
  columns = as_list(columns, "sort columns")
  local quoted = {}
  for index, name in ipairs(columns) do
    local direction = descending
    if type(descending) == "table" then
      direction = descending[index]
    end
    quoted[index] = quote_identifier(name) .. (direction and " DESC" or " ASC")
  end
  return self:sql("SELECT * FROM df ORDER BY " .. table.concat(quoted, ", "))
end

function DataFrame:group_by(keys, aggregates)
  keys = as_list(keys, "group keys")
  if type(aggregates) ~= "table" or #aggregates == 0 then
    error("group_by aggregates must be a non-empty list of SQL expressions", 2)
  end
  local select = {}
  for _, key in ipairs(keys) do
    select[#select + 1] = quote_identifier(key)
  end
  for _, expression in ipairs(aggregates) do
    if type(expression) ~= "string" or expression == "" then
      error("group_by aggregates must be non-empty SQL expressions", 2)
    end
    select[#select + 1] = expression
  end
  local group = {}
  for index, key in ipairs(keys) do
    group[index] = quote_identifier(key)
  end
  return self:sql("SELECT " .. table.concat(select, ", ") ..
    " FROM df GROUP BY " .. table.concat(group, ", "))
end

function DataFrame:join(other, options)
  local self_ptr = self:_require_open()
  if getmetatable(other) ~= DataFrame then
    error("join expects another DataFrame", 2)
  end
  local other_ptr = other:_require_open()
  if type(options) ~= "table" then
    error("join options must be a table", 2)
  end

  local how = options.how
  if how == nil then
    how = "inner"
  end
  if type(how) ~= "string" or how == "" then
    error("join type is required", 2)
  end
  how = how:lower()
  local valid = { inner=true, left=true, full=true, outer=true, semi=true,
    anti=true, cross=true }
  if not valid[how] then
    error("invalid join type '" .. tostring(options.how) ..
      "'; expected inner, left, full, semi, anti, or cross", 2)
  end

  if how == "cross" then
    if options.on ~= nil or options.left_on ~= nil or
        options.right_on ~= nil then
      error("cross join does not accept keys", 2)
    end
    local nulls_equal = options.nulls_equal
    if nulls_equal == nil then nulls_equal = false end
    if type(nulls_equal) ~= "boolean" then
      error("join nulls_equal must be a boolean", 2)
    end
    local err = ffi.new("char *[1]")
    local pointer = lib.pl_dataframe_join(self_ptr, other_ptr, how, nil, 0,
      nil, 0, nulls_equal and 1 or 0, err)
    return new_frame(pointer, err)
  end

  local left_keys, right_keys
  if options.on ~= nil then
    if options.left_on ~= nil or options.right_on ~= nil then
      error("join accepts either on or left_on/right_on, not both", 2)
    end
    left_keys = key_list(options.on, "join keys")
    right_keys = left_keys
  else
    if options.left_on == nil or options.right_on == nil then
      error("join requires on or both left_on and right_on", 2)
    end
    left_keys = key_list(options.left_on, "left join keys")
    right_keys = key_list(options.right_on, "right join keys")
  end
  if #left_keys ~= #right_keys then
    error(string.format("join key count mismatch: left has %d, right has %d",
      #left_keys, #right_keys), 2)
  end

  local nulls_equal = options.nulls_equal
  if nulls_equal == nil then
    nulls_equal = false
  end
  if type(nulls_equal) ~= "boolean" then
    error("join nulls_equal must be a boolean", 2)
  end

  local left_on = ffi.new("const char *[?]", #left_keys)
  local right_on = ffi.new("const char *[?]", #right_keys)
  for index, key in ipairs(left_keys) do
    left_on[index - 1] = key
  end
  for index, key in ipairs(right_keys) do
    right_on[index - 1] = key
  end

  local err = ffi.new("char *[1]")
  local pointer = lib.pl_dataframe_join(self_ptr, other_ptr, how,
    left_on, #left_keys, right_on, #right_keys,
    nulls_equal and 1 or 0, err)
  return new_frame(pointer, err)
end

local polars = {
  _VERSION = "0.17.0",
  null = json.null,
  DataFrame = DataFrame,
}

function polars.version()
  return ffi.string(lib.pl_version())
end

local CSV_OPTION_KEYS = {
  delimiter = true,
  header = true,
  quote = true,
  comment = true,
  columns = true,
  rename_columns = true,
  dtypes = true,
  null_values = true,
  skip_rows = true,
  n_rows = true,
  encoding = true,
  try_parse_dates = true,
}

local function csv_byte_option(options, key, default)
  local value = options[key]
  if value == nil then
    return default
  end
  if value == false then
    return ""
  end
  if type(value) ~= "string" then
    error("read_csv " .. key ..
      " must be a one-byte string or false", 3)
  end
  if value == "" then
    return ""
  end
  if #value ~= 1 then
    error("read_csv " .. key .. " must be exactly one byte", 3)
  end
  if value == "\n" or value == "\r" or value == "\0" then
    error("read_csv " .. key .. " byte is not allowed", 3)
  end
  return value
end

local function column_projection(value, label)
  label = label or "read_csv"
  if value == nil then
    return nil
  end
  local columns
  if type(value) == "string" then
    columns = { value }
  elseif type(value) == "table" then
    columns = value
  else
    error(label .. " columns must be a column name or a list of names", 3)
  end
  if #columns == 0 then
    error(label .. " columns must not be empty", 3)
  end
  local seen = {}
  local result = {}
  for index, name in ipairs(columns) do
    if type(name) ~= "string" or name == "" then
      error(label .. " columns entries must be non-empty strings", 3)
    end
    if seen[name] then
      error("duplicate " .. label .. " column '" .. name .. "'", 3)
    end
    seen[name] = true
    result[index] = name
  end
  if #result == 0 then
    error(label .. " columns must not be empty", 3)
  end
  return result
end

local function csv_columns(value)
  return column_projection(value, "read_csv")
end

-- Flattens the `dtypes` map into the ABI's column/dtype string pairs.
-- Sorting by column name keeps error reporting deterministic even though Lua
-- table iteration order is not. Dtype names are validated by the bridge so
-- there is a single alias table.
local function csv_dtypes(value)
  if value == nil then
    return nil, 0
  end
  if type(value) ~= "table" then
    error("read_csv dtypes must be a table of column = dtype pairs", 3)
  end
  local entries = {}
  for column, dtype in pairs(value) do
    if type(column) ~= "string" or column == "" then
      error("read_csv dtypes keys must be non-empty column names", 3)
    end
    if type(dtype) ~= "string" or dtype == "" then
      error("read_csv dtypes values must be non-empty dtype names", 3)
    end
    entries[#entries + 1] = { column, dtype }
  end
  if #entries == 0 then
    error("read_csv dtypes must not be empty", 3)
  end
  table.sort(entries, function(left, right)
    return left[1] < right[1]
  end)
  local flat = {}
  for index, entry in ipairs(entries) do
    flat[index * 2 - 1] = entry[1]
    flat[index * 2] = entry[2]
  end
  return flat, #entries
end

-- Accepts one literal marker shared by every column, a non-empty list of
-- markers for every column, or a table mapping column names to one marker
-- each. Named markers apply only to their column; empty fields remain null in
-- every column. Table shape is strict: a map is never silently treated as
-- an empty list, and list indices cannot be mixed with column keys.
local function csv_null_values(value)
  if value == nil then
    return nil, 0, nil, nil
  end
  if type(value) == "string" then
    if value == "" then
      error("read_csv null_values must not be empty", 3)
    end
    return { value }, 1, nil, nil
  end
  if type(value) ~= "table" then
    error("read_csv null_values must be a non-empty string or a list, " ..
      "or a table of column = marker pairs", 3)
  end
  local array_keys = {}
  local named_keys = {}
  for key in pairs(value) do
    if type(key) == "number" then
      if key < 1 or key % 1 ~= 0 then
        error("read_csv null_values list indices must be positive integers", 3)
      end
      array_keys[#array_keys + 1] = key
    elseif type(key) == "string" then
      named_keys[#named_keys + 1] = key
    else
      error("read_csv null_values keys must be column names or list indices", 3)
    end
  end
  if #array_keys > 0 and #named_keys > 0 then
    error("read_csv null_values must be either a list of markers or a " ..
      "table of column = marker pairs", 3)
  end
  if #named_keys > 0 then
    table.sort(named_keys)
    local columns = {}
    local markers = {}
    for index, column in ipairs(named_keys) do
      if column == "" then
        error("read_csv null_values column names must be non-empty strings", 3)
      end
      local marker = value[column]
      if type(marker) ~= "string" or marker == "" then
        error("read_csv null_values markers must be non-empty strings", 3)
      end
      columns[index] = column
      markers[index] = marker
    end
    return nil, 0, columns, markers
  end
  if #array_keys == 0 then
    error("read_csv null_values must not be empty", 3)
  end
  table.sort(array_keys)
  for index, key in ipairs(array_keys) do
    if key ~= index then
      error("read_csv null_values must be a contiguous list of strings", 3)
    end
  end
  local seen = {}
  local result = {}
  for index = 1, #array_keys do
    local marker = value[index]
    if type(marker) ~= "string" or marker == "" then
      error("read_csv null_values entries must be non-empty strings", 3)
    end
    if seen[marker] then
      error("duplicate read_csv null value '" .. marker .. "'", 3)
    end
    seen[marker] = true
    result[index] = marker
  end
  return result, #result, nil, nil
end

-- Replacement names are positional and replace the leading columns of the
-- frame that would otherwise be returned. Like columns/null_values, the table
-- must be a contiguous list; it is applied after projection and dtype
-- overrides, so it renames the columns the caller actually receives.
local function csv_rename_columns(value)
  if value == nil then
    return nil
  end
  if type(value) ~= "table" then
    error("read_csv rename_columns must be a non-empty list of column names", 3)
  end
  local keys = {}
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      error("read_csv rename_columns must be a non-empty list of column names", 3)
    end
    keys[#keys + 1] = key
  end
  if #keys == 0 then
    error("read_csv rename_columns must not be empty", 3)
  end
  table.sort(keys)
  for index, key in ipairs(keys) do
    if key ~= index then
      error("read_csv rename_columns must be a contiguous list of strings", 3)
    end
  end
  local seen = {}
  local result = {}
  for index = 1, #keys do
    local name = value[index]
    if type(name) ~= "string" or name == "" then
      error("read_csv rename_columns entries must be non-empty strings", 3)
    end
    if seen[name] then
      error("duplicate read_csv column name '" .. name .. "'", 3)
    end
    seen[name] = true
    result[index] = name
  end
  return result
end

-- Strict UTF-8 is the default and matches the pre-encoding behavior. The lossy
-- mode is opt-in because it changes invalid bytes to U+FFFD instead of failing
-- the read; names are matched case-insensitively like dtype aliases.
local function csv_encoding(value)
  if value == nil then
    return nil
  end
  if type(value) ~= "string" then
    error("read_csv encoding must be 'utf8' or 'utf8-lossy'", 3)
  end
  local normalized = value:lower()
  if normalized == "utf8" then
    return "utf8"
  end
  if normalized == "utf8-lossy" then
    return "utf8-lossy"
  end
  error("read_csv encoding must be 'utf8' or 'utf8-lossy'", 3)
end

-- Polars' row window counts are rows, not Lua table indices. For CSV,
-- skip_rows drops rows before the header is parsed; for Parquet it drops
-- leading data rows. In both cases n_rows limits the data rows after the
-- offset. Both are non-negative safe integers, and an absent n_rows becomes
-- the ABI's -1 sentinel for "read every remaining row".
local function row_window(options, label)
  label = label or "read_csv"
  if options == nil then
    return 0, -1, false
  end
  local requested = options.skip_rows ~= nil or options.n_rows ~= nil
  local skip_rows = options.skip_rows
  if skip_rows == nil then skip_rows = 0 end
  if type(skip_rows) ~= "number" or skip_rows < 0 or skip_rows % 1 ~= 0 or
      skip_rows > MAX_SAFE_INTEGER then
    error(label .. " skip_rows must be a non-negative integer", 3)
  end
  local n_rows = options.n_rows
  if n_rows == nil then
    return skip_rows, -1, requested
  end
  if type(n_rows) ~= "number" or n_rows < 0 or n_rows % 1 ~= 0 or
      n_rows > MAX_SAFE_INTEGER then
    error(label .. " n_rows must be a non-negative integer", 3)
  end
  return skip_rows, n_rows, requested
end

local function csv_row_window(options)
  return row_window(options, "read_csv")
end

-- Date inference is opt-in because it changes an ISO-looking string column
-- into a Date/Datetime column and therefore its schema and sorting behavior.
local function csv_try_parse_dates(value)
  if value == nil then
    return false
  end
  if type(value) ~= "boolean" then
    error("read_csv try_parse_dates must be a boolean", 3)
  end
  return value
end

local function csv_options(options)
  if options == nil then
    return ",", true, '"', "", nil, nil, 0, nil, 0, 0, -1, false, nil, nil,
      nil, nil, false
  end
  if type(options) ~= "table" then
    error("read_csv options must be a table", 3)
  end
  for key in pairs(options) do
    if not CSV_OPTION_KEYS[key] then
      error("read_csv options: unknown field '" .. tostring(key) .. "'", 3)
    end
  end
  local delimiter = options.delimiter
  if delimiter == nil then delimiter = "," end
  if type(delimiter) ~= "string" then
    error("read_csv delimiter must be a string", 3)
  end
  local header = options.header
  if header == nil then header = true end
  if type(header) ~= "boolean" then
    error("read_csv header must be a boolean", 3)
  end
  local quote = csv_byte_option(options, "quote", '"')
  local comment = csv_byte_option(options, "comment", "")
  local columns = csv_columns(options.columns)
  local rename_columns = csv_rename_columns(options.rename_columns)
  local dtypes, dtype_count = csv_dtypes(options.dtypes)
  local null_values, null_value_count, named_null_columns, named_null_values =
    csv_null_values(options.null_values)
  local skip_rows, n_rows, window_requested = csv_row_window(options)
  local encoding = csv_encoding(options.encoding)
  local try_parse_dates = csv_try_parse_dates(options.try_parse_dates)
  return delimiter, header, quote, comment, columns, dtypes, dtype_count,
    null_values, null_value_count, skip_rows, n_rows, window_requested,
    rename_columns, encoding, named_null_columns, named_null_values,
    try_parse_dates
end

function polars.read_csv(path, options)
  if type(path) ~= "string" or path == "" then
    error("read_csv path must be a non-empty string", 2)
  end
  local delimiter, header, quote, comment, columns, dtypes, dtype_count,
    null_values, null_value_count, skip_rows, n_rows, window_requested,
    rename_columns, encoding, named_null_columns, named_null_values,
    try_parse_dates = csv_options(options)
  local err = ffi.new("char *[1]")
  local names
  if columns ~= nil then
    names = ffi.new("const char *[?]", #columns)
    for index, name in ipairs(columns) do
      names[index - 1] = name
    end
  end
  local dtype_pairs
  if dtypes ~= nil then
    dtype_pairs = ffi.new("const char *[?]", #dtypes)
    for index, value in ipairs(dtypes) do
      dtype_pairs[index - 1] = value
    end
  end
  local markers
  if null_values ~= nil then
    markers = ffi.new("const char *[?]", #null_values)
    for index, value in ipairs(null_values) do
      markers[index - 1] = value
    end
  end
  local renames
  if rename_columns ~= nil then
    renames = ffi.new("const char *[?]", #rename_columns)
    for index, value in ipairs(rename_columns) do
      renames[index - 1] = value
    end
  end
  local named_columns
  local named_markers
  if named_null_columns ~= nil then
    named_columns = ffi.new("const char *[?]", #named_null_columns)
    named_markers = ffi.new("const char *[?]", #named_null_values)
    for index, value in ipairs(named_null_columns) do
      named_columns[index - 1] = value
      named_markers[index - 1] = named_null_values[index]
    end
  end
  local pointer
  if try_parse_dates then
    pointer = lib.pl_dataframe_read_csv_parsed(path, delimiter,
      header and 1 or 0, quote, comment, names, names and #columns or 0,
      dtype_pairs, dtype_count, markers, null_value_count, named_columns,
      named_markers, named_null_columns and #named_null_columns or 0,
      skip_rows, n_rows, renames, rename_columns and #rename_columns or 0,
      encoding, 1, err)
  elseif named_null_columns ~= nil then
    pointer = lib.pl_dataframe_read_csv_named_nulls(path, delimiter,
      header and 1 or 0, quote, comment, names, names and #columns or 0,
      dtype_pairs, dtype_count, named_columns, named_markers,
      #named_null_columns, skip_rows, n_rows, renames,
      rename_columns and #rename_columns or 0, encoding, err)
  elseif rename_columns ~= nil then
    pointer = lib.pl_dataframe_read_csv_renamed(path, delimiter,
      header and 1 or 0, quote, comment, names, names and #columns or 0,
      dtype_pairs, dtype_count, markers, null_value_count, skip_rows, n_rows,
      renames, #rename_columns, encoding, err)
  elseif encoding ~= nil then
    pointer = lib.pl_dataframe_read_csv_encoded(path, delimiter,
      header and 1 or 0, quote, comment, names, names and #columns or 0,
      dtype_pairs, dtype_count, markers, null_value_count, skip_rows, n_rows,
      encoding, err)
  elseif window_requested then
    pointer = lib.pl_dataframe_read_csv_row_window(path, delimiter,
      header and 1 or 0, quote, comment, names, names and #columns or 0,
      dtype_pairs, dtype_count, markers, null_value_count, skip_rows, n_rows,
      err)
  elseif null_values ~= nil then
    pointer = lib.pl_dataframe_read_csv_null_values(path, delimiter,
      header and 1 or 0, quote, comment, names, names and #columns or 0,
      dtype_pairs, dtype_count, markers, null_value_count, err)
  elseif dtypes ~= nil then
    pointer = lib.pl_dataframe_read_csv_typed(path, delimiter,
      header and 1 or 0, quote, comment, names, names and #columns or 0,
      dtype_pairs, dtype_count, err)
  elseif columns == nil then
    pointer = lib.pl_dataframe_read_csv_ex(path, delimiter,
      header and 1 or 0, quote, comment, err)
  else
    pointer = lib.pl_dataframe_read_csv_projected(path, delimiter,
      header and 1 or 0, quote, comment, names, #columns, err)
  end
  return new_frame(pointer, err)
end

local PARQUET_READ_OPTION_KEYS = {
  columns = true,
  skip_rows = true,
  n_rows = true,
}

local function parquet_read_options(options)
  if options == nil then
    return nil, 0, -1, false
  end
  if type(options) ~= "table" then
    error("read_parquet options must be a table", 3)
  end
  for key in pairs(options) do
    if not PARQUET_READ_OPTION_KEYS[key] then
      error("read_parquet options: unknown field '" .. tostring(key) .. "'", 3)
    end
  end
  local columns = column_projection(options.columns, "read_parquet")
  local skip_rows, n_rows, requested = row_window(options, "read_parquet")
  return columns, skip_rows, n_rows, requested or columns ~= nil
end

function polars.read_parquet(path, options)
  if type(path) ~= "string" or path == "" then
    error("read_parquet path must be a non-empty string", 2)
  end
  local columns, skip_rows, n_rows, requested = parquet_read_options(options)
  local err = ffi.new("char *[1]")
  local pointer
  if not requested then
    pointer = lib.pl_dataframe_read_parquet(path, err)
  else
    local names
    if columns ~= nil then
      names = ffi.new("const char *[?]", #columns)
      for index, name in ipairs(columns) do
        names[index - 1] = name
      end
    end
    pointer = lib.pl_dataframe_read_parquet_options(path, names,
      names and #columns or 0, skip_rows, n_rows, err)
  end
  return new_frame(pointer, err)
end

local JSON_READ_OPTION_KEYS = {
  format = true,
  columns = true,
}

local function read_json_options(options)
  if options == nil then
    return "array", nil
  end
  if type(options) ~= "table" then
    error("read_json options must be a table", 3)
  end
  for key in pairs(options) do
    if not JSON_READ_OPTION_KEYS[key] then
      error("read_json options: unknown field '" .. tostring(key) .. "'", 3)
    end
  end
  return json_format(options.format, "read_json"),
    column_projection(options.columns, "read_json")
end

function polars.read_json(path, options)
  if type(path) ~= "string" or path == "" then
    error("read_json path must be a non-empty string", 2)
  end
  local format, columns = read_json_options(options)
  local err = ffi.new("char *[1]")
  local names
  if columns ~= nil then
    names = ffi.new("const char *[?]", #columns)
    for index, name in ipairs(columns) do
      names[index - 1] = name
    end
  end
  local pointer = lib.pl_dataframe_read_json(path,
    format == "lines" and 1 or 0, names, names and #columns or 0, err)
  return new_frame(pointer, err)
end

return polars
