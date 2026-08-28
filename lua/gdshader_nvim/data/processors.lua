local knowledge = require("gdshader_nvim.data.knowledge")

local base = {
    --------------------------------------------------------
    -- Spatial
    --------------------------------------------------------

    spatial = {
        {
            name = "vertex",
            detail = "GDShader spatial vertex processor",
            allow_discard = false,
        },

        {
            name = "fragment",
            detail = "GDShader spatial fragment processor",
            allow_discard = true,
        },

        {
            name = "light",
            detail = "GDShader spatial light processor",
            allow_discard = true,
        },
    },

    --------------------------------------------------------
    -- CanvasItem
    --------------------------------------------------------

    canvas_item = {
        {
            name = "vertex",
            detail = "GDShader CanvasItem vertex processor",
            allow_discard = false,
        },

        {
            name = "fragment",
            detail = "GDShader CanvasItem fragment processor",
            allow_discard = true,
        },

        {
            name = "light",
            detail = "GDShader CanvasItem light processor",
            allow_discard = true,
        },
    },

    --------------------------------------------------------
    -- Particles
    --------------------------------------------------------

    particles = {
        {
            name = "start",
            detail = "GDShader particle start processor",
            allow_discard = false,
        },

        {
            name = "process",
            detail = "GDShader particle process processor",
            allow_discard = false,
        },
    },

    --------------------------------------------------------
    -- Sky
    --------------------------------------------------------

    sky = {
        {
            name = "sky",
            detail = "GDShader sky processor",
            allow_discard = false,
        },
    },

    --------------------------------------------------------
    -- Fog
    --------------------------------------------------------

    fog = {
        {
            name = "fog",
            detail = "GDShader fog processor",
            allow_discard = false,
        },
    },
}

return knowledge.register("processors", base)
