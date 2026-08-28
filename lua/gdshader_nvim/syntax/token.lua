local M = {}

local knowledge = require("gdshader_nvim.data.knowledge")

------------------------------------------------------------
-- Token kinds
------------------------------------------------------------

M.Kind = {
    IDENTIFIER = "identifier",
    KEYWORD = "keyword",
    TYPE = "type",

    BOOL = "bool_literal",
    INT = "int_literal",
    UINT = "uint_literal",
    FLOAT = "float_literal",
    STRING = "string_literal",

    OPERATOR = "operator",
    PUNCTUATION = "punctuation",

    LINE_COMMENT = "line_comment",
    BLOCK_COMMENT = "block_comment",
    DOC_COMMENT = "doc_comment",

    PREPROCESSOR = "preprocessor",

    EOF = "eof",
    ERROR = "error",
}

local Kind = M.Kind

------------------------------------------------------------
-- Keywords (static)
------------------------------------------------------------

local keyword_set = {}

local keywords = {
    "shader_type",
    "render_mode",

    "uniform",
    "varying",
    "const",
    "struct",

    "group_uniforms",

    "global",
    "instance",

    "flat",
    "smooth",

    "in",
    "out",
    "inout",

    "lowp",
    "mediump",
    "highp",

    "if",
    "else",

    "for",
    "while",
    "do",

    "switch",
    "case",
    "default",

    "break",
    "continue",
    "return",
    "discard",
}

for _, keyword in ipairs(keywords) do
    keyword_set[keyword] = true
end

------------------------------------------------------------
-- Type set (depends on the knowledge database)
--
-- Rebuilt lazily when the knowledge version changes, so
-- user-extended types are picked up.
------------------------------------------------------------

local type_set = nil

local built_version = -1

local function rebuild_types()
    type_set = {
        void = true,
    }

    local declared_types = knowledge.get("types") or {}

    for _, type_name in ipairs(declared_types) do
        type_set[type_name] = true
    end

    built_version = knowledge.version()
end

local function ensure_types()
    if built_version ~= knowledge.version() then
        rebuild_types()
    end
end

------------------------------------------------------------
-- Classify word
------------------------------------------------------------

function M.classify_word(value)
    if value == "true" or value == "false" then
        return Kind.BOOL
    end

    ensure_types()

    if type_set[value] then
        return Kind.TYPE
    end

    if keyword_set[value] then
        return Kind.KEYWORD
    end

    return Kind.IDENTIFIER
end

------------------------------------------------------------
-- Token
--
-- line / column:
-- 0-based byte position
--
-- offset:
-- 0-based byte offset
------------------------------------------------------------

function M.new(kind, value, line, column, offset, end_line, end_column, end_offset)
    return {
        kind = kind,
        value = value,

        line = line,
        column = column,
        offset = offset,

        end_line = end_line,
        end_column = end_column,
        end_offset = end_offset,

        length = end_offset - offset,
    }
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

function M.is_comment(item)
    if not item then
        return false
    end

    return item.kind == Kind.LINE_COMMENT or item.kind == Kind.BLOCK_COMMENT or item.kind == Kind.DOC_COMMENT
end

function M.is_doc_comment(item)
    return item and item.kind == Kind.DOC_COMMENT
end

function M.is_type(item)
    return item and item.kind == Kind.TYPE
end

function M.is_identifier(item)
    return item and item.kind == Kind.IDENTIFIER
end

function M.is_value(item, value)
    return item and item.value == value
end

return M
