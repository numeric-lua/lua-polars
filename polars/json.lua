--
-- Minimal JSON decoder used by the Polars bridge.
--
-- It intentionally has no external dependencies.  JSON null is represented by
-- the `json.null` sentinel so callers can distinguish it from a missing key.
--
local json = {}

json.null = setmetatable({}, {
  __tostring = function()
    return "null"
  end,
})

local function fail(position, message)
  error(string.format("invalid JSON at byte %d: %s", position, message), 3)
end

local function skip(text, index)
  while index <= #text do
    local byte = text:sub(index, index)
    if byte ~= " " and byte ~= "\n" and byte ~= "\r" and byte ~= "\t" then
      break
    end
    index = index + 1
  end
  return index
end

local function utf8_char(code)
  if code <= 0x7f then
    return string.char(code)
  elseif code <= 0x7ff then
    return string.char(
      0xc0 + math.floor(code / 0x40),
      0x80 + (code % 0x40))
  elseif code <= 0xffff then
    return string.char(
      0xe0 + math.floor(code / 0x1000),
      0x80 + (math.floor(code / 0x40) % 0x40),
      0x80 + (code % 0x40))
  end
  return string.char(
    0xf0 + math.floor(code / 0x40000),
    0x80 + (math.floor(code / 0x1000) % 0x40),
    0x80 + (math.floor(code / 0x40) % 0x40),
    0x80 + (code % 0x40))
end

local function parse_string(text, index)
  if text:sub(index, index) ~= '"' then
    fail(index, "expected a string")
  end
  index = index + 1
  local pieces = {}
  while index <= #text do
    local byte = text:sub(index, index)
    if byte == '"' then
      return table.concat(pieces), index + 1
    elseif byte == "\\" then
      local escaped = text:sub(index + 1, index + 1)
      if escaped == '"' or escaped == "\\" or escaped == "/" then
        pieces[#pieces + 1] = escaped
      elseif escaped == "b" then
        pieces[#pieces + 1] = "\b"
      elseif escaped == "f" then
        pieces[#pieces + 1] = "\f"
      elseif escaped == "n" then
        pieces[#pieces + 1] = "\n"
      elseif escaped == "r" then
        pieces[#pieces + 1] = "\r"
      elseif escaped == "t" then
        pieces[#pieces + 1] = "\t"
      elseif escaped == "u" then
        local hex = text:sub(index + 2, index + 5)
        if not hex:match("^%x%x%x%x$") then
          fail(index, "invalid unicode escape")
        end
        pieces[#pieces + 1] = utf8_char(tonumber(hex, 16))
        index = index + 4
      else
        fail(index, "invalid escape sequence")
      end
      index = index + 2
    else
      pieces[#pieces + 1] = byte
      index = index + 1
    end
  end
  fail(index, "unterminated string")
end

local function parse_number(text, index)
  local start = index
  if text:sub(index, index) == "-" then
    index = index + 1
  end
  local digits = 0
  while text:sub(index, index):match("%d") do
    index = index + 1
    digits = digits + 1
  end
  if digits == 0 then
    fail(start, "expected a number")
  end
  if text:sub(index, index) == "." then
    index = index + 1
    local fraction = 0
    while text:sub(index, index):match("%d") do
      index = index + 1
      fraction = fraction + 1
    end
    if fraction == 0 then
      fail(index, "expected digits after decimal point")
    end
  end
  local exponent = text:sub(index, index)
  if exponent == "e" or exponent == "E" then
    index = index + 1
    local sign = text:sub(index, index)
    if sign == "+" or sign == "-" then
      index = index + 1
    end
    local exponent_digits = 0
    while text:sub(index, index):match("%d") do
      index = index + 1
      exponent_digits = exponent_digits + 1
    end
    if exponent_digits == 0 then
      fail(index, "expected exponent digits")
    end
  end
  local number = tonumber(text:sub(start, index - 1))
  if number == nil then
    fail(start, "invalid number")
  end
  return number, index
end

local parse_value

local function parse_array(text, index)
  index = index + 1
  index = skip(text, index)
  local result = {}
  if text:sub(index, index) == "]" then
    return result, index + 1
  end
  while true do
    local value
    value, index = parse_value(text, index)
    result[#result + 1] = value
    index = skip(text, index)
    local delimiter = text:sub(index, index)
    if delimiter == "]" then
      return result, index + 1
    elseif delimiter ~= "," then
      fail(index, "expected ',' or ']'")
    end
    index = skip(text, index + 1)
  end
end

local function parse_object(text, index)
  index = index + 1
  index = skip(text, index)
  local result = {}
  if text:sub(index, index) == "}" then
    return result, index + 1
  end
  while true do
    local key
    key, index = parse_string(text, index)
    index = skip(text, index)
    if text:sub(index, index) ~= ":" then
      fail(index, "expected ':'")
    end
    index = skip(text, index + 1)
    local value
    value, index = parse_value(text, index)
    result[key] = value
    index = skip(text, index)
    local delimiter = text:sub(index, index)
    if delimiter == "}" then
      return result, index + 1
    elseif delimiter ~= "," then
      fail(index, "expected ',' or '}'")
    end
    index = skip(text, index + 1)
  end
end

parse_value = function(text, index)
  index = skip(text, index)
  local byte = text:sub(index, index)
  if byte == '"' then
    return parse_string(text, index)
  elseif byte == "{" then
    return parse_object(text, index)
  elseif byte == "[" then
    return parse_array(text, index)
  elseif byte == "t" and text:sub(index, index + 3) == "true" then
    return true, index + 4
  elseif byte == "f" and text:sub(index, index + 4) == "false" then
    return false, index + 5
  elseif byte == "n" and text:sub(index, index + 3) == "null" then
    return json.null, index + 4
  elseif byte == "-" or byte:match("%d") then
    return parse_number(text, index)
  end
  fail(index, "expected a value")
end

function json.decode(text)
  if type(text) ~= "string" then
    error("json.decode expects a string", 2)
  end
  local value, index = parse_value(text, 1)
  index = skip(text, index)
  if index <= #text then
    fail(index, "trailing data")
  end
  return value
end

return json
