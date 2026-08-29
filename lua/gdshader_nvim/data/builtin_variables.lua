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
                name = "VIEWPORT_SIZE",
                type = "vec2",
                mode = "in",
                detail = "Viewport size (pixels).",
            },
            {
                name = "VIEW_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "View matrix (world -> view).",
            },
            {
                name = "INV_VIEW_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Inverse view matrix (view -> world).",
            },
            {
                name = "MAIN_CAM_INV_VIEW_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Main camera inverse view matrix (view -> world).",
            },
            {
                name = "INV_PROJECTION_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Inverse projection matrix (clip -> view).",
            },
            {
                name = "NODE_POSITION_WORLD",
                type = "vec3",
                mode = "in",
                detail = "Node world position.",
            },
            {
                name = "NODE_POSITION_VIEW",
                type = "vec3",
                mode = "in",
                detail = "Node view-space position.",
            },
            {
                name = "CAMERA_POSITION_WORLD",
                type = "vec3",
                mode = "in",
                detail = "Camera world position.",
            },
            {
                name = "CAMERA_DIRECTION_WORLD",
                type = "vec3",
                mode = "in",
                detail = "Camera forward direction.",
            },
            {
                name = "CAMERA_VISIBLE_LAYERS",
                type = "uint",
                mode = "in",
                detail = "Camera visible layers.",
            },
            {
                name = "INSTANCE_ID",
                type = "int",
                mode = "in",
                detail = "Instance ID.",
            },
            {
                name = "INSTANCE_CUSTOM",
                type = "vec4",
                mode = "in",
                detail = "Instance custom data.",
            },
            {
                name = "VIEW_INDEX",
                type = "int",
                mode = "in",
                detail = "Current rendering view index.",
            },
            {
                name = "VIEW_MONO_LEFT",
                type = "int",
                mode = "in",
                detail = "Mono / left-eye constant, always 0.",
            },
            {
                name = "VIEW_RIGHT",
                type = "int",
                mode = "in",
                detail = "Right-eye constant, always 1.",
            },
            {
                name = "EYE_OFFSET",
                type = "vec3",
                mode = "in",
                detail = "Eye offset (multi-view rendering).",
            },
            {
                name = "VERTEX",
                type = "vec3",
                mode = "inout",
                detail = "Vertex position (model space).",
            },
            {
                name = "VERTEX_ID",
                type = "int",
                mode = "in",
                detail = "Index of the vertex in the buffer.",
            },
            {
                name = "NORMAL",
                type = "vec3",
                mode = "inout",
                detail = "Vertex normal (model space).",
            },
            {
                name = "TANGENT",
                type = "vec3",
                mode = "inout",
                detail = "Vertex tangent (model space).",
            },
            {
                name = "BINORMAL",
                type = "vec3",
                mode = "inout",
                detail = "Vertex binormal (model space).",
            },
            {
                name = "POSITION",
                type = "vec4",
                mode = "out",
                detail = "Clip-space position (override). Writing discards VERTEX.",
            },
            {
                name = "UV",
                type = "vec2",
                mode = "inout",
                detail = "UV channel 1.",
            },
            {
                name = "UV2",
                type = "vec2",
                mode = "inout",
                detail = "UV channel 2.",
            },
            {
                name = "COLOR",
                type = "vec4",
                mode = "inout",
                detail = "Vertex color.",
            },
            {
                name = "ROUGHNESS",
                type = "float",
                mode = "out",
                detail = "Vertex lighting roughness.",
            },
            {
                name = "POINT_SIZE",
                type = "float",
                mode = "inout",
                detail = "Point size when rendering points.",
            },
            {
                name = "MODELVIEW_MATRIX",
                type = "mat4",
                mode = "inout",
                detail = "Model-view matrix (model -> view).",
            },
            {
                name = "MODELVIEW_NORMAL_MATRIX",
                type = "mat3",
                mode = "inout",
                detail = "Model-view normal matrix.",
            },
            {
                name = "MODEL_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Model matrix (model -> world).",
            },
            {
                name = "MODEL_NORMAL_MATRIX",
                type = "mat3",
                mode = "in",
                detail = "Model normal matrix (model -> world).",
            },
            {
                name = "PROJECTION_MATRIX",
                type = "mat4",
                mode = "inout",
                detail = "Projection matrix (view -> clip).",
            },
            {
                name = "BONE_INDICES",
                type = "uvec4",
                mode = "in",
                detail = "Bone indices.",
            },
            {
                name = "BONE_WEIGHTS",
                type = "vec4",
                mode = "in",
                detail = "Bone weights.",
            },
            {
                name = "CUSTOM0",
                type = "vec4",
                mode = "in",
                detail = "Custom vertex data 0.",
            },
            {
                name = "CUSTOM1",
                type = "vec4",
                mode = "in",
                detail = "Custom vertex data 1.",
            },
            {
                name = "CUSTOM2",
                type = "vec4",
                mode = "in",
                detail = "Custom vertex data 2.",
            },
            {
                name = "CUSTOM3",
                type = "vec4",
                mode = "in",
                detail = "Custom vertex data 3.",
            },
            {
                name = "OUTPUT_IS_SRGB",
                type = "bool",
                mode = "in",
                detail = "Whether the output is sRGB.",
            },
            {
                name = "TIME",
                type = "float",
                mode = "in",
                detail = "Global time (seconds).",
            },
        },

        ----------------------------------------------------
        -- fragment()
        ----------------------------------------------------

        fragment = {
            {
                name = "VIEWPORT_SIZE",
                type = "vec2",
                mode = "in",
                detail = "Viewport size (pixels).",
            },
            {
                name = "FRAGCOORD",
                type = "vec4",
                mode = "in",
                detail = "Fragment coordinate (screen space).",
            },
            {
                name = "FRONT_FACING",
                type = "bool",
                mode = "in",
                detail = "Whether the fragment faces the camera.",
            },
            {
                name = "VIEW",
                type = "vec3",
                mode = "in",
                detail = "View direction (view space).",
            },
            {
                name = "UV",
                type = "vec2",
                mode = "in",
                detail = "UV channel 1.",
            },
            {
                name = "UV2",
                type = "vec2",
                mode = "in",
                detail = "UV channel 2.",
            },
            {
                name = "COLOR",
                type = "vec4",
                mode = "in",
                detail = "Interpolated vertex color.",
            },
            {
                name = "POINT_COORD",
                type = "vec2",
                mode = "in",
                detail = "Point sprite coordinate.",
            },
            {
                name = "MODEL_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Model matrix (model -> world).",
            },
            {
                name = "MODEL_NORMAL_MATRIX",
                type = "mat3",
                mode = "in",
                detail = "Model normal matrix (model -> world).",
            },
            {
                name = "VIEW_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "View matrix (world -> view).",
            },
            {
                name = "INV_VIEW_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Inverse view matrix (view -> world).",
            },
            {
                name = "PROJECTION_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Projection matrix (view -> clip).",
            },
            {
                name = "INV_PROJECTION_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Inverse projection matrix (clip -> view).",
            },
            {
                name = "NODE_POSITION_WORLD",
                type = "vec3",
                mode = "in",
                detail = "Node world position.",
            },
            {
                name = "NODE_POSITION_VIEW",
                type = "vec3",
                mode = "in",
                detail = "Node view-space position.",
            },
            {
                name = "CAMERA_POSITION_WORLD",
                type = "vec3",
                mode = "in",
                detail = "Camera world position.",
            },
            {
                name = "CAMERA_DIRECTION_WORLD",
                type = "vec3",
                mode = "in",
                detail = "Camera direction.",
            },
            {
                name = "CAMERA_VISIBLE_LAYERS",
                type = "uint",
                mode = "in",
                detail = "Camera visible layers.",
            },
            {
                name = "VERTEX",
                type = "vec3",
                mode = "in",
                detail = "Vertex position (view space).",
            },
            {
                name = "LIGHT_VERTEX",
                type = "vec3",
                mode = "inout",
                detail = "Writable VERTEX for lighting/shadow changes.",
            },
            {
                name = "VIEW_INDEX",
                type = "int",
                mode = "in",
                detail = "Current rendering view index.",
            },
            {
                name = "VIEW_MONO_LEFT",
                type = "int",
                mode = "in",
                detail = "Mono / left-eye constant.",
            },
            {
                name = "VIEW_RIGHT",
                type = "int",
                mode = "in",
                detail = "Right-eye constant.",
            },
            {
                name = "EYE_OFFSET",
                type = "vec3",
                mode = "in",
                detail = "Eye offset.",
            },
            {
                name = "SCREEN_UV",
                type = "vec2",
                mode = "in",
                detail = "Screen UV coordinate.",
            },
            {
                name = "DEPTH",
                type = "float",
                mode = "out",
                detail = "Custom depth (depth override).",
            },
            {
                name = "NORMAL",
                type = "vec3",
                mode = "inout",
                detail = "Fragment normal (view space).",
            },
            {
                name = "TANGENT",
                type = "vec3",
                mode = "inout",
                detail = "Fragment tangent (view space).",
            },
            {
                name = "BINORMAL",
                type = "vec3",
                mode = "inout",
                detail = "Fragment binormal (view space).",
            },
            {
                name = "NORMAL_MAP",
                type = "vec3",
                mode = "out",
                detail = "Normal map (tangent space).",
            },
            {
                name = "NORMAL_MAP_DEPTH",
                type = "float",
                mode = "out",
                detail = "Normal map depth.",
            },
            {
                name = "ALBEDO",
                type = "vec3",
                mode = "out",
                detail = "Albedo color (default white).",
            },
            {
                name = "ALPHA",
                type = "float",
                mode = "out",
                detail = "Alpha value. Writing enters the transparent pipeline.",
            },
            {
                name = "ALPHA_SCISSOR_THRESHOLD",
                type = "float",
                mode = "out",
                detail = "Alpha scissor threshold.",
            },
            {
                name = "ALPHA_HASH_SCALE",
                type = "float",
                mode = "out",
                detail = "Alpha hash scale.",
            },
            {
                name = "ALPHA_ANTIALIASING_EDGE",
                type = "float",
                mode = "out",
                detail = "Alpha anti-aliasing edge.",
            },
            {
                name = "ALPHA_TEXTURE_COORDINATE",
                type = "vec2",
                mode = "out",
                detail = "Alpha coverage texture coordinate.",
            },
            {
                name = "PREMUL_ALPHA_FACTOR",
                type = "float",
                mode = "out",
                detail = "Premultiplied alpha factor.",
            },
            {
                name = "METALLIC",
                type = "float",
                mode = "out",
                detail = "Metallic.",
            },
            {
                name = "SPECULAR",
                type = "float",
                mode = "out",
                detail = "Specular (default 0.5).",
            },
            {
                name = "ROUGHNESS",
                type = "float",
                mode = "out",
                detail = "Roughness.",
            },
            {
                name = "RIM",
                type = "float",
                mode = "out",
                detail = "Rim lighting strength.",
            },
            {
                name = "RIM_TINT",
                type = "float",
                mode = "out",
                detail = "Rim lighting tint.",
            },
            {
                name = "CLEARCOAT",
                type = "float",
                mode = "out",
                detail = "Clearcoat layer strength.",
            },
            {
                name = "CLEARCOAT_GLOSS",
                type = "float",
                mode = "out",
                detail = "Clearcoat layer gloss.",
            },
            {
                name = "ANISOTROPY",
                type = "float",
                mode = "out",
                detail = "Anisotropy.",
            },
            {
                name = "ANISOTROPY_FLOW",
                type = "vec2",
                mode = "out",
                detail = "Anisotropy flow direction.",
            },
            {
                name = "SSS_STRENGTH",
                type = "float",
                mode = "out",
                detail = "Subsurface scattering strength.",
            },
            {
                name = "SSS_TRANSMITTANCE_COLOR",
                type = "vec4",
                mode = "out",
                detail = "Subsurface scattering transmittance color.",
            },
            {
                name = "SSS_TRANSMITTANCE_DEPTH",
                type = "float",
                mode = "out",
                detail = "Subsurface scattering transmittance depth.",
            },
            {
                name = "SSS_TRANSMITTANCE_BOOST",
                type = "float",
                mode = "out",
                detail = "Subsurface scattering transmittance boost.",
            },
            {
                name = "BACKLIGHT",
                type = "vec3",
                mode = "inout",
                detail = "Backlight color.",
            },
            {
                name = "AO",
                type = "float",
                mode = "out",
                detail = "Ambient occlusion.",
            },
            {
                name = "AO_LIGHT_AFFECT",
                type = "float",
                mode = "out",
                detail = "AO light affect factor.",
            },
            {
                name = "EMISSION",
                type = "vec3",
                mode = "out",
                detail = "Emission color.",
            },
            {
                name = "FOG",
                type = "vec4",
                mode = "out",
                detail = "Custom fog color and blend.",
            },
            {
                name = "RADIANCE",
                type = "vec4",
                mode = "out",
                detail = "Custom radiance.",
            },
            {
                name = "IRRADIANCE",
                type = "vec4",
                mode = "out",
                detail = "Custom irradiance.",
            },
            {
                name = "OUTPUT_IS_SRGB",
                type = "bool",
                mode = "in",
                detail = "Whether the output is sRGB.",
            },
            {
                name = "TIME",
                type = "float",
                mode = "in",
                detail = "Global time (seconds).",
            },
        },

        ----------------------------------------------------
        -- light()
        ----------------------------------------------------

        light = {
            {
                name = "VIEWPORT_SIZE",
                type = "vec2",
                mode = "in",
                detail = "Viewport size (pixels).",
            },
            {
                name = "FRAGCOORD",
                type = "vec4",
                mode = "in",
                detail = "Fragment coordinate (screen space).",
            },
            {
                name = "MODEL_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Model matrix (model -> world).",
            },
            {
                name = "INV_VIEW_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Inverse view matrix (view -> world).",
            },
            {
                name = "VIEW_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "View matrix (world -> view).",
            },
            {
                name = "PROJECTION_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Projection matrix (view -> clip).",
            },
            {
                name = "INV_PROJECTION_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Inverse projection matrix (clip -> view).",
            },
            {
                name = "NORMAL",
                type = "vec3",
                mode = "in",
                detail = "Fragment normal (view space).",
            },
            {
                name = "SCREEN_UV",
                type = "vec2",
                mode = "in",
                detail = "Screen UV.",
            },
            {
                name = "UV",
                type = "vec2",
                mode = "in",
                detail = "UV channel 1.",
            },
            {
                name = "UV2",
                type = "vec2",
                mode = "in",
                detail = "UV channel 2.",
            },
            {
                name = "VIEW",
                type = "vec3",
                mode = "in",
                detail = "View direction.",
            },
            {
                name = "LIGHT",
                type = "vec3",
                mode = "in",
                detail = "Light direction (view space).",
            },
            {
                name = "LIGHT_COLOR",
                type = "vec3",
                mode = "in",
                detail = "Light color * energy * PI.",
            },
            {
                name = "SPECULAR_AMOUNT",
                type = "float",
                mode = "in",
                detail = "Specular amount.",
            },
            {
                name = "LIGHT_IS_DIRECTIONAL",
                type = "bool",
                mode = "in",
                detail = "Whether the light is directional.",
            },
            {
                name = "ATTENUATION",
                type = "float",
                mode = "in",
                detail = "Light attenuation.",
            },
            {
                name = "ALBEDO",
                type = "vec3",
                mode = "in",
                detail = "Albedo from the fragment.",
            },
            {
                name = "BACKLIGHT",
                type = "vec3",
                mode = "in",
                detail = "Backlight.",
            },
            {
                name = "METALLIC",
                type = "float",
                mode = "in",
                detail = "Metallic from the fragment.",
            },
            {
                name = "ROUGHNESS",
                type = "float",
                mode = "in",
                detail = "Roughness from the fragment.",
            },
            {
                name = "DIFFUSE_LIGHT",
                type = "vec3",
                mode = "out",
                detail = "Diffuse light output.",
            },
            {
                name = "SPECULAR_LIGHT",
                type = "vec3",
                mode = "out",
                detail = "Specular output.",
            },
            {
                name = "ALPHA",
                type = "float",
                mode = "out",
                detail = "Alpha value.",
            },
            {
                name = "OUTPUT_IS_SRGB",
                type = "bool",
                mode = "in",
                detail = "Whether the output is sRGB.",
            },
            {
                name = "TIME",
                type = "float",
                mode = "in",
                detail = "Global time (seconds).",
            },
        },
    },

    --------------------------------------------------------
    -- CanvasItem
    --------------------------------------------------------

    canvas_item = {
        vertex = {
            {
                name = "MODEL_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Local -> world transform.",
            },
            {
                name = "CANVAS_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "World -> canvas transform.",
            },
            {
                name = "SCREEN_MATRIX",
                type = "mat4",
                mode = "in",
                detail = "Canvas -> clip transform.",
            },
            {
                name = "INSTANCE_ID",
                type = "int",
                mode = "in",
                detail = "Instance ID.",
            },
            {
                name = "INSTANCE_CUSTOM",
                type = "vec4",
                mode = "in",
                detail = "Instance custom data.",
            },
            {
                name = "AT_LIGHT_PASS",
                type = "bool",
                mode = "in",
                detail = "Always false.",
            },
            {
                name = "TEXTURE_PIXEL_SIZE",
                type = "vec2",
                mode = "in",
                detail = "Default 2D texture normalized pixel size.",
            },
            {
                name = "VERTEX",
                type = "vec2",
                mode = "inout",
                detail = "Vertex position (local space, pixels).",
            },
            {
                name = "VERTEX_ID",
                type = "int",
                mode = "in",
                detail = "Index of the vertex in the buffer.",
            },
            {
                name = "UV",
                type = "vec2",
                mode = "inout",
                detail = "Normalized texture coordinates.",
            },
            {
                name = "COLOR",
                type = "vec4",
                mode = "inout",
                detail = "Vertex color * modulate * self_modulate.",
            },
            {
                name = "POINT_SIZE",
                type = "float",
                mode = "inout",
                detail = "Point size when drawing points.",
            },
            {
                name = "CUSTOM0",
                type = "vec4",
                mode = "in",
                detail = "Custom vertex data 0.",
            },
            {
                name = "CUSTOM1",
                type = "vec4",
                mode = "in",
                detail = "Custom vertex data 1.",
            },
            {
                name = "TIME",
                type = "float",
                mode = "in",
                detail = "Global time (seconds).",
            },
        },

        fragment = {
            {
                name = "FRAGCOORD",
                type = "vec4",
                mode = "in",
                detail = "Fragment coordinate (screen space).",
            },
            {
                name = "SCREEN_PIXEL_SIZE",
                type = "vec2",
                mode = "in",
                detail = "Single pixel size (resolution reciprocal).",
            },
            {
                name = "REGION_RECT",
                type = "vec4",
                mode = "in",
                detail = "Sprite region (x, y, w, h).",
            },
            {
                name = "POINT_COORD",
                type = "vec2",
                mode = "in",
                detail = "Coordinate when drawing points.",
            },
            {
                name = "TEXTURE",
                type = "sampler2D",
                mode = "in",
                detail = "Default 2D texture.",
            },
            {
                name = "TEXTURE_PIXEL_SIZE",
                type = "vec2",
                mode = "in",
                detail = "Default 2D texture normalized pixel size.",
            },
            {
                name = "AT_LIGHT_PASS",
                type = "bool",
                mode = "in",
                detail = "Always false.",
            },
            {
                name = "SPECULAR_SHININESS_TEXTURE",
                type = "sampler2D",
                mode = "in",
                detail = "Specular shininess texture.",
            },
            {
                name = "SPECULAR_SHININESS",
                type = "vec4",
                mode = "in",
                detail = "Specular shininess color.",
            },
            {
                name = "UV",
                type = "vec2",
                mode = "in",
                detail = "UV coordinate.",
            },
            {
                name = "SCREEN_UV",
                type = "vec2",
                mode = "in",
                detail = "Screen UV coordinate.",
            },
            {
                name = "NORMAL",
                type = "vec3",
                mode = "inout",
                detail = "Normal read from NORMAL_TEXTURE.",
            },
            {
                name = "NORMAL_TEXTURE",
                type = "sampler2D",
                mode = "in",
                detail = "Default 2D normal texture.",
            },
            {
                name = "NORMAL_MAP",
                type = "vec3",
                mode = "out",
                detail = "Normal map (overrides NORMAL).",
            },
            {
                name = "NORMAL_MAP_DEPTH",
                type = "float",
                mode = "out",
                detail = "Normal map depth scale.",
            },
            {
                name = "VERTEX",
                type = "vec2",
                mode = "inout",
                detail = "Pixel screen-space position.",
            },
            {
                name = "SHADOW_VERTEX",
                type = "vec2",
                mode = "inout",
                detail = "Writable, changes the shadow.",
            },
            {
                name = "LIGHT_VERTEX",
                type = "vec3",
                mode = "inout",
                detail = "Writable, changes lighting. Z is height.",
            },
            {
                name = "COLOR",
                type = "vec4",
                mode = "inout",
                detail = "vertex() COLOR * TEXTURE color. Also output.",
            },
            {
                name = "TIME",
                type = "float",
                mode = "in",
                detail = "Global time (seconds).",
            },
        },

        light = {
            {
                name = "FRAGCOORD",
                type = "vec4",
                mode = "in",
                detail = "Fragment coordinate (screen space).",
            },
            {
                name = "NORMAL",
                type = "vec3",
                mode = "in",
                detail = "Input normal.",
            },
            {
                name = "COLOR",
                type = "vec4",
                mode = "in",
                detail = "Color output by fragment().",
            },
            {
                name = "UV",
                type = "vec2",
                mode = "in",
                detail = "UV coordinate.",
            },
            {
                name = "TEXTURE",
                type = "sampler2D",
                mode = "in",
                detail = "Texture used by the current CanvasItem.",
            },
            {
                name = "TEXTURE_PIXEL_SIZE",
                type = "vec2",
                mode = "in",
                detail = "TEXTURE normalized pixel size.",
            },
            {
                name = "SCREEN_UV",
                type = "vec2",
                mode = "in",
                detail = "Screen UV coordinate.",
            },
            {
                name = "POINT_COORD",
                type = "vec2",
                mode = "in",
                detail = "Point sprite UV.",
            },
            {
                name = "LIGHT_COLOR",
                type = "vec4",
                mode = "in",
                detail = "Light2D color.",
            },
            {
                name = "LIGHT_ENERGY",
                type = "float",
                mode = "in",
                detail = "Light2D energy.",
            },
            {
                name = "LIGHT_POSITION",
                type = "vec3",
                mode = "in",
                detail = "Light2D screen-space position.",
            },
            {
                name = "LIGHT_DIRECTION",
                type = "vec3",
                mode = "in",
                detail = "Light2D screen-space direction.",
            },
            {
                name = "LIGHT_IS_DIRECTIONAL",
                type = "bool",
                mode = "in",
                detail = "Whether it is a DirectionalLight2D.",
            },
            {
                name = "LIGHT_VERTEX",
                type = "vec3",
                mode = "in",
                detail = "Pixel position (after fragment modification).",
            },
            {
                name = "LIGHT",
                type = "vec4",
                mode = "inout",
                detail = "Light2D output color.",
            },
            {
                name = "SPECULAR_SHININESS",
                type = "vec4",
                mode = "in",
                detail = "Specular shininess settings.",
            },
            {
                name = "SHADOW_MODULATE",
                type = "vec4",
                mode = "out",
                detail = "Shadow modulate color.",
            },
            {
                name = "TIME",
                type = "float",
                mode = "in",
                detail = "Global time (seconds).",
            },
        },
    },

    sky = {
        sky = {
            {
                name = "EYEDIR",
                type = "vec3",
                mode = "in",
                detail = "Normalized direction of the current pixel.",
            },

            {
                name = "SCREEN_UV",
                type = "vec2",
                mode = "in",
                detail = "Screen UV coordinate.",
            },

            {
                name = "SKY_COORDS",
                type = "vec2",
                mode = "in",
                detail = "Spherical UV for panorama texture mapping.",
            },

            {
                name = "HALF_RES_COLOR",
                type = "vec4",
                mode = "in",
                detail = "Half-resolution pass color.",
            },

            {
                name = "QUARTER_RES_COLOR",
                type = "vec4",
                mode = "in",
                detail = "Quarter-resolution pass color.",
            },

            {
                name = "COLOR",
                type = "vec3",
                mode = "out",
                detail = "Output color.",
            },

            {
                name = "ALPHA",
                type = "float",
                mode = "out",
                detail = "Output alpha (sub-pass only).",
            },

            {
                name = "FOG",
                type = "vec4",
                mode = "out",
                detail = "Fog color output.",
            },

            {
                name = "POSITION",
                type = "vec3",
                mode = "in",
                detail = "Camera position (world space).",
            },

            {
                name = "RADIANCE",
                type = "samplerCube",
                mode = "in",
                detail = "Radiance cubemap (background pass only).",
            },

            {
                name = "AT_HALF_RES_PASS",
                type = "bool",
                mode = "in",
                detail = "Whether in the half-resolution pass.",
            },

            {
                name = "AT_QUARTER_RES_PASS",
                type = "bool",
                mode = "in",
                detail = "Whether in the quarter-resolution pass.",
            },

            {
                name = "AT_CUBEMAP_PASS",
                type = "bool",
                mode = "in",
                detail = "Whether in the radiance cubemap pass.",
            },

            {
                name = "LIGHT0_ENABLED",
                type = "bool",
                mode = "in",
                detail = "Whether light 0 is enabled.",
            },

            {
                name = "LIGHT0_DIRECTION",
                type = "vec3",
                mode = "in",
                detail = "Light 0 direction.",
            },

            {
                name = "LIGHT0_ENERGY",
                type = "float",
                mode = "in",
                detail = "Light 0 energy.",
            },

            {
                name = "LIGHT0_COLOR",
                type = "vec3",
                mode = "in",
                detail = "Light 0 color.",
            },

            {
                name = "LIGHT0_SIZE",
                type = "float",
                mode = "in",
                detail = "Light 0 angular diameter (radians).",
            },

            {
                name = "LIGHT1_ENABLED",
                type = "bool",
                mode = "in",
                detail = "Whether light 1 is enabled.",
            },

            {
                name = "LIGHT1_DIRECTION",
                type = "vec3",
                mode = "in",
                detail = "Light 1 direction.",
            },

            {
                name = "LIGHT1_ENERGY",
                type = "float",
                mode = "in",
                detail = "Light 1 energy.",
            },

            {
                name = "LIGHT1_COLOR",
                type = "vec3",
                mode = "in",
                detail = "Light 1 color.",
            },

            {
                name = "LIGHT1_SIZE",
                type = "float",
                mode = "in",
                detail = "Light 1 angular diameter.",
            },

            {
                name = "LIGHT2_ENABLED",
                type = "bool",
                mode = "in",
                detail = "Whether light 2 is enabled.",
            },

            {
                name = "LIGHT2_DIRECTION",
                type = "vec3",
                mode = "in",
                detail = "Light 2 direction.",
            },

            {
                name = "LIGHT2_ENERGY",
                type = "float",
                mode = "in",
                detail = "Light 2 energy.",
            },

            {
                name = "LIGHT2_COLOR",
                type = "vec3",
                mode = "in",
                detail = "Light 2 color.",
            },

            {
                name = "LIGHT2_SIZE",
                type = "float",
                mode = "in",
                detail = "Light 2 angular diameter.",
            },

            {
                name = "LIGHT3_ENABLED",
                type = "bool",
                mode = "in",
                detail = "Whether light 3 is enabled.",
            },

            {
                name = "LIGHT3_DIRECTION",
                type = "vec3",
                mode = "in",
                detail = "Light 3 direction.",
            },

            {
                name = "LIGHT3_ENERGY",
                type = "float",
                mode = "in",
                detail = "Light 3 energy.",
            },

            {
                name = "LIGHT3_COLOR",
                type = "vec3",
                mode = "in",
                detail = "Light 3 color.",
            },

            {
                name = "LIGHT3_SIZE",
                type = "float",
                mode = "in",
                detail = "Light 3 angular diameter.",
            },

            {
                name = "TIME",
                type = "float",
                mode = "in",
                detail = "Global time (seconds).",
            },
        },
    },

    fog = {
        fog = {
            {
                name = "WORLD_POSITION",
                type = "vec3",
                mode = "in",
                detail = "Position of the current voxel in world space.",
            },

            {
                name = "OBJECT_POSITION",
                type = "vec3",
                mode = "in",
                detail = "World-space position of the FogVolume center.",
            },

            {
                name = "UVW",
                type = "vec3",
                mode = "in",
                detail = "3D UV for mapping 3D textures.",
            },

            {
                name = "SIZE",
                type = "vec3",
                mode = "in",
                detail = "FogVolume size.",
            },

            {
                name = "SDF",
                type = "vec3",
                mode = "in",
                detail = "Signed distance field to the FogVolume surface.",
            },

            {
                name = "ALBEDO",
                type = "vec3",
                mode = "out",
                detail = "Output base color, interacts with lighting.",
            },

            {
                name = "DENSITY",
                type = "float",
                mode = "out",
                detail = "Output density (may be negative to subtract volume).",
            },

            {
                name = "EMISSION",
                type = "vec3",
                mode = "out",
                detail = "Output emission color.",
            },

            {
                name = "TIME",
                type = "float",
                mode = "in",
                detail = "Global time (seconds).",
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
