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

local function library_candidates()
  local root = module_root()
  local suffix = jit.os == "OSX" and ".dylib" or ".so"
  local result = {
    root .. "/libpolars_lua" .. suffix,
    root .. "/target/release/libpolars_lua" .. suffix,
    root .. "/target/debug/libpolars_lua" .. suffix,
    root .. "/build/libpolars_lua" .. suffix,
  }
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
  _VERSION = "0.6.0",
  null = json.null,
  DataFrame = DataFrame,
}

function polars.version()
  return ffi.string(lib.pl_version())
end

function polars.read_csv(path)
  if type(path) ~= "string" or path == "" then
    error("read_csv path must be a non-empty string", 2)
  end
  local err = ffi.new("char *[1]")
  local pointer = lib.pl_dataframe_read_csv(path, err)
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
