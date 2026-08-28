local M = {}

local symbol_at = require("gdshader_nvim.semantic.symbol_at")

local context = require("gdshader_nvim.context")

local util = require("gdshader_nvim.util")

local hints = require("gdshader_nvim.syntax.hints")

local configured = false

------------------------------------------------------------
-- Project root
--
-- 用于：
--
-- #include "res://foo/bar.gdshaderinc"
------------------------------------------------------------

local function find_project_root(filename)
    if not filename or filename == "" then
        return nil
    end

    local directory = vim.fs.dirname(filename)

    if not directory then
        return nil
    end

    local found = vim.fs.find("project.godot", {
        path = directory,

        upward = true,

        type = "file",

        limit = 1,
    })

    if not found or not found[1] then
        return nil
    end

    return vim.fs.dirname(found[1])
end

------------------------------------------------------------
-- Include at cursor
------------------------------------------------------------

local function get_include_at_cursor(bufnr, row, column)
    local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)

    local line = lines[1]

    if not line then
        return nil
    end

    local path = line:match('^%s*#include%s+"([^"]+)"')

    if not path then
        return nil
    end

    --------------------------------------------------------
    -- 只在 cursor 位于 include 字符串附近时触发。
    --------------------------------------------------------

    local quote_start = line:find('"', 1, true)

    if not quote_start then
        return nil
    end

    local quote_end = line:find('"', quote_start + 1, true)

    if not quote_end then
        return nil
    end

    local lua_column = column + 1

    if lua_column < quote_start or lua_column > quote_end then
        return nil
    end

    return path
end

------------------------------------------------------------
-- Include path
------------------------------------------------------------

local function resolve_include_path(bufnr, include_path)
    local filename = vim.api.nvim_buf_get_name(bufnr)

    if filename == "" then
        return nil
    end

    --------------------------------------------------------
    -- res://
    --------------------------------------------------------

    if include_path:sub(1, 6) == "res://" then
        local root = find_project_root(filename)

        if not root then
            return nil
        end

        return vim.fs.normalize(vim.fs.joinpath(root, include_path:sub(7)))
    end

    --------------------------------------------------------
    -- Absolute
    --------------------------------------------------------

    if vim.fs.is_absolute(include_path) then
        return vim.fs.normalize(include_path)
    end

    --------------------------------------------------------
    -- Relative
    --------------------------------------------------------

    local directory = vim.fs.dirname(filename)

    if not directory then
        return nil
    end

    return vim.fs.normalize(vim.fs.joinpath(directory, include_path))
end

------------------------------------------------------------
-- Jump mark
------------------------------------------------------------

local function save_jump()
    pcall(function()
        vim.cmd("normal! m'")
    end)
end
------------------------------------------------------------
-- Jump
------------------------------------------------------------

local function jump_to(target)
    if not target then
        return
    end

    save_jump()

    --------------------------------------------------------
    -- Cross file
    --------------------------------------------------------

    if target.path and target.path ~= "" then
        local current = vim.api.nvim_buf_get_name(0)

        local current_normalized = current ~= "" and vim.fs.normalize(current) or ""

        local target_normalized = vim.fs.normalize(target.path)

        if current_normalized ~= target_normalized then
            vim.cmd("edit " .. vim.fn.fnameescape(target.path))
        end
    end

    --------------------------------------------------------
    -- Position
    --
    -- line:   1-based
    -- column: 0-based
    --------------------------------------------------------

    local line = math.max(1, target.line or 1)

    local column = math.max(0, target.column or 0)

    vim.api.nvim_win_set_cursor(0, {
        line,
        column,
    })

    --------------------------------------------------------
    -- Open folds and center.
    --------------------------------------------------------

    pcall(function()
        vim.cmd("normal! zv")
    end)

    pcall(function()
        vim.cmd("normal! zz")
    end)
end

------------------------------------------------------------
-- Symbol target
------------------------------------------------------------

local function symbol_target(symbol)
    if not symbol then
        return nil
    end

    local line = symbol.name_line or symbol.start_line or symbol.line

    if not line then
        return nil
    end

    return {
        line = line,

        column = symbol.name_column or symbol.start_column or 0,
    }
end

------------------------------------------------------------
-- User function
------------------------------------------------------------

local function goto_user_function(functions)
    if not functions or #functions == 0 then
        return
    end

    --------------------------------------------------------
    -- Single definition
    --------------------------------------------------------

    if #functions == 1 then
        jump_to(symbol_target(functions[1]))

        return
    end

    --------------------------------------------------------
    -- Future overload support.
    --------------------------------------------------------

    vim.ui.select(functions, {
        prompt = "GDShader definition:",

        format_item = function(fn)
            return context.get_function_signature(fn)
        end,
    }, function(choice)
        if not choice then
            return
        end

        jump_to(symbol_target(choice))
    end)
end

------------------------------------------------------------
-- Definition
------------------------------------------------------------

function M.goto_definition()
    local bufnr = vim.api.nvim_get_current_buf()

    if not util.is_supported(bufnr) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(0)

    local row = cursor[1] - 1

    local column = cursor[2]

    --------------------------------------------------------
    -- #include
    --------------------------------------------------------

    local include_path = get_include_at_cursor(bufnr, row, column)

    if include_path then
        --------------------------------------------------------
        -- #gdshader-hint-ignore / #gdshader-hint-redirection
        --------------------------------------------------------

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

        local line_text = lines[row + 1] or ""
        local next_text = lines[row + 2]

        local include_hints = hints.include_hints(line_text, next_text)

        local resolve_path = include_hints.redirect or include_path

        local target_path = resolve_include_path(bufnr, resolve_path)

        if target_path and vim.uv.fs_stat(target_path) then
            jump_to({
                path = target_path,

                line = 1,

                column = 0,
            })

            return
        end

        --------------------------------------------------------
        -- 被 #gdshader-hint-ignore 标记：静默跳过。
        --------------------------------------------------------

        if include_hints.ignore then
            return
        end

        vim.notify("GDShader include not found: " .. include_path, vim.log.levels.WARN)

        return
    end

    --------------------------------------------------------
    -- Semantic symbol
    --------------------------------------------------------

    local info = symbol_at.resolve(bufnr, row, column)

    if not info then
        return
    end

    --------------------------------------------------------
    -- Local / parameter / global
    --------------------------------------------------------

    if info.kind == "user_symbol" then
        jump_to(symbol_target(info.symbol))

        return
    end

    --------------------------------------------------------
    -- User function
    --------------------------------------------------------

    if info.kind == "user_function" then
        goto_user_function(info.functions)

        return
    end

    --------------------------------------------------------
    -- Built-ins / types / processor etc.
    --
    -- 与参考插件一样：
    -- 没有源码 declaration 就不跳。
    --------------------------------------------------------
end

------------------------------------------------------------
-- Attach
------------------------------------------------------------

function M.attach(bufnr)
    if not util.is_supported(bufnr) then
        return
    end

    if vim.b[bufnr].gdshader_nvim_definition_attached then
        return
    end

    vim.b[bufnr].gdshader_nvim_definition_attached = true

    --------------------------------------------------------
    -- Command
    --------------------------------------------------------

    vim.api.nvim_buf_create_user_command(bufnr, "GDShaderDefinition", function()
        M.goto_definition()
    end, {
        desc = "Go to GDShader definition",
    })

    --------------------------------------------------------
    -- <Plug>
    --------------------------------------------------------

    vim.keymap.set("n", "<Plug>(gdshader-nvim-definition)", M.goto_definition, {
        buffer = bufnr,

        silent = true,

        desc = "GDShader definition",
    })

    --------------------------------------------------------
    -- gd
    --
    -- 不覆盖用户已有 mapping。
    --------------------------------------------------------

    util.maybe_set_keymap(bufnr, require("gdshader_nvim.config").get().keymaps.definition, M.goto_definition, "GDShader definition")
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

    local group = vim.api.nvim_create_augroup("GDShaderNvimDefinition", {
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
    -- setup() 可能发生在 FileType 后
    --------------------------------------------------------

    local bufnr = vim.api.nvim_get_current_buf()

    if util.is_supported(bufnr) then
        M.attach(bufnr)
    end
end

return M
