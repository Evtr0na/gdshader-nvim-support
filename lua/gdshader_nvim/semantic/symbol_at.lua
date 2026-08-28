local M = {}

local context = require("gdshader_nvim.context")

local document = require("gdshader_nvim.semantic.document")

local token = require("gdshader_nvim.syntax.token")

local builtin_variables = require("gdshader_nvim.data.builtin_variables")

local processors = require("gdshader_nvim.data.processors")

local TokenKind = token.Kind

local knowledge = require("gdshader_nvim.data.knowledge")

------------------------------------------------------------
-- Lookup tables
--
-- Rebuilt lazily when the knowledge version changes, so
-- user-extended types / functions / hints / render modes are
-- picked up by hover and definition resolution.
------------------------------------------------------------

local type_set = nil

local shader_type_set = nil

local uniform_hint_map = nil

local builtin_function_map = nil

local render_mode_set = nil

local built_version = -1

local function rebuild()
    type_set = {
        void = true,
    }

    for _, name in ipairs(knowledge.get("types") or {}) do
        type_set[name] = true
    end

    shader_type_set = {}

    for _, name in ipairs(knowledge.get("shader_types") or {}) do
        shader_type_set[name] = true
    end

    uniform_hint_map = {}

    for _, hint in ipairs(knowledge.get("uniform_hints") or {}) do
        uniform_hint_map[hint.name] = hint
    end

    builtin_function_map = {}

    for _, fn in ipairs(knowledge.get("builtin_functions") or {}) do
        local list = builtin_function_map[fn.name]

        if not list then
            list = {}

            builtin_function_map[fn.name] = list
        end

        table.insert(list, fn)
    end

    render_mode_set = {}

    for _, modes in pairs(knowledge.get("render_modes") or {}) do
        for _, name in ipairs(modes) do
            render_mode_set[name] = true
        end
    end

    built_version = knowledge.version()
end

local function ensure()
    if built_version ~= knowledge.version() then
        rebuild()
    end
end

------------------------------------------------------------
-- Word
------------------------------------------------------------

local function is_word_char(char)
    if not char or char == "" then
        return false
    end

    return char:match("[%w_]") ~= nil
end

function M.get_word_at(bufnr, row, column)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)

    local line = lines[1]

    if not line or line == "" then
        return nil
    end

    --------------------------------------------------------
    -- column:
    -- Neovim 0-based byte column
    --
    -- Lua:
    -- 1-based string index
    --------------------------------------------------------

    local index = math.min(column + 1, #line)

    --------------------------------------------------------
    -- Cursor 在 word 后一个位置时，
    -- 向左尝试一次。
    --------------------------------------------------------

    if not is_word_char(line:sub(index, index)) then
        if index > 1 and is_word_char(line:sub(index - 1, index - 1)) then
            index = index - 1
        else
            return nil
        end
    end

    local start_index = index

    while start_index > 1 and is_word_char(line:sub(start_index - 1, start_index - 1)) do
        start_index = start_index - 1
    end

    local end_index = index

    while end_index < #line and is_word_char(line:sub(end_index + 1, end_index + 1)) do
        end_index = end_index + 1
    end

    local word = line:sub(start_index, end_index)

    if not word:match("^[%a_][%w_]*$") then
        return nil
    end

    return {
        word = word,

        line = line,

        row = row,

        start_column = start_index - 1,

        end_column = end_index,
    }
end

------------------------------------------------------------
-- Render mode context
------------------------------------------------------------

local function is_render_mode_context(bufnr, row)
    local semantic_document = document.get(bufnr)

    local root = semantic_document.ast

    if not root then
        return false
    end

    for _, node in ipairs(root.declarations or {}) do
        if
            node.kind == "render_mode"
            and row >= (node.start_line or 0)
            and row <= (node.end_line or node.start_line or 0)
        then
            return true
        end
    end

    return false
end

------------------------------------------------------------
-- Processor
------------------------------------------------------------

local function find_processor(shader_type, name)
    if not shader_type then
        return nil
    end

    for _, processor in ipairs(processors[shader_type] or {}) do
        if processor.name == name then
            return processor
        end
    end

    return nil
end

------------------------------------------------------------
-- Built-in unavailable in current processor
------------------------------------------------------------

local function find_other_builtin(shader_type, current_processor, name)
    if not shader_type then
        return nil
    end

    local shader_data = builtin_variables[shader_type]

    if not shader_data then
        return nil
    end

    local found = nil
    local available_in = {}

    for processor_name, variables in pairs(shader_data) do
        if processor_name ~= current_processor then
            for _, variable in ipairs(variables or {}) do
                if variable.name == name then
                    found = found or variable

                    table.insert(available_in, processor_name)

                    break
                end
            end
        end
    end

    if not found then
        return nil
    end

    table.sort(available_in)

    return {
        variable = found,

        available_in = available_in,
    }
end

------------------------------------------------------------
-- Resolve
------------------------------------------------------------

function M.resolve(bufnr, row, column)
    ensure()

    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local word_info = M.get_word_at(bufnr, row, column)

    if not word_info then
        return nil
    end

    local word = word_info.word

    local cursor_line = row + 1

    local result = {
        word = word,

        range = {
            line = row,

            start_column = word_info.start_column,

            end_column = word_info.end_column,
        },
    }

    --------------------------------------------------------
    -- shader_type spatial;
    --------------------------------------------------------

    if shader_type_set[word] and word_info.line:match("^%s*shader_type%s+") then
        result.kind = "shader_type"

        result.name = word

        return result
    end

    --------------------------------------------------------
    -- render_mode ...
    --------------------------------------------------------

    if render_mode_set[word] and is_render_mode_context(bufnr, row) then
        result.kind = "render_mode"

        result.name = word

        return result
    end

    --------------------------------------------------------
    -- User symbol
    --
    -- 必须在 built-in 前面，保持 shadowing。
    --------------------------------------------------------

    local symbol = context.get_user_symbol(bufnr, word, cursor_line)

    if symbol then
        result.kind = "user_symbol"

        result.symbol = symbol

        return result
    end

    --------------------------------------------------------
    -- User function
    --------------------------------------------------------

    local functions = context.get_user_functions_by_name(bufnr, word)

    if #functions > 0 then
        result.kind = "user_function"

        result.functions = functions

        return result
    end

    --------------------------------------------------------
    -- Current processor built-in
    --------------------------------------------------------

    local builtin = context.get_builtin_variable(bufnr, word, cursor_line)

    if builtin then
        result.kind = "builtin_variable"

        result.variable = builtin

        result.available = true

        return result
    end

    --------------------------------------------------------
    -- Processor name
    --------------------------------------------------------

    local shader_type = context.get_shader_type(bufnr)

    local processor = find_processor(shader_type, word)

    if processor then
        result.kind = "processor"

        result.processor = processor

        result.shader_type = shader_type

        return result
    end

    --------------------------------------------------------
    -- Built-in function
    --------------------------------------------------------

    local builtin_fns = builtin_function_map[word]

    if builtin_fns then
        result.kind = "builtin_function"

        result.functions = builtin_fns

        return result
    end

    --------------------------------------------------------
    -- Type
    --------------------------------------------------------

    if type_set[word] then
        result.kind = "type"

        result.name = word

        return result
    end

    --------------------------------------------------------
    -- Uniform hint
    --------------------------------------------------------

    local hint = uniform_hint_map[word]

    if hint then
        result.kind = "uniform_hint"

        result.hint = hint

        return result
    end

    --------------------------------------------------------
    -- Keyword
    --------------------------------------------------------

    if token.classify_word(word) == TokenKind.KEYWORD then
        result.kind = "keyword"

        result.name = word

        return result
    end

    --------------------------------------------------------
    -- Built-in exists, but not in current processor.
    --
    -- 对齐参考插件的跨 processor hover。
    --------------------------------------------------------

    local other_builtin = find_other_builtin(shader_type, context.get_processor(bufnr, cursor_line), word)

    if other_builtin then
        result.kind = "builtin_variable"

        result.variable = other_builtin.variable

        result.available = false

        result.available_in = other_builtin.available_in

        return result
    end

    return nil
end

return M
