--- A key value parser written with Lpeg.
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
-- @module luakeys

local lpeg = require('lpeg')

--- Generate the PEG parser using Lpeg.
--
-- @treturn userdata The parser
local function generate_parser()
  -- Optional whitespace
  local white_space = lpeg.S(' \t\n\r')^0

  --- Match literal string surrounded by whitespace
  local WhiteSpacedPattern = function(match)
    return white_space * lpeg.P(match) * white_space
  end

  local boolean_true =
    lpeg.P('true') +
    lpeg.P('TRUE') +
    lpeg.P('yes') +
    lpeg.P('YES')

  local boolean_false =
    lpeg.P('false') +
    lpeg.P('FALSE') +
    lpeg.P('no') +
    lpeg.P('NO')

  local number = lpeg.P({'number',
    number =
      lpeg.V('int') *
      lpeg.V('frac')^-1 *
      lpeg.V('exp')^-1,

    int = lpeg.V('sign')^-1 * (
      lpeg.R('19') * lpeg.V('digits') + lpeg.V('digit')
    ),

    sign = lpeg.S('+-'),
    digit = lpeg.R('09'),
    digits = lpeg.V('digit') * lpeg.V('digits') + lpeg.V('digit'),
    frac = lpeg.P('.') * lpeg.V('digits'),
    exp = lpeg.S('eE') * lpeg.V('sign')^-1 * lpeg.V('digits'),
  })

  --- Define data type dimension.
  --
  -- @return Lpeg patterns
  local function build_dimension_pattern()
    local sign = lpeg.S('-+')
    local integer = lpeg.R('09')^1
    local number = integer^1 * lpeg.P('.')^0 * integer^0
    local unit
    -- https://raw.githubusercontent.com/latex3/lualibs/master/lualibs-util-dim.lua
    for _, dimension_extension in ipairs({'bp', 'cc', 'cm', 'dd', 'em', 'ex', 'in', 'mm', 'nc', 'nd', 'pc', 'pt', 'sp'}) do
      if unit then
        unit = unit + lpeg.P(dimension_extension)
      else
        unit = lpeg.P(dimension_extension)
      end
    end

    return (sign^0 * number * unit)
  end

  --- Add values to a table in a two modes:
  --
  -- # Key value pair
  --
  -- If arg1 and arg2 are not nil, then arg1 is the key and arg2 is the
  -- value of a new table entry.
  --
  -- # Index value
  --
  -- If arg2 is nil, then arg1 is the value and is added as an indexed
  -- (by an integer) value.
  --
  -- @tparam table table
  -- @tparam mixed arg1
  -- @tparam mixed arg2
  --
  -- @treturn table
  local add_to_table = function(table, arg1, arg2)
    if arg2 == nil then
      local index = #table + 1
      return rawset(table, index, arg1)
    else
      return rawset(table, arg1, arg2)
    end
  end

  return lpeg.P({
    'list',
    value =
      lpeg.V('object') +
      lpeg.V('bool_value') +
      lpeg.V('dimension_value') +
      lpeg.V('number_value') +
      lpeg.V('string_value') +
      lpeg.V('string_value_unquoted'),

    bool_value =
      boolean_true * lpeg.Cc(true) +
      boolean_false * lpeg.Cc(false),

    dimension_value = lpeg.C(build_dimension_pattern()),

    string_value =
      white_space * lpeg.P('"') *
      lpeg.C((lpeg.P('\\"') + 1 - lpeg.P('"'))^0) *
      lpeg.P('"') * white_space,

    string_value_unquoted =
      white_space *
      lpeg.C((1 - lpeg.S('{},='))^1) *
      white_space,

    number_value =
      white_space * (number / tonumber) * white_space,

    -- ./ for tikz style keys
    key_word = lpeg.R('az', 'AZ', '09', './'),

    key = white_space * lpeg.C(
      lpeg.V('key_word')^1 *
      (lpeg.P(' ')^1 * lpeg.V('key_word')^1)^0
    ) * white_space,

    value_without_key =
      lpeg.V('dimension_value') +
      lpeg.V('number_value') +
      lpeg.V('string_value') +
      lpeg.V('string_value_unquoted'),

    key_value_pair =
      lpeg.V('key') * WhiteSpacedPattern('=') * lpeg.V('value'),

    member_pair =
      lpeg.Cg(
        lpeg.V('key_value_pair') +
        lpeg.V('value_without_key')
      ) * WhiteSpacedPattern(',')^-1,

    list = lpeg.Cf(
      lpeg.Ct('') * lpeg.V('member_pair')^0,
      add_to_table
    ),

    object =
      WhiteSpacedPattern('{') * lpeg.V('list') * WhiteSpacedPattern('}')
  })
end

local function trim(input_string)
  return input_string:gsub('^%s*(.-)%s*$', '%1')
end

--- Get the size of an array like table `{ 'one', 'two', 'three' }` = 3.
--
-- @tparam table value A table or any input.
--
-- @treturn number The size of the array like table. 0 if the input is
-- no table or the table is empty.
local function get_array_size(value)
  local count = 0
  if type(value) == 'table' then
    for _ in ipairs(value) do count = count + 1 end
  end
  return count
end

--- Get the size of a table `{ one = 'one', 'two', 'three' }` = 3.
--
-- @tparam table value A table or any input.
--
-- @treturn number The size of the array like table. 0 if the input is
-- no table or the table is empty.
local function get_table_size(value)
  local count = 0
  if type(value) == 'table' then
    for _ in pairs(value) do count = count + 1 end
  end
  return count
end

--- Unpack a single valued array table like `{ 'one' }` into `one` or
-- `{ 1 }` into `into`.
--
-- @treturn If the value is a array like table with one non table typed
-- value in it, the unpacked value, else the unchanged input.
local function unpack_single_valued_array_table(value)
  if
    type(value) == 'table' and
    get_array_size(value) == 1 and
    get_table_size(value) == 1 and
    type(value[1]) ~= 'table'
  then
    return value[1]
  end
  return value
end

--- This normalization tasks are performed on the raw input table
-- coming directly from the PEG parser:
--
-- 1. Trim all strings: ` text \n` into `text`
-- 2. Unpack all single valued array like tables: `{ 'text' }`
--    into `text`
--
-- @tparam table raw The raw input table coming directly from the PEG
--   parser
--
-- @treturn table A normalized table ready for the outside world.
local function normalize(raw)
  local function normalize_recursive(raw, result)
    for key, value in pairs(raw) do
      value = unpack_single_valued_array_table(value)
      if type(value) == 'table' then
        result[key] = normalize_recursive(value, {})
      elseif type(value) == 'string' then
        result[key] = trim(value)
      else
        result[key] = value
      end
    end
    return result
  end
  return normalize_recursive(raw, {})
end

local parser = generate_parser()

return {
  --- Parse a LaTeX/TeX style key-value string into a Lua table. With
  -- this function you should be able to parse key-value strings like
  -- this example:
  --
  --     show,
  --     hide,
  --     'string,with,commas inside single quotes',
  --     key with spaces = String without quotes,
  --     string="String with double quotes: ,{}=",
  --     dimension = 1cm,
  --     number = 2,
  --     float = 1.2,
  --     list = {one,two,three},
  --     key value list = {one=one,two=two,three=three},
  --     nested key = {
  --       nested key 2= {
  --         key = value,
  --       },
  --     },
  --
  -- The string above results in this Lua table:
  --
  --     {
  --       'show',
  --       'hide',
  --       'string,with,commas inside single quotes',
  --       ['key with spaces'] = 'String without quotes',
  --       string = 'String with double quotes: ,{}=',
  --       dimension = '1cm',
  --       number = 2,
  --       float = 1.2,
  --       list = {'one', 'two', 'three'},
  --       key value list = {
  --         one = 'one',
  --         three = 'three',
  --         two = 'two'
  --       },
  --       ['nested key'] = {
  --         ['nested key 2'] = {
  --           key = 'value'
  --         }
  --       },
  --     }
  --
  -- @treturn table A hopefully properly parsed table you can
  -- do something useful with.
  parse = function (input)
    return normalize(parser:match(input))
  end
}
