local M = {}

local symbol_at = require("gdshader_nvim.semantic.symbol_at")

local context = require("gdshader_nvim.context")

local util = require("gdshader_nvim.util")

local configured = false

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function code_block(text)
    return {
        "```gdshader",
        text,
        "```",
    }
end

local function append(target, values)
    for _, value in ipairs(values) do
        table.insert(target, value)
    end
end

local function blank(lines)
    if #lines > 0 and lines[#lines] ~= "" then
        table.insert(lines, "")
    end
end

local function sorted_type_names(types)
    local result = {}

    for name, enabled in pairs(types or {}) do
        if enabled then
            table.insert(result, name)
        end
    end

    table.sort(result)

    return result
end

------------------------------------------------------------
-- User symbol
------------------------------------------------------------

local function user_symbol_lines(symbol)
    local lines = {}

    local prefix = ""

    if symbol.kind == "uniform" then
        prefix = "uniform "

        if symbol.modifier then
            prefix = symbol.modifier .. " " .. prefix
        end
    elseif symbol.kind == "varying" then
        prefix = "varying "
    elseif symbol.kind == "const" then
        prefix = "const "
    elseif symbol.kind == "parameter" and symbol.mode then
        prefix = symbol.mode .. " "
    end

    local suffix = symbol.is_array and "[]" or ""

    append(lines, code_block(prefix .. (symbol.type or "?") .. " " .. symbol.name .. suffix))

    if symbol.start_line or symbol.line then
        blank(lines)

        table.insert(lines, "Declared at line " .. tostring(symbol.start_line or symbol.line) .. ".")
    end

    return lines
end

------------------------------------------------------------
-- User function
------------------------------------------------------------

local function user_function_lines(functions)
    local lines = {}

    for index, fn in ipairs(functions) do
        if index > 1 then
            blank(lines)
        end

        append(lines, code_block(context.get_function_signature(fn)))

        --------------------------------------------------------
        -- Doc comment (`///` / `/** */`)
        --------------------------------------------------------

        if fn.doc and fn.doc ~= "" then
            blank(lines)

            for _, doc_line in ipairs(vim.split(fn.doc, "\n", { plain = true })) do
                --------------------------------------------------------
                -- 加粗 @param / @return / @brief 等标签，
                -- 与 VSCode 的文档注释渲染对齐。
                --------------------------------------------------------

                table.insert(lines, doc_line:gsub("@(%w+)", "**@%1**"))
            end
        end

        if fn.start_line then
            blank(lines)

            table.insert(lines, "Declared at line " .. tostring(fn.start_line) .. ".")
        end
    end

    return lines
end

------------------------------------------------------------
-- Built-in variable
------------------------------------------------------------

local function builtin_variable_lines(info)
    local variable = info.variable

    local lines = {}

    append(lines, code_block((variable.mode or "in") .. " " .. (variable.type or "?") .. " " .. variable.name))

    if variable.detail and variable.detail ~= "" then
        blank(lines)

        table.insert(lines, variable.detail)
    end

    if info.available == false then
        blank(lines)

        local processors = table.concat(info.available_in or {}, ", ")

        if processors ~= "" then
            table.insert(lines, "**Not available in the current processor.**")

            table.insert(lines, "")

            table.insert(lines, "Available in: `" .. processors .. "`.")
        end
    end

    return lines
end

------------------------------------------------------------
-- Built-in function
------------------------------------------------------------

local function builtin_function_lines(functions)
    local lines = {}

    for index, fn in ipairs(functions) do
        if index > 1 then
            blank(lines)
        end

        append(lines, code_block(fn.signature or fn.name))

        if fn.description then
            blank(lines)

            table.insert(lines, fn.description)
        end
    end

    return lines
end

------------------------------------------------------------
-- Uniform hint
------------------------------------------------------------

local function uniform_hint_lines(hint)
    local lines = {
        "`" .. hint.name .. "`",
    }

    if hint.description then
        blank(lines)

        table.insert(lines, hint.description)
    end

    local applicable = sorted_type_names(hint.types)

    if #applicable > 0 then
        blank(lines)

        table.insert(lines, "Applicable types: `" .. table.concat(applicable, "`, `") .. "`.")
    end

    return lines
end

------------------------------------------------------------
-- Build markdown
------------------------------------------------------------

local function build_lines(info)
    if info.kind == "user_symbol" then
        return user_symbol_lines(info.symbol)
    end

    if info.kind == "user_function" then
        return user_function_lines(info.functions)
    end

    if info.kind == "builtin_variable" then
        return builtin_variable_lines(info)
    end

    if info.kind == "builtin_function" then
        return builtin_function_lines(info.functions)
    end

    if info.kind == "processor" then
        local lines = {}

        append(lines, code_block("void " .. info.processor.name .. "()"))

        if info.processor.detail then
            blank(lines)

            table.insert(lines, info.processor.detail)
        end

        return lines
    end

    if info.kind == "shader_type" then
        return {
            "`shader_type " .. info.name .. "`",
            "",
            "GDShader shader type.",
        }
    end

    if info.kind == "render_mode" then
        return {
            "`render_mode " .. info.name .. "`",
            "",
            "GDShader render mode.",
        }
    end

    if info.kind == "type" then
        return {
            "`" .. info.name .. "`",
            "",
            "GDShader type.",
        }
    end

    if info.kind == "uniform_hint" then
        return uniform_hint_lines(info.hint)
    end

    if info.kind == "keyword" then
        return {
            "`" .. info.name .. "`",
            "",
            "GDShader keyword.",
        }
    end

    return nil
end

------------------------------------------------------------
-- Hover
------------------------------------------------------------

function M.hover()
    local bufnr = vim.api.nvim_get_current_buf()

    if not util.is_supported(bufnr) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)

    local row = cursor[1] - 1

    local column = cursor[2]

    local info = symbol_at.resolve(bufnr, row, column)

    if not info then
        return
    end

    local lines = build_lines(info)

    if not lines or #lines == 0 then
        return
    end

    vim.lsp.util.open_floating_preview(lines, "markdown", {
        border = "rounded",

        focusable = true,

        focus_id = "gdshader_nvim_hover",

        max_width = 80,

        close_events = {
            "CursorMoved",
            "CursorMovedI",
            "InsertCharPre",
        },
    })
end

------------------------------------------------------------
-- Attach
------------------------------------------------------------

function M.attach(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    if vim.b[bufnr].gdshader_nvim_hover_attached then
        return
    end

    vim.b[bufnr].gdshader_nvim_hover_attached = true

    --------------------------------------------------------
    -- Command
    --------------------------------------------------------

    vim.api.nvim_buf_create_user_command(bufnr, "GDShaderHover", function()
        M.hover()
    end, {
        desc = "Show GDShader hover information",
    })

    --------------------------------------------------------
    -- <Plug>
    --------------------------------------------------------

    vim.keymap.set("n", "<Plug>(gdshader-nvim-hover)", M.hover, {
        buffer = bufnr,

        silent = true,

        desc = "GDShader hover",
    })

    --------------------------------------------------------
    -- K
    --
    -- 只有用户没有现有 K mapping 时才设置，
    -- 不覆盖你的 LSP/自定义键位。
    --------------------------------------------------------

    util.maybe_set_keymap(bufnr, require("gdshader_nvim.config").get().keymaps.hover, M.hover, "GDShader hover")
end

------------------------------------------------------------
-- Setup
------------------------------------------------------------

function M.setup()
    if configured then
        return
    end

    configured = true

    local config = require("gdshader_nvim.config").get()

    local group = vim.api.nvim_create_augroup("GDShaderNvimHover", {
        clear = true,
    })

    vim.api.nvim_create_autocmd("FileType", {
        group = group,

        pattern = config.filetypes,

        callback = function(args)
            M.attach(args.buf)
        end,
    })

    --------------------------------------------------------
    -- setup() 可能发生在 FileType 事件之后。
    --------------------------------------------------------

    local bufnr = vim.api.nvim_get_current_buf()

    if util.is_supported(bufnr) then
        M.attach(bufnr)
    end
end

return M
