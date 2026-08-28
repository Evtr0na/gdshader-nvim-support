local M = {}

local knowledge = require("gdshader_nvim.data.knowledge")

------------------------------------------------------------
-- Type lookup
--
-- Rebuilt lazily when the knowledge version changes, so
-- user-extended types are picked up.
------------------------------------------------------------

local type_set = nil

local built_version = -1

local function rebuild_types()
    type_set = {}

    local declared_types = knowledge.get("types") or {}

    for _, type_name in ipairs(declared_types) do
        type_set[type_name] = true
    end

    built_version = knowledge.version()
end

local function ensure_types()
    if built_version ~= knowledge.version() then
        rebuild_types()
    end
end

------------------------------------------------------------
-- Vector information
------------------------------------------------------------

local vector_info = {
    vec2 = {
        size = 2,
        family = "vec",
        scalar = "float",
    },

    vec3 = {
        size = 3,
        family = "vec",
        scalar = "float",
    },

    vec4 = {
        size = 4,
        family = "vec",
        scalar = "float",
    },

    ivec2 = {
        size = 2,
        family = "ivec",
        scalar = "int",
    },

    ivec3 = {
        size = 3,
        family = "ivec",
        scalar = "int",
    },

    ivec4 = {
        size = 4,
        family = "ivec",
        scalar = "int",
    },

    uvec2 = {
        size = 2,
        family = "uvec",
        scalar = "uint",
    },

    uvec3 = {
        size = 3,
        family = "uvec",
        scalar = "uint",
    },

    uvec4 = {
        size = 4,
        family = "uvec",
        scalar = "uint",
    },

    bvec2 = {
        size = 2,
        family = "bvec",
        scalar = "bool",
    },

    bvec3 = {
        size = 3,
        family = "bvec",
        scalar = "bool",
    },

    bvec4 = {
        size = 4,
        family = "bvec",
        scalar = "bool",
    },
}

------------------------------------------------------------
-- Matrix information
------------------------------------------------------------

local matrix_info = {
    mat2 = {
        size = 2,
        column = "vec2",
    },

    mat3 = {
        size = 3,
        column = "vec3",
    },

    mat4 = {
        size = 4,
        column = "vec4",
    },
}

------------------------------------------------------------
-- Scalar information
------------------------------------------------------------

local numeric_scalars = {
    int = true,
    uint = true,
    float = true,
}

------------------------------------------------------------
-- Public type API
------------------------------------------------------------

function M.is_type(type_name)
    ensure_types()

    return type_set[type_name] == true
end

function M.get_vector_info(type_name)
    return vector_info[type_name]
end

function M.get_vector_size(type_name)
    local info = vector_info[type_name]

    return info and info.size or nil
end

function M.is_numeric_scalar(type_name)
    return numeric_scalars[type_name] == true
end

function M.is_numeric_vector(type_name)
    local info = vector_info[type_name]

    if not info then
        return false
    end

    return numeric_scalars[info.scalar] == true
end

function M.is_numeric(type_name)
    return M.is_numeric_scalar(type_name) or M.is_numeric_vector(type_name)
end

------------------------------------------------------------
-- Index result
--
-- vec3[0] -> float
-- ivec4[0] -> int
-- mat4[0] -> vec4
------------------------------------------------------------

function M.get_index_result(type_name)
    local info = vector_info[type_name]

    if info then
        return info.scalar
    end

    local matrix = matrix_info[type_name]

    if matrix then
        return matrix.column
    end

    return nil
end
function M.is_matrix(type_name)
    return matrix_info[type_name] ~= nil
end

------------------------------------------------------------
-- Swizzle
------------------------------------------------------------

local swizzle_groups = {
    "xyzw",
    "rgba",
    "stpq",
}

local function is_valid_swizzle(member, vector_size)
    if #member < 1 or #member > 4 then
        return false
    end

    for _, group in ipairs(swizzle_groups) do
        local allowed = group:sub(1, vector_size)

        local valid = true

        for i = 1, #member do
            local char = member:sub(i, i)

            if not allowed:find(char, 1, true) then
                valid = false
                break
            end
        end

        if valid then
            return true
        end
    end

    return false
end

function M.get_swizzle_result(type_name, member)
    local info = vector_info[type_name]

    if not info then
        return nil
    end

    if not is_valid_swizzle(member, info.size) then
        return nil
    end

    --------------------------------------------------------
    -- vec3.x -> float
    --------------------------------------------------------

    if #member == 1 then
        return info.scalar
    end

    --------------------------------------------------------
    -- vec4.xyz -> vec3
    -- ivec4.xy -> ivec2
    --------------------------------------------------------

    return info.family .. tostring(#member)
end

------------------------------------------------------------
-- Texture sample result
------------------------------------------------------------

function M.get_sampled_vector_type(sampler_type)
    if not sampler_type then
        return nil
    end

    if sampler_type:match("^isampler") then
        return "ivec4"
    end

    if sampler_type:match("^usampler") then
        return "uvec4"
    end

    if sampler_type:match("^sampler") then
        return "vec4"
    end

    return nil
end

------------------------------------------------------------
-- Unary expressions
------------------------------------------------------------

function M.get_unary_result(operator, operand_type)
    if not operand_type then
        return nil
    end

    --------------------------------------------------------
    -- Logical not
    --------------------------------------------------------

    if operator == "!" then
        if operand_type == "bool" then
            return "bool"
        end

        return nil
    end

    --------------------------------------------------------
    -- Unary + / -
    --------------------------------------------------------

    if operator == "+" or operator == "-" then
        if M.is_numeric(operand_type) then
            return operand_type
        end

        if M.is_matrix(operand_type) then
            return operand_type
        end

        return nil
    end

    --------------------------------------------------------
    -- Bitwise not
    --------------------------------------------------------

    if operator == "~" then
        if operand_type == "int" or operand_type == "uint" then
            return operand_type
        end

        local info = vector_info[operand_type]

        if info and (info.scalar == "int" or info.scalar == "uint") then
            return operand_type
        end

        return nil
    end

    return nil
end

------------------------------------------------------------
-- Binary expressions
------------------------------------------------------------

function M.get_binary_result(left_type, operator, right_type)
    --------------------------------------------------------
    -- Unknown operand
    --------------------------------------------------------

    if not left_type or not right_type then
        return nil
    end

    --------------------------------------------------------
    -- Matrix arithmetic
    --
    -- mat4 + mat4
    -- mat4 - mat4
    --------------------------------------------------------

    if left_type == right_type and M.is_matrix(left_type) and (operator == "+" or operator == "-") then
        return left_type
    end

    --------------------------------------------------------
    -- Matrix * Matrix
    --------------------------------------------------------

    if operator == "*" and left_type == right_type and M.is_matrix(left_type) then
        return left_type
    end

    --------------------------------------------------------
    -- Matrix * scalar
    -- Matrix / scalar
    --------------------------------------------------------

    local left_matrix = matrix_info[left_type]

    if left_matrix and right_type == "float" and (operator == "*" or operator == "/") then
        return left_type
    end

    --------------------------------------------------------
    -- scalar * Matrix
    --------------------------------------------------------

    local right_matrix = matrix_info[right_type]

    if right_matrix and left_type == "float" and operator == "*" then
        return right_type
    end

    --------------------------------------------------------
    -- Matrix * Vector
    --
    -- mat4 * vec4 -> vec4
    -- mat3 * vec3 -> vec3
    --------------------------------------------------------

    if left_matrix and operator == "*" and right_type == left_matrix.column then
        return left_matrix.column
    end

    --------------------------------------------------------
    -- Vector * Matrix
    --------------------------------------------------------

    if right_matrix and operator == "*" and left_type == right_matrix.column then
        return right_matrix.column
    end

    --------------------------------------------------------
    -- Logical
    --------------------------------------------------------

    if operator == "&&" or operator == "||" then
        if left_type == "bool" and right_type == "bool" then
            return "bool"
        end

        return nil
    end

    --------------------------------------------------------
    -- Equality
    --------------------------------------------------------

    if operator == "==" or operator == "!=" then
        if left_type == right_type then
            return "bool"
        end

        return nil
    end

    --------------------------------------------------------
    -- Relational
    --------------------------------------------------------

    if operator == "<" or operator == "<=" or operator == ">" or operator == ">=" then
        if left_type == right_type and M.is_numeric_scalar(left_type) then
            return "bool"
        end

        return nil
    end

    --------------------------------------------------------
    -- Same-type arithmetic
    --------------------------------------------------------

    if operator == "+" or operator == "-" or operator == "*" or operator == "/" or operator == "%" then
        if left_type == right_type and M.is_numeric(left_type) then
            return left_type
        end
    end

    --------------------------------------------------------
    -- Vector * scalar
    -- Vector / scalar
    --------------------------------------------------------

    local left_vector = vector_info[left_type]

    if left_vector and right_type == left_vector.scalar and (operator == "*" or operator == "/") then
        return left_type
    end

    --------------------------------------------------------
    -- scalar * Vector
    --------------------------------------------------------

    local right_vector = vector_info[right_type]

    if right_vector and left_type == right_vector.scalar and operator == "*" then
        return right_type
    end

    return nil
end

------------------------------------------------------------
-- Ternary expression
------------------------------------------------------------

function M.get_ternary_result(condition_type, true_type, false_type)
    if condition_type ~= "bool" then
        return nil
    end

    if not true_type or not false_type then
        return nil
    end

    --------------------------------------------------------
    -- 第一阶段保持严格：
    --
    -- vec3 ? vec3 -> vec3
    -- float ? float -> float
    --------------------------------------------------------

    if true_type == false_type then
        return true_type
    end

    return nil
end

return M
