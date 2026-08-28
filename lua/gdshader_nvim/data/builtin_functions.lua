local knowledge = require("gdshader_nvim.data.knowledge")

local function same_as_argument(index)
    return {
        kind = "same_as_argument",
        index = index,
    }
end

local function fixed(type_name)
    return {
        kind = "fixed",
        type = type_name,
    }
end

local function sampled_vector(index)
    return {
        kind = "sampled_vector",
        index = index,
    }
end

local base = {

    --------------------------------------------------------
    -- Math
    --------------------------------------------------------

    {
        name = "abs",
        signature = "abs(x)",
        snippet = "abs(${1:x})",
        description = "Returns the absolute value of x.",
        return_type = same_as_argument(1),
    },

    {
        name = "min",
        signature = "min(a, b)",
        snippet = "min(${1:a}, ${2:b})",
        description = "Returns the minimum of a and b.",
        return_type = same_as_argument(1),
    },

    {
        name = "max",
        signature = "max(a, b)",
        snippet = "max(${1:a}, ${2:b})",
        description = "Returns the maximum of a and b.",
        return_type = same_as_argument(1),
    },

    {
        name = "clamp",
        signature = "clamp(x, minVal, maxVal)",
        snippet = "clamp(${1:x}, ${2:minVal}, ${3:maxVal})",
        description = "Constrains x to the specified range.",
        return_type = same_as_argument(1),
    },

    {
        name = "mix",
        signature = "mix(x, y, a)",
        snippet = "mix(${1:x}, ${2:y}, ${3:a})",
        description = "Performs linear interpolation between x and y.",
        return_type = same_as_argument(1),
    },

    {
        name = "step",
        signature = "step(edge, x)",
        snippet = "step(${1:edge}, ${2:x})",
        description = "Generates a step function.",
        return_type = same_as_argument(2),
    },

    {
        name = "smoothstep",
        signature = "smoothstep(edge0, edge1, x)",
        snippet = "smoothstep(${1:edge0}, ${2:edge1}, ${3:x})",
        description = "Performs smooth Hermite interpolation.",
        return_type = same_as_argument(3),
    },

    {
        name = "floor",
        signature = "floor(x)",
        snippet = "floor(${1:x})",
        description = "Returns the nearest integer less than or equal to x.",
        return_type = same_as_argument(1),
    },

    {
        name = "ceil",
        signature = "ceil(x)",
        snippet = "ceil(${1:x})",
        description = "Returns the nearest integer greater than or equal to x.",
        return_type = same_as_argument(1),
    },

    {
        name = "fract",
        signature = "fract(x)",
        snippet = "fract(${1:x})",
        description = "Returns the fractional part of x.",
        return_type = same_as_argument(1),
    },

    {
        name = "mod",
        signature = "mod(x, y)",
        snippet = "mod(${1:x}, ${2:y})",
        description = "Returns x modulo y.",
        return_type = same_as_argument(1),
    },

    --------------------------------------------------------
    -- Trigonometry
    --------------------------------------------------------

    {
        name = "sin",
        signature = "sin(angle)",
        snippet = "sin(${1:angle})",
        description = "Returns the sine of angle.",
        return_type = same_as_argument(1),
    },

    {
        name = "cos",
        signature = "cos(angle)",
        snippet = "cos(${1:angle})",
        description = "Returns the cosine of angle.",
        return_type = same_as_argument(1),
    },

    {
        name = "tan",
        signature = "tan(angle)",
        snippet = "tan(${1:angle})",
        description = "Returns the tangent of angle.",
        return_type = same_as_argument(1),
    },

    --------------------------------------------------------
    -- Vector
    --------------------------------------------------------

    {
        name = "length",
        signature = "length(x)",
        snippet = "length(${1:x})",
        description = "Returns the length of a vector.",
        return_type = fixed("float"),
    },

    {
        name = "distance",
        signature = "distance(p0, p1)",
        snippet = "distance(${1:p0}, ${2:p1})",
        description = "Returns the distance between two points.",
        return_type = fixed("float"),
    },

    {
        name = "dot",
        signature = "dot(x, y)",
        snippet = "dot(${1:x}, ${2:y})",
        description = "Returns the dot product of two vectors.",
        return_type = fixed("float"),
    },

    {
        name = "cross",
        signature = "cross(x, y)",
        snippet = "cross(${1:x}, ${2:y})",
        description = "Returns the cross product of two vec3 values.",
        return_type = same_as_argument(1),
    },

    {
        name = "normalize",
        signature = "normalize(x)",
        snippet = "normalize(${1:x})",
        description = "Returns a normalized vector.",
        return_type = same_as_argument(1),
    },

    {
        name = "reflect",
        signature = "reflect(I, N)",
        snippet = "reflect(${1:I}, ${2:N})",
        description = "Returns the reflection direction.",
        return_type = same_as_argument(1),
    },

    {
        name = "refract",
        signature = "refract(I, N, eta)",
        snippet = "refract(${1:I}, ${2:N}, ${3:eta})",
        description = "Returns the refraction direction.",
        return_type = same_as_argument(1),
    },

    --------------------------------------------------------
    -- Texture
    --------------------------------------------------------

    {
        name = "texture",
        signature = "texture(sampler, uv)",
        snippet = "texture(${1:sampler}, ${2:uv})",
        description = "Samples a texture.",
        return_type = sampled_vector(1),
    },

    {
        name = "textureLod",
        signature = "textureLod(sampler, uv, lod)",
        snippet = "textureLod(${1:sampler}, ${2:uv}, ${3:lod})",
        description = "Samples a texture at an explicit level of detail.",
        return_type = sampled_vector(1),
    },
}

return knowledge.register("builtin_functions", base)
