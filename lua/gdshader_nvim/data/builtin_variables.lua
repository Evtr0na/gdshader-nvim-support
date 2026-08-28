local knowledge = require("gdshader_nvim.data.knowledge")

local function extend(base, extra)
    local result = {}

    for _, item in ipairs(base) do
        table.insert(result, item)
    end

    for _, item in ipairs(extra or {}) do
        table.insert(result, item)
    end

    return result
end

local particles_shared = {
    {
        name = "LIFETIME",
        type = "float",
        mode = "in",
        detail = "Particle lifetime.",
    },

    {
        name = "DELTA",
        type = "float",
        mode = "in",
        detail = "Particle process delta time.",
    },

    {
        name = "NUMBER",
        type = "uint",
        mode = "in",
        detail = "Unique particle number since emission began.",
    },

    {
        name = "INDEX",
        type = "uint",
        mode = "in",
        detail = "Particle index.",
    },

    {
        name = "EMISSION_TRANSFORM",
        type = "mat4",
        mode = "in",
        detail = "Emitter transform.",
    },

    {
        name = "RANDOM_SEED",
        type = "uint",
        mode = "in",
        detail = "Particle random seed.",
    },

    {
        name = "ACTIVE",
        type = "bool",
        mode = "inout",
        detail = "Whether the particle is active.",
    },

    {
        name = "COLOR",
        type = "vec4",
        mode = "inout",
        detail = "Particle color.",
    },

    {
        name = "VELOCITY",
        type = "vec3",
        mode = "inout",
        detail = "Particle velocity.",
    },

    {
        name = "TRANSFORM",
        type = "mat4",
        mode = "inout",
        detail = "Particle transform.",
    },

    {
        name = "CUSTOM",
        type = "vec4",
        mode = "inout",
        detail = "Custom particle data.",
    },

    {
        name = "MASS",
        type = "float",
        mode = "inout",
        detail = "Particle mass.",
    },

    {
        name = "USERDATA1",
        type = "vec4",
        mode = "in",
    },

    {
        name = "USERDATA2",
        type = "vec4",
        mode = "in",
    },

    {
        name = "USERDATA3",
        type = "vec4",
        mode = "in",
    },

    {
        name = "USERDATA4",
        type = "vec4",
        mode = "in",
    },

    {
        name = "USERDATA5",
        type = "vec4",
        mode = "in",
    },

    {
        name = "USERDATA6",
        type = "vec4",
        mode = "in",
    },

    {
        name = "FLAG_EMIT_POSITION",
        type = "uint",
        mode = "in",
    },

    {
        name = "FLAG_EMIT_ROT_SCALE",
        type = "uint",
        mode = "in",
    },

    {
        name = "FLAG_EMIT_VELOCITY",
        type = "uint",
        mode = "in",
    },

    {
        name = "FLAG_EMIT_COLOR",
        type = "uint",
        mode = "in",
    },

    {
        name = "FLAG_EMIT_CUSTOM",
        type = "uint",
        mode = "in",
    },

    {
        name = "EMITTER_VELOCITY",
        type = "vec3",
        mode = "in",
    },

    {
        name = "INTERPOLATE_TO_END",
        type = "float",
        mode = "in",
    },

    {
        name = "AMOUNT_RATIO",
        type = "uint",
        mode = "in",
    },
}

local base = {
    --------------------------------------------------------
    -- Global
    --
    -- 所有 processor / 自定义函数都可以使用
    --------------------------------------------------------

    global = {
        {
            name = "TIME",
            type = "float",
            mode = "in",
            detail = "Global time",
        },

        {
            name = "PI",
            type = "float",
            mode = "in",
            detail = "Pi constant",
        },

        {
            name = "TAU",
            type = "float",
            mode = "in",
            detail = "Tau constant",
        },

        {
            name = "E",
            type = "float",
            mode = "in",
            detail = "Euler's number",
        },
    },

    --------------------------------------------------------
    -- Spatial
    --------------------------------------------------------

    spatial = {
        ----------------------------------------------------
        -- vertex()
        ----------------------------------------------------

        vertex = {
            {
                name = "VERTEX",
                type = "vec3",
                mode = "inout",
            },

            {
                name = "NORMAL",
                type = "vec3",
                mode = "inout",
            },

            {
                name = "TANGENT",
                type = "vec3",
                mode = "inout",
            },

            {
                name = "BINORMAL",
                type = "vec3",
                mode = "inout",
            },

            {
                name = "POSITION",
                type = "vec4",
                mode = "out",
            },

            {
                name = "UV",
                type = "vec2",
                mode = "inout",
            },

            {
                name = "UV2",
                type = "vec2",
                mode = "inout",
            },

            {
                name = "COLOR",
                type = "vec4",
                mode = "inout",
            },

            {
                name = "INSTANCE_CUSTOM",
                type = "vec4",
                mode = "in",
            },

            {
                name = "INSTANCE_ID",
                type = "int",
                mode = "in",
            },

            {
                name = "VIEWPORT_SIZE",
                type = "vec2",
                mode = "in",
            },

            {
                name = "MODEL_MATRIX",
                type = "mat4",
                mode = "in",
            },

            {
                name = "VIEW_MATRIX",
                type = "mat4",
                mode = "in",
            },

            {
                name = "PROJECTION_MATRIX",
                type = "mat4",
                mode = "inout",
            },

            {
                name = "CAMERA_POSITION_WORLD",
                type = "vec3",
                mode = "in",
            },
        },

        ----------------------------------------------------
        -- fragment()
        ----------------------------------------------------

        fragment = {
            {
                name = "FRAGCOORD",
                type = "vec4",
                mode = "in",
            },

            {
                name = "FRONT_FACING",
                type = "bool",
                mode = "in",
            },

            {
                name = "VIEW",
                type = "vec3",
                mode = "in",
            },

            {
                name = "VERTEX",
                type = "vec3",
                mode = "in",
            },

            {
                name = "UV",
                type = "vec2",
                mode = "in",
            },

            {
                name = "UV2",
                type = "vec2",
                mode = "in",
            },

            {
                name = "COLOR",
                type = "vec4",
                mode = "in",
            },

            {
                name = "SCREEN_UV",
                type = "vec2",
                mode = "in",
            },

            {
                name = "NORMAL",
                type = "vec3",
                mode = "inout",
            },

            {
                name = "TANGENT",
                type = "vec3",
                mode = "inout",
            },

            {
                name = "BINORMAL",
                type = "vec3",
                mode = "inout",
            },

            {
                name = "ALBEDO",
                type = "vec3",
                mode = "out",
            },

            {
                name = "ALPHA",
                type = "float",
                mode = "out",
            },

            {
                name = "METALLIC",
                type = "float",
                mode = "out",
            },

            {
                name = "SPECULAR",
                type = "float",
                mode = "out",
            },

            {
                name = "ROUGHNESS",
                type = "float",
                mode = "out",
            },

            {
                name = "EMISSION",
                type = "vec3",
                mode = "out",
            },

            {
                name = "NORMAL_MAP",
                type = "vec3",
                mode = "out",
            },

            {
                name = "NORMAL_MAP_DEPTH",
                type = "float",
                mode = "out",
            },

            {
                name = "AO",
                type = "float",
                mode = "out",
            },

            {
                name = "RIM",
                type = "float",
                mode = "out",
            },

            {
                name = "RIM_TINT",
                type = "float",
                mode = "out",
            },

            {
                name = "CLEARCOAT",
                type = "float",
                mode = "out",
            },

            {
                name = "CLEARCOAT_ROUGHNESS",
                type = "float",
                mode = "out",
            },
        },

        ----------------------------------------------------
        -- light()
        ----------------------------------------------------

        light = {
            {
                name = "NORMAL",
                type = "vec3",
                mode = "in",
            },

            {
                name = "UV",
                type = "vec2",
                mode = "in",
            },

            {
                name = "UV2",
                type = "vec2",
                mode = "in",
            },

            {
                name = "VIEW",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT_COLOR",
                type = "vec3",
                mode = "in",
            },

            {
                name = "ATTENUATION",
                type = "float",
                mode = "in",
            },

            {
                name = "ALBEDO",
                type = "vec3",
                mode = "in",
            },

            {
                name = "METALLIC",
                type = "float",
                mode = "in",
            },

            {
                name = "ROUGHNESS",
                type = "float",
                mode = "in",
            },

            {
                name = "DIFFUSE_LIGHT",
                type = "vec3",
                mode = "out",
            },

            {
                name = "SPECULAR_LIGHT",
                type = "vec3",
                mode = "out",
            },
        },
    },

    --------------------------------------------------------
    -- CanvasItem
    --------------------------------------------------------

    canvas_item = {
        vertex = {
            {
                name = "VERTEX",
                type = "vec2",
                mode = "inout",
            },

            {
                name = "UV",
                type = "vec2",
                mode = "inout",
            },

            {
                name = "COLOR",
                type = "vec4",
                mode = "inout",
            },

            {
                name = "INSTANCE_CUSTOM",
                type = "vec4",
                mode = "in",
            },

            {
                name = "TEXTURE_PIXEL_SIZE",
                type = "vec2",
                mode = "in",
            },

            {
                name = "MODEL_MATRIX",
                type = "mat4",
                mode = "in",
            },

            {
                name = "CANVAS_MATRIX",
                type = "mat4",
                mode = "in",
            },

            {
                name = "SCREEN_MATRIX",
                type = "mat4",
                mode = "in",
            },
        },

        fragment = {
            {
                name = "FRAGCOORD",
                type = "vec4",
                mode = "in",
            },

            {
                name = "UV",
                type = "vec2",
                mode = "in",
            },

            {
                name = "SCREEN_UV",
                type = "vec2",
                mode = "in",
            },

            {
                name = "COLOR",
                type = "vec4",
                mode = "inout",
            },

            {
                name = "NORMAL",
                type = "vec3",
                mode = "inout",
            },

            {
                name = "NORMAL_MAP",
                type = "vec3",
                mode = "out",
            },

            {
                name = "NORMAL_MAP_DEPTH",
                type = "float",
                mode = "out",
            },

            {
                name = "VERTEX",
                type = "vec2",
                mode = "inout",
            },

            {
                name = "LIGHT_VERTEX",
                type = "vec3",
                mode = "inout",
            },

            {
                name = "TEXTURE_PIXEL_SIZE",
                type = "vec2",
                mode = "in",
            },
        },

        light = {
            {
                name = "FRAGCOORD",
                type = "vec4",
                mode = "in",
            },

            {
                name = "NORMAL",
                type = "vec3",
                mode = "in",
            },

            {
                name = "COLOR",
                type = "vec4",
                mode = "in",
            },

            {
                name = "UV",
                type = "vec2",
                mode = "in",
            },

            {
                name = "SCREEN_UV",
                type = "vec2",
                mode = "in",
            },

            {
                name = "LIGHT_COLOR",
                type = "vec4",
                mode = "in",
            },

            {
                name = "LIGHT_ENERGY",
                type = "float",
                mode = "in",
            },

            {
                name = "LIGHT_POSITION",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT_DIRECTION",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT_VERTEX",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT",
                type = "vec4",
                mode = "inout",
            },

            {
                name = "SHADOW_MODULATE",
                type = "vec4",
                mode = "out",
            },
        },
    },

    sky = {
        sky = {
            {
                name = "EYEDIR",
                type = "vec3",
                mode = "in",
            },

            {
                name = "SCREEN_UV",
                type = "vec2",
                mode = "in",
            },

            {
                name = "SKY_COORDS",
                type = "vec2",
                mode = "in",
            },

            {
                name = "HALF_RES_COLOR",
                type = "vec4",
                mode = "in",
            },

            {
                name = "QUARTER_RES_COLOR",
                type = "vec4",
                mode = "in",
            },

            {
                name = "COLOR",
                type = "vec3",
                mode = "out",
            },

            {
                name = "ALPHA",
                type = "float",
                mode = "out",
            },

            {
                name = "FOG",
                type = "vec4",
                mode = "out",
            },

            {
                name = "POSITION",
                type = "vec3",
                mode = "in",
            },

            {
                name = "RADIANCE",
                type = "samplerCube",
                mode = "in",
            },

            {
                name = "AT_HALF_RES_PASS",
                type = "bool",
                mode = "in",
            },

            {
                name = "AT_QUARTER_RES_PASS",
                type = "bool",
                mode = "in",
            },

            {
                name = "AT_CUBEMAP_PASS",
                type = "bool",
                mode = "in",
            },

            {
                name = "LIGHT0_ENABLED",
                type = "bool",
                mode = "in",
            },

            {
                name = "LIGHT0_DIRECTION",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT0_ENERGY",
                type = "float",
                mode = "in",
            },

            {
                name = "LIGHT0_COLOR",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT0_SIZE",
                type = "float",
                mode = "in",
            },

            {
                name = "LIGHT1_ENABLED",
                type = "bool",
                mode = "in",
            },

            {
                name = "LIGHT1_DIRECTION",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT1_ENERGY",
                type = "float",
                mode = "in",
            },

            {
                name = "LIGHT1_COLOR",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT1_SIZE",
                type = "float",
                mode = "in",
            },

            {
                name = "LIGHT2_ENABLED",
                type = "bool",
                mode = "in",
            },

            {
                name = "LIGHT2_DIRECTION",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT2_ENERGY",
                type = "float",
                mode = "in",
            },

            {
                name = "LIGHT2_COLOR",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT2_SIZE",
                type = "float",
                mode = "in",
            },

            {
                name = "LIGHT3_ENABLED",
                type = "bool",
                mode = "in",
            },

            {
                name = "LIGHT3_DIRECTION",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT3_ENERGY",
                type = "float",
                mode = "in",
            },

            {
                name = "LIGHT3_COLOR",
                type = "vec3",
                mode = "in",
            },

            {
                name = "LIGHT3_SIZE",
                type = "float",
                mode = "in",
            },
        },
    },

    fog = {
        fog = {
            {
                name = "WORLD_POSITION",
                type = "vec3",
                mode = "in",
            },

            {
                name = "OBJECT_POSITION",
                type = "vec3",
                mode = "in",
            },

            {
                name = "UVW",
                type = "vec3",
                mode = "in",
            },

            {
                name = "SIZE",
                type = "vec3",
                mode = "in",
            },

            {
                name = "SDF",
                type = "vec3",
                mode = "in",
            },

            {
                name = "ALBEDO",
                type = "vec3",
                mode = "out",
            },

            {
                name = "DENSITY",
                type = "float",
                mode = "out",
            },

            {
                name = "EMISSION",
                type = "vec3",
                mode = "out",
            },
        },
    },

    --
    particles = {
        start = extend(particles_shared, {
            {
                name = "RESTART_POSITION",
                type = "bool",
                mode = "in",
            },

            {
                name = "RESTART_ROT_SCALE",
                type = "bool",
                mode = "in",
            },

            {
                name = "RESTART_VELOCITY",
                type = "bool",
                mode = "in",
            },

            {
                name = "RESTART_COLOR",
                type = "bool",
                mode = "in",
            },

            {
                name = "RESTART_CUSTOM",
                type = "bool",
                mode = "in",
            },
        }),

        process = extend(particles_shared, {
            {
                name = "RESTART",
                type = "bool",
                mode = "in",
            },

            {
                name = "COLLIDED",
                type = "bool",
                mode = "in",
            },

            {
                name = "COLLISION_NORMAL",
                type = "vec3",
                mode = "in",
            },

            {
                name = "COLLISION_DEPTH",
                type = "float",
                mode = "in",
            },

            {
                name = "ATTRACTOR_FORCE",
                type = "vec3",
                mode = "in",
            },
        }),
    },
}

return knowledge.register("builtin_variables", base)
