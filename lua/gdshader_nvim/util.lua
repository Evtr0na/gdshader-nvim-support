local M = {}

------------------------------------------------------------
-- Supported buffer
--
-- True when the buffer's filetype is one handled by the plugin.
------------------------------------------------------------

function M.is_supported(bufnr)
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
-- Buffer-local keymap
--
-- `key` may be:
--   * a string  -> set only if the user has not already mapped it
--   * false/nil -> do nothing (feature mapping disabled)
------------------------------------------------------------

function M.maybe_set_keymap(bufnr, key, fn, desc)
    if not key then
        return
    end

    local existing = vim.fn.maparg(key, "n", false, true)

    if type(existing) == "table" and not vim.tbl_isempty(existing) then
        return
    end

    vim.keymap.set("n", key, fn, {
        buffer = bufnr,

        silent = true,

        desc = desc,
    })
end

return M
