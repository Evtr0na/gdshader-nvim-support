local M = {}

------------------------------------------------------------
-- Default configuration
------------------------------------------------------------

local defaults = {
    --------------------------------------------------------
    -- File types handled by the plugin.
    -- Extend this if you add custom GDShader extensions.
    --------------------------------------------------------

    filetypes = {
        "gdshader",
        "gdshaderinc",
    },

    --------------------------------------------------------
    -- Feature toggles.
    -- completion requires blink.cmp; the rest are standalone.
    --------------------------------------------------------

    features = {
        completion = true,
        diagnostics = true,
        hover = true,
        definition = true,
        references = true,
        rename = true,
        color = true,
        format = true,
        template = true,
        semantic_tokens = true,
    },

    --------------------------------------------------------
    -- Diagnostics
    --------------------------------------------------------

    diagnostics = {
        debounce_ms = 150,
    },

    --------------------------------------------------------
    -- Keymaps.
    --
    -- Set to false to disable a mapping entirely, or to a
    -- string to use that key. Mappings are only set when the
    -- user has not already bound the key in the buffer.
    --------------------------------------------------------

    keymaps = {
        hover = "K",
        definition = "gd",
        references = "grr",
        rename = "grn",
        edit = false,   -- set to a key (e.g. "<leader>ce") to open the color editor
    },

    --------------------------------------------------------
    -- Completion
    --------------------------------------------------------

    completion = {
        trigger_characters = {
            ".",
            ":",
            ",",
            " ",
        },
    },

    --------------------------------------------------------
    -- Use the `gdshader` tree-sitter grammar for comment
    -- masking when available. Falls back to the built-in
    -- lexer otherwise.
    --------------------------------------------------------

    treesitter = true,

    --------------------------------------------------------
    -- Color preview
    --
    -- `decorate` adds an extmark swatch next to every vec3/vec4
    -- literal on change. Off by default to keep large buffers
    -- responsive; use :GDShaderColorDecoration to toggle.
    --------------------------------------------------------

    color = {
        -- Color editor backend for :GDShaderEditColor.
        --   "auto"    -> use ccc.nvim when installed, else builtin
        --   "builtin" -> always the built-in floating editor
        --   "ccc"     -> always ccc.nvim (falls back to builtin if absent)
        editor = "auto",

        decorate = false,
        debounce_ms = 200,

        -- The symbol drawn before each vec3/vec4 color literal when
        -- decoration is on. Change it (e.g. "■", "⬛", "#", "●") and
        -- re-toggle / re-edit to apply. Empty string falls back to "■".
        swatch = "■",
    },

    --------------------------------------------------------
    -- Semantic tokens (struct-name highlighting)
    --
    -- Mirrors the VSCode semantic-tokens provider: every use of a
    -- user-defined `struct` name (declaration, type reference,
    -- constructor call, return type) is highlighted. The highlight
    -- group links to `Type`; override it with
    -- `:highlight GdshaderStructType ...` if you want a custom look.
    --------------------------------------------------------

    semantic_tokens = {
        hl_group = "GdshaderStructType",
        debounce_ms = 200,
    },

    --------------------------------------------------------
    -- Formatting
    --
    -- `on_save` formats the buffer on `:w`. Leave off if you prefer
    -- conform.nvim's format_on_save (the plugin registers a
    -- `gdshader` conform formatter automatically).
    --------------------------------------------------------

    format = {
        on_save = false,
    },

    --------------------------------------------------------
    -- References picker
    --
    -- `picker` selects how `:GDShaderReferences` / `gr` / `grr`
    -- present results:
    --   "auto"      -> telescope when available, else quickfix
    --   "telescope" -> always telescope (falls back to quickfix)
    --   "quickfix"  -> always the quickfix list
    --------------------------------------------------------

    references = {
        picker = "auto",
    },

    --------------------------------------------------------
    -- Extra GDShader knowledge merged into the database.
    --
    -- See :help gdshader-nvim-support-extending for the schema.
    --------------------------------------------------------

    extra = {
        types = {},
        shader_types = {},
        builtin_functions = {},
        uniform_hints = {},
        builtin_variables = {},
        processors = {},
        render_modes = {},
    },
}

------------------------------------------------------------
-- State
------------------------------------------------------------

local config = vim.deepcopy(defaults)

M.defaults = vim.deepcopy(defaults)

local configured = false

------------------------------------------------------------
-- Deep merge (lists are concatenated, dicts are merged)
------------------------------------------------------------

local function is_list(value)
    return type(value) == "table" and vim.tbl_islist(value)
end

local function deep_merge(dst, src)
    for key, value in pairs(src) do
        if type(value) == "table" and type(dst[key]) == "table" then
            if is_list(value) and is_list(dst[key]) then
                for _, item in ipairs(value) do
                    table.insert(dst[key], item)
                end
            else
                deep_merge(dst[key], value)
            end
        else
            dst[key] = value
        end
    end

    return dst
end

------------------------------------------------------------
-- Setup
------------------------------------------------------------

function M.setup(opts)
    deep_merge(config, opts or {})

    --------------------------------------------------------
    -- Merge user knowledge into the database before anything
    -- reads it. Bumping the registry invalidates caches.
    --------------------------------------------------------

    if next(config.extra or {}) then
        require("gdshader_nvim.data.knowledge").extend(config.extra)
    end

    configured = true
end

function M.get()
    return config
end

function M.ensure()
    if not configured then
        M.setup()
    end
end

return M
