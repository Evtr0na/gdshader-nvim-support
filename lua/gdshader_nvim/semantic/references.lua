local M = {}

local syntax_source = require("gdshader_nvim.syntax.source")

local symbol_at = require("gdshader_nvim.semantic.symbol_at")

local token = require("gdshader_nvim.syntax.token")

local TokenKind = token.Kind

------------------------------------------------------------
-- Declaration position
--
-- semantic document 新版优先使用 name_line/name_column。
--
-- fallback 到 AST name_token，
-- 这样即使旧 cache/document 结构仍存在也能工作。
------------------------------------------------------------

local function symbol_position(symbol)
    if not symbol then
        return nil, nil
    end

    if symbol.name_line ~= nil then
        return symbol.name_line, symbol.name_column or 0
    end

    local ast_node = symbol.ast

    local name_token = ast_node and ast_node.name_token or nil

    if name_token then
        return name_token.line + 1, name_token.column
    end

    return symbol.start_line or symbol.line, symbol.start_column or 0
end

------------------------------------------------------------
-- Stable symbol identity
------------------------------------------------------------

local function symbol_key(symbol)
    local line, column = symbol_position(symbol)

    if not line then
        return nil
    end

    return table.concat({
        symbol.kind or "symbol",

        symbol.name or "",

        tostring(line),

        tostring(column or 0),
    }, ":")
end

------------------------------------------------------------
-- Semantic target
------------------------------------------------------------

------------------------------------------------------------
-- Collect user-defined struct names (token based)
------------------------------------------------------------

local function collect_struct_names(bufnr)
    local lexed = syntax_source.get_lexed(bufnr)

    local tokens = lexed.tokens or {}

    local names = {}

    local expect_name = false

    for _, tok in ipairs(tokens) do
        if token.is_comment(tok) then
            -- comments never separate `struct` from its name
        elseif tok.kind == TokenKind.KEYWORD and tok.value == "struct" then
            expect_name = true
        elseif expect_name then
            if tok.kind == TokenKind.IDENTIFIER then
                names[tok.value] = true
            end

            expect_name = false
        end
    end

    return names
end

function M.target_at(bufnr, row, column)
    local info = symbol_at.resolve(bufnr, row, column)

    if info then
        --------------------------------------------------------
        -- Variable / parameter / uniform / varying / const
        --------------------------------------------------------

        if info.kind == "user_symbol" then
            local key = symbol_key(info.symbol)

            if not key then
                return nil
            end

            return {
                kind = "symbol",

                name = info.word,

                symbol_key = key,

                symbol = info.symbol,

                range = info.range,

                cursor_column = column,
            }
        end

        --------------------------------------------------------
        -- User function
        --
        -- 当前函数 overload 仍以同名 family 处理。
        --------------------------------------------------------

        if info.kind == "user_function" then
            return {
                kind = "function",

                name = info.word,

                functions = info.functions,

                range = info.range,

                cursor_column = column,
            }
        end
    end

    --------------------------------------------------------
    -- User-defined struct type name
    --
    -- 与 VSCode 一致：可重命名 struct 类型名（声明、类型引用、
    -- 构造器、返回类型等处一并重命名）。
    --------------------------------------------------------

    local word_info = symbol_at.get_word_at(bufnr, row, column)

    if word_info then
        local struct_names = collect_struct_names(bufnr)

        if struct_names[word_info.word] then
            return {
                kind = "type",

                name = word_info.word,

                range = {
                    line = row,

                    start_column = word_info.start_column,

                    end_column = word_info.end_column,
                },

                cursor_column = column,
            }
        end
    end

    --------------------------------------------------------
    -- Built-in / processor / 基础类型 / keyword 等不可 rename。
    --------------------------------------------------------

    return nil
end

------------------------------------------------------------
-- Compare resolved occurrence with target
------------------------------------------------------------

local function matches_target(target, info)
    if not target or not info then
        return false
    end

    if target.kind == "symbol" then
        if info.kind ~= "user_symbol" then
            return false
        end

        return symbol_key(info.symbol) == target.symbol_key
    end

    if target.kind == "function" then
        return info.kind == "user_function" and info.word == target.name
    end

    return false
end

------------------------------------------------------------
-- Previous significant token
------------------------------------------------------------

local function previous_significant(tokens, index)
    for i = index - 1, 1, -1 do
        local item = tokens[i]

        if not token.is_comment(item) then
            return item
        end
    end

    return nil
end

------------------------------------------------------------
-- Uniform hint position
--
-- 避免：
--
-- float source_color;
--
-- uniform sampler2D tex : source_color;
--                         ^^^^^^^^^^^^
--
-- 被误认为变量 source_color 的 reference。
------------------------------------------------------------

local function is_uniform_hint_position(lines, item)
    local line = lines[item.line + 1]

    if not line then
        return false
    end

    local prefix = line:sub(1, item.column)

    if prefix:match("^%s*uniform%s+.-:%s*") then
        return true
    end

    if prefix:match("^%s*global%s+uniform%s+.-:%s*") then
        return true
    end

    if prefix:match("^%s*instance%s+uniform%s+.-:%s*") then
        return true
    end

    return false
end

------------------------------------------------------------
-- Candidate filter
------------------------------------------------------------

local function is_candidate(tokens, index, item, target, lines)
    if item.kind ~= TokenKind.IDENTIFIER then
        return false
    end

    if item.value ~= target.name then
        return false
    end

    --------------------------------------------------------
    -- obj.member
    --
    -- member 不属于普通 variable/function identity。
    --
    -- 同时避免：
    --
    -- float x;
    -- color.x;
    --
    -- 将 swizzle x 误认为变量 x。
    --------------------------------------------------------

    local previous = previous_significant(tokens, index)

    if previous and previous.value == "." then
        return false
    end

    --------------------------------------------------------
    -- uniform hint
    --------------------------------------------------------

    if is_uniform_hint_position(lines, item) then
        return false
    end

    return true
end

------------------------------------------------------------
-- Is declaration
------------------------------------------------------------

local function is_symbol_declaration(target, item)
    if target.kind ~= "symbol" then
        return false
    end

    local line, column = symbol_position(target.symbol)

    if not line then
        return false
    end

    return item.line + 1 == line and item.column == column
end

local function is_function_declaration(target, item)
    if target.kind ~= "function" then
        return false
    end

    for _, fn in ipairs(target.functions or {}) do
        local line, column = symbol_position(fn)

        if line and item.line + 1 == line and item.column == column then
            return true
        end
    end

    return false
end

------------------------------------------------------------
-- Find references
------------------------------------------------------------

------------------------------------------------------------
-- Find references of a user-defined struct type name
------------------------------------------------------------

local function find_struct_references(bufnr, target)
    local lexed = syntax_source.get_lexed(bufnr)

    local tokens = lexed.tokens or {}

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local result = {}

    for index, item in ipairs(tokens) do
        if item.kind == TokenKind.IDENTIFIER and item.value == target.name then
            --------------------------------------------------------
            -- 跳过成员访问 `obj.Name`（Name 是成员而非类型名）。
            --------------------------------------------------------

            local prev = previous_significant(tokens, index)

            if not (prev and prev.value == ".") then
                local is_decl = prev and prev.kind == TokenKind.KEYWORD and prev.value == "struct"

                table.insert(result, {
                    line = item.line,

                    column = item.column,

                    end_line = item.line,

                    end_column = item.column + #item.value,

                    text = lines[item.line + 1] or "",

                    declaration = is_decl,
                })
            end
        end
    end

    table.sort(result, function(a, b)
        if a.line ~= b.line then
            return a.line < b.line
        end

        return a.column < b.column
    end)

    return result
end

function M.find(bufnr, target)
    if not target then
        return {}
    end

    --------------------------------------------------------
    -- 用户自定义 struct 类型名：收集所有出现（构造器 / 类型引用 /
    -- 返回类型 / 声明），与 VSCode 一致。
    --------------------------------------------------------

    if target.kind == "type" then
        return find_struct_references(bufnr, target)
    end

    local lexed = syntax_source.get_lexed(bufnr)

    local tokens = lexed.tokens or {}

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local result = {}

    for index, item in ipairs(tokens) do
        if is_candidate(tokens, index, item, target, lines) then
            local info = symbol_at.resolve(bufnr, item.line, item.column)

            if matches_target(target, info) then
                table.insert(result, {
                    line = item.line,

                    column = item.column,

                    end_line = item.line,

                    end_column = item.column + #item.value,

                    text = lines[item.line + 1] or "",

                    declaration = is_symbol_declaration(target, item) or is_function_declaration(target, item),
                })
            end
        end
    end

    table.sort(result, function(a, b)
        if a.line ~= b.line then
            return a.line < b.line
        end

        return a.column < b.column
    end)

    return result
end

return M
