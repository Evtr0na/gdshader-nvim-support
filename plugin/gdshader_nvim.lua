------------------------------------------------------------
-- Early filetype detection
--
-- Registers the `.gdshader` / `.gdshaderinc` extensions so the
-- editor recognises GDShader files even before the plugin's
-- `setup()` runs. Feature wiring still happens in `setup()`.
------------------------------------------------------------

pcall(function()
    require("gdshader_nvim.filetypes").setup()
end)
