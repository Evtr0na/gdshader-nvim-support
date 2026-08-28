local M = {}

local util = require("gdshader_nvim.util")

local configured = false

local namespace = vim.api.nvim_create_namespace("gdshader_nvim_color")

local hl_counter = 0

------------------------------------------------------------
-- Parse a vec3 / vec4 literal on a line.
--
-- Returns the table at the cursor column if found, else the
-- first one on the line. Components are clamped to [0, 1].
------------------------------------------------------------

local function clamp01(x)
    if x < 0 then
        return 0
    end

    if x > 1 then
        return 1
    end

    return x
end

local function hex2(n)
    local s = string.format("%02x", math.min(255, math.max(0, math.floor(n * 255 + 0.5))))

    return s
end

local function parse_vec(line, column)
    --------------------------------------------------------
    -- 收集所有 vecN(...) 区间。
    --------------------------------------------------------

    local candidates = {}

    for vec_type in line:gmatch("vec[34]%s*%b()") do
        local open = line:find(vec_type, 1, true)

        if open then
            local close = open + #vec_type - 1

            local inner = vec_type:match("%((.*)%)")

            if inner then
                local parts = {}

                for value in inner:gmatch("[^,]+") do
                    local num = tonumber((value:gsub("%s+", "")):match("^[%-%d%.eE%+]+"))

                    if not num then
                        parts = nil

                        break
                    end

                    table.insert(parts, num)
                end

                if parts and #parts >= 3 then
                    table.insert(candidates, {
                        start_col = open - 1,
                        end_col = close,
                        components = parts,
                    })
                end
            end
        end
    end

    if #candidates == 0 then
        return nil
    end

    --------------------------------------------------------
    -- 优先光标所在的那一个。
    --------------------------------------------------------

    for _, candidate in ipairs(candidates) do
        if column >= candidate.start_col and column <= candidate.end_col then
            return candidate
        end
    end

    return candidates[1]
end

------------------------------------------------------------
-- Build a swatch highlight group for a color.
------------------------------------------------------------

local function swatch_hl(r, g, b)
    hl_counter = hl_counter + 1

    local name = "GDShaderColorSwatch" .. hl_counter

    local hex = "#" .. hex2(r) .. hex2(g) .. hex2(b)

    --------------------------------------------------------
    -- 文字颜色取对比色，保证色块可读。
    --------------------------------------------------------

    local luminance = 0.299 * r + 0.587 * g + 0.114 * b

    local fg = luminance > 0.5 and "#000000" or "#ffffff"

    pcall(vim.api.nvim_set_hl, 0, name, {
        fg = fg,
        bg = hex,
    })

    return name, hex
end

------------------------------------------------------------
-- Preview (command)
------------------------------------------------------------

function M.preview()
    local bufnr = vim.api.nvim_get_current_buf()

    if not util.is_supported(bufnr) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)

    local row = cursor[1] - 1

    local column = cursor[2]

    local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)

    local line = lines[1]

    if not line or line == "" then
        vim.notify("GDShader: no color literal on this line", vim.log.levels.INFO)

        return
    end

    local match = parse_vec(line, column)

    if not match then
        vim.notify("GDShader: no vec3/vec4 color under cursor", vim.log.levels.INFO)

        return
    end

    local c = match.components

    local r = clamp01(c[1])
    local g = clamp01(c[2])
    local b = clamp01(c[3])
    local a = c[4] ~= nil and clamp01(c[4]) or 1

    local _, hex = swatch_hl(r, g, b)

    local rgba = string.format("rgba(%d, %d, %d, %.2f)", r * 255, g * 255, b * 255, a)
    local rgb_hex = "#" .. hex2(r) .. hex2(g) .. hex2(b)
    local argb_hex = "#" .. hex2(a) .. hex2(r) .. hex2(g) .. hex2(b)

    local content = {
        "GDShader color",
        "",
        ("  %s  %s"):format(" ", hex),
        "",
        "HEX : " .. rgb_hex,
        "ARGB: " .. argb_hex,
        "RGBA: " .. rgba,
    }

    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    vim.api.nvim_buf_set_option(buf, "filetype", "gdshader")

    local width = 0

    for _, l in ipairs(content) do
        width = math.max(width, #l)
    end

    local win = vim.api.nvim_open_win(buf, false, {
        relative = "cursor",
        row = 1,
        col = 0,
        width = math.max(width, 12),
        height = #content,
        border = "rounded",
        style = "minimal",
        focusable = false,
        noautocmd = true,
    })

    --------------------------------------------------------
    -- 用真实色块覆盖色块行。
    --------------------------------------------------------

    local swatch_name = "GDShaderColorSwatchPreview"

    pcall(vim.api.nvim_set_hl, 0, swatch_name, { fg = hex, bg = hex })

    vim.api.nvim_buf_set_extmark(buf, vim.api.nvim_create_namespace("gdshader_nvim_preview"), 2, 0, {
        virt_text = { { "  " .. (" "):rep(math.max(0, width - 2)), swatch_name } },
        virt_text_pos = "overlay",
    })

    --------------------------------------------------------
    -- 自动关闭。
    --------------------------------------------------------

    vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, 4000)
end

------------------------------------------------------------
-- Decoration (extmark swatches on vec3/vec4 literals)
------------------------------------------------------------

function M.refresh(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if not util.is_supported(bufnr) then
        return
    end

    local config = require("gdshader_nvim.config").get()

    if not (config.features.color and config.color.decorate) then
        return
    end

    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

    local line_count = vim.api.nvim_buf_line_count(bufnr)

    for row = 0, line_count - 1 do
        local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)

        local line = lines[1]

        if line and line ~= "" then
            local match = parse_vec(line, -1)

            if match then
                local c = match.components

                local r = clamp01(c[1])
                local g = clamp01(c[2])
                local b = clamp01(c[3])

                local hl_name, _ = swatch_hl(r, g, b)

                pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, row, match.end_col, {
                    virt_text = { { " ■", hl_name } },
                    virt_text_pos = "eol",
                })
            end
        end
    end
end

------------------------------------------------------------
-- Toggle decoration
------------------------------------------------------------

function M.toggle_decoration()
    local config = require("gdshader_nvim.config").get()

    config.color.decorate = not config.color.decorate

    vim.notify("GDShader color decoration: " .. (config.color.decorate and "on" or "off"), vim.log.levels.INFO)

    M.refresh()
end

------------------------------------------------------------
-- Attach
------------------------------------------------------------

function M.attach(bufnr)
    if not util.is_supported(bufnr) then
        return
    end

    if vim.b[bufnr].gdshader_nvim_color_attached then
        return
    end

    vim.b[bufnr].gdshader_nvim_color_attached = true

    vim.api.nvim_buf_create_user_command(bufnr, "GDShaderPreviewColor", function()
        M.preview()
    end, {
        desc = "Preview GDShader vec3/vec4 color at cursor",
    })

    vim.api.nvim_buf_create_user_command(bufnr, "GDShaderColorDecoration", function()
        M.toggle_decoration()
    end, {
        desc = "Toggle GDShader color swatch decoration",
    })

    M.refresh(bufnr)
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

    local group = vim.api.nvim_create_augroup("GDShaderNvimColor", {
        clear = true,
    })

    vim.api.nvim_create_autocmd("FileType", {
        group = group,

        pattern = config.filetypes,

        callback = function(args)
            M.attach(args.buf)
        end,
    })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
        group = group,

        pattern = "*." .. table.concat(config.filetypes, ",*."),

        callback = function(args)
            local bufnr = args.buf

            if not util.is_supported(bufnr) then
                return
            end

            if not (config.features.color and config.color.decorate) then
                return
            end

            vim.defer_fn(function()
                if vim.api.nvim_buf_is_valid(bufnr) then
                    M.refresh(bufnr)
                end
            end, config.color.debounce_ms or 200)
        end,
    })

    local bufnr = vim.api.nvim_get_current_buf()

    if util.is_supported(bufnr) then
        M.attach(bufnr)
    end
end

return M
