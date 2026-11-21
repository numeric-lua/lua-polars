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
PlFrame *pl_dataframe_read_parquet(const char *path, char **err);
void pl_dataframe_free(PlFrame *frame);
int pl_dataframe_shape(PlFrame *frame, uint64_t *rows, uint64_t *cols);
char *pl_dataframe_schema_json(PlFrame *frame, char **err);
char *pl_dataframe_columns_json(PlFrame *frame, char **err);
PlFrame *pl_dataframe_head(PlFrame *frame, int64_t n, char **err);
PlFrame *pl_dataframe_join(
    PlFrame *left, PlFrame *right, const char *how,
    const char *const *left_on, uint64_t left_count,
    const char *const *right_on, uint64_t right_count,
    int32_t nulls_equal, char **err);
PlFrame *pl_dataframe_sql(PlFrame *frame, const char *query, char **err);
int pl_dataframe_write_csv(PlFrame *frame, const char *path, char **err);
int pl_dataframe_write_parquet(PlFrame *frame, const char *path, char **err);
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
  if type(count) ~= "number" or count < 0 or count % 1 ~= 0 then
    error("head count must be a non-negative integer", 2)
  end
  local err = ffi.new("char *[1]")
  local pointer = lib.pl_dataframe_head(self:_require_open(), count, err)
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

local function quote_identifier(name)
  return '"' .. tostring(name):gsub('"', '""') .. '"'
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

function DataFrame:drop_nulls()
  local conditions = {}
  for _, name in ipairs(self:columns()) do
    conditions[#conditions + 1] = quote_identifier(name) .. " IS NOT NULL"
  end
  return self:sql("SELECT * FROM df WHERE " .. table.concat(conditions, " AND "))
end

function DataFrame:fill_null(strategy)
  strategy = strategy or "zero"
  local fill = strategy == "zero" and 0 or strategy == "one" and 1 or nil
  if fill == nil then
    error("fill_null supports zero or one", 2)
  end
  local projections = {}
  for _, name in ipairs(self:columns()) do
    local quoted = quote_identifier(name)
    projections[#projections + 1] = "COALESCE(" .. quoted .. ", " ..
      tostring(fill) .. ") AS " .. quoted
  end
  return self:sql("SELECT " .. table.concat(projections, ", ") .. " FROM df")
end

function DataFrame:write_csv(path) return write_frame(self, path, "pl_dataframe_write_csv") end
function DataFrame:write_parquet(path) return write_frame(self, path, "pl_dataframe_write_parquet") end

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
  _VERSION = "0.9.0",
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
  dtypes = true,
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

local function csv_columns(value)
  if value == nil then
    return nil
  end
  local columns
  if type(value) == "string" then
    columns = { value }
  elseif type(value) == "table" then
    columns = value
  else
    error("read_csv columns must be a column name or a list of names", 3)
  end
  if #columns == 0 then
    error("read_csv columns must not be empty", 3)
  end
  local seen = {}
  local result = {}
  for index, name in ipairs(columns) do
    if type(name) ~= "string" or name == "" then
      error("read_csv columns entries must be non-empty strings", 3)
    end
    if seen[name] then
      error("duplicate read_csv column '" .. name .. "'", 3)
    end
    seen[name] = true
    result[index] = name
  end
  if #result == 0 then
    error("read_csv columns must not be empty", 3)
  end
  return result
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

local function csv_options(options)
  if options == nil then
    return ",", true, '"', "", nil, nil, 0
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
  local dtypes, dtype_count = csv_dtypes(options.dtypes)
  return delimiter, header, quote, comment, columns, dtypes, dtype_count
end

function polars.read_csv(path, options)
  if type(path) ~= "string" or path == "" then
    error("read_csv path must be a non-empty string", 2)
  end
  local delimiter, header, quote, comment, columns, dtypes, dtype_count =
    csv_options(options)
  local err = ffi.new("char *[1]")
  local names
  if columns ~= nil then
    names = ffi.new("const char *[?]", #columns)
    for index, name in ipairs(columns) do
      names[index - 1] = name
    end
  end
  local pointer
  if dtypes ~= nil then
    local dtype_pairs = ffi.new("const char *[?]", #dtypes)
    for index, value in ipairs(dtypes) do
      dtype_pairs[index - 1] = value
    end
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

function polars.read_parquet(path)
  if type(path) ~= "string" or path == "" then
    error("read_parquet path must be a non-empty string", 2)
  end
  local err = ffi.new("char *[1]")
  local pointer = lib.pl_dataframe_read_parquet(path, err)
  return new_frame(pointer, err)
end

return polars
