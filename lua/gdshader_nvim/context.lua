local M = {}

local builtin_variables = require("gdshader_nvim.data.builtin_variables")
local processors = require("gdshader_nvim.data.processors")
local document = require("gdshader_nvim.semantic.document")
------------------------------------------------------------
-- Processor lookup
------------------------------------------------------------

local function get_processors_for_shader(shader_type)
    if not shader_type then
        return {}
    end

    return processors[shader_type] or {}
end

local function get_processor_definition(shader_type, name)
    for _, processor in ipairs(get_processors_for_shader(shader_type)) do
        if processor.name == name then
            return processor
        end
    end

    return nil
end

local function is_processor_name(shader_type, name)
    return get_processor_definition(shader_type, name) ~= nil
end

------------------------------------------------------------
-- 获取当前文档中的所有函数
------------------------------------------------------------

function M.get_functions(bufnr)
    return document.get_functions(bufnr)
end

------------------------------------------------------------
-- 获取当前函数上下文
------------------------------------------------------------

function M.get_function_context(bufnr, cursor_line)
    bufnr = bufnr or 0

    cursor_line = cursor_line or vim.api.nvim_win_get_cursor(0)[1]

    for _, fn in ipairs(M.get_functions(bufnr)) do
        local end_line = fn.end_line or math.huge

        if cursor_line >= fn.start_line and cursor_line <= end_line then
            return fn
        end
    end

    return nil
end

------------------------------------------------------------
-- 获取当前 uniform 的类型
--
-- uniform float amount :
--         ↑
-- 返回 float
--
-- uniform sampler2D texture :
--         ↑
-- 返回 sampler2D
------------------------------------------------------------

function M.get_uniform_type_before_cursor(before_cursor)
    return before_cursor:match("uniform%s+" .. "([%a_][%w_]*)" .. "%s+" .. "[%a_][%w_]*" .. "%s*:")
end

------------------------------------------------------------
-- 查找 built-in variable
------------------------------------------------------------

function M.get_builtin_variable(bufnr, name, cursor_line)
    local variables = M.get_builtin_variables(bufnr, cursor_line)

    for _, item in ipairs(variables) do
        if item.name == name then
            return item
        end
    end

    return nil
end

------------------------------------------------------------
-- 获取 shader_type
------------------------------------------------------------

function M.get_shader_type(bufnr)
    return document.get_shader_type(bufnr)
end

------------------------------------------------------------
-- 获取当前上下文允许的 built-in variables
------------------------------------------------------------

function M.get_builtin_variables(bufnr, cursor_line)
    local result = {}

    --------------------------------------------------------
    -- Global built-ins
    --------------------------------------------------------

    for _, item in ipairs(builtin_variables.global or {}) do
        table.insert(result, item)
    end

    --------------------------------------------------------
    -- Shader type
    --
    -- VS Code defaults to `spatial` when no `shader_type` is
    -- declared yet, so built-in variables (VERTEX, ALBEDO, …)
    -- still surface during editing.
    --------------------------------------------------------

    local shader_type = M.get_shader_type(bufnr) or "spatial"

    local shader_data = builtin_variables[shader_type]

    if not shader_data then
        return result
    end

    --------------------------------------------------------
    -- Processor
    --------------------------------------------------------

    local processor = M.get_processor(bufnr, cursor_line)

    if not processor then
        return result
    end

    local processor_data = shader_data[processor]

    if not processor_data then
        return result
    end

    --------------------------------------------------------
    -- Processor-specific built-ins
    --------------------------------------------------------

    for _, item in ipairs(processor_data) do
        table.insert(result, item)
    end

    return result
end

------------------------------------------------------------
-- 获取所有 global declarations
------------------------------------------------------------

local function get_global_declarations(bufnr)
    return document.get_global_declarations(bufnr)
end

------------------------------------------------------------
-- 获取用户声明的 symbols
------------------------------------------------------------
--new
function M.get_user_symbols(bufnr, cursor_line)
    bufnr = bufnr or 0

    cursor_line = cursor_line or vim.api.nvim_win_get_cursor(0)[1]

    local result = {}
    local seen = {}

    --------------------------------------------------------
    -- Add symbol
    --
    -- 先加入的同名 symbol 胜出。
    --
    -- 因此顺序：
    --
    -- local inner
    -- local outer
    -- parameter
    -- global
    --------------------------------------------------------

    local function add_symbol(symbol)
        if not symbol or not symbol.name then
            return
        end

        if seen[symbol.name] then
            return
        end

        seen[symbol.name] = true

        table.insert(result, symbol)
    end

    --------------------------------------------------------
    -- Local scopes + parameters
    --------------------------------------------------------

    local local_symbols = document.get_local_symbols(bufnr, cursor_line)

    for _, symbol in ipairs(local_symbols) do
        add_symbol(symbol)
    end

    --------------------------------------------------------
    -- Global declarations
    --------------------------------------------------------

    local global_declarations = get_global_declarations(bufnr)

    for _, declaration in ipairs(global_declarations) do
        ----------------------------------------------------
        -- 保持现有行为：
        --
        -- cursor 后面的 global 暂时不可见。
        ----------------------------------------------------

        if declaration.line <= cursor_line then
            add_symbol(declaration)
        end
    end

    return result
end

------------------------------------------------------------
-- 根据名字查找用户 symbol
--
-- get_user_symbols() 已经按照：
--
-- inner local
-- outer local
-- parameter
-- global
--
-- 处理好了 shadowing。
--
-- 因此这里取第一个同名 symbol 即可。
------------------------------------------------------------

function M.get_user_symbol(bufnr, name, cursor_line)
    if not name or name == "" then
        return nil
    end

    local symbols = M.get_user_symbols(bufnr, cursor_line)

    for _, symbol in ipairs(symbols) do
        if symbol.name == name then
            return symbol
        end
    end

    return nil
end

------------------------------------------------------------
-- 获取用户自定义函数
------------------------------------------------------------

function M.get_user_functions(bufnr)
    bufnr = bufnr or 0

    local shader_type = M.get_shader_type(bufnr)

    local result = {}

    for _, fn in ipairs(M.get_functions(bufnr)) do
        ----------------------------------------------------
        -- 当前 shader 的 processor 不算 user function
        ----------------------------------------------------

        if not is_processor_name(shader_type, fn.name) then
            table.insert(result, fn)
        end
    end

    return result
end

------------------------------------------------------------
-- 用户函数 signature
------------------------------------------------------------

function M.get_function_signature(fn)
    local parameters = {}

    for _, parameter in ipairs(fn.parameters) do
        local text = ""

        if parameter.mode then
            text = parameter.mode .. " "
        end

        text = text .. parameter.type .. " " .. parameter.name

        table.insert(parameters, text)
    end

    return fn.return_type .. " " .. fn.name .. "(" .. table.concat(parameters, ", ") .. ")"
end

------------------------------------------------------------
-- 根据名字查用户函数
--
-- 返回数组，为以后 overload 做准备
------------------------------------------------------------

function M.get_user_functions_by_name(bufnr, name)
    local result = {}

    local functions = M.get_user_functions(bufnr)

    for _, fn in ipairs(functions) do
        if fn.name == name then
            table.insert(result, fn)
        end
    end

    return result
end

------------------------------------------------------------
-- "." 前面的函数调用
--
-- calculate_color(...).
------------------------------------------------------------

function M.get_function_call_before_dot(before_cursor)
    return before_cursor:match("([%a_][%w_]*)" .. "%s*" .. "%b()" .. "%s*" .. "%." .. "[%w_]*$")
end

------------------------------------------------------------
-- 用户函数返回类型
------------------------------------------------------------

function M.get_user_function_return_type(bufnr, name)
    local functions = M.get_user_functions_by_name(bufnr, name)

    if #functions == 0 then
        return nil
    end

    local return_type = functions[1].return_type

    --------------------------------------------------------
    -- 如果存在 overload，
    -- 只有所有返回类型一致时才安全推断
    --------------------------------------------------------

    for i = 2, #functions do
        if functions[i].return_type ~= return_type then
            return nil
        end
    end

    return return_type
end

------------------------------------------------------------
-- 获取当前所在函数
--
-- 例如：
--
-- void fragment() {
--     ...
-- }
--
-- 返回 "fragment"
------------------------------------------------------------

function M.get_processor(bufnr, cursor_line)
    local fn = M.get_function_context(bufnr, cursor_line)

    if not fn then
        return nil
    end

    local shader_type = M.get_shader_type(bufnr)

    if not shader_type then
        return nil
    end

    if get_processor_definition(shader_type, fn.name) then
        return fn.name
    end

    return nil
end

------------------------------------------------------------
-- 获取 "." 前面的 identifier
------------------------------------------------------------

function M.get_identifier_before_dot(before_cursor)
    return before_cursor:match("([%a_][%w_]*)%.[%w_]*$")
end

------------------------------------------------------------
-- 获取 identifier 类型
------------------------------------------------------------

function M.get_symbol_type(bufnr, name, cursor_line)
    --------------------------------------------------------
    -- 用户 symbol
    --------------------------------------------------------

    local symbol = M.get_user_symbol(bufnr, name, cursor_line)

    if symbol then
        return symbol.type
    end

    --------------------------------------------------------
    -- GDShader built-in
    --------------------------------------------------------

    local builtin = M.get_builtin_variable(bufnr, name, cursor_line)

    if builtin then
        return builtin.type
    end

    return nil
end

return M
