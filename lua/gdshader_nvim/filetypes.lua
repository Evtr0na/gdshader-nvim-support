local M = {}

local configured = false

------------------------------------------------------------
-- Filetype detection
--
-- Registers `.gdshader` / `.gdshaderinc` extensions. If you use
-- a different extension, add it via the `filetypes` config option
-- (only the base name is matched against the registered set).
------------------------------------------------------------

function M.setup()
    if configured then
        return
    end

    configured = true

    local config = require("gdshader_nvim.config").get()

    local extensions = {}

    for _, ft in ipairs(config.filetypes) do
        if ft == "gdshader" then
            extensions.gdshader = "gdshader"
        elseif ft == "gdshaderinc" then
            extensions.gdshaderinc = "gdshaderinc"
        end
    end

    if next(extensions) then
        pcall(vim.filetype.add, {
            extension = extensions,
        })
    end
end

return M
