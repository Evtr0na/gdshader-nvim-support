local M = {}

local function ok(msg)
    vim.health.ok(msg)
end

local function warn(msg)
    vim.health.warn(msg)
end

local function info(msg)
    vim.health.info(msg)
end

------------------------------------------------------------
-- Health check
------------------------------------------------------------

function M.check()
    local config = require("gdshader_nvim.config").get()

    vim.health.start("gdshader-nvim-support")

    --------------------------------------------------------
    -- Version
    --------------------------------------------------------

    local ok_version, plugin = pcall(require, "gdshader_nvim")

    if ok_version then
        ok("Plugin loaded.")
    else
        error("gdshader-nvim-support failed to load: " .. tostring(plugin))
        return
    end

    --------------------------------------------------------
    -- Filetypes
    --------------------------------------------------------

    info("Handled filetypes: " .. table.concat(config.filetypes, ", "))

    --------------------------------------------------------
    -- Features
    --------------------------------------------------------

    local features = {}

    for name, enabled in pairs(config.features) do
        if enabled then
            table.insert(features, name)
        end
    end

    info("Enabled features: " .. (#features > 0 and table.concat(features, ", ") or "none"))

    --------------------------------------------------------
    -- blink.cmp (required only for completion)
    --------------------------------------------------------

    if config.features.completion then
        local has_blink = pcall(require, "blink.cmp")

        if has_blink then
            ok("blink.cmp is available (completion enabled).")
        else
            warn("`completion` feature is enabled but blink.cmp is not installed. "
                .. "Install `Saghen/blink.cmp` and register the provider "
                .. '{ name = "GDShader", module = "gdshader_nvim" }.')
        end
    end

    --------------------------------------------------------
    -- tree-sitter grammar (optional, recommended)
    --------------------------------------------------------

    local has_parser = pcall(vim.treesitter.language.add, "gdshader")

    if has_parser then
        ok("`gdshader` tree-sitter grammar is available.")
    else
        if config.treesitter then
            warn("`treesitter` is enabled but no `gdshader` parser was found. "
                .. "The built-in lexer is used for comment masking. "
                .. "Install a `gdshader` grammar (e.g. via nvim-treesitter) for best results.")
        else
            info("tree-sitter backend disabled; using the built-in lexer.")
        end
    end
end

return M
