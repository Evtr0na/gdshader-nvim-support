local M = {}

local context = require("gdshader_nvim.context")

local semantic_types = require("gdshader_nvim.semantic.types")

local knowledge = require("gdshader_nvim.data.knowledge")

------------------------------------------------------------
-- Built-in function lookup
--
-- Rebuilt lazily when the knowledge version changes.
------------------------------------------------------------

local builtin_function_map = nil

local built_version = -1

local function rebuild_builtin_functions()
    builtin_function_map = {}

    local builtin_functions = knowledge.get("builtin_functions") or {}

    for _, fn in ipairs(builtin_functions) do
        builtin_function_map[fn.name] = builtin_function_map[fn.name] or {}

        table.insert(builtin_function_map[fn.name], fn)
    end

    built_version = knowledge.version()
end

local function ensure_builtin_functions()
    if built_version ~= knowledge.version() then
        rebuild_builtin_functions()
    end
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function trim(text)
    local result = text:gsub("^%s+", "")

    result = result:gsub("%s+$", "")

    return result
end

------------------------------------------------------------
-- Find top-level ternary expression
--
-- condition ? a : b
------------------------------------------------------------

local function find_ternary_expression(expression)
    local paren_depth = 0
    local bracket_depth = 0

    local question_index = nil
    local ternary_depth = 0

    for i = 1, #expression do
        local char = expression:sub(i, i)

        if char == "(" then
            paren_depth = paren_depth + 1
        elseif char == ")" then
            paren_depth = paren_depth - 1
        elseif char == "[" then
            bracket_depth = bracket_depth + 1
        elseif char == "]" then
            bracket_depth = bracket_depth - 1
        elseif paren_depth == 0 and bracket_depth == 0 then
            if char == "?" then
                if not question_index then
                    question_index = i
                end

                ternary_depth = ternary_depth + 1
            elseif char == ":" and question_index then
                ternary_depth = ternary_depth - 1

                if ternary_depth == 0 then
                    local condition = trim(expression:sub(1, question_index - 1))

                    local when_true = trim(expression:sub(question_index + 1, i - 1))

                    local when_false = trim(expression:sub(i + 1))

                    if condition ~= "" and when_true ~= "" and when_false ~= "" then
                        return condition, when_true, when_false
                    end

                    return nil
                end
            end
        end
    end

    return nil
end

------------------------------------------------------------
-- Binary operators
--
-- 从低优先级到高优先级。
------------------------------------------------------------

local binary_operator_groups = {
    {
        "||",
    },

    {
        "&&",
    },

    {
        "==",
        "!=",
    },

    {
        "<=",
        ">=",
        "<",
        ">",
    },

    {
        "+",
        "-",
    },

    {
        "*",
        "/",
        "%",
    },
}

------------------------------------------------------------
-- + / - 是否是 unary
------------------------------------------------------------

local unary_predecessors = {
    ["("] = true,
    ["["] = true,
    ["{"] = true,

    [","] = true,

    ["+"] = true,
    ["-"] = true,
    ["*"] = true,
    ["/"] = true,
    ["%"] = true,

    ["="] = true,
    ["<"] = true,
    [">"] = true,
    ["!"] = true,

    ["&"] = true,
    ["|"] = true,

    ["?"] = true,
    [":"] = true,
}

------------------------------------------------------------
-- 获取前一个非空白字符
------------------------------------------------------------

local function previous_non_space(text, index)
    for i = index, 1, -1 do
        local char = text:sub(i, i)

        if not char:match("%s") then
            return char
        end
    end

    return nil
end

local function is_unary_operator(expression, index, operator)
    if operator ~= "+" and operator ~= "-" then
        return false
    end

    local previous = previous_non_space(expression, index - 1)

    if not previous then
        return true
    end

    return unary_predecessors[previous] == true
end

------------------------------------------------------------
-- 查找最外层 binary operator
------------------------------------------------------------

local function find_binary_operator(expression)
    for _, operators in ipairs(binary_operator_groups) do
        local paren_depth = 0
        local bracket_depth = 0

        local last_match = nil

        local i = 1

        while i <= #expression do
            local char = expression:sub(i, i)

            if char == "(" then
                paren_depth = paren_depth + 1
            elseif char == ")" then
                paren_depth = paren_depth - 1
            elseif char == "[" then
                bracket_depth = bracket_depth + 1
            elseif char == "]" then
                bracket_depth = bracket_depth - 1
            elseif paren_depth == 0 and bracket_depth == 0 then
                for _, operator in ipairs(operators) do
                    local finish = i + #operator - 1

                    if expression:sub(i, finish) == operator then
                        if not is_unary_operator(expression, i, operator) then
                            last_match = {
                                index = i,
                                operator = operator,
                            }
                        end

                        i = finish
                        break
                    end
                end
            end

            i = i + 1
        end

        ----------------------------------------------------
        -- 同一级优先级采用最右边，
        -- 让 a - b - c 解析成：
        --
        -- (a - b) - c
        ----------------------------------------------------

        if last_match then
            local left = trim(expression:sub(1, last_match.index - 1))

            local right = trim(expression:sub(last_match.index + #last_match.operator))

            if left ~= "" and right ~= "" then
                return left, last_match.operator, right
            end
        end
    end

    return nil
end

------------------------------------------------------------
-- 去掉完整的外层括号
--
-- ((foo)) -> foo
------------------------------------------------------------

local function unwrap_parentheses(expression)
    expression = trim(expression)

    while expression:match("^%b()$") do
        expression = trim(expression:sub(2, -2))
    end

    return expression
end

------------------------------------------------------------
-- 按顶层逗号分割参数
--
-- foo(a, vec3(1, 2, 3), bar(x))
------------------------------------------------------------

local function split_arguments(text)
    local result = {}

    text = trim(text)

    if text == "" then
        return result
    end

    local start_index = 1

    local paren_depth = 0
    local bracket_depth = 0

    for i = 1, #text do
        local char = text:sub(i, i)

        if char == "(" then
            paren_depth = paren_depth + 1
        elseif char == ")" then
            paren_depth = paren_depth - 1
        elseif char == "[" then
            bracket_depth = bracket_depth + 1
        elseif char == "]" then
            bracket_depth = bracket_depth - 1
        elseif char == "," and paren_depth == 0 and bracket_depth == 0 then
            table.insert(result, trim(text:sub(start_index, i - 1)))

            start_index = i + 1
        end
    end

    local tail = trim(text:sub(start_index))

    if tail ~= "" then
        table.insert(result, tail)
    end

    return result
end

------------------------------------------------------------
-- 找最后一个顶层 "."
--
-- foo.bar
-- foo().bar
-- foo[0].bar
------------------------------------------------------------

local function find_last_top_level_dot(expression)
    local paren_depth = 0
    local bracket_depth = 0

    for i = #expression, 1, -1 do
        local char = expression:sub(i, i)

        if char == ")" then
            paren_depth = paren_depth + 1
        elseif char == "(" then
            paren_depth = paren_depth - 1
        elseif char == "]" then
            bracket_depth = bracket_depth + 1
        elseif char == "[" then
            bracket_depth = bracket_depth - 1
        elseif char == "." and paren_depth == 0 and bracket_depth == 0 then
            return i
        end
    end

    return nil
end

------------------------------------------------------------
-- Built-in function return rules
------------------------------------------------------------

local function resolve_return_rule(rule, argument_types)
    if not rule then
        return nil
    end

    --------------------------------------------------------
    -- fixed
    --------------------------------------------------------

    if rule.kind == "fixed" then
        return rule.type
    end

    --------------------------------------------------------
    -- same_as_argument
    --------------------------------------------------------

    if rule.kind == "same_as_argument" then
        return argument_types[rule.index]
    end

    --------------------------------------------------------
    -- sampled_vector
    --------------------------------------------------------

    if rule.kind == "sampled_vector" then
        local sampler_type = argument_types[rule.index]

        return semantic_types.get_sampled_vector_type(sampler_type)
    end
    return nil
end

------------------------------------------------------------
-- Forward declaration
------------------------------------------------------------

local infer_expression_type

------------------------------------------------------------
-- Built-in function call
------------------------------------------------------------

local function infer_builtin_call(bufnr, function_name, arguments, cursor_line, depth)
    ensure_builtin_functions()

    local definitions = builtin_function_map[function_name]

    if not definitions then
        return nil
    end

    local argument_types = {}

    for index, argument in ipairs(arguments) do
        argument_types[index] = infer_expression_type(bufnr, argument, cursor_line, depth + 1)
    end

    --------------------------------------------------------
    -- 以后允许 overload。
    --
    -- 如果多个定义能推断出不同返回值，
    -- 第一阶段宁可返回 nil。
    --------------------------------------------------------

    local inferred_type = nil

    for _, definition in ipairs(definitions) do
        local result = resolve_return_rule(definition.return_type, argument_types)

        if result then
            if inferred_type and inferred_type ~= result then
                return nil
            end

            inferred_type = result
        end
    end

    return inferred_type
end

------------------------------------------------------------
-- Expression inference
------------------------------------------------------------

infer_expression_type = function(bufnr, expression, cursor_line, depth)
    bufnr = bufnr or 0

    depth = depth or 0

    ----------------------------------------------------
    -- 防止异常递归
    ----------------------------------------------------

    if depth > 16 then
        return nil
    end

    expression = trim(expression or "")

    if expression == "" then
        return nil
    end

    expression = unwrap_parentheses(expression)

    ----------------------------------------------------
    -- Boolean literal
    ----------------------------------------------------

    if expression == "true" or expression == "false" then
        return "bool"
    end

    ----------------------------------------------------
    -- uint literal
    ----------------------------------------------------

    if expression:match("^%d+[uU]$") then
        return "uint"
    end

    ----------------------------------------------------
    -- Numeric literal
    ----------------------------------------------------

    if tonumber(expression) then
        if expression:find("[%.eE]") then
            return "float"
        end

        return "int"
    end

    ----------------------------------------------------
    -- Ternary expression
    ----------------------------------------------------

    local condition, when_true, when_false = find_ternary_expression(expression)

    if condition and when_true and when_false then
        local condition_type = infer_expression_type(bufnr, condition, cursor_line, depth + 1)

        local true_type = infer_expression_type(bufnr, when_true, cursor_line, depth + 1)

        local false_type = infer_expression_type(bufnr, when_false, cursor_line, depth + 1)

        return semantic_types.get_ternary_result(condition_type, true_type, false_type)
    end

    ----------------------------------------------------
    -- Binary expression
    ----------------------------------------------------

    local left, operator, right = find_binary_operator(expression)

    if left and operator and right then
        local left_type = infer_expression_type(bufnr, left, cursor_line, depth + 1)

        local right_type = infer_expression_type(bufnr, right, cursor_line, depth + 1)

        return semantic_types.get_binary_result(left_type, operator, right_type)
    end

    ----------------------------------------------------
    -- Unary expression
    --
    -- -foo
    -- +foo
    -- !condition
    -- ~flags
    ----------------------------------------------------

    local unary_operator = expression:match("^([!~+%-])")

    if unary_operator then
        local operand = trim(expression:sub(#unary_operator + 1))

        if operand ~= "" then
            local operand_type = infer_expression_type(bufnr, operand, cursor_line, depth + 1)

            return semantic_types.get_unary_result(unary_operator, operand_type)
        end
    end

    ----------------------------------------------------
    -- Member / swizzle
    --
    -- foo.xyz
    -- foo().rgb
    ----------------------------------------------------

    local dot_index = find_last_top_level_dot(expression)

    if dot_index then
        local base = trim(expression:sub(1, dot_index - 1))

        local member = trim(expression:sub(dot_index + 1))

        if member:match("^[%a_][%w_]*$") then
            local base_type = infer_expression_type(bufnr, base, cursor_line, depth + 1)

            if base_type then
                return semantic_types.get_member_result(bufnr, base_type, member)
            end
        end
    end

    ----------------------------------------------------
    -- Index
    --
    -- foo[0]
    ----------------------------------------------------

    local indexed_base = expression:match("^(.-)%[[^%[%]]+%]$")

    if indexed_base then
        local base_type = infer_expression_type(bufnr, indexed_base, cursor_line, depth + 1)

        if base_type then
            return semantic_types.get_index_result(base_type)
        end
    end
    ----------------------------------------------------
    -- Function call / constructor
    ----------------------------------------------------

    local function_name, parameter_text = expression:match("^([%a_][%w_]*)" .. "%s*" .. "(%b())" .. "$")

    if function_name and parameter_text then
        ------------------------------------------------
        -- Constructor
        --
        -- vec3(...)
        -- mat4(...)
        ------------------------------------------------

        if semantic_types.is_type(function_name) then
            return function_name
        end
        ------------------------------------------------
        -- User function
        ------------------------------------------------

        local user_return_type = context.get_user_function_return_type(bufnr, function_name)

        if user_return_type then
            return user_return_type
        end

        ------------------------------------------------
        -- Built-in function
        ------------------------------------------------

        local arguments = split_arguments(parameter_text:sub(2, -2))

        return infer_builtin_call(bufnr, function_name, arguments, cursor_line, depth)
    end

    ----------------------------------------------------
    -- Identifier
    ----------------------------------------------------

    if expression:match("^[%a_][%w_]*$") then
        return context.get_symbol_type(bufnr, expression, cursor_line)
    end

    return nil
end

------------------------------------------------------------
-- Public inference API
------------------------------------------------------------

function M.infer_expression_type(bufnr, expression, cursor_line)
    return infer_expression_type(bufnr, expression, cursor_line, 0)
end

------------------------------------------------------------
-- 判断是否是 member completion context
--
-- 避免把：
--
-- 1.0
--
-- 误认为：
--
-- expression.member
------------------------------------------------------------

function M.is_member_completion_context(before_cursor)
    local prefix = before_cursor:match("^(.*)%.[%w_]*$")

    if not prefix then
        return false
    end

    prefix = trim(prefix)

    if prefix == "" then
        return false
    end

    local last = prefix:sub(-1)

    if last:match("[%a_]") then
        return true
    end

    return last == ")" or last == "]"
end

------------------------------------------------------------
-- 获取最后一个 "." 左侧表达式
------------------------------------------------------------

function M.get_expression_before_dot(before_cursor)
    local prefix = before_cursor:match("^(.*)%.[%w_]*$")

    if not prefix then
        return nil
    end

    prefix = trim(prefix)

    if prefix == "" then
        return nil
    end

    --------------------------------------------------------
    -- 从右往左找表达式边界
    --------------------------------------------------------

    local paren_depth = 0
    local bracket_depth = 0

    for i = #prefix, 1, -1 do
        local char = prefix:sub(i, i)

        if char == ")" then
            paren_depth = paren_depth + 1
        elseif char == "(" then
            paren_depth = paren_depth - 1
        elseif char == "]" then
            bracket_depth = bracket_depth + 1
        elseif char == "[" then
            bracket_depth = bracket_depth - 1
        elseif paren_depth == 0 and bracket_depth == 0 then
            if
                char:match("%s")
                or char == ","
                or char == ";"
                or char == "="
                or char == "+"
                or char == "-"
                or char == "*"
                or char == "/"
                or char == "%"
                or char == "<"
                or char == ">"
                or char == "!"
                or char == "&"
                or char == "|"
                or char == "?"
                or char == ":"
                or char == "{"
                or char == "}"
            then
                return trim(prefix:sub(i + 1))
            end
        end
    end

    return prefix
end

return M
