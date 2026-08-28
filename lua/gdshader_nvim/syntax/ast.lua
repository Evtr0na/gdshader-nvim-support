local M = {}

------------------------------------------------------------
-- AST node kinds
------------------------------------------------------------

M.Kind = {
    DOCUMENT = "document",

    SHADER_TYPE = "shader_type",
    RENDER_MODE = "render_mode",

    DECLARATION = "declaration",
    FUNCTION = "function",
    PARAMETER = "parameter",

    --------------------------------------------------------
    -- Statements / scopes
    --------------------------------------------------------

    BLOCK = "block",
    FOR = "for",

    DISCARD = "discard_statement",
    EXPRESSION_STATEMENT = "expression_statement",

    --------------------------------------------------------
    -- Expressions
    --------------------------------------------------------

    ASSIGNMENT = "assignment_expression",

    PREPROCESSOR = "preprocessor",

    UNKNOWN = "unknown",
}

------------------------------------------------------------
-- Position
------------------------------------------------------------

local function start_position(item)
    if not item then
        return {
            line = 0,
            column = 0,
            offset = 0,
        }
    end

    return {
        line = item.line,
        column = item.column,
        offset = item.offset,
    }
end

local function end_position(item)
    if not item then
        return {
            line = 0,
            column = 0,
            offset = 0,
        }
    end

    return {
        line = item.end_line,
        column = item.end_column,
        offset = item.end_offset,
    }
end

------------------------------------------------------------
-- Node
------------------------------------------------------------

function M.new(kind, start_token)
    local start = start_position(start_token)

    return {
        kind = kind,

        start_line = start.line,
        start_column = start.column,
        start_offset = start.offset,

        end_line = start.line,
        end_column = start.column,
        end_offset = start.offset,
    }
end

------------------------------------------------------------
-- Finish node
------------------------------------------------------------

function M.finish(node, end_token)
    if not node then
        return nil
    end

    local finish = end_position(end_token)

    node.end_line = finish.line

    node.end_column = finish.column

    node.end_offset = finish.offset

    return node
end

return M
