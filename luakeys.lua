-- luakeys.lua
-- Copyright 2021-2022 Josef Friedrich
--
-- This work may be distributed and/or modified under the
-- conditions of the LaTeX Project Public License, either version 1.3c
-- of this license or (at your option) any later version.
-- The latest version of this license is in
--   http://www.latex-project.org/lppl.txt
-- and version 1.3c or later is part of all distributions of LaTeX
-- version 2008/05/04 or later.
--
-- This work has the LPPL maintenance status `maintained'.
--
-- The Current Maintainer of this work is Josef Friedrich.
--
-- This work consists of the files luakeys.lua, luakeys.sty, luakeys.tex
-- luakeys-debug.sty and luakeys-debug.tex.
--- A key-value parser written with Lpeg.
--
-- @module luakeys
local lpeg = require('lpeg')

if not tex then
  tex = {
    -- Dummy function for the tests.
    sp = function(input)
      return 1234567
    end,
  }
end

if not token then
  token = {
    set_macro = function(csname, content, global)
    end,
  }
end

--- Merge two tables in the first specified table.
--- The `merge_tables` function copies all keys from the `source` table
--- to a target table. It returns the modified target table.
---
---@see https://stackoverflow.com/a/1283608/10193818
---
---@param target table
---@param source table
---
---@return table target The modified target table.
local function merge_tables(target, source)
  for key, value in pairs(source) do
    if type(value) == 'table' then
      if type(target[key] or false) == 'table' then
        merge_tables(target[key] or {}, source[key] or {})
      elseif target[key] == nil then
        target[key] = value
      end
    elseif target[key] == nil then
      target[key] = value
    end
  end
  return target
end

---Clone a table.
---
---@see http://lua-users.org/wiki/CopyTable
---
---@param orig table
---
---@return table
local function clone_table(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[clone_table(orig_key)] = clone_table(orig_value)
    end
    setmetatable(copy, clone_table(getmetatable(orig)))
  else -- number, string, boolean, etc
    copy = orig
  end
  return copy
end

local utils = {
  --- Get the size of an array like table `{ 'one', 'two', 'three' }` = 3.
  ---
  ---@param value table # A table or any input.
  ---
  ---@return number # The size of the array like table. 0 if the input is no table or the table is empty.
  get_array_size = function(value)
    local count = 0
    if type(value) == 'table' then
      for _ in ipairs(value) do
        count = count + 1
      end
    end
    return count
  end,

  ---Get the size of a table `{ one = 'one', 'two', 'three' }` = 3.
  ---
  ---@param value table|any # A table or any input.
  ---
  ---@return number # The size of the array like table. 0 if the input is no table or the table is empty.
  get_table_size = function(value)
    local count = 0
    if type(value) == 'table' then
      for _ in pairs(value) do
        count = count + 1
      end
    end
    return count
  end,

  merge_tables = merge_tables,

  clone_table = clone_table,

  remove_from_array = function(array, element)
    for index, value in pairs(array) do
      if element == value then
        array[index] = nil
        return value
      end
    end
  end,

  ---Scan for an optional argument.
  ---
  ---@param initial_delimiter? string # The character that marks the beginning of an optional argument (by default `[`).
  ---@param end_delimiter? string # The character that marks the end of an optional argument (by default `]`).
  ---
  ---@return string|nil # The string that was enclosed by the delimiters. The delimiters themselves are not returned.
  scan_oarg = function(initial_delimiter, end_delimiter)
    if initial_delimiter == nil then
      initial_delimiter = '['
    end

    if end_delimiter == nil then
      end_delimiter = ']'
    end

    local function convert_token(t)
      if t.index ~= nil then
        return utf8.char(t.index)
      else
        return '\\' .. t.csname
      end
    end

    local function get_next_char()
      local t = token.get_next()
      return convert_token(t), t
    end

    local char, t = get_next_char()
    if char == initial_delimiter then
      local oarg = {}
      char = get_next_char()
      while char ~= end_delimiter do
        table.insert(oarg, char)
        char = get_next_char()
      end
      return table.concat(oarg, '')
    else
      token.put_next(t)
    end
  end,
}

local namespace = {
  opts = {
    assignment_operator = '=',
    convert_dimensions = false,
    debug = false,
    default = true,
    defaults = false,
    defs = false,
    format_keys = false,
    group_begin = '{',
    group_end = '}',
    hooks = {},
    list_separator = ',',
    naked_as_value = false,
    no_error = false,
    quotation_begin = '"',
    quotation_end = '"',
    unpack = true,
  },

  hooks = {
    kv_string = true,
    keys_before_opts = true,
    result_before_opts = true,
    keys_before_def = true,
    result_before_def = true,
    keys = true,
    result = true,
  },

  attrs = {
    alias = true,
    always_present = true,
    choices = true,
    data_type = true,
    default = true,
    exclusive_group = true,
    l3_tl_set = true,
    macro = true,
    match = true,
    name = true,
    opposite_keys = true,
    pick = true,
    process = true,
    required = true,
    sub_keys = true,
  },
}

--- The default options.
local default_options = clone_table(namespace.opts)

local function throw_error(message)
  if type(tex.error) == 'function' then
    tex.error(message)
  else
    error(message)
  end
end

--- Normalize the parse options.
---
---@param opts? table # Options in a raw format. The table may be empty or some keys are not set.
---
---@return table
local function normalize_opts(opts)
  if type(opts) ~= 'table' then
    opts = {}
  end
  for key, _ in pairs(opts) do
    if namespace.opts[key] == nil then
      throw_error('Unknown parse option: ' .. tostring(key) .. '!')
    end
  end
  local old_opts = opts
  opts = {}
  for name, _ in pairs(namespace.opts) do
    if old_opts[name] ~= nil then
      opts[name] = old_opts[name]
    else
      opts[name] = default_options[name]
    end
  end

  for hook in pairs(opts.hooks) do
    if namespace.hooks[hook] == nil then
      throw_error('Unknown hook: ' .. tostring(hook) .. '!')
    end
  end
  return opts
end

local l3_code_cctab = 10

--- Convert back to strings
-- @section

--- The function `render(tbl)` reverses the function
--- `parse(kv_string)`. It takes a Lua table and converts this table
--- into a key-value string. The resulting string usually has a
--- different order as the input table. In Lua only tables with
--- 1-based consecutive integer keys (a.k.a. array tables) can be
--- parsed in order.
---
---@param result table # A table to be converted into a key-value string.
---
---@return string # A key-value string that can be passed to a TeX macro.
local function render(result)
  local function render_inner(result)
    local output = {}
    local function add(text)
      table.insert(output, text)
    end
    for key, value in pairs(result) do
      if (key and type(key) == 'string') then
        if (type(value) == 'table') then
          if (next(value)) then
            add(key .. '={')
            add(render_inner(value))
            add('},')
          else
            add(key .. '={},')
          end
        else
          add(key .. '=' .. tostring(value) .. ',')
        end
      else
        add(tostring(value) .. ',')
      end
    end
    return table.concat(output)
  end
  return render_inner(result)
end

--- The function `stringify(tbl, for_tex)` converts a Lua table into a
--- printable string. Stringify a table means to convert the table into
--- a string. This function is used to realize the `debug` function.
--- `stringify(tbl, true)` (`for_tex = true`) generates a string which
--- can be embeded into TeX documents. The macro `\luakeysdebug{}` uses
--- this option. `stringify(tbl, false)` or `stringify(tbl)` generate a
--- string suitable for the terminal.
---
---@see https://stackoverflow.com/a/54593224/10193818
---
---@param result table # A table to stringify.
---@param for_tex? boolean # Stringify the table into a text string that can be embeded inside a TeX document via tex.print(). Curly braces and whites spaces are escaped.
---
---@return string
local function stringify(result, for_tex)
  local line_break, start_bracket, end_bracket, indent

  if for_tex then
    line_break = '\\par'
    start_bracket = '$\\{$'
    end_bracket = '$\\}$'
    indent = '\\ \\ '
  else
    line_break = '\n'
    start_bracket = '{'
    end_bracket = '}'
    indent = '  '
  end

  local function stringify_inner(input, depth)
    local output = {}
    depth = depth or 0

    local function add(depth, text)
      table.insert(output, string.rep(indent, depth) .. text)
    end

    local function format_key(key)
      if (type(key) == 'number') then
        return string.format('[%s]', key)
      else
        return string.format('[\'%s\']', key)
      end
    end

    if type(input) ~= 'table' then
      return tostring(input)
    end

    for key, value in pairs(input) do
      if (key and type(key) == 'number' or type(key) == 'string') then
        key = format_key(key)

        if (type(value) == 'table') then
          if (next(value)) then
            add(depth, key .. ' = ' .. start_bracket)
            add(0, stringify_inner(value, depth + 1))
            add(depth, end_bracket .. ',');
          else
            add(depth,
              key .. ' = ' .. start_bracket .. end_bracket .. ',')
          end
        else
          if (type(value) == 'string') then
            value = string.format('\'%s\'', value)
          else
            value = tostring(value)
          end

          add(depth, key .. ' = ' .. value .. ',')
        end
      end
    end

    return table.concat(output, line_break)
  end

  return start_bracket .. line_break .. stringify_inner(result, 1) ..
           line_break .. end_bracket
end

--- The function `debug(result)` pretty prints a Lua table to standard
--   output (stdout). It is a utility function that can be used to
--   debug and inspect the resulting Lua table of the function
--   `parse`. You have to compile your TeX document in a console to
--   see the terminal output.
--
---@param result table # A table to be printed to standard output for debugging purposes.
local function debug(result)
  print('\n' .. stringify(result, false))
end

--- Parser / Lpeg related
-- @section

--- Generate the PEG parser using Lpeg.
---
--- Explanations of some LPeg notation forms:
---
--- * `patt ^ 0` = `expression *`
--- * `patt ^ 1` = `expression +`
--- * `patt ^ -1` = `expression ?`
--- * `patt1 * patt2` = `expression1 expression2`: Sequence
--- * `patt1 + patt2` = `expression1 / expression2`: Ordered choice
---
--- * [TUGboat article: Parsing complex data formats in LuaTEX with LPEG](https://tug.or-g/TUGboat/tb40-2/tb125menke-Patterndf)
---
---@param initial_rule string # The name of the first rule of the grammar table passed to the `lpeg.P(attern)` function (e. g. `list`, `number`).
---@param opts? table # Whether the dimensions should be converted to scaled points (by default `false`).
---
---@return userdata # The parser.
local function generate_parser(initial_rule, opts)
  if type(opts) ~= 'table' then
    opts = normalize_opts(opts)
  end

  local Variable = lpeg.V
  local Pattern = lpeg.P
  local Set = lpeg.S
  local Range = lpeg.R
  local CaptureGroup = lpeg.Cg
  local CaptureFolding = lpeg.Cf
  local CaptureTable = lpeg.Ct
  local CaptureConstant = lpeg.Cc
  local CaptureSimple = lpeg.C

  -- Optional whitespace
  local white_space = Set(' \t\n\r')

  --- Match literal string surrounded by whitespace
  local ws = function(match)
    return white_space ^ 0 * Pattern(match) * white_space ^ 0
  end

  --- Convert a dimension to an normalized dimension string or an
  --- integer in the scaled points format.
  ---
  ---@param input string
  ---
  ---@return integer|string # A dimension as an integer or a dimension string.
  local capture_dimension = function(input)
    -- Remove all whitespaces
    input = input:gsub('%s+', '')
    -- Convert the unit string into lowercase.
    input = input:lower()
    if opts.convert_dimensions then
      return tex.sp(input)
    else
      return input
    end
  end

  --- Add values to a table in two modes:
  --
  -- Key-value pair:
  --
  -- If `arg1` and `arg2` are not nil, then `arg1` is the key and `arg2` is the
  -- value of a new table entry.
  --
  -- Indexed value:
  --
  -- If `arg2` is nil, then `arg1` is the value and is added as an indexed
  -- (by an integer) value.
  --
  ---@param result table # The result table to which an additional key-value pair or value should to be added
  ---@param arg1 any # The key or the value.
  ---@param arg2? any # Always the value.
  ---
  ---@return table # The result table to which an additional key-value pair or value has been added.
  local add_to_table = function(result, arg1, arg2)
    if arg2 == nil then
      local index = #result + 1
      return rawset(result, index, arg1)
    else
      return rawset(result, arg1, arg2)
    end
  end

  -- LuaFormatter off
  return Pattern({
    [1] = initial_rule,

    -- list_item*
    list = CaptureFolding(
      CaptureTable('') * Variable('list_item')^0,
      add_to_table
    ),

    -- '{' list '}'
    list_container =
      ws(opts.group_begin) * Variable('list') * ws(opts.group_end),

    -- ( list_container / key_value_pair / value ) ','?
    list_item =
      CaptureGroup(
        Variable('list_container') +
        Variable('key_value_pair') +
        Variable('value')
      ) * ws(opts.list_separator)^-1,

    -- key '=' (list_container / value)
    key_value_pair =
      (Variable('key') * ws(opts.assignment_operator)) * (Variable('list_container') + Variable('value')),

    -- number / string_quoted / string_unquoted
    key =
      Variable('number') +
      Variable('string_quoted') +
      Variable('string_unquoted'),

    -- boolean !value / dimension !value / number !value / string_quoted !value / string_unquoted
    -- !value -> Not-predicate -> * -Variable('value')
    value =
      Variable('boolean') * -Variable('value') +
      Variable('dimension') * -Variable('value') +
      Variable('number') * -Variable('value')  +
      Variable('string_quoted') * -Variable('value') +
      Variable('string_unquoted'),

    -- for is.boolean()
    boolean_only = Variable('boolean') * -1,

    -- boolean_true / boolean_false
    boolean =
      (
        Variable('boolean_true') * CaptureConstant(true) +
        Variable('boolean_false') * CaptureConstant(false)
      ),

    boolean_true =
      Pattern('true') +
      Pattern('TRUE') +
      Pattern('True'),

    boolean_false =
      Pattern('false') +
      Pattern('FALSE') +
      Pattern('False'),

    -- for is.dimension()
    dimension_only = Variable('dimension') * -1,

    dimension = (
      Variable('tex_number') * white_space^0 *
      Variable('unit')
    ) / capture_dimension,

    -- for is.number()
    number_only = Variable('number') * -1,

    -- capture number
    number = Variable('tex_number') / tonumber,

    -- sign? white_space? (integer+ fractional? / fractional)
    tex_number =
      Variable('sign')^0 * white_space^0 *
      (Variable('integer')^1 * Variable('fractional')^0) +
      Variable('fractional'),

    sign = Set('-+'),

    fractional = Pattern('.') * Variable('integer')^1,

    integer = Range('09')^1,

    -- 'bp' / 'BP' / 'cc' / etc.
    -- https://raw.githubusercontent.com/latex3/lualibs/master/lualibs-util-dim.lua
    -- https://github.com/TeX-Live/luatex/blob/51db1985f5500dafd2393aa2e403fefa57d3cb76/source/texk/web2c/luatexdir/lua/ltexlib.c#L434-L625
    unit =
      Pattern('bp') + Pattern('BP') +
      Pattern('cc') + Pattern('CC') +
      Pattern('cm') + Pattern('CM') +
      Pattern('dd') + Pattern('DD') +
      Pattern('em') + Pattern('EM') +
      Pattern('ex') + Pattern('EX') +
      Pattern('in') + Pattern('IN') +
      Pattern('mm') + Pattern('MM') +
      Pattern('mu') + Pattern('MU') +
      Pattern('nc') + Pattern('NC') +
      Pattern('nd') + Pattern('ND') +
      Pattern('pc') + Pattern('PC') +
      Pattern('pt') + Pattern('PT') +
      Pattern('px') + Pattern('PX') +
      Pattern('sp') + Pattern('SP'),

    -- '"' ('\"' / !'"')* '"'
    string_quoted =
      white_space^0 * Pattern(opts.quotation_begin) *
      CaptureSimple((Pattern('\\' .. opts.quotation_end) + 1 - Pattern(opts.quotation_end))^0) *
      Pattern(opts.quotation_end) * white_space^0,

    string_unquoted =
      white_space^0 *
      CaptureSimple(
        Variable('word_unquoted')^1 *
        (Set(' \t')^1 * Variable('word_unquoted')^1)^0) *
      white_space^0,

    word_unquoted = (1 - white_space - Set(
      opts.group_begin ..
      opts.group_end ..
      opts.assignment_operator  ..
      opts.list_separator))^1
  })
-- LuaFormatter on
end

local function visit_tree(tree, callback_func)
  if type(tree) ~= 'table' then
    throw_error('Parameter “tree” has to be a table, got: ' ..
                  tostring(tree))
  end
  local function visit_tree_recursive(tree,
    current,
    result,
    depth,
    callback_func)
    for key, value in pairs(current) do
      if type(value) == 'table' then
        value = visit_tree_recursive(tree, value, {}, depth + 1,
          callback_func)
      end

      key, value = callback_func(key, value, depth, current, tree)

      if key ~= nil and value ~= nil then
        result[key] = value
      end
    end
    if next(result) ~= nil then
      return result
    end
  end

  local result = visit_tree_recursive(tree, tree, {}, 1, callback_func)

  if result == nil then
    return {}
  end
  return result
end

local is = {
  boolean = function(value)
    if value == nil then
      return false
    end
    if type(value) == 'boolean' then
      return true
    end
    local parser = generate_parser('boolean_only')
    local result = parser:match(tostring(value))
    return result ~= nil
  end,

  dimension = function(value)
    if value == nil then
      return false
    end
    local parser = generate_parser('dimension_only')
    local result = parser:match(tostring(value))
    return result ~= nil
  end,

  integer = function(value)
    local n = tonumber(value)
    if n == nil then
      return false
    end
    return n == math.floor(n)
  end,

  number = function(value)
    if value == nil then
      return false
    end
    if type(value) == 'number' then
      return true
    end
    local parser = generate_parser('number_only')
    local result = parser:match(tostring(value))
    return result ~= nil
  end,

  string = function(value)
    return type(value) == 'string'
  end,
}

--- Apply the key-value-pair definitions (defs) on an input table in a
--- recursive fashion.
---
---@param defs table # A table containing all definitions.
---@param opts table # The parse options table.
---@param input table # The current input table.
---@param output table # The current output table.
---@param unknown table # Always the root unknown table.
---@param key_path table # An array of key names leading to the current
---@param input_root table # The root input table input and output table.
local function apply_definitions(defs,
  opts,
  input,
  output,
  unknown,
  key_path,
  input_root)
  local exclusive_groups = {}

  local function add_to_key_path(key_path, key)
    local new_key_path = {}

    for index, value in ipairs(key_path) do
      new_key_path[index] = value
    end

    table.insert(new_key_path, key)
    return new_key_path
  end

  local function get_default_value(def)
    if def.default ~= nil then
      return def.default
    elseif opts ~= nil and opts.default ~= nil then
      return opts.default
    end
    return true
  end

  local function find_value(search_key, def)
    if input[search_key] ~= nil then
      local value = input[search_key]
      input[search_key] = nil
      return value
      -- naked keys: values with integer keys
    elseif utils.remove_from_array(input, search_key) ~= nil then
      return get_default_value(def)
    end
  end

  local apply = {
    alias = function(value, key, def)
      if type(def.alias) == 'string' then
        def.alias = { def.alias }
      end
      local alias_value
      local used_alias_key
      -- To get an error if the key and an alias is present
      if value ~= nil then
        alias_value = value
        used_alias_key = key
      end
      for _, alias in ipairs(def.alias) do
        local v = find_value(alias, def)
        if v ~= nil then
          if alias_value ~= nil then
            throw_error(string.format(
              'Duplicate aliases “%s” and “%s” for key “%s”!',
              used_alias_key, alias, key))
          end
          used_alias_key = alias
          alias_value = v
        end
      end
      if alias_value ~= nil then
        return alias_value
      end
    end,

    always_present = function(value, key, def)
      if value == nil and def.always_present then
        return get_default_value(def)
      end
    end,

    choices = function(value, key, def)
      if value == nil then
        return
      end
      if def.choices ~= nil and type(def.choices) == 'table' then
        local is_in_choices = false
        for _, choice in ipairs(def.choices) do
          if value == choice then
            is_in_choices = true
          end
        end
        if not is_in_choices then
          throw_error('The value “' .. value ..
                        '” does not exist in the choices: ' ..
                        table.concat(def.choices, ', ') .. '!')
        end
      end
    end,

    data_type = function(value, key, def)
      if value == nil then
        return
      end
      if def.data_type ~= nil then
        local converted
        -- boolean
        if def.data_type == 'boolean' then
          if value == 0 or value == '' or not value then
            converted = false
          else
            converted = true
          end
          -- dimension
        elseif def.data_type == 'dimension' then
          if is.dimension(value) then
            converted = value
          end
          -- integer
        elseif def.data_type == 'integer' then
          if is.number(value) then
            local n = tonumber(value)
            if type(n) == 'number' and n ~= nil then
              converted = math.floor(n)
            end
          end
          -- number
        elseif def.data_type == 'number' then
          if is.number(value) then
            converted = tonumber(value)
          end
          -- string
        elseif def.data_type == 'string' then
          converted = tostring(value)
        else
          throw_error('Unknown data type: ' .. def.data_type)
        end
        if converted == nil then
          throw_error(
            'The value “' .. value .. '” of the key “' .. key ..
              '” could not be converted into the data type “' ..
              def.data_type .. '”!')
        else
          return converted
        end
      end
    end,

    exclusive_group = function(value, key, def)
      if value == nil then
        return
      end
      if def.exclusive_group ~= nil then
        if exclusive_groups[def.exclusive_group] ~= nil then
          throw_error('The key “' .. key ..
                        '” belongs to a mutually exclusive group “' ..
                        def.exclusive_group .. '” and the key “' ..
                        exclusive_groups[def.exclusive_group] ..
                        '” is already present!')
        else
          exclusive_groups[def.exclusive_group] = key
        end
      end
    end,

    l3_tl_set = function(value, key, def)
      if value == nil then
        return
      end
      if def.l3_tl_set ~= nil then
        tex.print(l3_code_cctab,
          '\\tl_set:Nn \\g_' .. def.l3_tl_set .. '_tl')
        tex.print('{' .. value .. '}')
      end
    end,

    macro = function(value, key, def)
      if value == nil then
        return
      end
      if def.macro ~= nil then
        token.set_macro(def.macro, value, 'global')
      end
    end,

    match = function(value, key, def)
      if value == nil then
        return
      end
      if def.match ~= nil then
        if type(def.match) ~= 'string' then
          throw_error('def.match has to be a string')
        end
        local match = string.match(value, def.match)
        if match == nil then
          throw_error(
            'The value “' .. value .. '” of the key “' .. key ..
              '” does not match “' .. def.match .. '”!')
        else
          return match
        end
      end
    end,

    opposite_keys = function(value, key, def)
      if def.opposite_keys ~= nil then
        local true_value = def.opposite_keys[true]
        local false_value = def.opposite_keys[false]
        if true_value == nil or false_value == nil then
          throw_error(
            'Usage opposite_keys = { [true] = "...", [false] = "..." }')
        end
        if utils.remove_from_array(input, true_value) ~= nil then
          return true
        elseif utils.remove_from_array(input, false_value) ~= nil then
          return false
        end
      end
    end,

    process = function(value, key, def)
      if value == nil then
        return
      end
      if def.process ~= nil and type(def.process) == 'function' then
        return def.process(value, input_root, output, unknown)
      end
    end,

    pick = function(value, key, def)
      if def.pick then
        if type(def.pick) == 'string' and is[def.pick] == nil then
          throw_error(
            'Wrong setting. Allowed settings for the attribute “def.pick” are: true, boolean, dimension, integer, number, string. Got “' ..
              tostring(def.pick) .. '”.')
        end

        if value ~= nil then
          return value
        end
        for i, v in pairs(input) do
          -- We can not use ipairs here. `ipairs(t)` iterates up to the
          -- first absent index. Values are deleted from the `input`
          -- table.
          if type(i) == 'number' then
            local picked_value = nil
            -- Pick a value by type:  boolean, dimension, integer, number, string
            if is[def.pick] ~= nil then
              if is[def.pick](v) then
                picked_value = v
              end
              -- Pick every value
            elseif v ~= nil then
              picked_value = v
            end
            if picked_value ~= nil then
              input[i] = nil
              return picked_value
            end
          end
        end
      end
    end,

    required = function(value, key, def)
      if def.required ~= nil and def.required and value == nil then
        throw_error(string.format('Missing required key “%s”!', key))
      end
    end,

    sub_keys = function(value, key, def)
      if def.sub_keys ~= nil then
        local v
        -- To get keys defined with always_present
        if value == nil then
          v = {}
        elseif type(value) == 'string' then
          v = { value }
        elseif type(value) == 'table' then
          v = value
        end
        v = apply_definitions(def.sub_keys, opts, v, output[key],
          unknown, add_to_key_path(key_path, key), input_root)
        if utils.get_table_size(v) > 0 then
          return v
        end
      end
    end,
  }

  --- standalone values are removed.
  -- For some callbacks and the third return value of parse, we
  -- need an unchanged raw result from the parse function.
  input = clone_table(input)
  if output == nil then
    output = {}
  end
  if unknown == nil then
    unknown = {}
  end
  if key_path == nil then
    key_path = {}
  end

  for index, def in pairs(defs) do
    -- Find key and def
    local key
    -- `{ key1 = { }, key2 = { } }`
    if type(def) == 'table' and def.name == nil and type(index) ==
      'string' then
      key = index
      -- `{ { name = 'key1' }, { name = 'key2' } }`
    elseif type(def) == 'table' and def.name ~= nil then
      key = def.name
      -- Definitions as strings in an array: `{ 'key1', 'key2' }`
    elseif type(index) == 'number' and type(def) == 'string' then
      key = def
      def = { default = get_default_value({}) }
    end

    if type(def) ~= 'table' then
      throw_error('Key definition must be a table!')
    end

    for attr, _ in pairs(def) do
      if namespace.attrs[attr] == nil then
        throw_error('Unknown definition attribute: ' .. tostring(attr))
      end
    end

    if key == nil then
      throw_error('Key name couldn’t be detected!')
    end

    local value = find_value(key, def)

    for _, def_opt in ipairs({
      'alias',
      'opposite_keys',
      'pick',
      'always_present',
      'required',
      'data_type',
      'choices',
      'match',
      'exclusive_group',
      'macro',
      'l3_tl_set',
      'process',
      'sub_keys',
    }) do
      if def[def_opt] ~= nil then
        local tmp_value = apply[def_opt](value, key, def)
        if tmp_value ~= nil then
          value = tmp_value
        end
      end
    end

    output[key] = value
  end

  if utils.get_table_size(input) > 0 then
    -- Move to the current unknown table.
    local current_unknown = unknown
    for _, key in ipairs(key_path) do
      if current_unknown[key] == nil then
        current_unknown[key] = {}
      end
      current_unknown = current_unknown[key]
    end

    -- Copy all unknown key-value-pairs to the current unknown table.
    for key, value in pairs(input) do
      current_unknown[key] = value
    end
  end

  return output, unknown
end

--- Parse a LaTeX/TeX style key-value string into a Lua table.
---
---@param kv_string string # A string in the TeX/LaTeX style key-value format as described above.
---@param opts table # A table containing the settings:
---   `convert_dimensions`, `unpack`, `naked_as_value`, `converter`,
---   `debug`, `preprocess`, `postprocess`.
--
---@return table result # The final result of all individual parsing and normalization steps.
---@return table unknown # A table with unknown, undefinied key-value pairs.
---@return table raw # The unprocessed, raw result of the LPeg parser.
local function parse(kv_string, opts)
  if kv_string == nil then
    return {}, {}, {}
  end

  opts = normalize_opts(opts)

  if type(opts.hooks.kv_string) == 'function' then
    kv_string = opts.hooks.kv_string(kv_string)
  end

  local result = generate_parser('list', opts):match(kv_string)
  local raw = clone_table(result)

  local function apply_hook(name)
    if type(opts.hooks[name]) == 'function' then
      if name:match('^keys') then
        result = visit_tree(result, opts.hooks[name])
      else
        opts.hooks[name](result)
      end

      if opts.debug then
        print('After the execution of the hook: ' .. name)
        debug(result)
      end
    end
  end

  local function apply_hooks(at)
    if at ~= nil then
      at = '_' .. at
    else
      at = ''
    end
    apply_hook('keys' .. at)
    apply_hook('result' .. at)
  end

  apply_hooks('before_opts')

  --- Normalize the result table of the LPeg parser. This normalization
  --  tasks are performed on the raw input table coming directly from
  --  the PEG parser:
  --
  ---@param result table # The raw input table coming directly from the PEG parser
  ---@param opts table # Some options.
  local function apply_opts(result, opts)
    local callbacks = {
      unpack = function(key, value)
        if type(value) == 'table' and utils.get_array_size(value) == 1 and
          utils.get_table_size(value) == 1 and type(value[1]) ~= 'table' then
          return key, value[1]
        end
        return key, value
      end,

      process_naked = function(key, value)
        if type(key) == 'number' and type(value) == 'string' then
          return value, opts.default
        end
        return key, value
      end,

      format_key = function(key, value)
        if type(key) == 'string' then
          for _, style in ipairs(opts.format_keys) do
            if style == 'lower' then
              key = key:lower()
            elseif style == 'snake' then
              key = key:gsub('[^%w]+', '_')
            elseif style == 'upper' then
              key = key:upper()
            else
              throw_error('Unknown style to format keys: ' ..
                            tostring(style) ..
                            ' Allowed styles are: lower, snake, upper')
            end
          end
        end
        return key, value
      end,
    }

    if opts.unpack then
      result = visit_tree(result, callbacks.unpack)
    end

    if not opts.naked_as_value and opts.defs == false then
      result = visit_tree(result, callbacks.process_naked)
    end

    if opts.format_keys then
      if type(opts.format_keys) ~= 'table' then
        throw_error(
          'The option “format_keys” has to be a table not ' ..
            type(opts.format_keys))
      end
      result = visit_tree(result, callbacks.format_key)
    end

    return result
  end
  result = apply_opts(result, opts)

  -- All unknown keys are stored in this table
  local unknown = nil
  if type(opts.defs) == 'table' then
    apply_hooks('before_defs')
    result, unknown = apply_definitions(opts.defs, opts, result, {}, {},
      {}, clone_table(result))
  end

  apply_hooks()

  if opts.defaults ~= nil and type(opts.defaults) == 'table' then
    merge_tables(result, opts.defaults)
  end

  if opts.debug then
    debug(result)
  end

  -- no_error
  if not opts.no_error and type(unknown) == 'table' and
    utils.get_table_size(unknown) > 0 then
    throw_error('Unknown keys: ' .. render(unknown))
  end
  return result, unknown, raw
end

--- Store results
-- @section

--- A table to store parsed key-value results.
local result_store = {}

--- Exports
-- @section

local export = {
  version = { 0, 7, 0 },

  namespace = namespace,

  ---This function is used in the documentation.
  ---
  ---@param from string # A key in the namespace table, either `opts`, `hook` or `attrs`.
  print_names = function(from)
    local names = {}
    for name in pairs(namespace[from]) do
      table.insert(names, name)
    end
    table.sort(names)
    tex.print(table.concat(names, ', '))
  end,

  print_default = function(from, name)
    tex.print(tostring(namespace[from][name]))
  end,

  --- @see default_options
  opts = default_options,

  --- @see stringify
  stringify = stringify,

  --- @see parse
  parse = parse,

  define = function(defs, opts)
    return function(kv_string, inner_opts)
      local options

      if inner_opts ~= nil and opts ~= nil then
        options = merge_tables(opts, inner_opts)
      elseif inner_opts ~= nil then
        options = inner_opts
      elseif opts ~= nil then
        options = opts
      end

      if options == nil then
        options = {}
      end

      options.defs = defs

      return parse(kv_string, options)
    end
  end,

  --- @see render
  render = render,

  --- @see debug
  debug = debug,

  --- The function `save(identifier, result): void` saves a result (a
  --  table from a previous run of `parse`) under an identifier.
  --  Therefore, it is not necessary to pollute the global namespace to
  --  store results for the later usage.
  --
  ---@param identifier string # The identifier under which the result is saved.
  --
  ---@param result table # A result to be stored and that was created by the key-value parser.
  save = function(identifier, result)
    result_store[identifier] = result
  end,

  --- The function `get(identifier): table` retrieves a saved result
  --  from the result store.
  --
  ---@param identifier string # The identifier under which the result was saved.
  ---
  ---@return table
  get = function(identifier)
    -- if result_store[identifier] == nil then
    --   throw_error('No stored result was found for the identifier \'' .. identifier .. '\'')
    -- end
    return result_store[identifier]
  end,

  is = is,

  utils = utils,
}

return export
