local M = {}

------------------------------------------------------------
-- GDShader hint comment scanner
--
-- Mirrors gdshader-src/src/parser/hint-scanner.ts. Extracts
-- the special `#gdshader-hint-*` comments and `#include` /
-- `#define` information from raw source text.
------------------------------------------------------------

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_def_hint(raw, line)
    raw = trim(raw):gsub(";%s*$", "")

    --------------------------------------------------------
    -- function: TYPE NAME(PARAMS)
    --------------------------------------------------------

    local type_name, name, params_str = raw:match("^(%w+)%s+(%w+)%s*%(([^)]*)%)")

    if type_name and name then
        local parameters = {}

        if params_str and params_str ~= "" then
            for part in params_str:gmatch("[^,]+") do
                local words = {}

                for w in part:gmatch("%S+") do
                    table.insert(words, w)
                end

                local pname = words[#words]
                local ptype = words[#words - 1] or "any"
                local qualifier = table.concat({ (table.unpack or unpack)(words, 1, math.max(0, #words - 2)) }, " ")

                table.insert(parameters, {
                    name = pname,
                    typeName = ptype,
                    qualifier = qualifier,
                })
            end
        end

        return {
            line = line,
            raw = raw,
            name = name,
            typeName = type_name,
            isFunction = true,
            signature = type_name .. " " .. name .. "(" .. params_str .. ")",
            parameters = parameters,
        }
    end

    --------------------------------------------------------
    -- variable: TYPE NAME
    --------------------------------------------------------

    local vtype, vname = raw:match("^(%w+)%s+(%w+)")

    if vtype and vname then
        return {
            line = line,
            raw = raw,
            name = vname,
            typeName = vtype,
            isFunction = false,
        }
    end

    return nil
end

local function parse_define_hint(raw, line)
    raw = trim(raw)

    local name = raw:match("^(%w+)")

    if not name then
        return nil
    end

    local rest = raw:sub(#name + 1)

    local is_function = false
    local parameters
    local body

    if rest:match("^%s*%(") then
        local p_end = rest:find("%)")

        if p_end then
            is_function = true

            local p_str = rest:sub(2, p_end - 1)

            parameters = {}

            for part in p_str:gmatch("[^,]+") do
                table.insert(parameters, trim(part))
            end

            body = trim(rest:sub(p_end + 1))
        end
    else
        body = trim(rest)
    end

    return {
        line = line,
        name = name,
        isFunction = is_function,
        parameters = parameters,
        body = body,
        origin = "hint",
    }
end

------------------------------------------------------------
-- Include hint lookup for a single #include line (+ next line)
------------------------------------------------------------

function M.include_hints(current_line, next_line)
    local result = { ignore = false, redirect = nil }

    local function check(line)
        if not line then
            return
        end

        if line:match("#gdshader%-hint%-ignore") then
            result.ignore = true
        end

        local redirect = line:match("#gdshader%-hint%-redirection%s*:%s*(%S+)")

        if redirect then
            result.redirect = redirect
        end
    end

    check(current_line)

    --------------------------------------------------------
    -- Only treat the next line as a hint when it is a comment,
    -- so a following #include directive is never mistaken.
    --------------------------------------------------------

    if next_line and (next_line:match("^%s*//") or next_line:match("^%s*/%*")) then
        check(next_line)
    end

    return result
end

------------------------------------------------------------
-- Scan
------------------------------------------------------------

function M.scan(source)
    local lines = {}

    for line in (source .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end

    local includes = {}
    local type_hints = {}
    local def_hints = {}
    local macros = {}

    for i, raw_line in ipairs(lines) do
        local line = raw_line:gsub("\r$", "")
        local trimmed = trim(line)

        local handled = false

        --------------------------------------------------------
        -- #define (with trailing \ continuation)
        --------------------------------------------------------

        local define_match = trimmed:match("^#%s*define%s+(%S.*)$")

        if define_match then
            local macro_name = define_match:match("^(%w+)")
            local rest = define_match:sub(#macro_name + 1)
            local is_function = false
            local parameters
            local body = rest

            if rest:match("^%s*%(") then
                local p_end = rest:find("%)")

                if p_end then
                    is_function = true

                    local p_str = rest:sub(2, p_end - 1)

                    parameters = {}

                    for part in p_str:gmatch("[^,]+") do
                        table.insert(parameters, trim(part))
                    end

                    body = trim(rest:sub(p_end + 1))
                end
            end

            table.insert(macros, {
                name = macro_name,
                line = i - 1,
                isFunction = is_function,
                parameters = parameters,
                body = body,
                origin = "define",
            })

            handled = true
        end

        --------------------------------------------------------
        -- #include
        --------------------------------------------------------

        if not handled then
            local include_match = trimmed:match('^#include%s+"([^"]+)"')

            if include_match then
                local path = include_match
                local is_res = path:sub(1, 6) == "res://"

                local next_line = lines[i + 1]

                local include_hints = M.include_hints(line, next_line)

                table.insert(includes, {
                    line = i - 1,
                    path = path,
                    isResPath = is_res,
                    isIgnored = include_hints.ignore,
                    redirectPath = include_hints.redirect,
                })

                handled = true
            end
        end

        --------------------------------------------------------
        -- Hint comments
        --------------------------------------------------------

        if not handled then
            ----------------------------------------------------
            -- // #gdshader-hint-type:TYPE  (and block comment form)
            ----------------------------------------------------

            local line_type = trimmed:match("//%s*#gdshader%-hint%-type%s*:%s*(%w+)")
                or line:match("%/%*%s*#gdshader%-hint%-type%s*:%s*(%w+)%s*%*%/")

            if line_type then
                table.insert(type_hints, { line = i - 1, typeName = line_type })
            end

            ----------------------------------------------------
            -- // #gdshader-hint-define:...  (and block comment form)
            ----------------------------------------------------

            local line_define = trimmed:match("//%s*#gdshader%-hint%-define%s*:%s*(.+)")
                or line:match("%/%*%s*#gdshader%-hint%-define%s*:%s*(.-)%s*%*%/")

            if line_define then
                local m = parse_define_hint(trim(line_define), i - 1)

                if m then
                    table.insert(macros, m)
                end
            else
                --------------------------------------------------
                -- // #gdshader-hint-(declare|def):...  (and block form)
                --------------------------------------------------

                local def_raw = trimmed:match("//%s*#gdshader%-hint%-(declare|def)%s*:%s*(.+)")
                    or line:match("%/%*%s*#gdshader%-hint%-(declare|def)%s*:%s*(.-)%s*%*%/")

                if def_raw then
                    local m = parse_def_hint(trim(def_raw), i - 1)

                    if m then
                        table.insert(def_hints, m)
                    end
                end
            end
        end
    end

    return {
        includes = includes,
        typeHints = type_hints,
        defHints = def_hints,
        macros = macros,
    }
end

return M
