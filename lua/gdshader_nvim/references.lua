local M = {}

local semantic_references = require("gdshader_nvim.semantic.references")

local util = require("gdshader_nvim.util")

local configured = false

------------------------------------------------------------
-- Current target
------------------------------------------------------------

local function current_target(bufnr)
    local cursor = vim.api.nvim_win_get_cursor(0)

    return semantic_references.target_at(bufnr, cursor[1] - 1, cursor[2])
end

------------------------------------------------------------
-- Build reference rows (shared by all pickers)
------------------------------------------------------------

local function build_items(bufnr, target, references)
    local filename = vim.api.nvim_buf_get_name(bufnr)

    local items = {}

    for _, reference in ipairs(references) do
        local text = reference.text:gsub("^%s+", ""):gsub("%s+$", "")

        table.insert(items, {
            filename = filename,

            lnum = reference.line + 1,

            col = reference.column + 1,

            text = (reference.declaration and "[declaration] " or "") .. text,
        })
    end

    return items
end

------------------------------------------------------------
-- Quickfix fallback
------------------------------------------------------------

local function show_quickfix(bufnr, target, references)
    vim.fn.setqflist({}, " ", {
        title = "GDShader references: " .. target.name,

        items = build_items(bufnr, target, references),
    })

    pcall(function()
        vim.cmd("copen")
    end)
end

------------------------------------------------------------
-- Telescope picker
--
-- Uses the user's own telescope (already configured in their
-- setup) so `gr`/`grr` feel native. Returns false if telescope
-- is unavailable so the caller can fall back to the quickfix list.
------------------------------------------------------------

local function show_telescope(bufnr, target, references)
    local ok_telescope, telescope = pcall(require, "telescope")

    if not ok_telescope or not telescope then
        return false
    end

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local items = build_items(bufnr, target, references)

    local previewer = conf.qflist_previewer or conf.grep_previewer

    pickers.new({}, {
        prompt_title = "GDShader references: " .. target.name,

        finder = finders.new_table({
            results = items,

            entry_maker = function(entry)
                return {
                    value = entry,

                    display = entry.text,

                    filename = entry.filename,

                    lnum = entry.lnum,

                    col = entry.col,
                }
            end,
        }),

        sorter = conf.generic_sorter({}),

        previewer = previewer,

        attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)

                local selection = action_state.get_selected_entry()

                if selection then
                    vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))

                    vim.api.nvim_win_set_cursor(0, {
                        selection.lnum,

                        math.max(0, selection.col - 1),
                    })
                end
            end)

            return true
        end,
    }):find()

    return true
end

------------------------------------------------------------
-- Show
------------------------------------------------------------

function M.show()
    local bufnr = vim.api.nvim_get_current_buf()

    if not util.is_supported(bufnr) then
        return
    end

    local target = current_target(bufnr)

    if not target then
        vim.notify("GDShader: no referenceable symbol under cursor", vim.log.levels.INFO)

        return
    end

    local references = semantic_references.find(bufnr, target)

    if #references == 0 then
        vim.notify("GDShader: no references found for " .. target.name, vim.log.levels.INFO)

        return
    end

    local picker = require("gdshader_nvim.config").get().references.picker

    if picker == "auto" then
        picker = pcall(require, "telescope") and "telescope" or "quickfix"
    end

    if picker == "telescope" and show_telescope(bufnr, target, references) then
        return
    end

    show_quickfix(bufnr, target, references)
end

------------------------------------------------------------
-- Attach
------------------------------------------------------------

function M.attach(bufnr)
    if not util.is_supported(bufnr) then
        return
    end

    if vim.b[bufnr].gdshader_nvim_references_attached then
        return
    end

    vim.b[bufnr].gdshader_nvim_references_attached = true

    vim.api.nvim_buf_create_user_command(bufnr, "GDShaderReferences", function()
        M.show()
    end, {
        desc = "Find GDShader references",
    })

    vim.keymap.set("n", "<Plug>(gdshader-nvim-references)", M.show, {
        buffer = bufnr,

        silent = true,

        desc = "GDShader references",
    })

    --------------------------------------------------------
    -- Neovim 0.11 LSP convention:
    -- grr = references
    --
    -- Also bind `gr`, which many configs map to telescope's
    -- LSP references picker — it has no data for a language
    -- without an LSP server, so we shadow it buffer-locally.
    --------------------------------------------------------

    util.maybe_set_keymap(bufnr, require("gdshader_nvim.config").get().keymaps.references, M.show, "GDShader references")

    --------------------------------------------------------
    -- 仅当 references 功能开启时才覆盖全局 `gr`
    -- （与 keymaps.references 开关保持一致）。
    --------------------------------------------------------

    if require("gdshader_nvim.config").get().features.references then
        util.maybe_set_keymap(bufnr, "gr", M.show, "GDShader references")
    end
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

    local group = vim.api.nvim_create_augroup("GDShaderNvimReferences", {
        clear = true,
    })

    vim.api.nvim_create_autocmd("FileType", {
        group = group,

        pattern = config.filetypes,

        callback = function(args)
            M.attach(args.buf)
        end,
    })

    local bufnr = vim.api.nvim_get_current_buf()

    if util.is_supported(bufnr) then
        M.attach(bufnr)
    end
end

return M
