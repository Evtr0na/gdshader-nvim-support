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

------------------------------------------------------------
-- Doc comment for a function
--
-- Collects the `///` / `/** */` DOC_COMMENT tokens immediately
-- above a function declaration (mirrors vscode doc comments).
------------------------------------------------------------

local function clean_doc(text)
    if not text then
        return ""
    end

    local lines = vim.split(text, "\n", { plain = true })

    for i, line in ipairs(lines) do
        --------------------------------------------------------
        -- 去掉行首的文档注释标记：
        --   /// comment          -> comment
        --   /** comment */       -> comment
        --   * middle line        -> middle line   (块注释正文)
        --------------------------------------------------------

        line = line:gsub("^///%s*", "")
        line = line:gsub("^/%*%*%s*", "")
        line = line:gsub("%s*%*%/%s*$", "")
        line = line:gsub("^%s*%*%s?", "")

        lines[i] = line
    end

    return table.concat(lines, "\n")
end

local function function_doc(tokens, node)
    if not tokens or not node then
        return nil
    end

    local start_line = node.start_line or 0
    local start_column = node.start_column or 0

    --------------------------------------------------------
    -- Find the token index at the function's start position.
    --------------------------------------------------------

    local index = nil

    for i, tok in ipairs(tokens) do
        if tok.line == start_line and tok.column == start_column then
            index = i

            break
        end
    end

    if not index or index <= 1 then
        return nil
    end

    --------------------------------------------------------
    -- Walk upward collecting contiguous DOC_COMMENT tokens.
    --------------------------------------------------------

    local lines = {}

    for j = index - 1, 1, -1 do
        local tok = tokens[j]

        if tok.kind ~= "doc_comment" then
            break
        end

        table.insert(lines, 1, clean_doc(tok.value))
    end

    if #lines == 0 then
        return nil
    end

    return table.concat(lines, "\n")
end

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

        structs = {},

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

            fn.doc = function_doc(lexed.tokens, node)

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

        ----------------------------------------------------
        -- Struct (user-defined type)
        ----------------------------------------------------

        elseif node.kind == AstKind.STRUCT then
            local struct = {
                name = node.name,

                members = {},

                name_line = to_context_line(node.start_line),

                name_column = node.start_column,

                start_line = to_context_line(node.start_line),

                start_column = node.start_column,

                end_line = to_context_line(node.end_line),

                end_column = node.end_column,
            }

            for _, member in ipairs(node.members or {}) do
                table.insert(struct.members, {
                    name = member.name,

                    type = member.type,

                    is_array = member.is_array == true,

                    name_line = to_context_line(member.start_line),

                    name_column = member.start_column,

                    line = to_context_line(member.start_line),

                    start_line = to_context_line(member.start_line),

                    start_column = member.start_column,

                    end_line = to_context_line(member.end_line),

                    end_column = member.end_column,
                })
            end

            table.insert(result.structs, struct)
        end
    end

    --------------------------------------------------------
    -- Hint comments (#gdshader-hint-*)
    -- (type / declare / define) — 对齐 vscode hint-scanner。
    --------------------------------------------------------

    local ok_hints, hints = pcall(require, "gdshader_nvim.syntax.hints")

    if ok_hints and hints then
        local src_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local src = table.concat(src_lines, "\n")

        local scanned = hints.scan(src)

        ----------------------------------------------------
        -- type hints: 覆盖紧邻上方的变量声明类型。
        ----------------------------------------------------

        for _, th in ipairs(scanned.typeHints or {}) do
            for _, g in ipairs(result.globals) do
                if g.end_line == th.line then
                    g.type = th.typeName

                    break
                end
            end
        end

        ----------------------------------------------------
        -- declare hints: 注入变量 / 函数符号。
        ----------------------------------------------------

        for _, dh in ipairs(scanned.defHints or {}) do
            if dh.isFunction then
                local params = {}

                for _, p in ipairs(dh.parameters or {}) do
                    table.insert(params, {
                        name = p.name,
                        type = p.typeName,
                        kind = "parameter",
                        mode = (p.qualifier and p.qualifier ~= "" and p.qualifier or nil),
                        name_line = dh.line + 1,
                        name_column = 0,
                        start_line = dh.line + 1,
                        start_column = 0,
                        end_line = dh.line + 1,
                        end_column = 0,
                    })
                end

                table.insert(result.functions, {
                    name = dh.name,
                    return_type = dh.typeName,
                    parameters = params,
                    name_line = dh.line + 1,
                    name_column = 0,
                    start_line = dh.line + 1,
                    end_line = dh.line + 1,
                    body_start_line = dh.line + 1,
                    body_end_line = dh.line + 1,
                    start_column = 0,
                    end_column = 0,
                    body_start_column = 0,
                    body_end_column = 0,
                    ast = nil,
                    scope = nil,
                    hint_declared = true,
                    prototype = true,
                    incomplete_body = true,
                })
            else
                table.insert(result.globals, {
                    name = dh.name,
                    type = dh.typeName,
                    kind = "global",
                    modifier = nil,
                    is_array = false,
                    name_line = dh.line + 1,
                    name_column = 0,
                    line = dh.line + 1,
                    start_line = dh.line + 1,
                    start_column = 0,
                    end_line = dh.line + 1,
                    end_column = 0,
                    ast = nil,
                    hint_declared = true,
                })
            end
        end

        result.macros = scanned.macros
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

------------------------------------------------------------
-- Structs (user-defined types)
------------------------------------------------------------

function M.get_structs(bufnr)
    return M.get(bufnr).structs or {}
end

function M.get_struct(bufnr, name)
    if not name then
        return nil
    end

    for _, struct in ipairs(M.get_structs(bufnr) or {}) do
        if struct.name == name then
            return struct
        end
    end

    return nil
end

function M.get_diagnostics(bufnr)
    return M.get(bufnr).diagnostics
end

return M
