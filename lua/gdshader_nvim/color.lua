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
    -- Defensive: non-numeric values (e.g. a missing component when a vecN
    -- literal has more than 4 in-range parts) clamp to 0 instead of erroring.
    x = tonumber(x) or 0

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

local function parse_vec_list(line)
    --------------------------------------------------------
    -- 收集一行内所有 vecN(...) 区间。
    -- 使用 frontier pattern %f[%w] 确保 vec 前面不是单词字符，
    -- 避免误匹配 ivec3 / bvec3 / myvec3 等。
    --------------------------------------------------------

    local candidates = {}

    for vec_type in line:gmatch("%f[%w]vec[34]%s*%b()") do
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
                    --------------------------------------------------------
                    -- VS Code only treats a `vec3` / `vec4` literal as a
                    -- color when every component is within [0, 1]; other
                    -- numeric vectors (e.g. positions) are not colored.
                    --------------------------------------------------------

                    local is_color = true

                    for _, component in ipairs(parts) do
                        if component < 0 or component > 1 then
                            is_color = false

                            break
                        end
                    end

                    if is_color then
                        table.insert(candidates, {
                            start_col = open - 1,
                            end_col = close,
                            components = parts,
                        })
                    end
                end
            end
        end
    end

    return candidates
end

local function parse_vec(line, column)
    local candidates = parse_vec_list(line)

    if #candidates == 0 then
        return nil
    end

    --------------------------------------------------------
    -- 优先光标所在的那一个。
    --------------------------------------------------------

    if column and column >= 0 then
        for _, candidate in ipairs(candidates) do
            if column >= candidate.start_col and column <= candidate.end_col then
                return candidate
            end
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
    -- 色块由前景字符（如 ■）的 fg 构成，背景透明（NONE）：
    -- 只给字符本身上色，不为字符格铺背景色，避免“背景色 +
    -- 前景字符”的双层效果。bg 设为 "NONE" 表示继承/透明。
    --------------------------------------------------------

    pcall(vim.api.nvim_set_hl, 0, name, {
        fg = hex,
        bg = "NONE",
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

    local swatch = config.color.swatch

    if not swatch or swatch == "" then
        swatch = "■"
    end

    local pad_left = tonumber(config.color.swatch_pad_left) or 0

    if pad_left < 0 then
        pad_left = 0
    end

    local pad_right = tonumber(config.color.swatch_pad_right) or 0

    if pad_right < 0 then
        pad_right = 0
    end

    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

    local line_count = vim.api.nvim_buf_line_count(bufnr)

    for row = 0, line_count - 1 do
        local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)

        local line = lines[1]

        if line and line ~= "" then
            local matches = parse_vec_list(line)

            for _, match in ipairs(matches) do
                local c = match.components

                local r = clamp01(c[1])
                local g = clamp01(c[2])
                local b = clamp01(c[3])

                local hl_name, _ = swatch_hl(r, g, b)

                local virt_text = {}

                if pad_left > 0 then
                    table.insert(virt_text, { string.rep(" ", pad_left), "" })
                end

                table.insert(virt_text, { swatch, hl_name })

                if pad_right > 0 then
                    table.insert(virt_text, { string.rep(" ", pad_right), "" })
                end

                pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, row, match.start_col, {
                    virt_text = virt_text,
                    virt_text_pos = "inline",
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
-- Edit (command)
--
-- nvim-idiomatic equivalent of VS Code's "click to edit color"
-- (ColorPresentation). Opens a floating editor pre-filled with
-- the RGB(A) components of the vec3/vec4 literal under the
-- cursor; on commit the literal in the source buffer is replaced.
------------------------------------------------------------

local edit_ns = vim.api.nvim_create_namespace("gdshader_nvim_color_edit")

local function fmt_component(x)
    --------------------------------------------------------
    -- Trim to a sane precision: drop trailing zeros, keep up
    -- to 4 significant digits (mirrors how Godot writes them).
    --------------------------------------------------------

    local v = clamp01(x)

    if math.floor(v) == v and math.abs(v) < 1e9 then
        return string.format("%d", math.floor(v + 0.5))
    end

    local s = string.format("%.4g", v)

    return s
end

local function build_vec_text(n, comps)
    local parts = {}

    for i = 1, n do
        table.insert(parts, fmt_component(comps[i]))
    end

    return string.format("vec%d(%s)", n, table.concat(parts, ", "))
end

local function parse_editor_line(line)
    --------------------------------------------------------
    -- Accept "R: 0.5", "R 0.5", "R=0.5" — case-insensitive.
    --------------------------------------------------------

    local key, val = line:match("^%s*([RGBA])%s*[:=]?%s*([%-%d%.eE%+]+)")

    if not key then
        return nil
    end

    local num = tonumber(val)

    if not num then
        return nil
    end

    return key:upper(), clamp01(num)
end

local function parse_hex_line(line)
    if not line:lower():find("hex") then
        return nil
    end

    local hex8 = line:match("#?([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])")

    if hex8 then
        return {
            tonumber(hex8:sub(1, 2), 16) / 255,
            tonumber(hex8:sub(3, 4), 16) / 255,
            tonumber(hex8:sub(5, 6), 16) / 255,
            tonumber(hex8:sub(7, 8), 16) / 255,
        }
    end

    local hex6 = line:match("#?([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])")

    if hex6 then
        return {
            tonumber(hex6:sub(1, 2), 16) / 255,
            tonumber(hex6:sub(3, 4), 16) / 255,
            tonumber(hex6:sub(5, 6), 16) / 255,
            nil,
        }
    end

    return nil
end

local function comps_to_hex(comps)
    local r = clamp01(comps[1])
    local g = clamp01(comps[2])
    local b = clamp01(comps[3])
    local a = comps[4]

    local out = "#" .. hex2(r) .. hex2(g) .. hex2(b)

    if a then
        out = out .. hex2(a)
    end

    return out
end

local function edit_preview_swatch(buf, row, comps)
    local r = clamp01(comps[1] or 0)
    local g = clamp01(comps[2] or 0)
    local b = clamp01(comps[3] or 0)

    local _, hex = swatch_hl(r, g, b)

    pcall(vim.api.nvim_buf_set_extmark, buf, edit_ns, row, 0, {
        id = 1,
        virt_text = { { "  " .. (" "):rep(10), "GDShaderColorSwatchPreviewEdit" } },
        virt_text_pos = "overlay",
    })

    pcall(vim.api.nvim_set_hl, 0, "GDShaderColorSwatchPreviewEdit", { fg = hex, bg = hex })
end

------------------------------------------------------------
-- ccc.nvim backend (optional)
--
-- gdshader-nvim-support owns all GDShader syntax: it parses the
-- vec3/vec4 literal into RGB(A) and writes the result back as a
-- vec3/vec4. ccc.nvim is used purely as the color-editing UI. We
-- seed ccc with our RGB(A) and override its <CR>/q mappings so it
-- never parses GDShader text and never writes its own output format.
------------------------------------------------------------

-- ccc is designed around a single, reused core (its own :CccPick keeps
-- one core alive). Reusing this instance across opens avoids the dangling
-- UI/window state that a fresh Core.new() on every open would leave behind
-- (which broke h/l on the second open). Lazily created on first use.
local ccc_core = nil

local function ccc_ready()
    local ok, ccc = pcall(require, "ccc")

    if not ok or not ccc then
        return false
    end

    local ok_cfg, mod = pcall(require, "ccc.config")

    if not ok_cfg or not mod then
        return false
    end

    local opts = mod.options or {}

    if not next(opts) then
        -- ccc is installed but not set up yet: initialise with defaults so
        -- the picker has valid inputs / outputs / mappings. setup() leaves an
        -- already-populated options table untouched, so this is safe to call.
        local ok_s = pcall(mod.setup, {})

        if not ok_s then
            return false
        end
    end

    return true
end

local function open_ccc(bufnr, row, column, match)
    if not ccc_ready() then
        return false
    end

    -- Reuse one ccc core across all opens (see note on `ccc_core` above).
    -- Creating a fresh Core.new() per open left the previous UI/window
    -- state dangling and broke h/l on the second open.
    if not ccc_core then
        local core_ok, core = pcall(function()
            return require("ccc.core").new()
        end)

        if not core_ok or not core then
            return false
        end

        ccc_core = core
    end

    local core = ccc_core

    -- If a previous picker is still open, close it so the reused UI can be
    -- reopened cleanly.
    if core.ui.winid and vim.api.nvim_win_is_valid(core.ui.winid) then
        pcall(core.ui.close, core.ui)
    end

    -- Each edit starts in RGB input mode (GDShader's native color space).
    pcall(function() core.color:reset_mode() end)

    local comps = match.components
    local n = #comps

    -- Seed ccc with our GDShader RGB(A). ccc never reads the source text.
    pcall(function()
        -- ccc works in 0..1 RGB; our comps are already 0..1.
        core.color:set_rgb({ comps[1], comps[2], comps[3] })
    end)

    if n == 4 then
        pcall(function() core.color.alpha:set(comps[4]) end)
    else
        -- vec3 has no alpha: hide the slider so it cannot become vec4.
        pcall(function() core.color.alpha:hide() end)
    end

    -- Placeholder range; we never let ccc write text back.
    core.range = { row + 1, column, row + 1, column }

    local open_ok = pcall(function()
        core.ui:open(core.color, core.prev_colors)
    end)

    if not open_ok or not core.ui.winid then
        return false
    end

    -- Cancel path: closing the picker must not modify the source buffer.
    core.ui.on_quit_callback = function() end

    local utils = require("ccc.utils")

    local function commit()
        local rgb = { 0, 0, 0 }

        pcall(function() rgb = core.color:get_rgb() end)

        -- ccc returns 0..1 RGB; clamp into GDShader's 0..1 range.
        -- Build exactly `n` components: the first three from ccc's RGB,
        -- the 4th (for vec4) from ccc's alpha, and any extra source
        -- components preserved as-is (defensive; valid GLSL is vec3/vec4).
        local new_comps = {}

        for i = 1, 3 do
            new_comps[i] = clamp01(rgb[i] or 0)
        end

        if n >= 4 then
            local a

            pcall(function() a = core.color.alpha:get() end)

            if a == nil then
                a = comps[4]
            end

            new_comps[4] = clamp01(a)
        end

        for i = 5, n do
            new_comps[i] = clamp01(comps[i])
        end

        local replacement = build_vec_text(n, new_comps)

        if vim.api.nvim_buf_is_valid(bufnr) then
            pcall(vim.api.nvim_buf_set_text, bufnr, row, match.start_col, row, match.end_col, { replacement })
        end

        pcall(function() core.ui:close() end)
        M.refresh(bufnr)
    end

    local opts = require("ccc.config").options

    for lhs, rhs in pairs(opts.mappings) do
        if lhs == "<CR>" then
            vim.keymap.set("n", lhs, commit, { nowait = true, buffer = core.ui.bufnr, silent = true })
        elseif lhs == "q" then
            vim.keymap.set("n", lhs, function()
                pcall(function() core.ui:close() end)
            end, { nowait = true, buffer = core.ui.bufnr, silent = true })
        else
            vim.keymap.set("n", lhs, utils.bind(rhs, core), { nowait = true, buffer = core.ui.bufnr, silent = true })
        end
    end

    return true
end

------------------------------------------------------------
-- Dispatcher: chooses the color editor backend.
------------------------------------------------------------

function M.edit_color()
    local bufnr = vim.api.nvim_get_current_buf()

    if not util.is_supported(bufnr) then
        vim.notify("GDShader: not a gdshader buffer", vim.log.levels.INFO)

        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local column = cursor[2]
    local line = (vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]) or ""

    if not line or line == "" then
        vim.notify("GDShader: no color literal on this line", vim.log.levels.INFO)

        return
    end

    local match = parse_vec(line, column)

    if not match then
        vim.notify("GDShader: no vec3/vec4 color under cursor", vim.log.levels.INFO)

        return
    end

    local cfg = require("gdshader_nvim.config").get()
    local editor = (cfg.color and cfg.color.editor) or "auto"

    if editor ~= "builtin" then
        local ok = open_ccc(bufnr, row, column, match)

        if not ok and editor == "ccc" then
            vim.notify("GDShader: ccc.nvim not available, using built-in editor", vim.log.levels.WARN)
        end

        if ok then
            return
        end
    end

    -- Fallback (or explicit builtin): the built-in floating editor.
    M.edit()
end

function M.edit()
    local bufnr = vim.api.nvim_get_current_buf()

    if not util.is_supported(bufnr) then
        vim.notify("GDShader: not a gdshader buffer", vim.log.levels.INFO)

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

    local comps = match.components

    local n = #comps

    --------------------------------------------------------
    -- Build the editor buffer content.
    --------------------------------------------------------

    local editor_lines = {
        "# GDShader color editor — edit R/G/B" .. (n == 4 and "/A, then <CR> to apply (q to cancel)" or ", then <CR> to apply (q to cancel)"),
        "",
        "R: " .. fmt_component(comps[1]),
        "G: " .. fmt_component(comps[2]),
        "B: " .. fmt_component(comps[3]),
    }

    if n == 4 then
        table.insert(editor_lines, "A: " .. fmt_component(comps[4]))
    end

    table.insert(editor_lines, "HEX: " .. comps_to_hex(comps))
    table.insert(editor_lines, "")
    table.insert(editor_lines, "# edit R/G/B/A or the HEX line (clamped to [0, 1])")

    local ebuf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_lines(ebuf, 0, -1, false, editor_lines)
    vim.api.nvim_buf_set_option(ebuf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(ebuf, "modifiable", true)
    -- 故意不设为 "gdshader"，避免触发本插件对编辑器缓冲区的诊断/补全等 FileType 钩子。
    vim.api.nvim_buf_set_option(ebuf, "filetype", "gdshader_color_edit")

    local width = 0

    for _, l in ipairs(editor_lines) do
        width = math.max(width, #l)
    end

    local ewin = vim.api.nvim_open_win(ebuf, true, {
        relative = "cursor",
        row = 1,
        col = 0,
        width = math.max(width, 24),
        height = #editor_lines,
        border = "rounded",
        style = "minimal",
        noautocmd = true,
    })

    edit_preview_swatch(ebuf, 0, comps)

    --------------------------------------------------------
    -- Live swatch update as the user types.
    --------------------------------------------------------

    local function refresh_swatch()
        local cur = vim.api.nvim_buf_get_lines(ebuf, 0, -1, false)

        local rc = { [1] = nil, [2] = nil, [3] = nil, [4] = nil }

        for _, l in ipairs(cur) do
            local k, v = parse_editor_line(l)

            if k == "R" then rc[1] = v
            elseif k == "G" then rc[2] = v
            elseif k == "B" then rc[3] = v
            elseif k == "A" then rc[4] = v end
        end

        local hex = nil

        for _, l in ipairs(cur) do
            local h = parse_hex_line(l)

            if h then hex = h; break end
        end

        if hex then
            edit_preview_swatch(ebuf, 0, { hex[1], hex[2], hex[3], hex[4] or 1 })
        elseif rc[1] and rc[2] and rc[3] then
            edit_preview_swatch(ebuf, 0, { rc[1], rc[2], rc[3], rc[4] or 1 })
        end
    end

    vim.api.nvim_create_autocmd("TextChanged", {
        buffer = ebuf,
        callback = refresh_swatch,
    })

    --------------------------------------------------------
    -- Commit: parse, clamp, replace the source literal.
    --------------------------------------------------------

    local function commit()
        local cur = vim.api.nvim_buf_get_lines(ebuf, 0, -1, false)

        local parsed = {}

        for _, l in ipairs(cur) do
            local k, v = parse_editor_line(l)

            if k then
                parsed[k] = v
            end
        end

        -- HEX line takes precedence when valid.
        local hex = nil

        for _, l in ipairs(cur) do
            local h = parse_hex_line(l)

            if h then hex = h; break end
        end

        if hex then
            local new_comps = { hex[1], hex[2], hex[3] }

            if n == 4 then
                new_comps[4] = hex[4] ~= nil and hex[4] or comps[4]
            end

            for i = 5, n do
                new_comps[i] = clamp01(comps[i])
            end

            local replacement = build_vec_text(n, new_comps)

            pcall(vim.api.nvim_buf_set_text, bufnr, row, match.start_col, row, match.end_col, { replacement })

            if vim.api.nvim_win_is_valid(ewin) then
                vim.api.nvim_win_close(ewin, true)
            end

            M.refresh(bufnr)

            return
        end

        if not (parsed.R and parsed.G and parsed.B) then
            vim.notify("GDShader: R/G/B required to apply color", vim.log.levels.WARN)

            return
        end

        local new_comps = { parsed.R, parsed.G, parsed.B }

        if n == 4 then
            new_comps[4] = parsed.A ~= nil and parsed.A or comps[4]
        end

        for i = 5, n do
            new_comps[i] = clamp01(comps[i])
        end

        local replacement = build_vec_text(n, new_comps)

        pcall(vim.api.nvim_buf_set_text, bufnr, row, match.start_col, row, match.end_col, { replacement })

        if vim.api.nvim_win_is_valid(ewin) then
            vim.api.nvim_win_close(ewin, true)
        end

        M.refresh(bufnr)
    end

    vim.keymap.set("n", "<CR>", commit, { buffer = ebuf, nowait = true, silent = true })
    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(ewin) then
            vim.api.nvim_win_close(ewin, true)
        end
    end, { buffer = ebuf, nowait = true, silent = true })
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

    vim.api.nvim_buf_create_user_command(bufnr, "GDShaderEditColor", function()
        M.edit_color()
    end, {
        desc = "Edit GDShader vec3/vec4 color (ccc.nvim or built-in)",
    })

    M.refresh(bufnr)

    --------------------------------------------------------
    -- <Plug> + configurable keymap
    --------------------------------------------------------

    vim.keymap.set("n", "<Plug>(gdshader-nvim-edit-color)", M.edit, {
        buffer = bufnr,

        silent = true,

        desc = "Edit GDShader color",
    })

    util.maybe_set_keymap(bufnr, require("gdshader_nvim.config").get().keymaps.edit, M.edit_color, "Edit GDShader color")
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

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave", "BufWinEnter" }, {
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
