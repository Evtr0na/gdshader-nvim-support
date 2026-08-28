local M = {}

local lexer = require("gdshader_nvim.syntax.lexer")

local token = require("gdshader_nvim.syntax.token")

local cache = require("gdshader_nvim.semantic.cache")

local treesitter = require("gdshader_nvim.syntax.treesitter")

------------------------------------------------------------
-- Mask segment
--
-- 保持字符串长度不变，只把内容换为空格。
--
-- Tree-sitter column 是 0-based byte offset。
------------------------------------------------------------

local function mask_segment(line, start_col, end_col)
    if end_col <= start_col then
        return line
    end

    local left = line:sub(1, start_col)

    local middle = string.rep(" ", end_col - start_col)

    local right = line:sub(end_col + 1)

    return left .. middle .. right
end

------------------------------------------------------------
-- Mask comment range
------------------------------------------------------------

local function mask_comment(lines, range)
    local start_row = range.start_row

    local start_col = range.start_col

    local end_row = range.end_row

    local end_col = range.end_col

    --------------------------------------------------------
    -- Single line
    --------------------------------------------------------

    if start_row == end_row then
        local index = start_row + 1

        local line = lines[index]

        if line then
            lines[index] = mask_segment(line, start_col, end_col)
        end

        return
    end

    --------------------------------------------------------
    -- First line
    --------------------------------------------------------

    do
        local index = start_row + 1

        local line = lines[index]

        if line then
            lines[index] = mask_segment(line, start_col, #line)
        end
    end

    --------------------------------------------------------
    -- Middle lines
    --------------------------------------------------------

    for row = start_row + 1, end_row - 1 do
        local index = row + 1

        local line = lines[index]

        if line then
            lines[index] = string.rep(" ", #line)
        end
    end

    --------------------------------------------------------
    -- Last line
    --------------------------------------------------------

    if end_col > 0 then
        local index = end_row + 1

        local line = lines[index]

        if line then
            lines[index] = mask_segment(line, 0, end_col)
        end
    end
end

------------------------------------------------------------
-- Lexer result
------------------------------------------------------------

function M.get_lexed(bufnr)
    return cache.memo(bufnr, "syntax_lexed", function(raw_lines)
        local source = table.concat(raw_lines, "\n")

        return lexer.tokenize(source, {
            include_comments = true,
        })
    end) or {
        tokens = {},
        diagnostics = {},
    }
end

------------------------------------------------------------
-- Lexer comment masking
------------------------------------------------------------

local function mask_lexer_comments(lines, lexed)
    for _, item in ipairs(lexed.tokens or {}) do
        if token.is_comment(item) then
            mask_comment(lines, {
                start_row = item.line,

                start_col = item.column,

                end_row = item.end_line,

                end_col = item.end_column,
            })
        end
    end

    return lines
end

------------------------------------------------------------
-- Lexer diagnostics
------------------------------------------------------------

function M.get_lexer_diagnostics(bufnr)
    local lexed = M.get_lexed(bufnr)

    return lexed.diagnostics or {}
end

------------------------------------------------------------
-- Semantic source lines
--
-- 和真实 buffer 保持：
--
-- 行数相同
-- column 基本相同
--
-- 但 comment 内容被 mask。
------------------------------------------------------------

function M.get_lines(bufnr)
    return cache.memo(bufnr, "syntax_source_lines", function(raw_lines)
        local lines = vim.deepcopy(raw_lines)

        local use_treesitter = require("gdshader_nvim.config").get().treesitter

        local ranges = nil

        if use_treesitter then
            ranges = treesitter.get_comment_ranges(bufnr)
        end

        ------------------------------------------------
        -- Tree-sitter unavailable / disabled
        ------------------------------------------------

        if not ranges then
            local lexed = M.get_lexed(bufnr)

            return mask_lexer_comments(lines, lexed)
        end
        ------------------------------------------------
        -- Tree-sitter comments
        ------------------------------------------------

        for _, range in ipairs(ranges) do
            mask_comment(lines, range)
        end

        return lines
    end) or {}
end

------------------------------------------------------------
-- Backend
------------------------------------------------------------

function M.using_treesitter(bufnr)
    return treesitter.is_available(bufnr)
end

return M
