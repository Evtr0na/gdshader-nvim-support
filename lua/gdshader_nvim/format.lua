local M = {}

local util = require("gdshader_nvim.util")

local configured = false

------------------------------------------------------------
-- Per-line brace scanning
--
-- Counts '{' / '}' that are NOT inside a string or a comment.
-- `block` carries the block-comment state across lines.
-- Lines starting with '#' (preprocessor) are ignored for depth.
------------------------------------------------------------

local function scan_line(line, block)
    local open = 0
    local close = 0

    local in_string = false
    local in_line_comment = false
    local in_block = block

    local i = 1
    local n = #line

    while i <= n do
        local c = line:sub(i, i)
        local next_c = line:sub(i + 1, i + 1)

        if in_line_comment then
            -- rest of line ignored
            break
        end

        if in_block then
            if c == "*" and next_c == "/" then
                in_block = false

                i = i + 2
            else
                i = i + 1
            end
        elseif in_string then
            if c == "\\" then
                i = i + 2
            elseif c == '"' then
                in_string = false

                i = i + 1
            else
                i = i + 1
            end
        else
            if c == "/" and next_c == "/" then
                in_line_comment = true
            elseif c == "/" and next_c == "*" then
                in_block = true

                i = i + 2
            elseif c == '"' then
                in_string = true

                i = i + 1
            elseif c == "{" then
                open = open + 1

                i = i + 1
            elseif c == "}" then
                close = close + 1

                i = i + 1
            else
                i = i + 1
            end
        end
    end

    return open, close, in_block
end

------------------------------------------------------------
-- Compute reformatted lines
------------------------------------------------------------

function M.reformat(lines, shiftwidth)
    local result = {}
    local indent = 0
    local block = false

    local pad = string.rep(" ", shiftwidth)

    for _, raw in ipairs(lines) do
        --------------------------------------------------------
        -- 同时去掉行首与行尾空白，避免重新缩进时叠加在已有缩进之上
        -- （修复重复格式化导致缩进逐层加深的问题）。
        --------------------------------------------------------

        local trimmed = raw:match("^%s*(.-)%s*$")

        local is_preprocessor = trimmed:match("^%s*#%w") ~= nil

        --------------------------------------------------------
        -- 本行显示用的缩进。以 '}' 开头的行在显示时先回退一级，
        -- 但后面的 brace 扫描仍会把它计入，因此 `} else {` 的后继
        -- 语句体仍保持当前层级（与 VSCode 行为一致）。
        --------------------------------------------------------

        local display_indent = indent

        if not is_preprocessor and not block then
            if trimmed:match("^}") then
                display_indent = math.max(0, indent - 1)
            end
        end

        local out

        if is_preprocessor then
            out = trimmed
        else
            out = (display_indent > 0 and pad:rep(display_indent) or "") .. trimmed
        end

        table.insert(result, out)

        --------------------------------------------------------
        -- 更新缩进层级。
        --------------------------------------------------------

        if not is_preprocessor then
            local open, close, new_block = scan_line(trimmed, block)

            block = new_block

            indent = indent + open - close

            if indent < 0 then
                indent = 0
            end
        end
    end

    return result
end

------------------------------------------------------------
-- get_edits (LSP / conform style)
--
-- Returns a single TextEdit replacing the whole buffer.
------------------------------------------------------------

function M.get_edits(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if not util.is_supported(bufnr) then
        return {}
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local shiftwidth = vim.bo[bufnr].shiftwidth or 4

    local formatted = M.reformat(lines, shiftwidth)

    local current = table.concat(lines, "\n")
    local next_text = table.concat(formatted, "\n")

    if current == next_text then
        return {}
    end

    local line_count = vim.api.nvim_buf_line_count(bufnr)

    return {
        {
            range = {
                start = { line = 0, character = 0 },
                ["end"] = { line = line_count, character = 0 },
            },
            newText = next_text,
        },
    }
end

------------------------------------------------------------
-- format (apply in place)
------------------------------------------------------------

function M.format(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if not util.is_supported(bufnr) then
        vim.notify("GDShader: not a GDShader buffer", vim.log.levels.WARN)

        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local shiftwidth = vim.bo[bufnr].shiftwidth or 4

    local formatted = M.reformat(lines, shiftwidth)

    --------------------------------------------------------
    -- 仅替换实际变化的行，自底向上，合并为一个 undo 步。
    --------------------------------------------------------

    local changed = 0
    local first_edit = true

    for row = #lines, 1, -1 do
        local original = lines[row]:gsub("%s+$", "")
        local new_line = formatted[row]

        if original ~= new_line then
            if not first_edit then
                pcall(vim.cmd, "undojoin")
            end

            first_edit = false

            local line_len = #lines[row]

            pcall(vim.api.nvim_buf_set_text, bufnr, row - 1, 0, row - 1, line_len, { new_line })

            changed = changed + 1
        end
    end

    if changed > 0 then
        vim.notify("GDShader: formatted " .. changed .. " line(s)", vim.log.levels.INFO)
    end
end

------------------------------------------------------------
-- Conform integration
--
-- Registers a `gdshader` formatter with conform.nvim so that
-- `formatters_by_ft = { gdshader = { "gdshader" } }` (or
-- `:ConformFormat`) routes to this plugin. Best-effort: if
-- conform is not installed or its API differs, this is a no-op
-- and the native `:GDShaderFormat` command / format-on-save
-- still work.
------------------------------------------------------------

function M.try_register_conform()
    local ok, conform = pcall(require, "conform")

    if not ok or not conform then
        return false
    end

    conform.formatters = conform.formatters or {}

    if conform.formatters["gdshader"] then
        return true
    end

    conform.formatters["gdshader"] = {
        meta = {
            url = "https://github.com/XiaoDouXd/gdshader-nvim-support",
            description = "GDShader formatter (gdshader-nvim-support)",
        },

        format = function(_, ctx, callback)
            local ok_format, err = pcall(function()
                local bufnr = ctx.buf or vim.api.nvim_get_current_buf()

                if not util.is_supported(bufnr) then
                    callback(nil, {})

                    return
                end

                local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

                local shiftwidth = vim.bo[bufnr].shiftwidth or 4

                local formatted = M.reformat(lines, shiftwidth)

                local current = table.concat(lines, "\n")
                local next_text = table.concat(formatted, "\n")

                if current == next_text then
                    callback(nil, {})

                    return
                end

                local line_count = vim.api.nvim_buf_line_count(bufnr)

                callback(nil, {
                    {
                        text = next_text .. "\n",

                        range = {
                            start = { line = 0, character = 0 },
                            ["end"] = { line = line_count, character = 0 },
                        },
                    },
                })
            end)

            if not ok_format then
                callback(err)
            end
        end,
    }

    return true
end

------------------------------------------------------------
-- Attach
------------------------------------------------------------

function M.attach(bufnr)
    if not util.is_supported(bufnr) then
        return
    end

    if vim.b[bufnr].gdshader_nvim_format_attached then
        return
    end

    vim.b[bufnr].gdshader_nvim_format_attached = true

    vim.api.nvim_buf_create_user_command(bufnr, "GDShaderFormat", function()
        M.format(bufnr)
    end, {
        desc = "Format the current GDShader buffer",
    })
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

    local group = vim.api.nvim_create_augroup("GDShaderNvimFormat", {
        clear = true,
    })

    --------------------------------------------------------
    -- Register a conform.nvim formatter (best-effort).
    -- Re-attempt once conform is (re)loaded, since plugin
    -- setup may run before conform is available.
    --------------------------------------------------------

    M.try_register_conform()

    vim.api.nvim_create_autocmd({ "User" }, {
        group = group,

        pattern = { "ConformLoaded", "ConformSetup" },

        callback = function()
            M.try_register_conform()
        end,
    })

    vim.api.nvim_create_autocmd("VimEnter", {
        group = group,

        once = true,

        callback = function()
            M.try_register_conform()
        end,
    })

    --------------------------------------------------------
    -- Optional format-on-save (independent of conform).
    -- If you use conform's format_on_save, keep this off to
    -- avoid double formatting.
    --------------------------------------------------------

    if config.format.on_save then
        vim.api.nvim_create_autocmd("BufWritePre", {
            group = group,

            pattern = "*." .. table.concat(config.filetypes, ",*."),

            callback = function(args)
                if not util.is_supported(args.buf) then
                    return
                end

                if vim.b[args.buf].gdshader_nvim_formatting then
                    return
                end

                vim.b[args.buf].gdshader_nvim_formatting = true

                pcall(M.format, args.buf)

                vim.b[args.buf].gdshader_nvim_formatting = nil
            end,
        })
    end

    vim.api.nvim_create_autocmd("FileType", {
        group = group,

        pattern = config.filetypes,

        callback = function(args)
            M.attach(args.buf)
        end,
    })

    local bufnr = vim.api.nvim_get_current_buf()

    if util.is_supported(bufnr) then
        M.attach(bufnr)
    end
end

return M
