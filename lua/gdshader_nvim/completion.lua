local source = {}

------------------------------------------------------------
-- Dependencies
------------------------------------------------------------

local ok_blink, blink_types = pcall(require, "blink.cmp.types")

local kinds = (ok_blink and blink_types.CompletionItemKind) or vim.lsp.protocol.CompletionItemKind

local diagnostics = require("gdshader_nvim.diagnostics")
local types = require("gdshader_nvim.data.types")

local uniform_hints = require("gdshader_nvim.data.uniform_hints")

local context = require("gdshader_nvim.context")
local render_modes = require("gdshader_nvim.data.render_modes")
local swizzles = require("gdshader_nvim.data.swizzles")
local builtin_functions = require("gdshader_nvim.data.builtin_functions")
local processors = require("gdshader_nvim.data.processors")

local inference = require("gdshader_nvim.semantic.inference")
local semantic_types = require("gdshader_nvim.semantic.types")
local shader_type_names = require("gdshader_nvim.data.shader_types")
local hover = require("gdshader_nvim.hover")
local definition = require("gdshader_nvim.definition")

local references = require("gdshader_nvim.references")

local rename = require("gdshader_nvim.rename")

local document = require("gdshader_nvim.semantic.document")

------------------------------------------------------------
-- Static data
------------------------------------------------------------

local shader_types = {}

for _, name in ipairs(shader_type_names) do
    table.insert(shader_types, {
        label = name,

        kind = kinds.Keyword,

        detail = "GDShader shader type",
    })
end

local general_items = {
    --------------------------------------------------------
    -- Keywords (full set, mirrors vscode keywords.ts)
    --------------------------------------------------------

    {
        label = "void",
        kind = kinds.Keyword,
        detail = "GDShader function return type",
    },

    { label = "shader_type", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "render_mode", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "uniform", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "varying", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "const", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "struct", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "group_uniforms", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "global", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "instance", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "flat", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "smooth", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "in", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "out", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "inout", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "lowp", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "mediump", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "highp", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "if", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "else", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "for", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "while", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "do", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "switch", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "case", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "default", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "break", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "continue", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "return", kind = kinds.Keyword, detail = "GDShader keyword" },
    { label = "discard", kind = kinds.Keyword, detail = "GDShader keyword" },

    --------------------------------------------------------
    -- Constants
    --------------------------------------------------------

    { label = "true", kind = kinds.Constant, detail = "GDShader constant" },
    { label = "false", kind = kinds.Constant, detail = "GDShader constant" },
    { label = "PI", kind = kinds.Constant, detail = "Pi constant" },
    { label = "TAU", kind = kinds.Constant, detail = "Tau constant" },
    { label = "E", kind = kinds.Constant, detail = "Euler's number" },
    { label = "INF", kind = kinds.Constant, detail = "Infinity constant" },
    { label = "NAN", kind = kinds.Constant, detail = "Not-a-number constant" },
}

------------------------------------------------------------
-- Item builders
------------------------------------------------------------

local function make_user_symbol_items(bufnr, cursor_line)
    local items = {}

    local symbols = context.get_user_symbols(bufnr, cursor_line)

    for _, symbol in ipairs(symbols) do
        local kind = kinds.Variable

        if symbol.kind == "const" then
            kind = kinds.Constant
        end

        local detail = symbol.type .. " · GDShader " .. symbol.kind

        if symbol.mode then
            detail = symbol.mode .. " " .. detail
        end

        table.insert(items, {
            label = symbol.name,

            kind = kind,

            detail = detail,
        })
    end

    return items
end

local function make_user_function_items(bufnr)
    local items = {}

    local functions = context.get_user_functions(bufnr)

    for _, fn in ipairs(functions) do
        local placeholders = {}

        ----------------------------------------------------
        -- 根据参数自动生成 snippet
        ----------------------------------------------------

        for index, parameter in ipairs(fn.parameters) do
            table.insert(placeholders, "${" .. index .. ":" .. parameter.name .. "}")
        end

        local insert_text = fn.name .. "(" .. table.concat(placeholders, ", ") .. ")"

        local signature = context.get_function_signature(fn)

        table.insert(items, {
            label = fn.name,

            kind = kinds.Function,

            detail = signature .. " · user function",

            documentation = {
                kind = "markdown",

                value = "```gdshader\n" .. signature .. "\n```",
            },

            insertText = insert_text,

            insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
        })
    end

    return items
end

local function make_uniform_hint_items(uniform_type)
    local items = {}

    for _, hint in ipairs(uniform_hints) do
        ----------------------------------------------------
        -- 只显示适用于当前类型的 hint。
        -- `["*"] = true` 表示适用于所有类型。
        ----------------------------------------------------

        if hint.types[uniform_type] or hint.types["*"] then
            table.insert(items, {
                label = hint.name,

                kind = kinds.EnumMember,

                detail = "GDShader uniform hint · " .. uniform_type,

                documentation = hint.description and {
                    kind = "markdown",
                    value = hint.description,
                } or nil,

                insertText = hint.snippet or hint.name,

                insertTextFormat = hint.snippet and vim.lsp.protocol.InsertTextFormat.Snippet
                    or vim.lsp.protocol.InsertTextFormat.PlainText,
            })
        end
    end

    return items
end

local function make_type_items(bufnr)
    local items = {}

    for _, type_name in ipairs(types) do
        table.insert(items, {
            label = type_name,

            kind = kinds.TypeParameter,

            detail = "GDShader type",
        })
    end

    --------------------------------------------------------
    -- User-defined struct types (declared in the buffer).
    --------------------------------------------------------

    if bufnr then
        for _, struct in ipairs(document.get_structs(bufnr) or {}) do
            table.insert(items, {
                label = struct.name,

                kind = kinds.Struct,

                detail = "GDShader struct",
            })
        end
    end

    return items
end

------------------------------------------------------------
-- #gdshader-hint-(declare|def): type completion
--
-- Mirrors VS Code: `void` is not a valid hint-declare type, and
-- the suggested types are offered as plain labels.
------------------------------------------------------------

local function make_hint_declare_type_items(bufnr)
    local items = {}

    for _, type_name in ipairs(types) do
        if type_name ~= "void" then
            table.insert(items, {
                label = type_name,

                kind = kinds.TypeParameter,

                detail = "GDShader type",
            })
        end
    end

    for _, struct in ipairs(document.get_structs(bufnr or 0) or {}) do
        table.insert(items, {
            label = struct.name,

            kind = kinds.Struct,

            detail = "GDShader struct",
        })
    end

    return items
end

------------------------------------------------------------
-- Struct member completion
--
-- obj.<cursor>  ->  members of the struct that `obj` has.
------------------------------------------------------------

local function make_struct_member_items(bufnr, type_name)
    local items = {}

    local members = semantic_types.get_struct_members(bufnr, type_name)

    if not members then
        return items
    end

    for _, member in ipairs(members) do
        table.insert(items, {
            label = member.name,

            kind = kinds.Field,

            detail = (member.type or "?" ) .. (member.is_array and "[]" or "") .. " · struct member",
        })
    end

    return items
end

local function make_builtin_function_items(processor)
    local items = {}

    for _, fn in ipairs(builtin_functions) do
        ----------------------------------------------------
        -- 上下文受限的内置函数
        -- (如 dFdx 仅 fragment, emit_subparticle 仅粒子)
        -- 不在当前 processor 时跳过。
        ----------------------------------------------------

        local skip = false

        if fn.context then
            local allowed = false

            for _, ctx in ipairs(fn.context) do
                if ctx == processor then
                    allowed = true

                    break
                end
            end

            if not allowed then
                skip = true
            end
        end

        if not skip then
            local documentation = "```gdshader\n" .. fn.signature .. "\n```"

            if fn.description then
                documentation = documentation .. "\n\n" .. fn.description
            end

            table.insert(items, {
                label = fn.name,

                -- 它本质上是函数，
                -- 即使 insertText 使用 snippet。
                kind = kinds.Function,

                detail = fn.signature,

                documentation = {
                    kind = "markdown",
                    value = documentation,
                },

                insertText = fn.snippet,

                insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
            })
        end
    end

    return items
end

local processor_examples = {
    spatial = {
        vertex = 'void vertex() {\n\t// VERTEX.y += sin(TIME) * 0.1;\n\t// UV = UV * 2.0;\n\t$0\n}',
        fragment = 'void fragment() {\n\t// ALBEDO = vec3(1.0);\n\t// ROUGHNESS = 0.5;\n\t// METALLIC = 0.0;\n\t$0\n}',
        light = 'void light() {\n\t// float NdotL = max(dot(NORMAL, LIGHT), 0.0);\n\t// DIFFUSE_LIGHT += LIGHT_COLOR * NdotL * ATTENUATION;\n\t$0\n}',
    },
    canvas_item = {
        vertex = 'void vertex() {\n\t// VERTEX += vec2(sin(TIME), 0.0);\n\t$0\n}',
        fragment = 'void fragment() {\n\t// vec4 tex = texture(TEXTURE, UV);\n\t// COLOR = tex;\n\t$0\n}',
        light = 'void light() {\n\t// LIGHT = vec4(LIGHT_COLOR.rgb * LIGHT_ENERGY, 1.0);\n\t$0\n}',
    },
    particles = {
        start = 'void start() {\n\t// VELOCITY = vec3(0.0, 1.0, 0.0);\n\t// COLOR = vec4(1.0);\n\t$0\n}',
        process = 'void process() {\n\t// VELOCITY.y -= 9.8 * DELTA;\n\t// COLOR.a -= DELTA / LIFETIME;\n\t$0\n}',
    },
    sky = {
        sky = 'void sky() {\n\t// COLOR = mix(vec3(0.1), vec3(0.3, 0.5, 1.0), clamp(EYEDIR.y, 0.0, 1.0));\n\t$0\n}',
    },
    fog = {
        fog = 'void fog() {\n\t// DENSITY = 1.0;\n\t// ALBEDO = vec3(0.8);\n\t// EMISSION = vec3(0.0);\n\t$0\n}',
    },
}

local function make_processor_snippet_items(shader_type)
    local items = {}

    local shader_processors = processors[shader_type] or {}

    for _, processor in ipairs(shader_processors) do
        local snippet = (processor_examples[shader_type] and processor_examples[shader_type][processor.name])
            or ("void " .. processor.name .. "() {\n\t${1}\n}")

        table.insert(items, {
            label = processor.name,

            kind = kinds.Snippet,

            detail = processor.detail,

            insertText = snippet,

            insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
        })
    end

    return items
end

local function make_processor_items(shader_type)
    local items = {}

    local shader_processors = processors[shader_type] or {}

    for _, processor in ipairs(shader_processors) do
        table.insert(items, {
            label = processor.name,

            kind = kinds.Function,

            detail = processor.detail,

            insertText = processor.name .. "() {\n\t${1}\n}",

            insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
        })
    end

    return items
end

local function make_render_mode_items(shader_type)
    local items = {}

    local modes = render_modes[shader_type] or {}

    for _, name in ipairs(modes) do
        table.insert(items, {
            label = name,
            kind = kinds.EnumMember,

            detail = "GDShader " .. shader_type .. " render mode",
        })
    end

    return items
end

local function make_swizzle_items(vector_size, type_name)
    local items = {}

    for _, name in ipairs(swizzles.for_size(vector_size)) do
        table.insert(items, {
            label = name,
            kind = kinds.Field,

            detail = type_name .. " swizzle",
        })
    end

    return items
end

------------------------------------------------------------
-- #include / #gdshader-hint-redirection path completion
--
-- 列出当前文件所在目录（相对 ./ ../ 以及 res://）下的
-- .gdshader / .gdshaderinc 文件与子目录。
------------------------------------------------------------

local function make_include_path_items(bufnr, before_cursor, cursor_line, col)
    local partial = before_cursor:match('#include%s+"([^"]*)$')
        or before_cursor:match("#gdshader%-hint%-redirection%s*:%s*(%S*)$")

    if partial == nil then
        return {}
    end

    --------------------------------------------------------
    -- 仅替换已输入的部分路径（保留 ./ ../ 前缀）。
    --------------------------------------------------------

    local range = {
        start = { line = cursor_line - 1, character = col - #partial },
        ["end"] = { line = cursor_line - 1, character = col },
    }

    local filename = vim.api.nvim_buf_get_name(bufnr)

    if filename == "" then
        return {}
    end

    local base_dir = vim.fs.dirname(filename)

    if not base_dir then
        return {}
    end

    local last_slash = partial:find("/[^/]*$")
    local dir_part = last_slash and partial:sub(1, last_slash) or ""

    local target_dir = dir_part ~= "" and vim.fs.normalize(vim.fs.joinpath(base_dir, dir_part)) or base_dir

    local ok, entries = pcall(vim.fn.readdir, target_dir)

    if not ok or not entries then
        return {}
    end

    local items = {}

    for _, entry in ipairs(entries) do
        local full = dir_part .. entry

        if vim.fn.isdirectory(vim.fs.joinpath(target_dir, entry)) == 1 then
            table.insert(items, {
                label = entry,

                kind = kinds.Folder,

                detail = "GDShader include directory",

                insertText = full .. "/",

                insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,

                range = range,
            })
        elseif entry:match("%.gdshaderinc$") or entry:match("%.gdshader$") then
            table.insert(items, {
                label = entry,

                kind = kinds.File,

                detail = "GDShader include file",

                insertText = full,

                insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,

                range = range,
            })
        end
    end

    return items
end

------------------------------------------------------------
-- #gdshader-hint-* comment completion
------------------------------------------------------------

local function make_hint_comment_items(before_cursor, cursor_line, col)
    local s, e = before_cursor:find("#gdshader%-hint%-%w*$")

    local range = nil

    if s then
        range = {
            start = { line = cursor_line - 1, character = s - 1 },
            ["end"] = { line = cursor_line - 1, character = e },
        }
    end

    local hints = {
        { label = "#gdshader-hint-ignore", snippet = "#gdshader-hint-ignore" },
        { label = "#gdshader-hint-declare:", snippet = "#gdshader-hint-declare:${1:type} ${2:name}" },
        { label = "#gdshader-hint-define:", snippet = "#gdshader-hint-define:${1:NAME}" },
        { label = "#gdshader-hint-type:", snippet = "#gdshader-hint-type:${1:type}" },
        { label = "#gdshader-hint-redirection:", snippet = "#gdshader-hint-redirection:${1:./path}" },
    }

    local items = {}

    for _, h in ipairs(hints) do
        local item = {
            label = h.label,

            kind = kinds.Snippet,

            detail = "GDShader hint comment",

            insertText = h.snippet,

            insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
        }

        if range then
            item.range = range
        end

        table.insert(items, item)
    end

    return items
end

------------------------------------------------------------
-- Preprocessor directive completion (#include / #define / ...)
------------------------------------------------------------

local function make_preprocessor_items(before_cursor, cursor_line, col)
    local s, e = before_cursor:find("#%w*$")

    local range = nil

    if s then
        range = {
            start = { line = cursor_line - 1, character = s - 1 },
            ["end"] = { line = cursor_line - 1, character = e },
        }
    end

    local directives = {
        { name = "#include", snippet = '#include "${1:path}"' },
        { name = "#define", snippet = "#define ${1:NAME} ${2:value}" },
        { name = "#ifdef", snippet = "#ifdef ${1:NAME}" },
        { name = "#ifndef", snippet = "#ifndef ${1:NAME}" },
        { name = "#if", snippet = "#if ${1:condition}" },
        { name = "#elif", snippet = "#elif ${1:condition}" },
        { name = "#else", snippet = "#else" },
        { name = "#endif", snippet = "#endif" },
        { name = "#undef", snippet = "#undef ${1:NAME}" },
    }

    local items = {}

    for _, d in ipairs(directives) do
        local item = {
            label = d.name,

            kind = kinds.Keyword,

            detail = "GDShader preprocessor",

            insertText = d.snippet,

            insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
        }

        if range then
            item.range = range
        end

        table.insert(items, item)
    end

    return items
end

local function make_builtin_variable_items(bufnr, cursor_line)
    local items = {}

    local variables = context.get_builtin_variables(bufnr, cursor_line)

    for _, variable in ipairs(variables) do
        local detail = variable.mode .. " " .. variable.type .. " · GDShader built-in"

        local documentation = nil

        if variable.detail then
            documentation = {
                kind = "markdown",
                value = "```gdshader\n"
                    .. variable.mode
                    .. " "
                    .. variable.type
                    .. " "
                    .. variable.name
                    .. "\n```\n\n"
                    .. variable.detail,
            }
        end

        table.insert(items, {
            label = variable.name,

            kind = kinds.Variable,

            detail = detail,

            documentation = documentation,
        })
    end

    return items
end

local function make_context_items(ctx, cursor_line)
    local items = vim.deepcopy(general_items)

    --------------------------------------------------------
    -- Current shader: symbols
    --------------------------------------------------------

    vim.list_extend(items, make_user_symbol_items(ctx.bufnr, cursor_line))

    --------------------------------------------------------
    -- Current shader: functions
    --------------------------------------------------------

    vim.list_extend(items, make_user_function_items(ctx.bufnr))

    --------------------------------------------------------
    -- Godot built-in variables
    --------------------------------------------------------

    vim.list_extend(items, make_builtin_variable_items(ctx.bufnr, cursor_line))

    --------------------------------------------------------
    -- Godot built-in functions
    -- (按当前 processor 过滤上下文受限函数)
    --------------------------------------------------------

    local processor = context.get_processor(ctx.bufnr, cursor_line)

    vim.list_extend(items, make_builtin_function_items(processor))

    --------------------------------------------------------
    -- Processor snippets
    --------------------------------------------------------

    local shader_type = context.get_shader_type(ctx.bufnr)

    vim.list_extend(items, make_processor_snippet_items(shader_type))

    --------------------------------------------------------
    -- Types
    --------------------------------------------------------

    vim.list_extend(items, make_type_items(ctx.bufnr))

    return items
end

------------------------------------------------------------
-- Blink source
------------------------------------------------------------

function source.new()
    --------------------------------------------------------
    -- Ensure the plugin (and its standalone features) are booted.
    -- Booting is idempotent.
    --------------------------------------------------------

    require("gdshader_nvim").ensure_setup()

    return setmetatable({}, {
        __index = source,
    })
end

------------------------------------------------------------
-- Enabled
------------------------------------------------------------

function source:enabled()
    local config = require("gdshader_nvim.config").get()

    local ft = vim.bo.filetype

    for _, supported in ipairs(config.filetypes) do
        if ft == supported then
            return true
        end
    end

    return false
end

------------------------------------------------------------
-- Trigger characters
------------------------------------------------------------

function source:get_trigger_characters()
    local config = require("gdshader_nvim.config").get()

    return config.completion.trigger_characters
end

------------------------------------------------------------
-- Completion
------------------------------------------------------------

function source:get_completions(ctx, callback)
    --------------------------------------------------------
    -- Cursor context
    --------------------------------------------------------

    local line = vim.api.nvim_get_current_line()

    local cursor = vim.api.nvim_win_get_cursor(0)

    local cursor_line = cursor[1]

    -- column 是 0-based
    local col = cursor[2]

    local before_cursor = line:sub(1, col)

    local items = {}

    --------------------------------------------------------
    -- #include / #gdshader-hint-redirection path completion
    --------------------------------------------------------

    if before_cursor:match('^#include%s+"([^"]*)$')
        or before_cursor:match("#gdshader%-hint%-redirection%s*:%s*(%S*)$") then
        items = make_include_path_items(ctx.bufnr, before_cursor, cursor_line, col)

    --------------------------------------------------------
    -- #gdshader-hint-* comment completion
    --------------------------------------------------------

    elseif before_cursor:match("//%s*#gdshader%-hint%-%w*$")
        or before_cursor:match("/%*%s*#gdshader%-hint%-%w*$") then
        items = make_hint_comment_items(before_cursor, cursor_line, col)

    --------------------------------------------------------
    -- #gdshader-hint-(declare|def): type completion
    --------------------------------------------------------

    elseif before_cursor:match("//%s*#gdshader%-hint%-(declare|def)%s*:%s*%w*$") then
        items = make_hint_declare_type_items(ctx.bufnr)

    --------------------------------------------------------
    -- # preprocessor directive completion (#include / #define / #if / ...)
    --------------------------------------------------------

    elseif before_cursor:match("^%s*#%w*$") then
        items = make_preprocessor_items(before_cursor, cursor_line, col)

    --------------------------------------------------------
    -- shader_type
    --------------------------------------------------------

    elseif before_cursor:match("shader_type%s+[%w_]*$") then
        items = shader_types

    --------------------------------------------------------
    -- render_mode
    --------------------------------------------------------
    elseif before_cursor:match("render_mode%s+[%w_,%s]*$") then
        local shader_type = context.get_shader_type(ctx.bufnr)

        if shader_type then
            items = make_render_mode_items(shader_type)
        end

    --------------------------------------------------------
    -- processor function
    --------------------------------------------------------
    elseif before_cursor:match("void%s+[%w_]*$") then
        local shader_type = context.get_shader_type(ctx.bufnr)

        items = make_processor_items(shader_type)

    --------------------------------------------------------
    -- Member / Swizzle
    --------------------------------------------------------
    elseif inference.is_member_completion_context(before_cursor) then
        local expression = inference.get_expression_before_dot(before_cursor)

        local type_name = nil

        if expression then
            type_name = inference.infer_expression_type(ctx.bufnr, expression, cursor_line)
        end

        if type_name then
            --------------------------------------------------------
            -- Struct member completion (obj.field)
            --------------------------------------------------------

            if semantic_types.is_struct(ctx.bufnr, type_name) then
                items = make_struct_member_items(ctx.bufnr, type_name)
            else
                local vector_size = semantic_types.get_vector_size(type_name)
                if vector_size then
                    items = make_swizzle_items(vector_size, type_name)
                end
            end
        end

    --------------------------------------------------------
    -- uniform type
    --------------------------------------------------------
    elseif before_cursor:match("uniform%s+[%w_]*$")
        or before_cursor:match("varying%s+[%w_]*$")
        or before_cursor:match("const%s+[%w_]*$") then
        items = make_type_items(ctx.bufnr)

    --------------------------------------------------------
    -- uniform hint
    --------------------------------------------------------
    elseif before_cursor:match('uniform%s+.-:%s*[%w_,()%s"%.%-]*$') then
        local uniform_type = context.get_uniform_type_before_cursor(before_cursor)

        if uniform_type then
            items = make_uniform_hint_items(uniform_type)
        end

    --------------------------------------------------------
    -- General + context-aware built-ins
    --------------------------------------------------------
    else
        items = make_context_items(ctx, cursor_line)
    end

    --------------------------------------------------------
    -- Return
    --------------------------------------------------------

    callback({
        items = items,

        is_incomplete_forward = false,
        is_incomplete_backward = false,
    })
end

return source
