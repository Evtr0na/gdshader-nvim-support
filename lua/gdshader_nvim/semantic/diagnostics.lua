local M = {}

local cache = require("gdshader_nvim.semantic.cache")

local document = require("gdshader_nvim.semantic.document")

local processors = require("gdshader_nvim.data.processors")

local builtin_variables = require("gdshader_nvim.data.builtin_variables")

local ast = require("gdshader_nvim.syntax.ast")

local AstKind = ast.Kind

local shader_types = require("gdshader_nvim.data.shader_types")

------------------------------------------------------------
-- Lookup tables
------------------------------------------------------------

local knowledge = require("gdshader_nvim.data.knowledge")

------------------------------------------------------------
-- Lookup tables (rebuilt lazily when the knowledge changes)
------------------------------------------------------------

local shader_type_set = nil

local all_processor_names = nil

local built_version = -1

local function rebuild()
    shader_type_set = {}

    for _, name in ipairs(knowledge.get("shader_types") or {}) do
        shader_type_set[name] = true
    end

    all_processor_names = {}

    for _, processor_list in pairs(knowledge.get("processors") or {}) do
        for _, processor in ipairs(processor_list) do
            all_processor_names[processor.name] = true
        end
    end

    built_version = knowledge.version()
end

local function ensure()
    if built_version ~= knowledge.version() then
        rebuild()
    end
end

------------------------------------------------------------
-- 所有已知 processor 名称
--
-- 用于区分：
--
-- void fragment() {}
--
-- 和：
--
-- void my_function() {}
------------------------------------------------------------

------------------------------------------------------------
-- Range
------------------------------------------------------------

local function token_range(item)
    if not item then
        return nil
    end

    return {
        line = item.line,

        column = item.column,

        end_line = item.end_line,

        end_column = item.end_column,
    }
end

local function node_range(node)
    if not node then
        return nil
    end

    return {
        line = node.start_line,

        column = node.start_column,

        end_line = node.end_line,

        end_column = node.end_column,
    }
end

------------------------------------------------------------
-- Diagnostic
------------------------------------------------------------

local function add(result, range, severity, code, message)
    range = range or {
        line = 0,
        column = 0,
        end_line = 0,
        end_column = 1,
    }

    table.insert(result, {
        line = range.line or 0,

        column = range.column or 0,

        end_line = range.end_line or range.line or 0,

        end_column = range.end_column or ((range.column or 0) + 1),

        severity = severity,

        code = code,

        source = "gdshader_nvim",

        message = message,
    })
end

------------------------------------------------------------
-- Existing lexer / parser diagnostics
------------------------------------------------------------

local function add_syntax_diagnostics(result, semantic_document)
    for _, diagnostic in ipairs(semantic_document.diagnostics or {}) do
        local line = diagnostic.line or 0

        local column = diagnostic.column or 0

        local length = math.max(1, diagnostic.length or 1)

        add(result, {
            line = line,

            column = column,

            end_line = line,

            end_column = column + length,
        }, "error", "syntax", diagnostic.message or "GDShader syntax error")
    end
end

------------------------------------------------------------
-- Current file is include?
------------------------------------------------------------

local function is_include_file(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)

    return name:match("%.gdshaderinc$") ~= nil
end

------------------------------------------------------------
-- shader_type diagnostics
------------------------------------------------------------

local function check_shader_type(result, bufnr, semantic_document)
    ensure()

    local root = semantic_document.ast

    local shader_node = nil

    if root then
        for _, node in ipairs(root.declarations or {}) do
            if node.kind == "shader_type" then
                shader_node = node

                break
            end
        end
    end

    --------------------------------------------------------
    -- gdshaderinc 不强制 shader_type
    --------------------------------------------------------

    if not shader_node then
        if not is_include_file(bufnr) then
            add(result, nil, "error", "missing-shader-type", "Missing shader_type declaration")
        end

        return
    end

    --------------------------------------------------------
    -- Invalid shader type
    --------------------------------------------------------

    local type_name = shader_node.shader_type

    if type_name and not shader_type_set[type_name] then
        add(
            result,
            token_range(shader_node.type_token) or node_range(shader_node),
            "error",
            "invalid-shader-type",
            "Unknown shader type '" .. type_name .. "'. Expected: " .. table.concat(shader_types, ", ")
        )
    end
end

------------------------------------------------------------
-- Processor diagnostics
------------------------------------------------------------

local function check_processors(result, semantic_document)
    ensure()

    local shader_type = semantic_document.shader_type

    if not shader_type or not shader_type_set[shader_type] then
        return
    end

    local allowed = {}

    for _, processor in ipairs(processors[shader_type] or {}) do
        allowed[processor.name] = true
    end

    for _, fn in ipairs(semantic_document.functions or {}) do
        ----------------------------------------------------
        -- 普通 user function 不参与 processor 检查
        ----------------------------------------------------

        if all_processor_names[fn.name] and not allowed[fn.name] then
            local ast_node = fn.ast

            add(
                result,
                ast_node and (token_range(ast_node.name_token) or node_range(ast_node)) or nil,
                "warning",
                "invalid-processor",
                "Processor '" .. fn.name .. "' is not valid for shader_type " .. shader_type
            )
        end
    end
end

------------------------------------------------------------
-- Processor definition
------------------------------------------------------------

local function get_processor_definition(shader_type, name)
    for _, processor in ipairs(processors[shader_type] or {}) do
        if processor.name == name then
            return processor
        end
    end

    return nil
end

------------------------------------------------------------
-- Walk statement AST
------------------------------------------------------------

local function walk_statement(node, visitor)
    if not node then
        return
    end

    visitor(node)

    --------------------------------------------------------
    -- Block
    --------------------------------------------------------

    if node.kind == AstKind.BLOCK then
        for _, child in ipairs(node.statements or {}) do
            walk_statement(child, visitor)
        end

        return
    end

    --------------------------------------------------------
    -- For body
    --------------------------------------------------------

    if node.kind == AstKind.FOR then
        if node.body then
            walk_statement(node.body, visitor)
        end

        return
    end
end

------------------------------------------------------------
-- discard diagnostics
------------------------------------------------------------

local function check_discard_usage(result, semantic_document)
    local shader_type = semantic_document.shader_type

    if not shader_type then
        return
    end

    for _, fn in ipairs(semantic_document.functions or {}) do
        local definition = get_processor_definition(shader_type, fn.name)

        ----------------------------------------------------
        -- User function / invalid processor:
        -- 暂时交给其它 diagnostics。
        ----------------------------------------------------

        if definition and definition.allow_discard == false and fn.ast and fn.ast.body then
            walk_statement(fn.ast.body, function(node)
                if node.kind ~= AstKind.DISCARD then
                    return
                end

                add(
                    result,
                    token_range(node.keyword_token) or node_range(node),
                    "error",
                    "discard-not-allowed",
                    "discard is not allowed in processor '" .. fn.name .. "'"
                )
            end)
        end
    end
end

------------------------------------------------------------
-- Built-in lookup
------------------------------------------------------------

local function get_builtin_lookup(shader_type, processor_name)
    local result = {}

    --------------------------------------------------------
    -- Global built-ins
    --------------------------------------------------------

    for _, item in ipairs(builtin_variables.global or {}) do
        result[item.name] = item
    end

    --------------------------------------------------------
    -- Processor built-ins
    --------------------------------------------------------

    local shader_data = builtin_variables[shader_type]

    local processor_data = shader_data and shader_data[processor_name] or nil

    for _, item in ipairs(processor_data or {}) do
        result[item.name] = item
    end

    return result
end

------------------------------------------------------------
-- Read-only built-in diagnostics
------------------------------------------------------------

local function check_builtin_writes(result, semantic_document)
    local shader_type = semantic_document.shader_type

    if not shader_type then
        return
    end

    for _, fn in ipairs(semantic_document.functions or {}) do
        local definition = get_processor_definition(shader_type, fn.name)

        ----------------------------------------------------
        -- 第一阶段：
        -- 只检查 processor body。
        ----------------------------------------------------

        if definition and fn.ast and fn.ast.body then
            local builtins = get_builtin_lookup(shader_type, fn.name)

            walk_statement(fn.ast.body, function(node)
                if node.kind ~= AstKind.EXPRESSION_STATEMENT then
                    return
                end

                local expression = node.expression

                if not expression or expression.kind ~= AstKind.ASSIGNMENT then
                    return
                end

                local name = expression.target_name

                local builtin = builtins[name]

                ------------------------------------------------
                -- mode == in => read-only
                ------------------------------------------------

                if builtin and builtin.mode == "in" then
                    add(
                        result,
                        token_range(expression.target_token) or node_range(expression),
                        "error",
                        "builtin-readonly",
                        "Built-in variable '" .. name .. "' is read-only in processor '" .. fn.name .. "'"
                    )
                end
            end)
        end
    end
end

------------------------------------------------------------
-- Build
------------------------------------------------------------

local function build(bufnr)
    local semantic_document = document.get(bufnr)

    local result = {}

    add_syntax_diagnostics(result, semantic_document)

    check_shader_type(result, bufnr, semantic_document)

    check_processors(result, semantic_document)

    check_discard_usage(result, semantic_document)

    check_builtin_writes(result, semantic_document)

    return result
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

function M.get(bufnr)
    return cache.memo(bufnr, "semantic_diagnostics", function()
        return build(bufnr)
    end) or {}
end

return M
