local M = {}

local util = require("gdshader_nvim.util")

local configured = false

------------------------------------------------------------
-- Templates (mirror gdshader-src/src/commands.ts)
------------------------------------------------------------

local templates = {
    spatial = [[shader_type spatial;
render_mode blend_mix;

uniform vec4 albedo_color : source_color = vec4(1.0);

void vertex() {
	// Vertex shader.
}

void fragment() {
	ALBEDO = albedo_color.rgb;
	ALPHA = albedo_color.a;
}

void light() {
	// Light shader.
}
]],

    canvas_item = [[shader_type canvas_item;

uniform vec4 modulate_color : source_color = vec4(1.0);

void vertex() {
	// Vertex shader.
}

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	COLOR = tex_color * modulate_color;
}

void light() {
	// Light shader.
}
]],

    particles = [[shader_type particles;

uniform float spread : hint_range(0.0, 180.0) = 45.0;

void start() {
	// Particle init.
}

void process() {
	// Particle process.
}
]],

    sky = [[shader_type sky;

uniform vec4 top_color : source_color = vec4(0.3, 0.5, 1.0, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);

void sky() {
	COLOR = mix(bottom_color.rgb, top_color.rgb, clamp(EYEDIR.y, 0.0, 1.0));
}
]],

    fog = [[shader_type fog;

void fog() {
	DENSITY = 1.0;
	ALBEDO = vec3(1.0);
	EMISSION = vec3(0.0);
}
]],
}

local shader_types = {
    { label = "spatial",     description = "Spatial (3D)" },
    { label = "canvas_item", description = "Canvas item (2D)" },
    { label = "particles",   description = "Particles" },
    { label = "sky",         description = "Sky" },
    { label = "fog",         description = "Fog" },
}

------------------------------------------------------------
-- Insert
------------------------------------------------------------

function M.insert()
    local bufnr = vim.api.nvim_get_current_buf()

    if not util.is_supported(bufnr) then
        vim.notify("GDShader: open a .gdshader file first", vim.log.levels.WARN)

        return
    end

    vim.ui.select(shader_types, {
        prompt = "Insert GDShader template:",
        format_item = function(item)
            return item.label .. "  —  " .. item.description
        end,
    }, function(choice)
        if not choice then
            return
        end

        local template = templates[choice.label]

        if not template then
            return
        end

        --------------------------------------------------------
        -- 在光标处插入，保持后续内容。
        --------------------------------------------------------

        local cursor = vim.api.nvim_win_get_cursor(0)

        local row = cursor[1] - 1

        local col = cursor[2]

        local lines = vim.split(template, "\n", { plain = true, trimempty = false })

        --------------------------------------------------------
        -- 去掉模板末尾空行，避免多余空行。
        --------------------------------------------------------

        while #lines > 0 and lines[#lines] == "" do
            table.remove(lines)
        end

        vim.api.nvim_buf_set_text(bufnr, row, col, row, col, lines)

        local new_row = row + #lines

        pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, new_row), 0 })
    end)
end

------------------------------------------------------------
-- Attach
------------------------------------------------------------

function M.attach(bufnr)
    if not util.is_supported(bufnr) then
        return
    end

    if vim.b[bufnr].gdshader_nvim_template_attached then
        return
    end

    vim.b[bufnr].gdshader_nvim_template_attached = true

    vim.api.nvim_buf_create_user_command(bufnr, "GDShaderInsertTemplate", function()
        M.insert()
    end, {
        desc = "Insert a GDShader shader template",
    })
end

------------------------------------------------------------
-- Setup
------------------------------------------------------------

function M.setup()
    if configured then
        return
    end

    configured = true

    local config = require("gdshader_nvim.config").get()

    local group = vim.api.nvim_create_augroup("GDShaderNvimTemplate", {
        clear = true,
    })

    vim.api.nvim_create_autocmd("FileType", {
        group = group,

        pattern = config.filetypes,

        callback = function(args)
            M.attach(args.buf)
        end,
    })

    local bufnr = vim.api.nvim_get_current_buf()

    if util.is_supported(bufnr) then
        M.attach(bufnr)
    end
end

return M
