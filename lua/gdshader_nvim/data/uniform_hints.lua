local knowledge = require("gdshader_nvim.data.knowledge")

local base = {
    --------------------------------------------------------
    -- Color
    --------------------------------------------------------

    {
        name = "source_color",

        types = {
            vec3 = true,
            vec4 = true,
            sampler2D = true,
        },

        description = "Treat the value or texture as sRGB color data.",
    },

    --------------------------------------------------------
    -- Numeric
    --------------------------------------------------------

    {
        name = "hint_range",

        types = {
            int = true,
            float = true,
        },

        snippet = "hint_range(${1:0.0}, ${2:1.0}, ${3:0.01})",

        description = "Restrict the value to a range.",
    },

    {
        name = "hint_enum",

        types = {
            int = true,
        },

        snippet = 'hint_enum("${1:Option1}", "${2:Option2}")',

        description = "Display an integer as an enum in the Inspector.",
    },

    --------------------------------------------------------
    -- sampler2D
    --------------------------------------------------------

    {
        name = "hint_normal",

        types = {
            sampler2D = true,
        },

        description = "Use the texture as a normal map.",
    },

    {
        name = "hint_default_white",

        types = {
            sampler2D = true,
        },

        description = "Use opaque white as the default texture.",
    },

    {
        name = "hint_default_black",

        types = {
            sampler2D = true,
        },

        description = "Use opaque black as the default texture.",
    },

    {
        name = "hint_default_transparent",

        types = {
            sampler2D = true,
        },

        description = "Use transparent black as the default texture.",
    },

    {
        name = "hint_anisotropy",

        types = {
            sampler2D = true,
        },

        description = "Use the texture as a flow map.",
    },

    --------------------------------------------------------
    -- Roughness
    --------------------------------------------------------

    {
        name = "hint_roughness_r",
        types = { sampler2D = true },
    },

    {
        name = "hint_roughness_g",
        types = { sampler2D = true },
    },

    {
        name = "hint_roughness_b",
        types = { sampler2D = true },
    },

    {
        name = "hint_roughness_a",
        types = { sampler2D = true },
    },

    {
        name = "hint_roughness_normal",
        types = { sampler2D = true },
    },

    {
        name = "hint_roughness_gray",
        types = { sampler2D = true },
    },

    --------------------------------------------------------
    -- Screen textures
    --------------------------------------------------------

    {
        name = "hint_screen_texture",

        types = {
            sampler2D = true,
        },

        description = "Use this sampler as the screen texture.",
    },

    {
        name = "hint_depth_texture",

        types = {
            sampler2D = true,
        },

        description = "Use this sampler as the screen depth texture.",
    },

    {
        name = "hint_normal_roughness_texture",

        types = {
            sampler2D = true,
        },

        description = "Use this sampler as the normal-roughness texture.",
    },

    --------------------------------------------------------
    -- Filtering
    --------------------------------------------------------

    {
        name = "filter_nearest",
        types = { sampler2D = true },
    },

    {
        name = "filter_linear",
        types = { sampler2D = true },
    },

    {
        name = "filter_nearest_mipmap",
        types = { sampler2D = true },
    },

    {
        name = "filter_linear_mipmap",
        types = { sampler2D = true },
    },

    {
        name = "filter_nearest_mipmap_anisotropic",
        types = { sampler2D = true },
    },

    {
        name = "filter_linear_mipmap_anisotropic",
        types = { sampler2D = true },
    },

    --------------------------------------------------------
    -- Repeat
    --------------------------------------------------------

    {
        name = "repeat_enable",
        types = { sampler2D = true },
    },

    {
        name = "repeat_disable",
        types = { sampler2D = true },
    },

    --------------------------------------------------------
    -- Roughness (generic)
    --------------------------------------------------------

    {
        name = "hint_roughness",
        types = { sampler2D = true },
        description = "Use the texture as a generic roughness map.",
    },

    --------------------------------------------------------
    -- Instance index (applicable to any type)
    --------------------------------------------------------

    {
        name = "instance_index",
        types = { ["*"] = true },
        description = "Index of the current instance (for instance uniforms).",
    },
}

return knowledge.register("uniform_hints", base)
