local M = {}

local util = require("gdshader_nvim.util")
local token = require("gdshader_nvim.syntax.token")
local syntax_source = require("gdshader_nvim.syntax.source")

local TokenKind = token.Kind

local configured = false

local namespace = vim.api.nvim_create_namespace("gdshader_nvim_semantic_tokens")

-- Highlight group for struct type names. Default name is linked to the
-- built-in `Type` group in setup(); the user can override via the
-- `semantic_tokens.hl_group` config option.
local hl_group = "GdshaderStructType"

local function get_hl_group()
    local ok, cfg = pcall(require, "gdshader_nvim.config")

    if ok and cfg then
        return cfg.get().semantic_tokens.hl_group or hl_group
    end

    return hl_group
end

------------------------------------------------------------
-- Collect struct names declared in the buffer:
--
--   struct MyStruct { ... };
--   struct Point { ... };
--
-- Mirrors the VSCode semantic-tokens analysis, which highlights the
-- names of user-defined structs wherever they are used as a type.
------------------------------------------------------------

local function collect_struct_names(tokens)
    local names = {}
    local expect_name = false

    for _, tok in ipairs(tokens) do
        if token.is_comment(tok) then
            -- comments never separate `struct` from its name
        elseif tok.kind == TokenKind.KEYWORD and tok.value == "struct" then
            expect_name = true
        elseif expect_name then
            if tok.kind == TokenKind.IDENTIFIER then
                names[tok.value] = true
            end

            expect_name = false
        end
    end

    return names
end

------------------------------------------------------------
-- Highlight every identifier token whose value is a struct name,
-- except member access (`obj.field` where `field` happens to match).
------------------------------------------------------------

local function apply_highlights(bufnr, tokens, names)
    local prev = nil
    local group = get_hl_group()

    for _, tok in ipairs(tokens) do
        if not token.is_comment(tok) then
            if tok.kind == TokenKind.IDENTIFIER and names[tok.value] then
                if not prev or prev.value ~= "." then
                    pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, tok.line, tok.column, {
                        end_col = tok.column + #tok.value,

                        hl_group = group,

                        priority = 120,
                    })
                end
            end

            prev = tok
        end
    end
end

------------------------------------------------------------
-- Refresh (idempotent)
------------------------------------------------------------

function M.refresh(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if not util.is_supported(bufnr) then
        return
    end

    local config = require("gdshader_nvim.config").get()

    if not config.features.semantic_tokens then
        return
    end

    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

    local lexed = syntax_source.get_lexed(bufnr)

    local tokens = lexed.tokens or {}

    if #tokens == 0 then
        return
    end

    local names = collect_struct_names(tokens)

    if not next(names) then
        return
    end

    apply_highlights(bufnr, tokens, names)
end

------------------------------------------------------------
-- Attach
------------------------------------------------------------

function M.attach(bufnr)
    if not util.is_supported(bufnr) then
        return
    end

    if vim.b[bufnr].gdshader_nvim_semantic_tokens_attached then
        return
    end

    vim.b[bufnr].gdshader_nvim_semantic_tokens_attached = true

    M.refresh(bufnr)
end

------------------------------------------------------------
-- Setup
-----------------------------------------------------------

function M.setup()
    if configured then
        return
    end

    configured = true

    --------------------------------------------------------
    -- Link the highlight group to `Type` (colorscheme aware).
    -- Users can override with `:highlight GdshaderStructType ...`
    -- (or whichever group the `semantic_tokens.hl_group` option names).
    --------------------------------------------------------

    pcall(vim.api.nvim_set_hl, 0, get_hl_group(), { link = "Type" })

    local config = require("gdshader_nvim.config").get()

    local group = vim.api.nvim_create_augroup("GDShaderNvimSemanticTokens", {
        clear = true,
    })

    vim.api.nvim_create_autocmd("FileType", {
        group = group,

        pattern = config.filetypes,

        callback = function(args)
            M.attach(args.buf)
        end,
    })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave", "BufWinEnter" }, {
        group = group,

        pattern = "*." .. table.concat(config.filetypes, ",*."),

        callback = function(args)
            if not util.is_supported(args.buf) then
                return
            end

            if not require("gdshader_nvim.config").get().features.semantic_tokens then
                return
            end

            vim.defer_fn(function()
                if vim.api.nvim_buf_is_valid(args.buf) then
                    M.refresh(args.buf)
                end
            end, require("gdshader_nvim.config").get().semantic_tokens.debounce_ms or 200)
        end,
    })

    --------------------------------------------------------
    -- setup() may run after a gdshader buffer is already open.
    --------------------------------------------------------

    local bufnr = vim.api.nvim_get_current_buf()

    if util.is_supported(bufnr) then
        M.attach(bufnr)
    end
end

return M
