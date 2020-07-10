local lpeg = require('lpeg')

--- See [lpeg.P](http://www.inf.puc-rio.br/~roberto/lpeg#op-p)
--
-- Like `"literal"` in peg.js.
local Pattern = lpeg.P

--- See [lpeg.R](http://www.inf.puc-rio.br/~roberto/lpeg#op-r)
--
-- Like `[a-z]` in peg.js.
local Range = lpeg.R

--- See [lpeg.S](http://www.inf.puc-rio.br/~roberto/lpeg#op-s)
--
-- Like `[characters]` in peg.js.
local Set = lpeg.S

--- See [lpeg.C](http://www.inf.puc-rio.br/~roberto/lpeg#cap-c)
local capture = lpeg.C

--- See [lpeg.Ct](http://www.inf.puc-rio.br/~roberto/lpeg#cap-t)
local capture_table = lpeg.Ct

--- See [lpeg.Cf](http://www.inf.puc-rio.br/~roberto/lpeg#cap-f)
local capture_fold = lpeg.Cf

--- See [lpeg.Cg](http://www.inf.puc-rio.br/~roberto/lpeg#cap-g)
local capture_group = lpeg.Cg

--- See [lpeg.Cg](http://www.inf.puc-rio.br/~roberto/lpeg#cap-cc)
local capture_constant = lpeg.Cc



--- Define data type boolean.
--
-- @return Lpeg patterns
local function data_type_boolean ()
  local boolean_true = (
    Pattern('true') +
    Pattern('TRUE') +
    Pattern('yes') +
    Pattern('YES')
  ) * capture_constant(true)

  local boolean_false = (
    Pattern('false') +
    Pattern('FALSE') +
    Pattern('no') +
    Pattern('NO')
  ) * capture_constant(false)

  return boolean_true + boolean_false
end

--- Define data type integer.
--
-- @return Lpeg patterns
local function data_type_integer()
  -- patt / function
  -- Creates a function capture. It calls the given function passing
  -- all captures made b nby patt as arguments, or the whole match if
  -- patt made no capture. The values returned by the function are the
  -- final values of the capture. In particular, if function returns
  -- no value, there is no captured value
  return Range('09')^1 / tonumber
end

--- Define data type dimension.
--
-- @return Lpeg patterns
-- local function data_type_dimension()
--   local sign = Set('-+')
--   local integer = Range('09')^1
--   local number = integer^1 * Pattern('.')^0 * integer^0
--   local unit =
--     Pattern('pt') +
--     Pattern('cm') +
--     Pattern('mm') +
--     Pattern('sp') +
--     Pattern('bp') +
--     Pattern('in') +
--     Pattern('pc') +
--     Pattern('dd') +
--     Pattern('cc')

--   -- patt / function -> function capture
--   return (sign^0 * number * unit) / tex.sp
-- end

--- Define data type string.
--
-- @return Lpeg patterns
local data_type_string = function()
  return capture(Range('az', 'AZ', '09')^1)
end

local data_types = {
  boolean = data_type_boolean(),
  integer = data_type_integer(),
  --dimension = data_type_dimension(),
  string = data_type_string(),
}


local white_space = Set(' \t\r\n')^0

local capture_key_value_pair = function(arg1, arg2)
  print(arg1)
  print(arg2)
  return arg1, arg2
end

---
--
-- @tparam string key
-- @tparam table definition keys: alias, type
local build_single_key_value_definition = function(key, definition)
  local key_pattern
  if definition.alias then
    -- alias = {'mlines', 'minlines'}
    if type(definition.alias) == 'table' then
      key_pattern = Pattern(key)
      for _, value in ipairs(definition.alias) do
        key_pattern = key_pattern + Pattern(value)  -- long alias first: 'bool', 'b'
      end
      key_pattern = (key_pattern) * capture_constant(key)
    -- alias = 'minlines'
    else
      key_pattern =
        (Pattern(key) + Pattern(definition.alias)) *
        capture_constant(key)
    end
  else
    key_pattern = capture(Pattern(key))
  end

  -- show -> show=true
  if definition.type == 'keyonly' then
    return key_pattern * capture_constant(true)
  -- key=value
  else
    return
      key_pattern * white_space *
      Pattern('=') * white_space *
      data_types[definition.type]
  end
end

--- A naive key value parser written with Lpeg to get rid of kvoptions.
--
-- * `patt^0` = `expression *` (peg.js)
-- * `patt^1` = `expression +` (peg.js)
-- * `patt^-1` = `expression ?` (peg.js)
-- * `patt1 * patt2` = `expression1 expression2` (peg.js) -> Sequence
-- * `patt1 + patt2` = `expression1 / expression2` (peg.js) -> Ordered choice
--
-- * [TUGboat article: Parsing complex data formats in LuaTEX with LPEG](https://tug.org/TUGboat/tb40-2/tb125menke-lpeg.pdf)
-- * [Dimension handling in lualibs](https://github.com/lualatex/lualibs/blob/master/lualibs-util-dim.lua)
--
-- @tparam string input The key value options in a unparsed fashion as a
--   string.
--
-- @treturn table The key value options as a table.
local function build_parser(definitions)
  local key_values

  for key, definition in pairs(definitions) do
    local key_value = build_single_key_value_definition(key, definition)

    if not key_values then
      key_values = key_value
    else
      key_values = key_values + key_value
    end
  end

  -- Catch left over keys or key value pairs for error reportings
  local generic_catcher = capture(Range('az')^1) * white_space *
    Pattern('=')^-1 * white_space *
    capture(Range('09', 'az', 'AZ')^0) / capture_key_value_pair

  local keyval_groups = capture_group(key_values + generic_catcher * Pattern(',')^-1)

  -- rawset (table, index, value)
  -- Sets the real value of table[index] to value, without invoking the
  -- __newindex metamethod. table must be a table, index any value
  -- different from nil and NaN, and value any Lua value.
  return capture_fold(capture_table('') * keyval_groups^0, rawset)
end

return {
  build_parser = build_parser,
}