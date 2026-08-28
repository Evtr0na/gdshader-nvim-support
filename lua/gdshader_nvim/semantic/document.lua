local M = {}

local cache = require("gdshader_nvim.semantic.cache")

local syntax_source = require("gdshader_nvim.syntax.source")

local parser = require("gdshader_nvim.syntax.parser")

local ast = require("gdshader_nvim.syntax.ast")

local AstKind = ast.Kind

------------------------------------------------------------
-- Position conversion
--
-- Lexer / AST:
--     0-based
--
-- context.lua 旧 API:
--     line 使用 1-based
------------------------------------------------------------
local function to_context_line(line)
    if line == nil then
        return nil
    end

    return line + 1
end
------------------------------------------------------------
-- Name position
------------------------------------------------------------

local function get_name_position(node)
    local name_token = node and node.name_token or nil

    if name_token then
        return to_context_line(name_token.line), name_token.column
    end

    return to_context_line(node and node.start_line or nil), node and node.start_column or nil
end
------------------------------------------------------------
-- Parameter
------------------------------------------------------------

local function convert_parameter(node)
    local name_line, name_column = get_name_position(node)

    return {
        name = node.name,

        type = node.data_type,

        kind = "parameter",

        mode = node.mode,

        precision = node.precision,

        is_array = node.is_array == true,

        name_line = name_line,

        name_column = name_column,

        start_line = to_context_line(node.start_line),

        start_column = node.start_column,

        end_line = to_context_line(node.end_line),

        end_column = node.end_column,

        ast = node,
    }
end
------------------------------------------------------------
-- Function
------------------------------------------------------------

local function convert_function(node)
    local parameters = {}

    local name_line, name_column = get_name_position(node)
    for _, parameter in ipairs(node.parameters or {}) do
        table.insert(parameters, convert_parameter(parameter))
    end

    return {
        name_line = name_line,

        name_column = name_column,

        name = node.name,

        return_type = node.return_type,

        parameters = parameters,

        prototype = node.prototype == true,

        incomplete_body = node.incomplete_body == true,

        ----------------------------------------------------
        -- context.lua 当前使用这些字段。
        ----------------------------------------------------

        start_line = to_context_line(node.start_line),

        end_line = to_context_line(node.end_line),

        body_start_line = to_context_line(node.body_start_line),

        body_end_line = to_context_line(node.body_end_line),

        ----------------------------------------------------
        -- Columns 保持 Neovim / AST 的 0-based。
        ----------------------------------------------------

        start_column = node.start_column,

        end_column = node.end_column,

        body_start_column = node.body_start_column,

        body_end_column = node.body_end_column,

        ----------------------------------------------------
        -- 保留原 AST。
        --
        -- 后面迁移 diagnostics / definition 时有用。
        ----------------------------------------------------

        ast = node,
    }
end

------------------------------------------------------------
-- Global declaration
------------------------------------------------------------

local function convert_declaration(node)
    local name_line, name_column = get_name_position(node)

    return {
        name = node.name,

        type = node.data_type,

        kind = node.declaration_kind,

        modifier = node.modifier,

        is_array = node.is_array == true,

        has_initializer = node.has_initializer == true,

        has_hint = node.has_hint == true,

        name_line = name_line,

        name_column = name_column,

        line = to_context_line(node.start_line),

        start_line = to_context_line(node.start_line),

        start_column = node.start_column,

        end_line = to_context_line(node.end_line),

        end_column = node.end_column,

        ast = node,
    }
end
------------------------------------------------------------
-- Scope
------------------------------------------------------------

local function make_scope(kind, node)
    return {
        kind = kind,

        start_line = to_context_line(node.start_line),

        start_column = node.start_column,

        end_line = to_context_line(node.end_line),

        end_column = node.end_column,

        symbols = {},

        children = {},

        ast = node,
    }
end

------------------------------------------------------------
-- Forward declaration
------------------------------------------------------------

local build_block_scope

------------------------------------------------------------
-- For scope
------------------------------------------------------------

local function build_for_scope(node)
    local scope = make_scope("for-init", node)

    --------------------------------------------------------
    -- for (int i = ...)
    --------------------------------------------------------

    if node.init and node.init.kind == AstKind.DECLARATION then
        table.insert(scope.symbols, convert_declaration(node.init))
    end

    --------------------------------------------------------
    -- Body
    --------------------------------------------------------

    if node.body then
        if node.body.kind == AstKind.BLOCK then
            table.insert(scope.children, build_block_scope(node.body))
        elseif node.body.kind == AstKind.FOR then
            table.insert(scope.children, build_for_scope(node.body))
        end
    end

    return scope
end

------------------------------------------------------------
-- Block scope
------------------------------------------------------------

build_block_scope = function(node)
    local scope = make_scope("block", node)

    for _, statement in ipairs(node.statements or {}) do
        ------------------------------------------------
        -- Local variable / const
        ------------------------------------------------

        if statement.kind == AstKind.DECLARATION then
            table.insert(scope.symbols, convert_declaration(statement))

            ------------------------------------------------
            -- Nested block
            ------------------------------------------------
        elseif statement.kind == AstKind.BLOCK then
            table.insert(scope.children, build_block_scope(statement))

            ------------------------------------------------
            -- For
            ------------------------------------------------
        elseif statement.kind == AstKind.FOR then
            table.insert(scope.children, build_for_scope(statement))
        end
    end

    return scope
end

------------------------------------------------------------
-- Function scope
------------------------------------------------------------

local function build_function_scope(node)
    local scope = make_scope("function", node)

    --------------------------------------------------------
    -- Parameters
    --------------------------------------------------------

    for _, parameter in ipairs(node.parameters or {}) do
        table.insert(scope.symbols, convert_parameter(parameter))
    end

    --------------------------------------------------------
    -- Function body creates its own block scope.
    --------------------------------------------------------

    if node.body then
        table.insert(scope.children, build_block_scope(node.body))
    end

    return scope
end

------------------------------------------------------------
-- Build semantic document
------------------------------------------------------------

local function build_document(bufnr)
    local lexed = syntax_source.get_lexed(bufnr)

    local parsed = parser.parse(lexed.tokens or {})

    local root = parsed.ast

    local result = {
        ast = root,

        shader_type = nil,

        render_modes = {},

        functions = {},

        globals = {},

        preprocessors = {},

        diagnostics = {},

        function_scopes = {},
    }

    --------------------------------------------------------
    -- Lexer diagnostics
    --------------------------------------------------------

    for _, diagnostic in ipairs(lexed.diagnostics or {}) do
        table.insert(result.diagnostics, diagnostic)
    end

    --------------------------------------------------------
    -- Parser diagnostics
    --------------------------------------------------------

    for _, diagnostic in ipairs(parsed.diagnostics or {}) do
        table.insert(result.diagnostics, diagnostic)
    end

    if not root then
        return result
    end

    --------------------------------------------------------
    -- Top-level declarations
    --------------------------------------------------------

    for _, node in ipairs(root.declarations or {}) do
        ----------------------------------------------------
        -- shader_type
        ----------------------------------------------------

        if node.kind == AstKind.SHADER_TYPE then
            if not result.shader_type then
                result.shader_type = node.shader_type
            end

        ----------------------------------------------------
        -- render_mode
        ----------------------------------------------------
        elseif node.kind == AstKind.RENDER_MODE then
            for _, mode in ipairs(node.modes or {}) do
                table.insert(result.render_modes, mode)
            end

        ----------------------------------------------------
        -- Global declaration
        ----------------------------------------------------
        elseif node.kind == AstKind.DECLARATION then
            table.insert(result.globals, convert_declaration(node))

        ----------------------------------------------------
        -- Function
        ----------------------------------------------------
        elseif node.kind == AstKind.FUNCTION then
            local fn = convert_function(node)

            local scope = build_function_scope(node)

            fn.scope = scope

            table.insert(result.functions, fn)

            table.insert(result.function_scopes, scope)
        ----------------------------------------------------
        -- Preprocessor
        ----------------------------------------------------
        elseif node.kind == AstKind.PREPROCESSOR then
            table.insert(result.preprocessors, {
                directive = node.directive,

                arguments = node.arguments or {},

                line = to_context_line(node.start_line),

                ast = node,
            })
        end
    end

    return result
end

------------------------------------------------------------
-- Document
------------------------------------------------------------

function M.get(bufnr)
    return cache.memo(bufnr, "semantic_document", function()
        return build_document(bufnr)
    end) or {
        shader_type = nil,

        render_modes = {},

        functions = {},

        function_scopes = {},

        globals = {},

        preprocessors = {},

        diagnostics = {},
    }
end

------------------------------------------------------------
-- Scope contains position
------------------------------------------------------------

local function scope_contains_line(scope, line)
    if not scope or not line then
        return false
    end

    local start_line = scope.start_line or 1

    local end_line = scope.end_line or math.huge

    return line >= start_line and line <= end_line
end

------------------------------------------------------------
-- Find scope path
--
-- result:
--
-- function
-- block
-- nested block
-- ...
------------------------------------------------------------

local function find_scope_path(scope, line, path)
    if not scope_contains_line(scope, line) then
        return false
    end

    table.insert(path, scope)

    for _, child in ipairs(scope.children or {}) do
        if find_scope_path(child, line, path) then
            return true
        end
    end

    return true
end

------------------------------------------------------------
-- Visible local symbols
--
-- 最内层优先。
--
-- 同 scope：
-- 后声明优先。
------------------------------------------------------------

function M.get_local_symbols(bufnr, cursor_line)
    local semantic_document = M.get(bufnr)

    local root_scope = nil

    --------------------------------------------------------
    -- 找所在函数
    --------------------------------------------------------

    for _, scope in ipairs(semantic_document.function_scopes or {}) do
        if scope_contains_line(scope, cursor_line) then
            root_scope = scope

            break
        end
    end

    if not root_scope then
        return {}
    end

    --------------------------------------------------------
    -- function -> ... -> innermost
    --------------------------------------------------------

    local path = {}

    find_scope_path(root_scope, cursor_line, path)

    local result = {}
    local seen = {}

    --------------------------------------------------------
    -- innermost -> function
    --------------------------------------------------------

    for path_index = #path, 1, -1 do
        local scope = path[path_index]

        local symbols = scope.symbols or {}

        ----------------------------------------------------
        -- 同 scope 后声明的优先
        ----------------------------------------------------

        for symbol_index = #symbols, 1, -1 do
            local symbol = symbols[symbol_index]

            local declaration_line = symbol.start_line or symbol.line or 1

            ------------------------------------------------
            -- 光标之后的声明不可见
            ------------------------------------------------

            if declaration_line <= cursor_line and not seen[symbol.name] then
                seen[symbol.name] = true

                table.insert(result, symbol)
            end
        end
    end

    return result
end

------------------------------------------------------------
-- Public lookup API
------------------------------------------------------------

function M.get_shader_type(bufnr)
    return M.get(bufnr).shader_type
end

function M.get_render_modes(bufnr)
    return M.get(bufnr).render_modes
end

function M.get_functions(bufnr)
    return M.get(bufnr).functions
end

function M.get_global_declarations(bufnr)
    return M.get(bufnr).globals
end

function M.get_preprocessors(bufnr)
    return M.get(bufnr).preprocessors
end

function M.get_diagnostics(bufnr)
    return M.get(bufnr).diagnostics
end

return M
