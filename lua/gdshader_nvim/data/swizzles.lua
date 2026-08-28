local M = {}

------------------------------------------------------------
-- 缓存
------------------------------------------------------------

local cache = {}

------------------------------------------------------------
-- 递归生成组合
------------------------------------------------------------

local function generate_combinations(chars, max_length, prefix, result)
    prefix = prefix or ""
    result = result or {}

    if #prefix > 0 then
        table.insert(result, prefix)
    end

    if #prefix >= max_length then
        return result
    end

    for _, char in ipairs(chars) do
        generate_combinations(chars, max_length, prefix .. char, result)
    end

    return result
end

------------------------------------------------------------
-- 根据 vec 长度生成 swizzle
------------------------------------------------------------

function M.for_size(size)
    if cache[size] then
        return cache[size]
    end

    if size < 2 or size > 4 then
        return {}
    end

    local groups = {
        { "x", "y", "z", "w" },
        { "r", "g", "b", "a" },
        { "s", "t", "p", "q" },
    }

    local result = {}

    for _, group in ipairs(groups) do
        local chars = {}

        for i = 1, size do
            table.insert(chars, group[i])
        end

        local combinations = generate_combinations(chars, 4)

        vim.list_extend(result, combinations)
    end

    cache[size] = result

    return result
end

return M
