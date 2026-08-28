------------------------------------------------------------
-- gdshader_blink
--
-- blink.cmp completion-source alias for gdshader-nvim-support.
--
-- blink.cmp looks up the provider module by the `module` field
-- configured in your blink.cmp `providers` table. The canonical
-- module is `gdshader_nvim` (used by the README/doc examples),
-- but many setups (including the bundled example config) point
-- `module` at `gdshader_blink`. This thin shim keeps both names
-- working so you do not have to edit your blink.cmp config.
--
-- blink.cmp calls `require("gdshader_blink").new(...)` to
-- instantiate the source; we delegate straight to the plugin.
------------------------------------------------------------

local M = {}

--- blink.cmp source factory.
---
--- @return table  A completion source instance (see gdshader_nvim.completion).
function M.new(...)
    return require("gdshader_nvim").new(...)
end

return M
