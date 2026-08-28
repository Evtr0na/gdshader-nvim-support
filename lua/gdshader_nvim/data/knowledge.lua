------------------------------------------------------------
-- Knowledge database
--
-- Single source of truth for the GDShader knowledge base.
-- Data modules register their base tables here and return the
-- live, mutable table, so consumer modules (which build lookup
-- sets from the data) can detect changes via `version()`.
------------------------------------------------------------

local M = {}

local data = {}

local version = 0

local base_loaded = false

------------------------------------------------------------
-- Ensure the base knowledge tables are registered.
--
-- Data modules register themselves via `register()` the first
-- time they are required. Calling this up-front guarantees the
-- database is populated before any lookup or extension, so that
-- `extend()` merges into the real base instead of overwriting it.
------------------------------------------------------------

function M.ensure_base()
    if base_loaded then
        return
    end

    base_loaded = true

    for _, name in ipairs({
        "types",
        "shader_types",
        "builtin_functions",
        "uniform_hints",
        "builtin_variables",
        "processors",
        "render_modes",
    }) do
        pcall(require, "gdshader_nvim.data." .. name)
    end
end

------------------------------------------------------------
-- Register a base table and return the live reference.
------------------------------------------------------------

function M.register(key, base)
    M.ensure_base()

    data[key] = vim.deepcopy(base)

    return data[key]
end

function M.get(key)
    M.ensure_base()

    return data[key]
end

------------------------------------------------------------
-- Version bump — invalidates consumer lookup caches.
------------------------------------------------------------

function M.bump()
    version = version + 1
end

function M.version()
    return version
end

------------------------------------------------------------
-- Extend the knowledge base with user data.
--
-- Lists are concatenated; dictionaries are merged recursively.
-- After merging, the version is bumped so cached lookups rebuild.
------------------------------------------------------------

local islist = vim.islist or vim.tbl_islist

local function is_list(value)
    return type(value) == "table" and islist(value)
end

local function deep_extend(dst, src)
    for key, value in pairs(src) do
        if type(value) == "table" and type(dst[key]) == "table" then
            if is_list(value) and is_list(dst[key]) then
                for _, item in ipairs(value) do
                    table.insert(dst[key], item)
                end
            else
                deep_extend(dst[key], value)
            end
        else
            dst[key] = value
        end
    end
end

function M.extend(extra)
    M.ensure_base()

    if not extra then
        return
    end

    deep_extend(data, extra)

    M.bump()
end

return M
