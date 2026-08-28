local M = {}

------------------------------------------------------------
-- Buffer semantic cache
--
-- 每个 buffer 根据 changedtick 自动失效。
------------------------------------------------------------

local buffers = {}

------------------------------------------------------------
-- Resolve buffer
------------------------------------------------------------

local function resolve_bufnr(bufnr)
    if not bufnr or bufnr == 0 then
        return vim.api.nvim_get_current_buf()
    end

    return bufnr
end

------------------------------------------------------------
-- 获取 buffer state
------------------------------------------------------------

local function get_state(bufnr)
    bufnr = resolve_bufnr(bufnr)

    --------------------------------------------------------
    -- buffer 已失效
    --------------------------------------------------------

    if not vim.api.nvim_buf_is_valid(bufnr) then
        buffers[bufnr] = nil

        return nil
    end

    local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)

    local state = buffers[bufnr]

    --------------------------------------------------------
    -- 第一次读取，或者 buffer 已发生变化
    --------------------------------------------------------

    if not state or state.changedtick ~= changedtick then
        state = {
            changedtick = changedtick,

            lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),

            values = {},
            has_value = {},
        }

        buffers[bufnr] = state
    end

    return state
end

------------------------------------------------------------
-- 获取当前 buffer 的源码行
--
-- 注意：
-- 返回值视为只读，不要直接修改。
------------------------------------------------------------

function M.get_lines(bufnr)
    local state = get_state(bufnr)

    if not state then
        return {}
    end

    return state.lines
end

------------------------------------------------------------
-- changedtick-aware memo
--
-- cache.memo(bufnr, "functions", function(lines)
--     return parse_functions(lines)
-- end)
--
-- nil 也可以被缓存，所以额外使用 has_value。
------------------------------------------------------------

function M.memo(bufnr, key, builder)
    local state = get_state(bufnr)

    if not state then
        return nil
    end

    if state.has_value[key] then
        return state.values[key]
    end

    local value = builder(state.lines)

    state.values[key] = value

    state.has_value[key] = true

    return value
end

------------------------------------------------------------
-- 手动清除某个 buffer
------------------------------------------------------------

function M.invalidate(bufnr)
    bufnr = resolve_bufnr(bufnr)

    buffers[bufnr] = nil
end

------------------------------------------------------------
-- 清除全部 cache
------------------------------------------------------------

function M.clear()
    buffers = {}
end

return M
