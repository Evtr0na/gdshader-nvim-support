local M = {}

local semantic_diagnostics = require("gdshader_nvim.semantic.diagnostics")

local namespace = vim.api.nvim_create_namespace("gdshader_nvim")

local configured = false

local generations = {}

------------------------------------------------------------
-- Severity
------------------------------------------------------------

local severity_map = {
    error = vim.diagnostic.severity.ERROR,

    warning = vim.diagnostic.severity.WARN,

    info = vim.diagnostic.severity.INFO,

    hint = vim.diagnostic.severity.HINT,
}

------------------------------------------------------------
-- Supported buffer
------------------------------------------------------------

local function is_supported(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end

    local config = require("gdshader_nvim.config").get()

    local ft = vim.bo[bufnr].filetype

    for _, supported in ipairs(config.filetypes) do
        if ft == supported then
            return true
        end
    end

    return false
end

------------------------------------------------------------
-- Filetype patterns for autocmds
------------------------------------------------------------

local function filetype_patterns()
    local config = require("gdshader_nvim.config").get()

    local patterns = {}

    for _, ft in ipairs(config.filetypes) do
        table.insert(patterns, "*." .. ft)
    end

    return patterns
end

------------------------------------------------------------
-- Refresh
------------------------------------------------------------

function M.refresh(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if not is_supported(bufnr) then
        vim.diagnostic.reset(namespace, bufnr)

        return
    end

    local source = semantic_diagnostics.get(bufnr)

    local diagnostics = {}

    for _, item in ipairs(source) do
        table.insert(diagnostics, {
            lnum = item.line or 0,

            col = item.column or 0,

            end_lnum = item.end_line or item.line or 0,

            end_col = item.end_column or ((item.column or 0) + 1),

            severity = severity_map[item.severity] or vim.diagnostic.severity.ERROR,

            message = item.message,

            source = item.source or "gdshader_nvim",

            code = item.code,
        })
    end

    vim.diagnostic.set(namespace, bufnr, diagnostics, {})
end

------------------------------------------------------------
-- Debounced refresh
------------------------------------------------------------

function M.schedule(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    generations[bufnr] = (generations[bufnr] or 0) + 1

    local generation = generations[bufnr]

    vim.defer_fn(function()
        if generations[bufnr] ~= generation then
            return
        end

        if not vim.api.nvim_buf_is_valid(bufnr) then
            return
        end

        M.refresh(bufnr)
    end, require("gdshader_nvim.config").get().diagnostics.debounce_ms)
end

------------------------------------------------------------
-- Setup
------------------------------------------------------------

function M.setup()
    if configured then
        return
    end

    configured = true

    local group = vim.api.nvim_create_augroup("GDShaderBlinkDiagnostics", {
        clear = true,
    })

    vim.api.nvim_create_autocmd({
        "BufEnter",
        "TextChanged",
        "TextChangedI",
        "InsertLeave",
    }, {
        group = group,

        pattern = filetype_patterns(),

        callback = function(args)
            M.schedule(args.buf)
        end,
    })

    vim.api.nvim_create_autocmd("BufDelete", {
        group = group,

        pattern = filetype_patterns(),

        callback = function(args)
            generations[args.buf] = nil

            vim.diagnostic.reset(namespace, args.buf)
        end,
    })
end

return M
