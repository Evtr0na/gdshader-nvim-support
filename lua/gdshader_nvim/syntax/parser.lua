local M = {}

local token = require("gdshader_nvim.syntax.token")

local ast = require("gdshader_nvim.syntax.ast")

local TokenKind = token.Kind

local AstKind = ast.Kind

------------------------------------------------------------
-- Parser
------------------------------------------------------------

local Parser = {}

Parser.__index = Parser

------------------------------------------------------------
-- Fallback EOF
--
-- 正常 lexer 一定会生成 EOF。
-- 这里额外创建 fallback，只是让 Parser API
-- 在收到不完整/手工 token stream 时仍然安全。
------------------------------------------------------------

local function make_fallback_eof(tokens)
    local last = tokens[#tokens]

    local line = last and last.end_line or 0

    local column = last and last.end_column or 0

    local offset = last and last.end_offset or 0

    return token.new(TokenKind.EOF, "", line, column, offset, line, column, offset)
end

--
-- Collect struct names up front so the single-pass parser can
-- treat them as declarable types (variable / function return
-- types) the way the VS Code analyzer does.
------------------------------------------------------------

local function collect_user_types(tokens)
    local names = {}

    for index, item in ipairs(tokens) do
        if item.kind == TokenKind.KEYWORD and item.value == "struct" then
            local name_token = tokens[index + 1]

            if name_token and name_token.kind == TokenKind.IDENTIFIER then
                names[name_token.value] = true
            end
        end
    end

    return names
end


function Parser.new(tokens)
    tokens = tokens or {}

    return setmetatable({
        tokens = tokens,

        index = 1,

        diagnostics = {},

        user_types = collect_user_types(tokens),

        eof_token = make_fallback_eof(tokens),
    }, Parser)
end
------------------------------------------------------------
-- Trivia
------------------------------------------------------------

local function is_trivia(item)
    return token.is_comment(item)
end

function Parser:skip_trivia()
    while self.index <= #self.tokens do
        local item = self.tokens[self.index]

        if not is_trivia(item) then
            break
        end

        self.index = self.index + 1
    end
end

------------------------------------------------------------
-- Peek
--
-- offset 按“非 trivia token”计算。
------------------------------------------------------------

function Parser:peek(offset)
    self:skip_trivia()

    offset = offset or 0

    local index = self.index

    local count = 0

    while index <= #self.tokens do
        local item = self.tokens[index]

        if not is_trivia(item) then
            if count == offset then
                return item
            end

            count = count + 1
        end

        index = index + 1
    end

    --------------------------------------------------------
    -- Parser cursor 永远返回 token。
    --------------------------------------------------------

    return self.eof_token
end
------------------------------------------------------------
-- Advance
------------------------------------------------------------

function Parser:advance()
    self:skip_trivia()

    local item = self.tokens[self.index] or self.eof_token

    --------------------------------------------------------
    -- EOF 不再向后移动。
    --------------------------------------------------------

    if item.kind ~= TokenKind.EOF then
        self.index = self.index + 1
    end

    return item
end
------------------------------------------------------------
-- Checks
------------------------------------------------------------

function Parser:is_eof()
    return self:peek().kind == TokenKind.EOF
end

------------------------------------------------------------
-- User-defined (struct) type
------------------------------------------------------------

function Parser:is_user_type(item)
    return item and item.kind == TokenKind.IDENTIFIER and self.user_types[item.value] == true
end

function Parser:is_declarable_type(item)
    return is_type(item) or self:is_user_type(item)
end

function Parser:check_value(value)
    return self:peek().value == value
end

function Parser:check_kind(kind)
    return self:peek().kind == kind
end

function Parser:match_value(value)
    if not self:check_value(value) then
        return nil
    end

    return self:advance()
end

------------------------------------------------------------
-- Diagnostics
------------------------------------------------------------

function Parser:error_at(item, message)
    item = item or self:peek()

    table.insert(self.diagnostics, {
        line = item and item.line or 0,

        column = item and item.column or 0,

        length = item and math.max(1, item.length or 1) or 1,

        message = message,
    })
end

------------------------------------------------------------
-- Identifier
------------------------------------------------------------

local function is_identifier(item)
    return item and item.kind == TokenKind.IDENTIFIER
end

------------------------------------------------------------
-- Type
------------------------------------------------------------

local function is_type(item)
    return item and item.kind == TokenKind.TYPE
end

------------------------------------------------------------
-- User-defined types
------------------------------------------------------------
-- Shader type
--
-- shader_type spatial;
------------------------------------------------------------

function Parser:parse_shader_type()
    local start = self:advance()

    local node = ast.new(AstKind.SHADER_TYPE, start)

    local name = self:peek()

    if is_identifier(name) then
        self:advance()

        node.shader_type = name.value

        node.type_token = name
    else
        self:error_at(name, "Expected shader type")
    end

    local last = name or start

    --------------------------------------------------------
    -- completion 时允许暂时没有 ;
    --------------------------------------------------------

    if self:check_value(";") then
        last = self:advance()
    end

    return ast.finish(node, last)
end

------------------------------------------------------------
-- Render mode
--
-- render_mode unshaded, cull_disabled;
------------------------------------------------------------

function Parser:parse_render_mode()
    local start = self:advance()

    local node = ast.new(AstKind.RENDER_MODE, start)

    node.modes = {}

    local last = start

    while not self:is_eof() do
        local item = self:peek()

        if item.value == ";" then
            last = self:advance()

            break
        end

        if is_identifier(item) or item.kind == TokenKind.KEYWORD then
            table.insert(node.modes, item.value)

            last = self:advance()
        elseif item.value == "," then
            last = self:advance()
        else
            break
        end
    end

    return ast.finish(node, last)
end

------------------------------------------------------------
-- Declaration tail
--
-- uniform sampler2D tex : hint_normal;
-- const float X = 1.0;
-- vec3 colors[4];
------------------------------------------------------------

function Parser:parse_declaration_tail(node, last)
    local paren_depth = 0
    local bracket_depth = 0

    while not self:is_eof() do
        local item = self:peek()

        if item.value == ";" and paren_depth == 0 and bracket_depth == 0 then
            last = self:advance()

            break
        end

        ----------------------------------------------------
        -- 不应该跨进另一个 block
        ----------------------------------------------------

        if (item.value == "{" or item.value == "}") and paren_depth == 0 and bracket_depth == 0 then
            break
        end

        if item.value == "(" then
            paren_depth = paren_depth + 1
        elseif item.value == ")" then
            paren_depth = math.max(0, paren_depth - 1)
        elseif item.value == "[" then
            bracket_depth = bracket_depth + 1

            node.is_array = true
        elseif item.value == "]" then
            bracket_depth = math.max(0, bracket_depth - 1)
        elseif item.value == "=" and paren_depth == 0 and bracket_depth == 0 then
            node.has_initializer = true
        elseif item.value == ":" and paren_depth == 0 and bracket_depth == 0 then
            node.has_hint = true
        end

        last = self:advance()
    end

    return ast.finish(node, last)
end

------------------------------------------------------------
-- Qualified declaration
--
-- uniform float value;
-- varying vec3 normal;
-- const float PI2 = ...;
------------------------------------------------------------

function Parser:parse_qualified_declaration()
    local qualifier = self:advance()

    local type_item = self:peek()

    if not is_type(type_item) and not self:is_user_type(type_item) then
        self:error_at(type_item, "Expected type after " .. qualifier.value)

        local node = ast.new(AstKind.DECLARATION, qualifier)

        node.declaration_kind = qualifier.value

        return { ast.finish(node, qualifier) }
    end

    self:advance()

    local type_name = type_item.value

    --------------------------------------------------------
    -- Build one declaration node for a name.
    --------------------------------------------------------

    local function make_decl(name_token)
        local node = ast.new(AstKind.DECLARATION, name_token)

        node.declaration_kind = qualifier.value

        node.data_type = type_name

        node.name = name_token.value

        node.name_token = name_token

        return node
    end

    local name = self:peek()

    if not is_identifier(name) then
        self:error_at(name, "Expected declaration name")

        local node = ast.new(AstKind.DECLARATION, qualifier)

        node.declaration_kind = qualifier.value

        node.data_type = type_name

        return { ast.finish(node, type_item) }
    end

    self:advance()

    local first = make_decl(name)

    local nodes = { first }

    --------------------------------------------------------
    -- Multi-variable declarations:
    --
    --   uniform float a, b;
    --   const int X = 1, Y = 2;
    --
    -- Each name becomes its own top-level declaration so
    -- completion / hover / definition see every symbol
    -- (matches the VS Code analyzer's pendingVarDecls).
    --------------------------------------------------------

    while not self:is_eof() do
        local item = self:peek()

        if item.value == ";" then
            self:advance()

            break
        elseif item.value == "," then
            self:advance()

            local next_name = self:peek()

            if not is_identifier(next_name) then
                break
            end

            self:advance()

            local decl = make_decl(next_name)

            ----------------------------------------------------
            -- Optional array size: NAME[4]
            ----------------------------------------------------

            if self:check_value("[") then
                decl.is_array = true

                while not self:is_eof() and not self:check_value("]") do
                    self:advance()
                end

                if self:check_value("]") then
                    self:advance()
                end
            end

            table.insert(nodes, decl)
        else
            ----------------------------------------------------
            -- Unexpected token; stop collecting.
            ----------------------------------------------------

            break
        end
    end

    return nodes
end

------------------------------------------------------------
-- Parameter
------------------------------------------------------------

local parameter_modes = {
    ["in"] = true,
    ["out"] = true,
    ["inout"] = true,
}

local precision_qualifiers = {
    ["lowp"] = true,
    ["mediump"] = true,
    ["highp"] = true,
}

function Parser:parse_parameter()
    local first = self:peek()

    if not first then
        return nil
    end

    local node = ast.new(AstKind.PARAMETER, first)

    --------------------------------------------------------
    -- in / out / inout
    --------------------------------------------------------

    local item = self:peek()

    if item and parameter_modes[item.value] then
        node.mode = item.value

        self:advance()
    end

    --------------------------------------------------------
    -- lowp / mediump / highp
    --------------------------------------------------------

    item = self:peek()

    if item and precision_qualifiers[item.value] then
        node.precision = item.value

        self:advance()
    end

    --------------------------------------------------------
    -- type
    --------------------------------------------------------

    local type_item = self:peek()

    if not is_type(type_item) then
        self:error_at(type_item, "Expected parameter type")

        return nil
    end

    self:advance()

    node.data_type = type_item.value

    --------------------------------------------------------
    -- name
    --------------------------------------------------------

    local name = self:peek()

    if not is_identifier(name) then
        self:error_at(name, "Expected parameter name")

        return nil
    end

    self:advance()

    node.name = name.value

    node.name_token = name

    local last = name

    --------------------------------------------------------
    -- Array parameter
    --------------------------------------------------------

    if self:check_value("[") then
        node.is_array = true

        last = self:advance()

        while not self:is_eof() and not self:check_value("]") do
            last = self:advance()
        end

        if self:check_value("]") then
            last = self:advance()
        end
    end

    return ast.finish(node, last)
end

------------------------------------------------------------
-- Parameters
------------------------------------------------------------

function Parser:parse_parameters()
    local result = {}

    if not self:match_value("(") then
        self:error_at(self:peek(), "Expected '('")

        return result, nil
    end

    local last = nil

    while not self:is_eof() and not self:check_value(")") do
        local parameter = self:parse_parameter()

        if parameter then
            table.insert(result, parameter)
        end

        if self:check_value(",") then
            last = self:advance()
        elseif not self:check_value(")") then
            ------------------------------------------------
            -- Recovery
            ------------------------------------------------

            self:error_at(self:peek(), "Expected ',' or ')'")

            self:advance()
        end
    end

    if self:check_value(")") then
        last = self:advance()
    else
        self:error_at(self:peek(), "Expected ')'")
    end

    return result, last
end

------------------------------------------------------------
-- Skip until top-level delimiter
--
-- 用于：
--
-- for (... ; ... ; ...)
--
-- 会尊重：
--
-- foo(a, b)
-- array[index]
------------------------------------------------------------

function Parser:skip_until_top_level(delimiter)
    local paren_depth = 0
    local bracket_depth = 0

    local last = nil

    while not self:is_eof() do
        local item = self:peek()

        ----------------------------------------------------
        -- 当前 delimiter
        ----------------------------------------------------

        if item.value == delimiter and paren_depth == 0 and bracket_depth == 0 then
            last = self:advance()

            return last
        end

        ----------------------------------------------------
        -- Nested parentheses
        ----------------------------------------------------

        if item.value == "(" then
            paren_depth = paren_depth + 1
        elseif item.value == ")" then
            if paren_depth > 0 then
                paren_depth = paren_depth - 1
            elseif delimiter == ")" then
                last = self:advance()

                return last
            end
        elseif item.value == "[" then
            bracket_depth = bracket_depth + 1
        elseif item.value == "]" then
            if bracket_depth > 0 then
                bracket_depth = bracket_depth - 1
            end
        end

        last = self:advance()
    end

    return last
end

------------------------------------------------------------
-- Local declaration lookahead
--
-- vec3 color;
-- float value = 1.0;
-- const int COUNT = 4;
-- highp vec3 normal;
------------------------------------------------------------

function Parser:is_local_declaration_start()
    local offset = 0

    local item = self:peek(offset)

    if not item then
        return false
    end

    --------------------------------------------------------
    -- const
    --------------------------------------------------------

    if item.value == "const" then
        offset = offset + 1

        item = self:peek(offset)
    end

    --------------------------------------------------------
    -- precision
    --------------------------------------------------------

    if item and precision_qualifiers[item.value] then
        offset = offset + 1

        item = self:peek(offset)
    end

    --------------------------------------------------------
    -- type
    --------------------------------------------------------

    if not is_type(item) and not self:is_user_type(item) then
        return false
    end

    offset = offset + 1

    --------------------------------------------------------
    -- name
    --------------------------------------------------------

    local name = self:peek(offset)

    if not is_identifier(name) then
        return false
    end

    --------------------------------------------------------
    -- 防止把其它奇怪结构误认成 declaration。
    --------------------------------------------------------

    local after_name = self:peek(offset + 1)

    if after_name and after_name.value == "(" then
        return false
    end

    return true
end

------------------------------------------------------------
-- Local declaration
------------------------------------------------------------

function Parser:parse_local_declaration()
    if not self:is_local_declaration_start() then
        return nil
    end

    local first = self:peek()

    local node = ast.new(AstKind.DECLARATION, first)

    node.scope = "local"

    --------------------------------------------------------
    -- const
    --------------------------------------------------------

    if self:check_value("const") then
        node.declaration_kind = "const"

        self:advance()
    else
        node.declaration_kind = "variable"
    end

    --------------------------------------------------------
    -- precision
    --------------------------------------------------------

    local item = self:peek()

    if item and precision_qualifiers[item.value] then
        node.precision = item.value

        self:advance()
    end

    --------------------------------------------------------
    -- type
    --------------------------------------------------------

    local type_item = self:advance()

    node.data_type = type_item.value

    --------------------------------------------------------
    -- name
    --------------------------------------------------------

    local name = self:advance()

    node.name = name.value

    node.name_token = name

    --------------------------------------------------------
    -- initializer / array / ;
    --------------------------------------------------------

    return self:parse_declaration_tail(node, name)
end

------------------------------------------------------------
-- Assignment operators
------------------------------------------------------------

local assignment_operators = {
    ["="] = true,

    ["+="] = true,
    ["-="] = true,
    ["*="] = true,
    ["/="] = true,
    ["%="] = true,

    ["<<="] = true,
    [">>="] = true,

    ["&="] = true,
    ["|="] = true,
    ["^="] = true,
}

------------------------------------------------------------
-- Inspect assignment statement
--
-- 第一阶段只识别：
--
-- NAME = ...
-- NAME.x = ...
-- NAME[index] = ...
-- NAME += ...
--
-- 暂时不构造完整 expression tree。
------------------------------------------------------------

function Parser:inspect_assignment_statement()
    local first = self:peek()

    --------------------------------------------------------
    -- 当前第一版只接受 identifier 作为 assignment root。
    --------------------------------------------------------

    if not is_identifier(first) then
        return nil
    end

    local offset = 0

    local paren_depth = 0
    local bracket_depth = 0

    while true do
        local item = self:peek(offset)

        if not item or item.kind == TokenKind.EOF then
            break
        end

        ----------------------------------------------------
        -- Statement end
        ----------------------------------------------------

        if item.value == ";" and paren_depth == 0 and bracket_depth == 0 then
            break
        end

        ----------------------------------------------------
        -- 不跨 block boundary
        ----------------------------------------------------

        if (item.value == "{" or item.value == "}") and paren_depth == 0 and bracket_depth == 0 then
            break
        end

        ----------------------------------------------------
        -- Nesting
        ----------------------------------------------------

        if item.value == "(" then
            paren_depth = paren_depth + 1
        elseif item.value == ")" then
            if paren_depth == 0 then
                break
            end

            paren_depth = paren_depth - 1
        elseif item.value == "[" then
            bracket_depth = bracket_depth + 1
        elseif item.value == "]" then
            bracket_depth = math.max(0, bracket_depth - 1)

        ----------------------------------------------------
        -- Top-level assignment
        ----------------------------------------------------
        elseif paren_depth == 0 and bracket_depth == 0 and assignment_operators[item.value] then
            return {
                target_token = first,
                operator_token = item,
            }
        end

        offset = offset + 1
    end

    return nil
end

------------------------------------------------------------
-- Parse assignment statement
------------------------------------------------------------

function Parser:parse_assignment_statement()
    local info = self:inspect_assignment_statement()

    if not info then
        return nil, nil
    end

    local start = self:peek()

    local expression = ast.new(AstKind.ASSIGNMENT, start)

    expression.target_name = info.target_token.value

    expression.target_token = info.target_token

    expression.operator = info.operator_token.value

    expression.operator_token = info.operator_token

    local last = start

    local paren_depth = 0
    local bracket_depth = 0

    --------------------------------------------------------
    -- Consume statement
    --------------------------------------------------------

    while not self:is_eof() do
        local item = self:peek()

        ----------------------------------------------------
        -- ;
        ----------------------------------------------------

        if item.value == ";" and paren_depth == 0 and bracket_depth == 0 then
            last = self:advance()

            break
        end

        ----------------------------------------------------
        -- Editing state:
        --
        -- assignment 后面还没写 ;
        ----------------------------------------------------

        if item.value == "}" and paren_depth == 0 and bracket_depth == 0 then
            break
        end

        ----------------------------------------------------
        -- Nesting
        ----------------------------------------------------

        if item.value == "(" then
            paren_depth = paren_depth + 1
        elseif item.value == ")" then
            paren_depth = math.max(0, paren_depth - 1)
        elseif item.value == "[" then
            bracket_depth = bracket_depth + 1
        elseif item.value == "]" then
            bracket_depth = math.max(0, bracket_depth - 1)
        end

        last = self:advance()
    end

    ast.finish(expression, last)

    --------------------------------------------------------
    -- Expression statement
    --------------------------------------------------------

    local statement = ast.new(AstKind.EXPRESSION_STATEMENT, start)

    statement.expression = expression

    return ast.finish(statement, last), last
end

------------------------------------------------------------
-- Discard
------------------------------------------------------------

function Parser:parse_discard_statement()
    local start = self:advance()

    local node = ast.new(AstKind.DISCARD, start)

    node.keyword_token = start

    local last = start

    --------------------------------------------------------
    -- completion/editing state 中允许暂时缺 ;
    --------------------------------------------------------

    if self:check_value(";") then
        last = self:advance()
    end

    return ast.finish(node, last), last
end

------------------------------------------------------------
-- Forward declarations
------------------------------------------------------------

local parse_block
local parse_for_statement

------------------------------------------------------------
-- For statement
--
-- 第一阶段的目的不是解析 condition expression，
-- 而是准确建立：
--
-- for-init scope
-- body scope
------------------------------------------------------------

parse_for_statement = function(self)
    local start = self:advance()

    local node = ast.new(AstKind.FOR, start)

    local last = start

    ----------------------------------------------------
    -- (
    ----------------------------------------------------

    if not self:match_value("(") then
        self:error_at(self:peek(), "Expected '(' after for")

        return ast.finish(node, last), last
    end

    ----------------------------------------------------
    -- Init
    --
    -- for (int i = 0; ...)
    ----------------------------------------------------

    if self:check_value(";") then
        last = self:advance()
    elseif self:is_local_declaration_start() then
        node.init = self:parse_local_declaration()

        if node.init then
            last = node.init
        end
    else
        last = self:skip_until_top_level(";") or last
    end

    ----------------------------------------------------
    -- Condition
    ----------------------------------------------------

    if not self:is_eof() then
        last = self:skip_until_top_level(";") or last
    end

    ----------------------------------------------------
    -- Update
    ----------------------------------------------------

    if not self:is_eof() then
        last = self:skip_until_top_level(")") or last
    end

    ----------------------------------------------------
    -- Body block
    ----------------------------------------------------

    if self:check_value("{") then
        local body, body_last = parse_block(self)

        node.body = body

        last = body_last or body or last

    ------------------------------------------------------------
    -- Nested for
    ------------------------------------------------------------
    elseif self:check_value("for") then
        local body, body_last = parse_for_statement(self)

        node.body = body

        last = body_last or body or last

    ------------------------------------------------------------
    -- discard;
    ------------------------------------------------------------
    elseif self:check_value("discard") then
        local body, body_last = self:parse_discard_statement()

        node.body = body

        last = body_last or body or last

    ------------------------------------------------------------
    -- Assignment
    ------------------------------------------------------------
    elseif self:inspect_assignment_statement() then
        local body, body_last = self:parse_assignment_statement()

        node.body = body

        last = body_last or body or last

    ------------------------------------------------------------
    -- Other single statement
    ------------------------------------------------------------
    else
        last = self:skip_until_top_level(";") or last
    end

    return ast.finish(node, last), last
end

------------------------------------------------------------
-- Block
--
-- {
--     vec3 x;
--
--     if (...) {
--         float y;
--     }
-- }
--
-- 第一阶段：
--
-- 我们只提取真正影响 scope 的东西：
--
-- local declaration
-- nested block
-- for
--
-- 其它 expression / if / while token 暂时直接跨过，
-- 但遇到它们后面的 { 时仍会递归进入 block。
------------------------------------------------------------

parse_block = function(self)
    local open_brace = self:match_value("{")

    if not open_brace then
        self:error_at(self:peek(), "Expected '{'")

        return nil, nil
    end

    local node = ast.new(AstKind.BLOCK, open_brace)

    node.statements = {}

    local last = open_brace

    while not self:is_eof() do
        ------------------------------------------------
        -- }
        ------------------------------------------------

        if self:check_value("}") then
            local close_brace = self:advance()

            return ast.finish(node, close_brace), close_brace
        end

        ------------------------------------------------
        -- Nested block
        ------------------------------------------------

        if self:check_value("{") then
            local child, child_last = parse_block(self)

            if child then
                table.insert(node.statements, child)
            end

            last = child_last or child or last

            ------------------------------------------------
            -- for
            ------------------------------------------------
        elseif self:check_value("for") then
            local for_node, for_last = parse_for_statement(self)

            if for_node then
                table.insert(node.statements, for_node)
            end

            last = for_last or for_node or last

            ------------------------------------------------
            -- Local declaration
            ------------------------------------------------
        elseif self:is_local_declaration_start() then
            local declaration = self:parse_local_declaration()

            if declaration then
                table.insert(node.statements, declaration)

                last = declaration
            end

        ------------------------------------------------
        -- discard
        ------------------------------------------------
        elseif self:check_value("discard") then
            local statement, statement_last = self:parse_discard_statement()

            if statement then
                table.insert(node.statements, statement)

                last = statement_last or statement or last
            end

        ------------------------------------------------
        -- Assignment expression statement
        ------------------------------------------------
        elseif self:inspect_assignment_statement() then
            local statement, statement_last = self:parse_assignment_statement()

            if statement then
                table.insert(node.statements, statement)

                last = statement_last or statement or last
            end

        ------------------------------------------------
        -- 其它 token
        ------------------------------------------------
        else
            last = self:advance() or last
        end
    end

    ----------------------------------------------------
    -- Editing state: missing }
    ----------------------------------------------------

    node.incomplete = true

    return ast.finish(node, last), last
end

------------------------------------------------------------
-- Function
------------------------------------------------------------

function Parser:parse_function(return_type, name, start)
    local node = ast.new(AstKind.FUNCTION, start)

    node.name = name.value
    node.name_token = name

    node.return_type = return_type.value

    local parameters, close_paren = self:parse_parameters()

    node.parameters = parameters

    local last = close_paren or name

    --------------------------------------------------------
    -- Prototype / incomplete declaration
    --------------------------------------------------------

    if self:check_value(";") then
        node.prototype = true

        last = self:advance()

        return ast.finish(node, last)
    end

    --------------------------------------------------------
    -- 编辑过程中还没有 {
    --------------------------------------------------------

    if not self:check_value("{") then
        return ast.finish(node, last)
    end

    --------------------------------------------------------
    -- Body AST
    --------------------------------------------------------

    local body, body_last = parse_block(self)

    node.body = body

    if body then
        node.body_start_line = body.start_line

        node.body_start_column = body.start_column

        node.body_end_line = body.end_line

        node.body_end_column = body.end_column

        node.incomplete_body = body.incomplete == true
    end

    return ast.finish(node, body_last or close_paren or name)
end

------------------------------------------------------------
-- Type-led top-level item
--
-- vec3 calculate(...){}
-- vec3 global_value;
------------------------------------------------------------

function Parser:parse_type_item()
    local type_item = self:advance()

    local name = self:peek()

    if not is_identifier(name) then
        self:error_at(name, "Expected identifier after type")

        return nil
    end

    self:advance()

    --------------------------------------------------------
    -- Function
    --------------------------------------------------------

    if self:check_value("(") then
        return self:parse_function(type_item, name, type_item)
    end

    --------------------------------------------------------
    -- Global variable
    --------------------------------------------------------

    local node = ast.new(AstKind.DECLARATION, type_item)

    node.declaration_kind = "variable"

    node.data_type = type_item.value

    node.name = name.value

    node.name_token = name

    return self:parse_declaration_tail(node, name)
end

------------------------------------------------------------
-- instance uniform / global uniform
------------------------------------------------------------

function Parser:parse_modifier_declaration()
    local modifier = self:advance()

    if not self:check_value("uniform") then
        return nil
    end

    local nodes = self:parse_qualified_declaration()

    if nodes then
        for _, node in ipairs(nodes) do
            node.modifier = modifier.value

            node.start_line = modifier.line

            node.start_column = modifier.column

            node.start_offset = modifier.offset
        end
    end

    return nodes
end

------------------------------------------------------------
-- Preprocessor
--
-- #include "..."
------------------------------------------------------------

function Parser:parse_preprocessor()
    local directive = self:advance()

    local node = ast.new(AstKind.PREPROCESSOR, directive)

    node.directive = directive.value

    node.arguments = {}

    local last = directive

    --------------------------------------------------------
    -- Lexer token 里没有 whitespace，
    -- 所以用 line 判断 directive 的参数范围。
    --------------------------------------------------------

    while not self:is_eof() do
        local item = self:peek()

        if item.line ~= directive.line then
            break
        end

        table.insert(node.arguments, item.value)

        last = self:advance()
    end

    return ast.finish(node, last)
end

------------------------------------------------------------
-- Struct
--
-- struct MyStruct {
--     vec3 position;
--     vec4 color;
--     float weights[4];
-- };
------------------------------------------------------------

function Parser:parse_struct()
    local start = self:advance()

    local node = ast.new(AstKind.STRUCT, start)

    node.members = {}

    local name = self:peek()

    if is_identifier(name) then
        self:advance()

        node.name = name.value

        node.name_token = name
    else
        self:error_at(name, "Expected struct name")
    end

    if not self:match_value("{") then
        self:error_at(self:peek(), "Expected '{' after struct name")

        return ast.finish(node, name or start)
    end

    while not self:is_eof() do
        local item = self:peek()

        if item.value == "}" then
            self:advance()

            break
        end

        ----------------------------------------------------
        -- Member: TYPE|USER_TYPE NAME ['[' SIZE ']'] ';'
        ----------------------------------------------------

        local type_item = self:peek()

        local member_type = nil

        if is_type(type_item) or self:is_user_type(type_item) then
            self:advance()

            member_type = type_item.value
        else
            self:error_at(type_item, "Expected struct member type")

            break
        end

        local member_name = self:peek()

        if not is_identifier(member_name) then
            self:error_at(member_name, "Expected struct member name")

            break
        end

        self:advance()

        local member = {
            name = member_name.value,

            type = member_type,

            is_array = false,

            name_token = member_name,

            start_line = member_name.line,

            start_column = member_name.column,

            end_line = member_name.end_line,

            end_column = member_name.end_column,
        }

        ----------------------------------------------------
        -- Consume to ';', honoring '[' ... ']'.
        ----------------------------------------------------

        while not self:is_eof() do
            local t = self:peek()

            if t.value == ";" then
                self:advance()

                break
            elseif t.value == "{" or t.value == "}" then
                break
            elseif t.value == "[" then
                member.is_array = true

                self:advance()

                while not self:is_eof() and not self:check_value("]") do
                    self:advance()
                end

                if self:check_value("]") then
                    self:advance()
                end
            else
                self:advance()
            end
        end

        table.insert(node.members, member)
    end

    --------------------------------------------------------
    -- Optional trailing ';' (struct MyStruct { ... };)
    --------------------------------------------------------

    if self:check_value(";") then
        self:advance()
    end

    local last_token = node.name_token or start

    return ast.finish(node, last_token)
end

------------------------------------------------------------
-- group_uniforms
--
-- group_uniforms GroupName {
--     uniform float amount = 1.0;
--     uniform vec4 tint : source_color = vec4(1.0);
-- };
--
-- The block only groups uniforms in the inspector; every
-- inner declaration is still a global symbol, so we surface
-- them as ordinary top-level declarations.
------------------------------------------------------------

function Parser:parse_group_uniforms()
    --------------------------------------------------------
    -- group_uniforms GroupName {
    --------------------------------------------------------

    self:advance() -- group_uniforms

    if is_identifier(self:peek()) then
        self:advance() -- group name
    end

    if not self:match_value("{") then
        return {}
    end

    local nodes = {}

    while not self:is_eof() do
        local item = self:peek()

        if item.value == "}" then
            self:advance()

            break
        end

        local inner = nil

        if item.value == "uniform" or item.value == "varying" or item.value == "const" then
            inner = self:parse_qualified_declaration()
        elseif self:is_declarable_type(item) then
            inner = { self:parse_type_item() }
        else
            self:advance()

            inner = nil
        end

        if inner then
            for _, n in ipairs(inner) do
                table.insert(nodes, n)
            end
        end
    end

    if self:check_value(";") then
        self:advance()
    end

    return nodes
end

------------------------------------------------------------
-- Recovery
--
-- Parser v1 不认识的结构完整跳过，
-- 防止 struct/body 内内容被误当 global。
------------------------------------------------------------

function Parser:skip_unknown()
    local depth = 0

    while not self:is_eof() do
        local item = self:advance()

        if not item then
            return
        end

        if item.value == "{" then
            depth = depth + 1
        elseif item.value == "}" then
            if depth > 0 then
                depth = depth - 1
            end

            if depth == 0 then
                return
            end
        elseif item.value == ";" and depth == 0 then
            return
        end
    end
end

------------------------------------------------------------
-- Document
------------------------------------------------------------

function Parser:parse_document()
    local first = self:peek()

    local document = ast.new(AstKind.DOCUMENT, first)

    document.declarations = {}

    while not self:is_eof() do
        local item = self:peek()

        local node = nil

        ----------------------------------------------------
        -- shader_type
        ----------------------------------------------------

        if item.value == "shader_type" then
            node = self:parse_shader_type()

        ----------------------------------------------------
        -- render_mode
        ----------------------------------------------------
        elseif item.value == "render_mode" then
            node = self:parse_render_mode()

        ----------------------------------------------------
        -- uniform / varying / const
        ----------------------------------------------------
        elseif item.value == "uniform" or item.value == "varying" or item.value == "const" then
            node = self:parse_qualified_declaration()

        ----------------------------------------------------
        -- global uniform / instance uniform
        ----------------------------------------------------
        ----------------------------------------------------
        -- flat / smooth interpolation qualifier before varying
        ----------------------------------------------------

        elseif item.value == "flat" or item.value == "smooth" then
            self:advance()

            node = self:parse_qualified_declaration()

        ----------------------------------------------------
        -- struct
        ----------------------------------------------------

        elseif item.value == "struct" then
            node = self:parse_struct()

        ----------------------------------------------------
        -- group_uniforms
        ----------------------------------------------------

        elseif item.value == "group_uniforms" then
            node = self:parse_group_uniforms()

        elseif item.value == "global" or item.value == "instance" then
            node = self:parse_modifier_declaration()

            if not node then
                self:skip_unknown()
            end

        ----------------------------------------------------
        -- Function / global variable
        ----------------------------------------------------
        elseif self:is_declarable_type(item) then
            node = self:parse_type_item()

        ----------------------------------------------------
        -- #include / #define / ...
        ----------------------------------------------------
        elseif item.kind == TokenKind.PREPROCESSOR then
            node = self:parse_preprocessor()

        ----------------------------------------------------
        -- Parser v1 暂不认识
        ----------------------------------------------------
        else
            self:skip_unknown()
        end

        if node then
            if node.kind then
                table.insert(document.declarations, node)
            else
                for _, sub in ipairs(node) do
                    table.insert(document.declarations, sub)
                end
            end
        end
    end

    local eof = self:peek() or first

    ast.finish(document, eof)

    return document
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

function M.parse(tokens)
    local parser = Parser.new(tokens)

    local document = parser:parse_document()

    return {
        ast = document,

        diagnostics = parser.diagnostics,
    }
end

return M
