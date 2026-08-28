------------------------------------------------------------
-- gdshader-nvim-support
--
-- GDShader language support for Neovim: completion (blink.cmp),
-- diagnostics, hover, definition, references and rename — all
-- powered by a self-contained GDShader lexer/parser (with an
-- optional tree-sitter backend for comment handling).
------------------------------------------------------------

local M = {}

local config = require("gdshader_nvim.config")

------------------------------------------------------------
-- Boot enabled features
--
-- Each feature's own `setup()` is idempotent, so calling this
-- more than once is safe.
------------------------------------------------------------

local function boot()
    local cfg = config.get()

    require("gdshader_nvim.filetypes").setup()

    if cfg.features.diagnostics then
        require("gdshader_nvim.diagnostics").setup()
    end

    if cfg.features.hover then
        require("gdshader_nvim.hover").setup()
    end

    if cfg.features.definition then
        require("gdshader_nvim.definition").setup()
    end

    if cfg.features.references then
        require("gdshader_nvim.references").setup()
    end

    if cfg.features.rename then
        require("gdshader_nvim.rename").setup()
    end
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

--- Setup the plugin.
---
---@param opts table|nil  See |gdshader-nvim-support-config|
function M.setup(opts)
    config.setup(opts)

    boot()
end

--- Ensure setup has run (used by the completion source factory).
function M.ensure_setup()
    config.ensure()

    boot()
end

--- Merge extra GDShader knowledge into the database.
---
---@param extra table  See |gdshader-nvim-support-extending|
function M.extend(extra)
    require("gdshader_nvim.data.knowledge").extend(extra)
end

--- blink.cmp completion source factory.
---
--- Register the provider in your blink.cmp config:
---
---   sources = {
---     default = { "gdshader", ... },
---     providers = {
---       gdshader = { name = "GDShader", module = "gdshader_nvim" },
---     },
---   }
---
--- When blink instantiates the source it calls `require("gdshader_nvim").new()`.
function M.new()
    M.ensure_setup()

    return require("gdshader_nvim.completion").new()
end

return M
