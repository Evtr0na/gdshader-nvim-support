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
--   * a string  -> set a buffer-local mapping (see below)
--   * false/nil -> do nothing (feature mapping disabled)
--
-- We only skip when the user has already bound `key` *buffer-locally*
-- in THIS buffer. Otherwise we set a buffer-local mapping. This is the
-- desired behaviour for a language with no LSP server: the mapping
-- shadows any global LSP keymap (e.g. telescope's `gd`/`gr`) inside
-- gdshader buffers, while other filetypes keep their LSP behaviour.
------------------------------------------------------------

function M.maybe_set_keymap(bufnr, key, fn, desc)
    if not key then
        return
    end

    local existing = nil

    pcall(function()
        existing = vim.fn.maparg(key, "n", false, true, bufnr)
    end)

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
