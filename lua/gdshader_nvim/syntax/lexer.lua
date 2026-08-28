local M = {}

local token = require("gdshader_nvim.syntax.token")

local Kind = token.Kind

------------------------------------------------------------
-- Character helpers
------------------------------------------------------------

local function is_digit(char)
    return char >= "0" and char <= "9"
end

local function is_hex_digit(char)
    return is_digit(char) or (char >= "a" and char <= "f") or (char >= "A" and char <= "F")
end

local function is_ident_start(char)
    if not char or char == "" or char == "\0" then
        return false
    end

    return (char >= "a" and char <= "z") or (char >= "A" and char <= "Z") or char == "_"
end

local function is_ident_char(char)
    return is_ident_start(char) or is_digit(char)
end

------------------------------------------------------------
-- Scanner
------------------------------------------------------------

local Scanner = {}

Scanner.__index = Scanner

function Scanner.new(source, options)
    return setmetatable({
        source = source or "",

        length = #(source or ""),

        ------------------------------------------------
        -- Lua string index:
        -- 1-based
        ------------------------------------------------

        pos = 1,

        ------------------------------------------------
        -- Editor positions:
        -- 0-based
        ------------------------------------------------

        line = 0,
        column = 0,

        tokens = {},
        diagnostics = {},

        include_comments = options and options.include_comments == true or false,

        ------------------------------------------------
        -- 当前行目前是否只有空白
        ------------------------------------------------

        line_only_whitespace = true,
    }, Scanner)
end

------------------------------------------------------------
-- Cursor
------------------------------------------------------------

function Scanner:peek(offset)
    offset = offset or 0

    local index = self.pos + offset

    if index < 1 or index > self.length then
        return "\0"
    end

    return self.source:sub(index, index)
end

function Scanner:advance()
    if self.pos > self.length then
        return "\0"
    end

    local char = self.source:sub(self.pos, self.pos)

    self.pos = self.pos + 1

    if char == "\n" then
        self.line = self.line + 1

        self.column = 0

        self.line_only_whitespace = true
    else
        self.column = self.column + 1

        if char ~= " " and char ~= "\t" and char ~= "\r" then
            self.line_only_whitespace = false
        end
    end

    return char
end

------------------------------------------------------------
-- Position
------------------------------------------------------------

function Scanner:mark()
    return {
        pos = self.pos,

        line = self.line,
        column = self.column,

        offset = self.pos - 1,
    }
end

------------------------------------------------------------
-- Emit
------------------------------------------------------------

function Scanner:emit(kind, start)
    local value = self.source:sub(start.pos, self.pos - 1)

    table.insert(
        self.tokens,
        token.new(kind, value, start.line, start.column, start.offset, self.line, self.column, self.pos - 1)
    )
end

function Scanner:add_diagnostic(start, message)
    table.insert(self.diagnostics, {
        line = start.line,
        column = start.column,

        length = math.max(1, self.pos - start.pos),

        message = message,
    })
end

------------------------------------------------------------
-- Whitespace
------------------------------------------------------------

function Scanner:skip_whitespace()
    while self.pos <= self.length do
        local char = self:peek()

        if char == " " or char == "\t" or char == "\r" or char == "\n" then
            self:advance()
        else
            break
        end
    end
end

------------------------------------------------------------
-- Identifier / keyword / type
------------------------------------------------------------

function Scanner:read_identifier()
    local start = self:mark()

    while self.pos <= self.length and is_ident_char(self:peek()) do
        self:advance()
    end

    local value = self.source:sub(start.pos, self.pos - 1)

    local kind = token.classify_word(value)

    self:emit(kind, start)
end

------------------------------------------------------------
-- Line comment
--
-- // ...
-- /// doc ...
------------------------------------------------------------

function Scanner:read_line_comment()
    local start = self:mark()

    local is_doc = self:peek(2) == "/"

    while self.pos <= self.length and self:peek() ~= "\n" do
        self:advance()
    end

    if self.include_comments then
        self:emit(is_doc and Kind.DOC_COMMENT or Kind.LINE_COMMENT, start)
    end
end

------------------------------------------------------------
-- Block comment
--
-- /* ... */
-- /** doc ... */
------------------------------------------------------------

function Scanner:read_block_comment()
    local start = self:mark()

    --------------------------------------------------------
    -- /*
    --------------------------------------------------------

    self:advance()
    self:advance()

    local is_doc = self:peek() == "*" and self:peek(1) ~= "/"

    local closed = false

    while self.pos <= self.length do
        if self:peek() == "*" and self:peek(1) == "/" then
            self:advance()
            self:advance()

            closed = true
            break
        end

        self:advance()
    end

    if self.include_comments then
        self:emit(is_doc and Kind.DOC_COMMENT or Kind.BLOCK_COMMENT, start)
    end

    if not closed then
        self:add_diagnostic(start, "Unclosed block comment")
    end
end

------------------------------------------------------------
-- String
------------------------------------------------------------

function Scanner:read_string()
    local start = self:mark()

    --------------------------------------------------------
    -- opening "
    --------------------------------------------------------

    self:advance()

    local closed = false

    while self.pos <= self.length do
        local char = self:peek()

        if char == '"' then
            self:advance()

            closed = true
            break
        elseif char == "\n" then
            break
        elseif char == "\\" then
            self:advance()

            if self.pos <= self.length and self:peek() ~= "\n" then
                self:advance()
            end
        else
            self:advance()
        end
    end

    self:emit(Kind.STRING, start)

    if not closed then
        self:add_diagnostic(start, "Unclosed string literal")
    end
end

------------------------------------------------------------
-- Number
------------------------------------------------------------

function Scanner:read_number()
    local start = self:mark()

    local is_float = false
    local is_uint = false

    --------------------------------------------------------
    -- Hexadecimal
    --------------------------------------------------------

    if self:peek() == "0" and (self:peek(1) == "x" or self:peek(1) == "X") then
        self:advance()
        self:advance()

        while is_hex_digit(self:peek()) do
            self:advance()
        end

        if self:peek() == "u" or self:peek() == "U" then
            is_uint = true
            self:advance()
        end

        self:emit(is_uint and Kind.UINT or Kind.INT, start)

        return
    end

    --------------------------------------------------------
    -- .123
    --------------------------------------------------------

    if self:peek() == "." then
        is_float = true

        self:advance()

        while is_digit(self:peek()) do
            self:advance()
        end
    else
        ----------------------------------------------------
        -- Integer part
        ----------------------------------------------------

        while is_digit(self:peek()) do
            self:advance()
        end

        ----------------------------------------------------
        -- Fraction
        --
        -- 1.0
        -- 1.
        --
        -- 1.foo 则保持：
        --
        -- 1
        -- .
        -- foo
        ----------------------------------------------------

        if self:peek() == "." and not is_ident_start(self:peek(1)) then
            is_float = true

            self:advance()

            while is_digit(self:peek()) do
                self:advance()
            end
        end
    end

    --------------------------------------------------------
    -- Exponent
    --------------------------------------------------------

    if self:peek() == "e" or self:peek() == "E" then
        is_float = true

        self:advance()

        if self:peek() == "+" or self:peek() == "-" then
            self:advance()
        end

        local exponent_start = self.pos

        while is_digit(self:peek()) do
            self:advance()
        end

        if exponent_start == self.pos then
            self:add_diagnostic(start, "Malformed numeric exponent")
        end
    end

    --------------------------------------------------------
    -- Suffix
    --------------------------------------------------------

    if self:peek() == "f" or self:peek() == "F" then
        is_float = true

        self:advance()
    elseif not is_float and (self:peek() == "u" or self:peek() == "U") then
        is_uint = true

        self:advance()
    end

    --------------------------------------------------------
    -- Emit
    --------------------------------------------------------

    local kind = Kind.INT

    if is_float then
        kind = Kind.FLOAT
    elseif is_uint then
        kind = Kind.UINT
    end

    self:emit(kind, start)
end

------------------------------------------------------------
-- Preprocessor
--
-- #include
-- #define
-- #ifdef
--
-- 这里只读取 directive 名字。
--
-- #include "res://foo.gdshaderinc"
--
-- 会得到：
--
-- preprocessor "#include"
-- string       "\"res://foo.gdshaderinc\""
--
-- 因此字符串里的 // 永远不会被误认成注释。
------------------------------------------------------------

function Scanner:read_preprocessor()
    local start = self:mark()

    self:advance()

    while is_ident_char(self:peek()) do
        self:advance()
    end

    self:emit(Kind.PREPROCESSOR, start)
end

------------------------------------------------------------
-- Operators
------------------------------------------------------------

local multi_operators = {
    "<<=",
    ">>=",

    "==",
    "!=",
    "<=",
    ">=",

    "<<",
    ">>",

    "&&",
    "||",

    "++",
    "--",

    "+=",
    "-=",
    "*=",
    "/=",
    "%=",

    "&=",
    "|=",
    "^=",
}

local single_operators = {
    ["="] = true,

    ["!"] = true,
    ["<"] = true,
    [">"] = true,

    ["+"] = true,
    ["-"] = true,
    ["*"] = true,
    ["/"] = true,
    ["%"] = true,

    ["&"] = true,
    ["|"] = true,
    ["^"] = true,
    ["~"] = true,

    ["?"] = true,
    [":"] = true,
}

local punctuation = {
    [";"] = true,
    [","] = true,
    ["."] = true,

    ["("] = true,
    [")"] = true,

    ["{"] = true,
    ["}"] = true,

    ["["] = true,
    ["]"] = true,
}

function Scanner:read_operator_or_punctuation()
    --------------------------------------------------------
    -- Longest match first
    --------------------------------------------------------

    for _, operator in ipairs(multi_operators) do
        if self.source:sub(self.pos, self.pos + #operator - 1) == operator then
            local start = self:mark()

            for _ = 1, #operator do
                self:advance()
            end

            self:emit(Kind.OPERATOR, start)

            return true
        end
    end

    local char = self:peek()

    if single_operators[char] then
        local start = self:mark()

        self:advance()

        self:emit(Kind.OPERATOR, start)

        return true
    end

    if punctuation[char] then
        local start = self:mark()

        self:advance()

        self:emit(Kind.PUNCTUATION, start)

        return true
    end

    return false
end

------------------------------------------------------------
-- Error
------------------------------------------------------------

function Scanner:read_unknown()
    local start = self:mark()

    local char = self:peek()

    self:advance()

    self:emit(Kind.ERROR, start)

    self:add_diagnostic(start, "Unexpected character: " .. vim.inspect(char))
end

------------------------------------------------------------
-- Main
------------------------------------------------------------

function Scanner:scan()
    while self.pos <= self.length do
        self:skip_whitespace()

        if self.pos > self.length then
            break
        end

        local char = self:peek()

        ----------------------------------------------------
        -- Preprocessor
        ----------------------------------------------------

        if char == "#" and self.line_only_whitespace then
            self:read_preprocessor()

        ----------------------------------------------------
        -- Comment
        ----------------------------------------------------
        elseif char == "/" and self:peek(1) == "/" then
            self:read_line_comment()
        elseif char == "/" and self:peek(1) == "*" then
            self:read_block_comment()

        ----------------------------------------------------
        -- String
        ----------------------------------------------------
        elseif char == '"' then
            self:read_string()

        ----------------------------------------------------
        -- Number
        ----------------------------------------------------
        elseif is_digit(char) then
            self:read_number()
        elseif char == "." and is_digit(self:peek(1)) then
            self:read_number()

        ----------------------------------------------------
        -- Identifier / keyword
        ----------------------------------------------------
        elseif is_ident_start(char) then
            self:read_identifier()

        ----------------------------------------------------
        -- Operator / punctuation
        ----------------------------------------------------
        elseif self:read_operator_or_punctuation() then
            -- handled

            ----------------------------------------------------
            -- Error
            ----------------------------------------------------
        else
            self:read_unknown()
        end
    end

    --------------------------------------------------------
    -- EOF
    --------------------------------------------------------

    table.insert(
        self.tokens,
        token.new(Kind.EOF, "", self.line, self.column, self.pos - 1, self.line, self.column, self.pos - 1)
    )

    return {
        tokens = self.tokens,

        diagnostics = self.diagnostics,
    }
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

function M.tokenize(source, options)
    return Scanner.new(source, options):scan()
end

return M
