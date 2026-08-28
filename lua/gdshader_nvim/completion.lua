local source = {}

------------------------------------------------------------
-- Dependencies
------------------------------------------------------------

local ok_blink, blink_types = pcall(require, "blink.cmp.types")

local kinds = (ok_blink and blink_types.CompletionItemKind) or vim.lsp.protocol.CompletionItemKind

local diagnostics = require("gdshader_nvim.diagnostics")
local types = require("gdshader_nvim.data.types")

local uniform_hints = require("gdshader_nvim.data.uniform_hints")

local context = require("gdshader_nvim.context")
local render_modes = require("gdshader_nvim.data.render_modes")
local swizzles = require("gdshader_nvim.data.swizzles")
local builtin_functions = require("gdshader_nvim.data.builtin_functions")
local processors = require("gdshader_nvim.data.processors")

local inference = require("gdshader_nvim.semantic.inference")
local semantic_types = require("gdshader_nvim.semantic.types")
local shader_type_names = require("gdshader_nvim.data.shader_types")
local hover = require("gdshader_nvim.hover")
local definition = require("gdshader_nvim.definition")

local references = require("gdshader_nvim.references")

local rename = require("gdshader_nvim.rename")

------------------------------------------------------------
-- Static data
------------------------------------------------------------

local shader_types = {}

for _, name in ipairs(shader_type_names) do
    table.insert(shader_types, {
        label = name,

        kind = kinds.Keyword,

        detail = "GDShader shader type",
    })
end

local general_items = {
    --------------------------------------------------------
    -- Keywords
    --------------------------------------------------------

    {
        label = "void",
        kind = kinds.Keyword,
        detail = "GDShader function return type",
    },

    {
        label = "shader_type",
        kind = kinds.Keyword,
        detail = "GDShader keyword",
    },

    {
        label = "render_mode",
        kind = kinds.Keyword,
        detail = "GDShader keyword",
    },

    {
        label = "uniform",
        kind = kinds.Keyword,
        detail = "GDShader keyword",
    },

    {
        label = "varying",
        kind = kinds.Keyword,
        detail = "GDShader keyword",
    },

    {
        label = "const",
        kind = kinds.Keyword,
        detail = "GDShader keyword",
    },
}

------------------------------------------------------------
-- Item builders
------------------------------------------------------------

local function make_user_symbol_items(bufnr, cursor_line)
    local items = {}

    local symbols = context.get_user_symbols(bufnr, cursor_line)

    for _, symbol in ipairs(symbols) do
        local kind = kinds.Variable

        if symbol.kind == "const" then
            kind = kinds.Constant
        end

        local detail = symbol.type .. " · GDShader " .. symbol.kind

        if symbol.mode then
            detail = symbol.mode .. " " .. detail
        end

        table.insert(items, {
            label = symbol.name,

            kind = kind,

            detail = detail,
        })
    end

    return items
end

local function make_user_function_items(bufnr)
    local items = {}

    local functions = context.get_user_functions(bufnr)

    for _, fn in ipairs(functions) do
        local placeholders = {}

        ----------------------------------------------------
        -- 根据参数自动生成 snippet
        ----------------------------------------------------

        for index, parameter in ipairs(fn.parameters) do
            table.insert(placeholders, "${" .. index .. ":" .. parameter.name .. "}")
        end

        local insert_text = fn.name .. "(" .. table.concat(placeholders, ", ") .. ")"

        local signature = context.get_function_signature(fn)

        table.insert(items, {
            label = fn.name,

            kind = kinds.Function,

            detail = signature .. " · user function",

            documentation = {
                kind = "markdown",

                value = "```gdshader\n" .. signature .. "\n```",
            },

            insertText = insert_text,

            insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
        })
    end

    return items
end

local function make_uniform_hint_items(uniform_type)
    local items = {}

    for _, hint in ipairs(uniform_hints) do
        ----------------------------------------------------
        -- 只显示适用于当前类型的 hint
        ----------------------------------------------------

        if hint.types[uniform_type] then
            table.insert(items, {
                label = hint.name,

                kind = kinds.EnumMember,

                detail = "GDShader uniform hint · " .. uniform_type,

                documentation = hint.description and {
                    kind = "markdown",
                    value = hint.description,
                } or nil,

                insertText = hint.snippet or hint.name,

                insertTextFormat = hint.snippet and vim.lsp.protocol.InsertTextFormat.Snippet
                    or vim.lsp.protocol.InsertTextFormat.PlainText,
            })
        end
    end

    return items
end

local function make_type_items()
    local items = {}

    for _, type_name in ipairs(types) do
        table.insert(items, {
            label = type_name,

            kind = kinds.TypeParameter,

            detail = "GDShader type",
        })
    end

    return items
end

local function make_builtin_function_items()
    local items = {}

    for _, fn in ipairs(builtin_functions) do
        local documentation = "```gdshader\n" .. fn.signature .. "\n```"

        if fn.description then
            documentation = documentation .. "\n\n" .. fn.description
        end

        table.insert(items, {
            label = fn.name,

            -- 它本质上是函数，
            -- 即使 insertText 使用 snippet。
            kind = kinds.Function,

            detail = fn.signature,

            documentation = {
                kind = "markdown",
                value = documentation,
            },

            insertText = fn.snippet,

            insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
        })
    end

    return items
end

local function make_processor_snippet_items(shader_type)
    local items = {}

    local shader_processors = processors[shader_type] or {}

    for _, processor in ipairs(shader_processors) do
        table.insert(items, {
            label = processor.name,

            kind = kinds.Snippet,

            detail = processor.detail,

            insertText = "void " .. processor.name .. "() {\n\t${1}\n}",

            insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
        })
    end

    return items
end

local function make_processor_items(shader_type)
    local items = {}

    local shader_processors = processors[shader_type] or {}

    for _, processor in ipairs(shader_processors) do
        table.insert(items, {
            label = processor.name,

            kind = kinds.Function,

            detail = processor.detail,

            insertText = processor.name .. "() {\n\t${1}\n}",

            insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
        })
    end

    return items
end

local function make_render_mode_items(shader_type)
    local items = {}

    local modes = render_modes[shader_type] or {}

    for _, name in ipairs(modes) do
        table.insert(items, {
            label = name,
            kind = kinds.EnumMember,

            detail = "GDShader " .. shader_type .. " render mode",
        })
    end

    return items
end

local function make_swizzle_items(vector_size, type_name)
    local items = {}

    for _, name in ipairs(swizzles.for_size(vector_size)) do
        table.insert(items, {
            label = name,
            kind = kinds.Field,

            detail = type_name .. " swizzle",
        })
    end

    return items
end

local function make_builtin_variable_items(bufnr, cursor_line)
    local items = {}

    local variables = context.get_builtin_variables(bufnr, cursor_line)

    for _, variable in ipairs(variables) do
        local detail = variable.mode .. " " .. variable.type .. " · GDShader built-in"

        local documentation = nil

        if variable.detail then
            documentation = {
                kind = "markdown",
                value = "```gdshader\n"
                    .. variable.mode
                    .. " "
                    .. variable.type
                    .. " "
                    .. variable.name
                    .. "\n```\n\n"
                    .. variable.detail,
            }
        end

        table.insert(items, {
            label = variable.name,

            kind = kinds.Variable,

            detail = detail,

            documentation = documentation,
        })
    end

    return items
end

local function make_context_items(ctx, cursor_line)
    local items = vim.deepcopy(general_items)

    --------------------------------------------------------
    -- Current shader: symbols
    --------------------------------------------------------

    vim.list_extend(items, make_user_symbol_items(ctx.bufnr, cursor_line))

    --------------------------------------------------------
    -- Current shader: functions
    --------------------------------------------------------

    vim.list_extend(items, make_user_function_items(ctx.bufnr))

    --------------------------------------------------------
    -- Godot built-in variables
    --------------------------------------------------------

    vim.list_extend(items, make_builtin_variable_items(ctx.bufnr, cursor_line))

    --------------------------------------------------------
    -- Godot built-in functions
    --------------------------------------------------------

    vim.list_extend(items, make_builtin_function_items())

    --------------------------------------------------------
    -- Processor snippets
    --------------------------------------------------------

    local shader_type = context.get_shader_type(ctx.bufnr)

    vim.list_extend(items, make_processor_snippet_items(shader_type))

    --------------------------------------------------------
    -- Types
    --------------------------------------------------------

    vim.list_extend(items, make_type_items())

    return items
end

------------------------------------------------------------
-- Blink source
------------------------------------------------------------

function source.new()
    --------------------------------------------------------
    -- Ensure the plugin (and its standalone features) are booted.
    -- Booting is idempotent.
    --------------------------------------------------------

    require("gdshader_nvim").ensure_setup()

    return setmetatable({}, {
        __index = source,
    })
end

------------------------------------------------------------
-- Enabled
------------------------------------------------------------

function source:enabled()
    local config = require("gdshader_nvim.config").get()

    local ft = vim.bo.filetype

    for _, supported in ipairs(config.filetypes) do
        if ft == supported then
            return true
        end
    end

    return false
end

------------------------------------------------------------
-- Trigger characters
------------------------------------------------------------

function source:get_trigger_characters()
    local config = require("gdshader_nvim.config").get()

    return config.completion.trigger_characters
end

------------------------------------------------------------
-- Completion
------------------------------------------------------------

function source:get_completions(ctx, callback)
    --------------------------------------------------------
    -- Cursor context
    --------------------------------------------------------

    local line = vim.api.nvim_get_current_line()

    local cursor = vim.api.nvim_win_get_cursor(0)

    local cursor_line = cursor[1]

    -- column 是 0-based
    local col = cursor[2]

    local before_cursor = line:sub(1, col)

    local items = {}

    --------------------------------------------------------
    -- shader_type
    --------------------------------------------------------

    if before_cursor:match("shader_type%s+[%w_]*$") then
        items = shader_types

    --------------------------------------------------------
    -- render_mode
    --------------------------------------------------------
    elseif before_cursor:match("render_mode%s+[%w_,%s]*$") then
        local shader_type = context.get_shader_type(ctx.bufnr)

        if shader_type then
            items = make_render_mode_items(shader_type)
        end

    --------------------------------------------------------
    -- processor function
    --------------------------------------------------------
    elseif before_cursor:match("void%s+[%w_]*$") then
        local shader_type = context.get_shader_type(ctx.bufnr)

        items = make_processor_items(shader_type)

    --------------------------------------------------------
    -- Member / Swizzle
    --------------------------------------------------------
    elseif inference.is_member_completion_context(before_cursor) then
        local expression = inference.get_expression_before_dot(before_cursor)

        local type_name = nil

        if expression then
            type_name = inference.infer_expression_type(ctx.bufnr, expression, cursor_line)
        end

        if type_name then
            local vector_size = semantic_types.get_vector_size(type_name)
            if vector_size then
                items = make_swizzle_items(vector_size, type_name)
            end
        end

    --------------------------------------------------------
    -- uniform type
    --------------------------------------------------------
    elseif before_cursor:match("uniform%s+[%w_]*$") then
        items = make_type_items()

    --------------------------------------------------------
    -- uniform hint
    --------------------------------------------------------
    elseif before_cursor:match('uniform%s+.-:%s*[%w_,()%s"%.%-]*$') then
        local uniform_type = context.get_uniform_type_before_cursor(before_cursor)

        if uniform_type then
            items = make_uniform_hint_items(uniform_type)
        end

    --------------------------------------------------------
    -- General + context-aware built-ins
    --------------------------------------------------------
    else
        items = make_context_items(ctx, cursor_line)
    end

    --------------------------------------------------------
    -- Return
    --------------------------------------------------------

    callback({
        items = items,

        is_incomplete_forward = false,
        is_incomplete_backward = false,
    })
end

return source
