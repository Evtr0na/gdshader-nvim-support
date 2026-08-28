local M = {}

------------------------------------------------------------
-- Buffer
------------------------------------------------------------

local function resolve_bufnr(bufnr)
    if not bufnr or bufnr == 0 then
        return vim.api.nvim_get_current_buf()
    end

    return bufnr
end

------------------------------------------------------------
-- Parser
------------------------------------------------------------

function M.get_parser(bufnr)
    bufnr = resolve_bufnr(bufnr)

    if not vim.api.nvim_buf_is_valid(bufnr) then
        return nil
    end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "gdshader")

    if not ok then
        return nil
    end

    return parser
end

------------------------------------------------------------
-- Available
------------------------------------------------------------

function M.is_available(bufnr)
    return M.get_parser(bufnr) ~= nil
end

------------------------------------------------------------
-- Root
------------------------------------------------------------

function M.get_root(bufnr)
    local parser = M.get_parser(bufnr)

    if not parser then
        return nil
    end

    local ok, trees = pcall(function()
        return parser:parse()
    end)

    if not ok or not trees or not trees[1] then
        return nil
    end

    return trees[1]:root()
end

------------------------------------------------------------
-- Comment node
------------------------------------------------------------

local function is_comment_type(node_type)
    if node_type == "comment" then
        return true
    end

    return node_type:match("comment$") ~= nil
end

------------------------------------------------------------
-- Comment ranges
--
-- Tree-sitter row / column:
-- 0-based
-- end position is exclusive
------------------------------------------------------------

function M.get_comment_ranges(bufnr)
    local root = M.get_root(bufnr)

    if not root then
        return nil
    end

    local result = {}

    local function visit(node)
        local node_type = node:type()

        if is_comment_type(node_type) then
            local start_row, start_col, end_row, end_col = node:range()

            table.insert(result, {
                start_row = start_row,

                start_col = start_col,

                end_row = end_row,

                end_col = end_col,

                type = node_type,
            })

            ------------------------------------------------
            -- comment 内部没必要继续递归
            ------------------------------------------------

            return
        end

        for child in node:iter_children() do
            visit(child)
        end
    end

    visit(root)

    return result
end

------------------------------------------------------------
-- Node path
--
-- 用于开发阶段观察 gdshader grammar。
------------------------------------------------------------

function M.get_node_path(bufnr, row, col)
    local root = M.get_root(bufnr)

    if not root then
        return {}
    end

    local node = root:named_descendant_for_range(row, col, row, col)

    if not node then
        return {}
    end

    local result = {}

    while node do
        table.insert(result, node:type())

        node = node:parent()
    end

    return result
end

return M
