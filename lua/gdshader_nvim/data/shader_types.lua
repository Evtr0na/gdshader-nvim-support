local knowledge = require("gdshader_nvim.data.knowledge")

local base = {
    "spatial",
    "canvas_item",
    "particles",
    "sky",
    "fog",
}

return knowledge.register("shader_types", base)
