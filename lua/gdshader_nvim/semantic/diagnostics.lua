local M = {}

local cache = require("gdshader_nvim.semantic.cache")

local document = require("gdshader_nvim.semantic.document")

local processors = require("gdshader_nvim.data.processors")

local builtin_variables = require("gdshader_nvim.data.builtin_variables")

local ast = require("gdshader_nvim.syntax.ast")

local AstKind = ast.Kind

local shader_types = require("gdshader_nvim.data.shader_types")

local token = require("gdshader_nvim.syntax.token")

local syntax_source = require("gdshader_nvim.syntax.source")

local context = require("gdshader_nvim.context")

local semantic_types = require("gdshader_nvim.semantic.types")

local inference = require("gdshader_nvim.semantic.inference")

------------------------------------------------------------
-- Lookup tables
------------------------------------------------------------

local knowledge = require("gdshader_nvim.data.knowledge")

------------------------------------------------------------
-- Lookup tables (rebuilt lazily when the knowledge changes)
------------------------------------------------------------

local shader_type_set = nil

local all_processor_names = nil

local builtin_param_map = nil

local built_version = -1

------------------------------------------------------------
-- 解析内置函数签名为参数类型表
--
-- signature 形如 "vec4 texture(sampler2D s, vec2 uv)" / "int floatBitsToInt(float x)"
-- / "T mix(T a, T b, T t)"。取首个 '(' 到匹配 ')' 之间的内容，按 depth-0 逗号切分，
-- 每段取首个空白前 token 作为类型，返回 { types = {...}, count = #types }；
-- 无法解析返回 nil。
------------------------------------------------------------

local function parse_signature_params(signature)
    if not signature then
        return nil
    end

    local open = signature:find("%(")

    if not open then
        return nil
    end

    local depth = 0
    local close = nil

    for j = open, #signature do
        local c = signature:sub(j, j)

        if c == "(" then
            depth = depth + 1
        elseif c == ")" then
            depth = depth - 1

            if depth == 0 then
                close = j

                break
            end
        end
    end

    if not close then
        return nil
    end

    local inner = signature:sub(open + 1, close - 1)
    local types = {}

    for part in inner:gmatch("[^,]+") do
        local trimmed = part:match("^%s*(.-)%s*$")

        if trimmed ~= "" then
            local t = trimmed:match("^%S+")

            table.insert(types, t)
        end
    end

    return { types = types, count = #types }
end

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

    builtin_param_map = {}

    for _, fn in ipairs(knowledge.get("builtin_functions") or {}) do
        builtin_param_map[fn.name] = parse_signature_params(fn.signature)
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
-- Delimiter balance (braces / parentheses / brackets)
--
-- Mirrors vscode "Mismatched braces/parentheses detection".
-- Comment / string tokens are skipped, so multi-line block
-- comments never distort the count.
------------------------------------------------------------

local openers = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local closers = { [")"] = "(", ["]"] = "[", ["}"] = "{" }

local function is_string_or_comment(tok)
    return tok.kind == "string" or token.is_comment(tok)
end

local function check_delimiters(result, bufnr)
    local ok, lexed = pcall(syntax_source.get_lexed, bufnr)

    if not ok then
        return
    end

    local tokens = lexed.tokens or {}

    local stack = {}

    for _, tok in ipairs(tokens) do
        if not is_string_or_comment(tok) then
            local v = tok.value

            if openers[v] then
                table.insert(stack, tok)
            elseif closers[v] then
                if #stack > 0 and stack[#stack].value == closers[v] then
                    table.remove(stack)
                else
                    add(result, token_range(tok), "error", "unmatched-delimiter", "Unmatched '" .. v .. "'.")
                end
            end
        end
    end

    for _, opener in ipairs(stack) do
        add(result, token_range(opener), "error", "unmatched-delimiter", "Unmatched '" .. opener.value .. "'.")
    end
end

------------------------------------------------------------
-- Missing semicolon
--
-- Mirrors vscode "Missing semicolon warnings". Skips the
-- closing ')' of if/for/while conditions to avoid flagging
-- brace-less control-flow bodies.
------------------------------------------------------------

local control_keywords = { ["if"] = true, ["for"] = true, ["while"] = true }

local function is_value_end(tok)
    if not tok then
        return false
    end

    if tok.kind == "identifier" or tok.kind == "number" or tok.kind == "int"
        or tok.kind == "float" or tok.kind == "uint" or tok.kind == "string" then
        return true
    end

    -- 注意：'}' 是块结束符，不代表"一个需要 ; 的值"。
    -- 若把 '}' 当作 value-end，会在函数/块的正常闭合处（如 remap 的 '}'）
    -- 误报 "Missing ';' at end of statement"，而 Godot / vscode 不会。
    -- '(' 同样不是值结尾，也不在此列。
    if tok.kind == "punctuation" and (tok.value == ")" or tok.value == "]") then
        return true
    end

    return false
end

local function is_continuation(tok)
    if not tok then
        return true
    end

    local v = tok.value

    -- '}' 结束一个块，并不是"当前语句的延续"：
    -- 它前面的语句若缺 ';'（例如块内最后一条语句没写分号），
    -- 应当照常被报出，而不是被 '}' 吞掉。Godot / vscode 亦然。
    -- '{' 仍保留：if/for/while 条件后的 '{' 是块开始，视作延续。
    if v == ";" or v == "," or v == "{" or v == ")" or v == "]" or v == "." or v == ":" then
        return true
    end

    if tok.kind == "operator" then
        return true
    end

    return false
end

local function check_missing_semicolons(result, bufnr)
    local ok, lexed = pcall(syntax_source.get_lexed, bufnr)

    if not ok then
        return
    end

    local tokens = lexed.tokens or {}

    --------------------------------------------------------
    -- 预处理器指令（#ifdef / #include / #define ...) 独占整行，
    -- 其后不需要 ';'。把这些行上的 token 全部排除，避免对
    --   #ifdef EXTRA
    -- 之类行误报 “Missing ';' at end of statement”。
    --------------------------------------------------------

    local pp_lines = {}

    for _, tok in ipairs(tokens) do
        if tok.kind == "preprocessor" then
            pp_lines[tok.line] = true
        end
    end

    --------------------------------------------------------
    -- Significant (non-comment, non-preprocessor-line) token indices.
    --------------------------------------------------------

    local sig = {}

    for i, tok in ipairs(tokens) do
        if not token.is_comment(tok) and not pp_lines[tok.line] then
            table.insert(sig, i)
        end
    end

    --------------------------------------------------------
    -- Mark the ')' that closes if/for/while conditions.
    --------------------------------------------------------

    local control_close = {}
    local paren_depth = 0
    local pending_control_depth = nil

    for _, idx in ipairs(sig) do
        local tok = tokens[idx]

        if tok.kind == "keyword" and control_keywords[tok.value] then
            pending_control_depth = paren_depth
        elseif tok.value == "(" and tok.kind == "punctuation" then
            paren_depth = paren_depth + 1
        elseif tok.value == ")" and tok.kind == "punctuation" then
            if pending_control_depth ~= nil and paren_depth == pending_control_depth + 1 then
                control_close[idx] = true

                pending_control_depth = nil
            end

            paren_depth = paren_depth - 1
        end
    end

    --------------------------------------------------------
    -- Detect value-ending tokens followed by a new statement.
    --------------------------------------------------------

    for k = 1, #sig do
        local idx = sig[k]
        local tok = tokens[idx]

        if is_value_end(tok) and not control_close[idx] then
            local next_idx = sig[k + 1]

            if next_idx then
                local next_tok = tokens[next_idx]

                if next_tok.line > tok.line and not is_continuation(next_tok) then
                    add(result, token_range(tok), "warning", "missing-semicolon", "Missing ';' at end of statement.")
                end
            end
        end
    end
end

------------------------------------------------------------
-- #include resolution diagnostics
--
-- Mirrors vscode diagnosticsProvider #include handling:
--   - redirection target missing  -> error
--   - res:// with no redirection  -> hint (unresolved)
--   - plain include missing file  -> error
------------------------------------------------------------

local function check_includes(result, bufnr)
    local filename = vim.api.nvim_buf_get_name(bufnr)

    if filename == "" then
        return
    end

    local source_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local ok, hints = pcall(require, "gdshader_nvim.syntax.hints")

    if not ok or not hints then
        return
    end

    local src = table.concat(source_lines, "\n")

    local scanned = hints.scan(src)

    local dir = vim.fs.dirname(filename)

    for _, inc in ipairs(scanned.includes or {}) do
        local line = inc.line or 0

        local line_len = math.max(1, #(source_lines[line + 1] or ""))

        if inc.redirectPath then
            local target = vim.fs.normalize(vim.fs.joinpath(dir, inc.redirectPath))

            if not vim.uv.fs_stat(target) then
                add(result, {
                    line = line, column = 0,
                    end_line = line, end_column = line_len,
                }, "error", "include-redirect-not-found",
                "Redirection target not found: " .. inc.redirectPath)
            end
        elseif inc.isResPath and not inc.isIgnored then
            add(result, {
                line = line, column = 0,
                end_line = line, end_column = line_len,
            }, "hint", "include-res-unresolved",
            "Unresolved res:// include '" .. inc.path .. "' (use #gdshader-hint-redirection to resolve).")
        elseif not inc.isIgnored then
            local target = vim.fs.normalize(vim.fs.joinpath(dir, inc.path))

            if not vim.uv.fs_stat(target) then
                add(result, {
                    line = line, column = 0,
                    end_line = line, end_column = line_len,
                }, "error", "include-not-found",
                "Include not found: " .. inc.path)
            end
        end
    end
end

------------------------------------------------------------
-- Duplicate declaration diagnostics
--
-- Mirrors vscode analyzer duplicate checks:
--   - function name duplicates
--   - global declaration (uniform/varying/variable/global) name duplicates
--   - parameter / local variable duplicates within the same scope
------------------------------------------------------------

local function add_at(result, line, column, name, severity, code, message)
    add(
        result,
        {
            line = math.max(0, (line or 1) - 1),
            column = column or 0,
            end_line = math.max(0, (line or 1) - 1),
            end_column = (column or 0) + #(name or ""),
        },
        severity,
        code,
        message
    )
end

local function check_duplicate_in_scope(result, scope)
    if not scope then
        return
    end

    local seen = {}

    for _, symbol in ipairs(scope.symbols or {}) do
        local name = symbol.name

        if name and not seen[name] then
            seen[name] = true
        else
            add_at(result, symbol.name_line or symbol.start_line or symbol.line,
                symbol.name_column or symbol.start_column or 0, name,
                "error", "duplicate-declaration",
                "Duplicate declaration of '" .. tostring(name) .. "'.")
        end
    end

    for _, child in ipairs(scope.children or {}) do
        check_duplicate_in_scope(result, child)
    end
end

local function check_duplicate_declarations(result, semantic_document)
    -- 1. Functions (skip hint-declared prototypes so they don't clash
    --    with a real definition, matching vscode's HintDefined handling).
    local fn_seen = {}

    for _, fn in ipairs(semantic_document.functions or {}) do
        if not fn.hint_declared then
            local name = fn.name

            if name and not fn_seen[name] then
                fn_seen[name] = true
            else
                add_at(result, fn.name_line, fn.name_column, name,
                    "error", "duplicate-function",
                    "Duplicate function '" .. tostring(name) .. "'.")
            end
        end
    end

    -- 2. Globals (uniform / varying / variable / global / hint-injected global)
    local g_seen = {}

    for _, g in ipairs(semantic_document.globals or {}) do
        if not g.hint_declared then
            local name = g.name

            if name and not g_seen[name] then
                g_seen[name] = true
            else
                add_at(result, g.name_line or g.line, g.name_column or g.start_column, name,
                    "error", "duplicate-declaration",
                    "Duplicate declaration of '" .. tostring(name) .. "'.")
            end
        end
    end

    -- 3. Parameters / locals (within each function's scope tree)
    for _, fn in ipairs(semantic_document.functions or {}) do
        check_duplicate_in_scope(result, fn.scope)
    end
end

------------------------------------------------------------
-- Parameter shadowing diagnostics
--
-- 对齐 vscode analyzer.analyzeVariableDecl 的 shadowParam 警告：
-- 函数体内声明的局部变量 / const 若与某个参数同名，则报 warning。
--
-- vscode 通过 lookupInEnclosingFunctionScope 从当前块父级向上
-- 找到第一个同名符号；若该符号是 Parameter 即告警。nvim 的函数
-- 作用域 fn.scope 的 symbols 即参数，其 children 为函数体各块
-- 作用域，逐层扫描即可。
------------------------------------------------------------

local function check_parameter_shadowing(result, semantic_document)
    for _, fn in ipairs(semantic_document.functions or {}) do
        local scope = fn.scope

        if not scope then
            goto continue
        end

        --------------------------------------------------------
        -- 本函数的参数名集合（函数作用域的 symbols 即参数）。
        --------------------------------------------------------

        local param_names = {}

        for _, sym in ipairs(scope.symbols or {}) do
            if sym.kind == "parameter" then
                param_names[sym.name] = true
            end
        end

        if not next(param_names) then
            goto continue
        end

        --------------------------------------------------------
        -- 递归扫描函数体各块作用域的局部声明。
        -- enclosing 为从“当前块父级”到函数作用域的链（不含当前块）。
        --------------------------------------------------------

        local function walk(blk, enclosing)
            for _, sym in ipairs(blk.symbols or {}) do
                if sym.kind == "variable" or sym.kind == "const" then
                    ----------------------------------------------------
                    -- 从最近的外层作用域向上找第一个同名符号。
                    ----------------------------------------------------

                    local shadowed = nil

                    for i = 1, #enclosing do
                        local enc = enclosing[i]

                        for _, esym in ipairs(enc.symbols or {}) do
                            if esym.name == sym.name then
                                shadowed = esym

                                break
                            end
                        end

                        if shadowed then
                            break
                        end
                    end

                    ----------------------------------------------------
                    -- 仅当被遮蔽的是参数时才告警（对齐 vscode）。
                    ----------------------------------------------------

                    if shadowed and shadowed.kind == "parameter" then
                        add_at(result, sym.name_line or sym.start_line,
                            sym.name_column or sym.start_column, sym.name,
                            "warning", "param-shadow",
                            "Variable '" .. tostring(sym.name) .. "' shadows a parameter with the same name.")
                    end
                end
            end

            for _, child in ipairs(blk.children or {}) do
                local new_enclosing = { blk }

                for _, e in ipairs(enclosing) do
                    table.insert(new_enclosing, e)
                end

                walk(child, new_enclosing)
            end
        end

        for _, child in ipairs(scope.children or {}) do
            walk(child, { scope })
        end

        ::continue::
    end
end

------------------------------------------------------------
-- Type mismatch (assignment / variable initialization)
--
-- 对齐 vscode analyzer：
--   - analyzeVariableDecl：声明初始化类型不符（declType vs initType）
--   - analyzeExpression(AssignExpr)：'=' 赋值语句左右类型不符
-- 两者共用严格的 isTypeCompatible（仅“完全相同”或含 void 才兼容）。
--
-- nvim 的词法器不把 if/while 体建成 AST，因此这里用**基于 token** 的
-- 扫描覆盖所有 '='（含 if/while 内的赋值），比只走函数体 AST 更完整。
------------------------------------------------------------

local function is_type_compatible(expected, actual)
    if expected == actual then
        return true
    end

    if expected == "void" or actual == "void" then
        return true
    end

    return false
end

------------------------------------------------------------
-- 在 '='（token 索引 eq_i）处把语句拆成左 / 右表达式文本
--
-- 语句边界：向后找到上一个 depth-0 的 ; { }，向前找到下一个
-- depth-0 的 ; }。深度用括号 / 方括号计数，避免跨进嵌套表达式。
------------------------------------------------------------

local function split_at_eq(tokens, eq_i)
    local dp = 0
    local db = 0
    local stmt_start = 0

    for i = eq_i - 1, 1, -1 do
        local v = tokens[i].value

        if v == ")" then
            dp = dp + 1
        elseif v == "(" then
            dp = dp - 1
        elseif v == "]" then
            db = db + 1
        elseif v == "[" then
            db = db - 1
        elseif (v == ";" or v == "{" or v == "}") and dp == 0 and db == 0 then
            stmt_start = i

            break
        end
    end

    dp = 0
    db = 0

    local stmt_end = #tokens + 1

    for i = eq_i + 1, #tokens do
        local v = tokens[i].value

        if v == ")" then
            dp = dp + 1
        elseif v == "(" then
            dp = dp - 1
        elseif v == "]" then
            db = db + 1
        elseif v == "[" then
            db = db - 1
        elseif (v == ";" or v == "}") and dp == 0 and db == 0 then
            stmt_end = i

            break
        end
    end

    local left = {}
    local right = {}

    for i = stmt_start + 1, eq_i - 1 do
        table.insert(left, tokens[i].value)
    end

    for i = eq_i + 1, stmt_end - 1 do
        table.insert(right, tokens[i].value)
    end

    local l = table.concat(left, " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    local r = table.concat(right, " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""

    return l, r
end

------------------------------------------------------------
-- 预计算：每个 token 之前的括号 / 方括号深度（用于判定 depth-0 的 '='）
------------------------------------------------------------

local function compute_depth(tokens)
    local pdepth = {}
    local dp = 0
    local db = 0

    for i, t in ipairs(tokens) do
        pdepth[i] = { dp, db }

        local v = t.value

        if v == "(" then
            dp = dp + 1
        elseif v == ")" then
            dp = dp - 1
        elseif v == "[" then
            db = db + 1
        elseif v == "]" then
            db = db - 1
        end
    end

    return pdepth
end

local function check_type_mismatches(result, bufnr, semantic_document)
    local ok, lexed = pcall(syntax_source.get_lexed, bufnr)

    if not ok then
        return
    end

    local tokens = lexed.tokens or {}

    if #tokens == 0 then
        return
    end

    local pdepth = compute_depth(tokens)

    --------------------------------------------------------
    -- 1) 收集声明（含初始化）的 '=' token 索引，避免被当作赋值语句重复检查。
    --    同时这些声明本身要做“初始化类型不符”检查。
    --------------------------------------------------------

    local decl_eq_indices = {}
    local decl_symbols = {}

    local function reg_decl(sym)
        if not sym or not sym.has_initializer then
            return
        end

        table.insert(decl_symbols, sym)
    end

    for _, g in ipairs(semantic_document.globals or {}) do
        reg_decl(g)
    end

    for _, fn in ipairs(semantic_document.functions or {}) do
        local scope = fn.scope

        if scope then
            local function walk(blk)
                for _, sym in ipairs(blk.symbols or {}) do
                    reg_decl(sym)
                end

                for _, child in ipairs(blk.children or {}) do
                    walk(child)
                end
            end

            walk(scope)
        end
    end

    --------------------------------------------------------
    -- 2) 声明初始化类型检查（对齐 vscode analyzeVariableDecl）
    --------------------------------------------------------

    for _, sym in ipairs(decl_symbols) do
        local lo_l = (sym.start_line or 1) - 1
        local hi_l = (sym.end_line or sym.start_line or 1) - 1

        local eq_i = nil
        local dp = 0
        local db = 0

        for i, t in ipairs(tokens) do
            local v = t.value

            if v == "(" then
                dp = dp + 1
            elseif v == ")" then
                dp = dp - 1
            elseif v == "[" then
                db = db + 1
            elseif v == "]" then
                db = db - 1
            elseif t.line >= lo_l and t.line <= hi_l and v == "=" and t.kind == "operator"
                and dp == 0 and db == 0 then
                eq_i = i

                break
            end
        end

        if not eq_i then
            goto continue_decl
        end

        decl_eq_indices[eq_i] = true

        local _, init_text = split_at_eq(tokens, eq_i)

        if init_text == "" then
            goto continue_decl
        end

        local decl_type = sym.type
        local cursor_line = sym.name_line or sym.start_line or 1
        local init_type = inference.infer_expression_type(bufnr, init_text, cursor_line)

        if decl_type and init_type and not is_type_compatible(decl_type, init_type) then
            add_at(result, sym.name_line or sym.start_line,
                sym.name_column or sym.start_column, sym.name,
                "error", "type-mismatch",
                "Type mismatch: cannot assign '" .. tostring(init_type) .. "' to '" .. tostring(decl_type) .. "'.")
        end

        ::continue_decl::
    end

    --------------------------------------------------------
    -- 3) 赋值语句类型检查（对齐 vscode analyzeExpression / AssignExpr）
    --    所有 depth-0 的 '='（且不属于声明初始化）都参与检查。
    --------------------------------------------------------

    for i, t in ipairs(tokens) do
        if t.kind == "operator" and t.value == "=" and pdepth[i][1] == 0 and pdepth[i][2] == 0 then
            if decl_eq_indices[i] then
                goto continue_assign
            end

            local left, right = split_at_eq(tokens, i)

            if left == "" or right == "" then
                goto continue_assign
            end

            local cursor_line = t.line + 1
            local left_type = inference.infer_expression_type(bufnr, left, cursor_line)
            local right_type = inference.infer_expression_type(bufnr, right, cursor_line)

            if left_type and right_type and not is_type_compatible(left_type, right_type) then
                add(result, token_range(t), "error", "type-mismatch",
                    "Type mismatch: cannot assign '" .. tostring(right_type) .. "' to '" .. tostring(left_type) .. "'.")
            end

            ::continue_assign::
        end
    end
end

------------------------------------------------------------
-- Function call argument count / type checking
--
-- 对齐 vscode analyzer.checkCallArgs：对用户函数 / #gdshader-hint-declare
-- 声明的函数，检查调用时的参数数量与逐参数类型（内置函数无 parameters，
-- 与 vscode 一致跳过）。内置构造器（vec3(...) 等）与结构体构造器也跳过。
--
-- nvim 词法器不把调用表达式建成 AST，故用 token 扫描：定位「标识符 + (」
-- 的调用点，抽取实参文本推断类型后比较。
------------------------------------------------------------

local function is_generic_type(type_name)
    if not type_name then
        return true
    end

    if type(type_name) ~= "string" then
        return true
    end

    if type_name:match("^[A-Z]$") then
        return true
    end

    if type_name == "genType" or type_name == "genIType" or type_name == "genUType"
        or type_name == "genBType" or type_name == "mat" or type_name == "vec"
        or type_name == "bvec" or type_name == "ivec" or type_name == "uvec"
        or type_name == "any" then
        return true
    end

    return false
end

------------------------------------------------------------
-- 抽取一对匹配括号之间的实参文本列表（按 depth-0 逗号切分）
------------------------------------------------------------

local function extract_args(tokens, open_i)
    local depth = 0
    local close_i = nil

    for j = open_i, #tokens do
        local v = tokens[j].value

        if v == "(" then
            depth = depth + 1
        elseif v == ")" then
            depth = depth - 1

            if depth == 0 then
                close_i = j

                break
            end
        end
    end

    if not close_i then
        return {}
    end

    local args = {}
    local cur = {}
    local cur_start = nil
    local dp = 0
    local db = 0

    for j = open_i + 1, close_i - 1 do
        local v = tokens[j].value

        if v == "(" then
            dp = dp + 1

            table.insert(cur, v)
        elseif v == ")" then
            dp = dp - 1

            table.insert(cur, v)
        elseif v == "[" then
            db = db + 1

            table.insert(cur, v)
        elseif v == "]" then
            db = db - 1

            table.insert(cur, v)
        elseif v == "," and dp == 0 and db == 0 then
            table.insert(args, {
                text = table.concat(cur):match("^%s*(.-)%s*$") or "",

                start_i = cur_start,

                end_i = j - 1,
            })

            cur = {}

            cur_start = nil
        else
            if cur_start == nil then
                cur_start = j
            end

            table.insert(cur, v)
        end
    end

    table.insert(args, {
        text = table.concat(cur):match("^%s*(.-)%s*$") or "",

        start_i = cur_start,

        end_i = close_i - 1,
    })

    return args
end

local function check_call_args(result, bufnr, semantic_document)
    ensure()

    local ok, lexed = pcall(syntax_source.get_lexed, bufnr)

    if not ok then
        return
    end

    local tokens = lexed.tokens or {}

    if #tokens == 0 then
        return
    end

    local callables = {}

    for _, fn in ipairs(semantic_document.functions or {}) do
        if fn.name and fn.parameters and not callables[fn.name] then
            callables[fn.name] = fn
        end
    end

    local struct_names = {}

    for _, st in ipairs(semantic_document.structs or {}) do
        if st.name then
            struct_names[st.name] = true
        end
    end

    local decl_starters = {
        ["const"] = true, ["uniform"] = true, ["varying"] = true,
        ["global"] = true, ["instance"] = true, ["in"] = true, ["out"] = true,
        ["inout"] = true, ["flat"] = true, ["smooth"] = true,
        ["lowp"] = true, ["mediump"] = true, ["highp"] = true,
    }

    for i, t in ipairs(tokens) do
        if t.value == "(" and t.kind == "punctuation" then
            local pred = tokens[i - 1]

            if not pred or pred.kind ~= "identifier" then
                goto continue_call
            end

            local before = tokens[i - 2]

            if before and before.value == "." then
                goto continue_call
            end

            if before and (before.kind == "type" or decl_starters[before.value]
                or struct_names[before.value]) then
                goto continue_call
            end

            local fn_name = pred.value

            if semantic_types.is_type(fn_name) or struct_names[fn_name] then
                goto continue_call
            end

            local args = extract_args(tokens, i)
            local arg_count = #args

            if arg_count == 1 and (args[1].text or "") == "" then
                arg_count = 0
            end

            -- 解析被调符号的参数表：优先用户函数，其次内置函数。
            -- 注意：vscode 的 checkCallArgs 对内置函数提前 return 不检查；
            -- 这里额外覆盖内置函数，使诊断比 vscode 更严格。
            local params = {}

            local fn = callables[fn_name]

            if fn and fn.parameters then
                for _, p in ipairs(fn.parameters) do
                    table.insert(params, { type = p.type, name = p.name })
                end
            else
                local binfo = builtin_param_map and builtin_param_map[fn_name]

                if not binfo then
                    goto continue_call
                end

                for _, t in ipairs(binfo.types) do
                    table.insert(params, { type = t })
                end
            end

            local param_count = #params

            if arg_count ~= param_count then
                add(result, token_range(pred), "error", "arg-count",
                    "Function '" .. fn_name .. "' expects " .. param_count .. " argument(s), but " .. arg_count .. " were provided.")

                goto continue_call
            end

            for p_i, param in ipairs(params) do
                local arg_entry = args[p_i] or {}
                local arg_text = arg_entry.text or ""

                if arg_text == "" then
                    goto continue_call
                end

                if is_generic_type(param.type) then
                else
                    local arg_type = inference.infer_expression_type(bufnr, arg_text, pred.line + 1)

                    if arg_type and not is_type_compatible(param.type, arg_type) then
                        local atok = arg_entry.start_i and tokens[arg_entry.start_i] or pred

                        add(result, token_range(atok), "error", "arg-type",
                            "Argument '" .. tostring(param.name or ("arg" .. p_i)) .. "' type mismatch: expected '" .. tostring(param.type) .. "', got '" .. tostring(arg_type) .. "'.")
                    end
                end
            end
        end

        ::continue_call::
    end
end

------------------------------------------------------------
-- Processor return diagnostics

------------------------------------------------------------
-- Processor return diagnostics
--
-- Mirrors vscode analyzer.checkReturnInBlock: void processor
-- functions (vertex / start / process / ...) must not contain a
-- `return` statement. `allow_return` defaults to false; a
-- processor can opt in by setting it to true in the data table.
------------------------------------------------------------

local function check_processor_returns(result, bufnr, semantic_document)
    local shader_type = semantic_document.shader_type

    if not shader_type then
        return
    end

    local valid = {}

    for _, p in ipairs(processors[shader_type] or {}) do
        valid[p.name] = p
    end

    local ok, lexed = pcall(syntax_source.get_lexed, bufnr)

    local tokens = (ok and lexed) and (lexed.tokens or {}) or {}

    for _, fn in ipairs(semantic_document.functions or {}) do
        local def = valid[fn.name]

        if def and def.allow_return ~= true then
            local lo = (fn.start_line or 1) - 1
            local hi = (fn.end_line or 1) - 1

            for _, tok in ipairs(tokens) do
                if tok.kind == "keyword" and tok.value == "return"
                    and tok.line >= lo and tok.line <= hi then
                    add(result, token_range(tok), "error", "return-in-processor",
                        "return is not allowed in processor function '" .. fn.name .. "'.")
                end
            end
        end
    end
end

------------------------------------------------------------
-- Build
------------------------------------------------------------

------------------------------------------------------------
-- Conditional compilation block pairing
--
-- Mirrors vscode analyzer.checkConditionalBlocks:
--   #ifdef / #ifndef / #if ... #elif / #else / #endif pairing.
------------------------------------------------------------

local conditional_directives = {
    ifdef = true,
    ifndef = true,
    ["if"] = true,
    elif = true,
    ["else"] = true,
    endif = true,
}

local function check_conditionals(result, bufnr)
    local source_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local stack = {}

    for idx, raw_line in ipairs(source_lines) do
        local line = raw_line:gsub("\r$", "")

        local directive = line:match("^%s*#%s*(%w+)")

        if directive and conditional_directives[directive] then
            local zero_line = idx - 1

            local hash_col = (line:find("#", 1, true) or 1) - 1

            if directive == "ifdef" or directive == "ifndef" or directive == "if" then
                table.insert(stack, { dir = directive, line = zero_line, column = hash_col, has_else = false })
            elseif directive == "elif" then
                if #stack == 0 then
                    add(result, { line = zero_line, column = hash_col, end_line = zero_line, end_column = hash_col + #directive },
                        "error", "cond-stray-elif", "#elif without matching #if")
                elseif stack[#stack].has_else then
                    add(result, { line = zero_line, column = hash_col, end_line = zero_line, end_column = hash_col + #directive },
                        "error", "cond-elif-after-else", "#elif after #else")
                end
            elseif directive == "else" then
                if #stack == 0 then
                    add(result, { line = zero_line, column = hash_col, end_line = zero_line, end_column = hash_col + #directive },
                        "error", "cond-stray-else", "#else without matching #if")
                elseif stack[#stack].has_else then
                    add(result, { line = zero_line, column = hash_col, end_line = zero_line, end_column = hash_col + #directive },
                        "error", "cond-duplicate-else", "duplicate #else")
                else
                    stack[#stack].has_else = true
                end
            elseif directive == "endif" then
                if #stack == 0 then
                    add(result, { line = zero_line, column = hash_col, end_line = zero_line, end_column = hash_col + #directive },
                        "error", "cond-stray-endif", "#endif without matching #if")
                else
                    table.remove(stack)
                end
            end
        end
    end

    for _, open in ipairs(stack) do
        add(result, { line = open.line, column = open.column, end_line = open.line, end_column = open.column + #open.dir },
            "error", "cond-unclosed", "unclosed #" .. open.dir)
    end
end

------------------------------------------------------------
-- Undefined identifier
--
-- 对齐 vscode analyzer.analyzeExpression 的 undefinedIdent 检查：
-- 函数体内出现的标识符引用若在当前作用域 / 内置 / 用户函数 /
-- 结构体 / 类型构造函数中都无法解析，则报 warning。
--
-- 与 vscode 一致：存在未 ignored 的 res:// include 时禁用本检查
-- （可能来自 include，无法在本文件内解析）。
------------------------------------------------------------

local function check_undefined_identifiers(result, bufnr, semantic_document)
    --------------------------------------------------------
    -- shader_type 缺失或非法时，内置变量无法可靠解析，跳过本检查。
    -- （对齐 vscode：vscode 缺失时默认 spatial；这里保守地不在类型
    --  不明确时报 undefined，避免误伤“缺失/非法 shader_type”的样例，
    --  保持 fixtures 期望稳定。）
    --------------------------------------------------------

    ensure()

    local st = semantic_document.shader_type

    if not (st and shader_type_set[st]) then
        return
    end

    --------------------------------------------------------
    -- 未解析的 res:// include 时，跳过（对齐 vscode suppressUndefinedCheck）。
    --------------------------------------------------------

    local ok_hints, hints = pcall(require, "gdshader_nvim.syntax.hints")

    if ok_hints and hints then
        local src_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

        local scanned = hints.scan(table.concat(src_lines, "\n"))

        if scanned.hasUnresolvedResIncludes then
            return
        end
    end

    --------------------------------------------------------
    -- 词法 token（用于抽取函数体内的标识符引用）。
    --------------------------------------------------------

    local ok, lexed = pcall(syntax_source.get_lexed, bufnr)

    if not ok then
        return
    end

    local tokens = lexed.tokens or {}

    --------------------------------------------------------
    -- 本文件结构体名（构造函数 MyStruct(...) 不算 undefined）。
    --------------------------------------------------------

    local struct_names = {}

    for _, s in ipairs(semantic_document.structs or {}) do
        if s.name then
            struct_names[s.name] = true
        end
    end

    --------------------------------------------------------
    -- 内置函数名（texture / clamp / sin ... 不算 undefined）。
    --------------------------------------------------------

    local builtin_function_names = {}

    for _, fn in ipairs(knowledge.get("builtin_functions") or {}) do
        builtin_function_names[fn.name] = true
    end

    --------------------------------------------------------
    -- 跳过声明名（函数名 / 结构体名）：它们是“定义”而非“引用”，
    -- 且不在任何变量作用域内，会被误判为 undefined。
    --------------------------------------------------------

    local skip_positions = {}

    for _, fn in ipairs(semantic_document.functions or {}) do
        if fn.name_line and fn.name_column then
            -- name_line 为 1-based，name_column 为 0-based（与 token 一致）。
            skip_positions[(fn.name_line - 1) .. ":" .. fn.name_column] = true
        end
    end

    for _, s in ipairs(semantic_document.structs or {}) do
        if s.name_line and s.name_column then
            skip_positions[(s.name_line - 1) .. ":" .. s.name_column] = true
        end
    end

    local function is_resolved(name, line)
        ----------------------------------------------------
        -- 类型 / 结构体 / 内置函数：直接解析。
        ----------------------------------------------------

        if semantic_types.is_type(name) then
            return true
        end

        if struct_names[name] then
            return true
        end

        if builtin_function_names[name] then
            return true
        end

        ----------------------------------------------------
        -- 用户符号（local / param / global）/ 内置变量 / 用户函数。
        ----------------------------------------------------

        if context.get_user_symbol(bufnr, name, line) then
            return true
        end

        if context.get_builtin_variable(bufnr, name, line) then
            return true
        end

        if #context.get_user_functions_by_name(bufnr, name) > 0 then
            return true
        end

        return false
    end

    --------------------------------------------------------
    -- 仅在各函数体行范围内扫描标识符引用。
    --------------------------------------------------------

    for _, fn in ipairs(semantic_document.functions or {}) do
        local lo = (fn.start_line or 1) - 1
        local hi = (fn.end_line or 1) - 1

        if hi >= lo then
            for i, tok in ipairs(tokens) do
                if tok.line >= lo and tok.line <= hi and tok.kind == "identifier"
                    and not skip_positions[tok.line .. ":" .. tok.column] then
                    ----------------------------------------------------
                    -- 跳过成员访问 a.b / a.b.c 中的 b、c
                    -- （其前一个是 '.' 标点）。
                    ----------------------------------------------------

                    local prev = nil

                    for j = i - 1, 1, -1 do
                        local t = tokens[j]

                        if not token.is_comment(t) then
                            prev = t

                            break
                        end
                    end

                    if prev and prev.kind == "punctuation" and prev.value == "." then
                        -- 成员 / swizzle，非自由引用
                    else
                        local name = tok.value

                        if not is_resolved(name, tok.line + 1) then
                            add(
                                result,
                                token_range(tok),
                                "warning",
                                "undefined-identifier",
                                "Undefined identifier '" .. name .. "'."
                            )
                        end
                    end
                end
            end
        end
    end
end

local function build(bufnr)
    local semantic_document = document.get(bufnr)

    local result = {}

    add_syntax_diagnostics(result, semantic_document)

    check_shader_type(result, bufnr, semantic_document)

    check_processors(result, semantic_document)

    check_discard_usage(result, semantic_document)

    check_builtin_writes(result, semantic_document)

    check_delimiters(result, bufnr)

    check_missing_semicolons(result, bufnr)

    -- vscode-parity diagnostics
    check_includes(result, bufnr)

    check_duplicate_declarations(result, semantic_document)

    check_parameter_shadowing(result, semantic_document)

    check_type_mismatches(result, bufnr, semantic_document)

    check_call_args(result, bufnr, semantic_document)

    check_processor_returns(result, bufnr, semantic_document)

    check_conditionals(result, bufnr)

    check_undefined_identifiers(result, bufnr, semantic_document)

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
