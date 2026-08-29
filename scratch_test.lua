vim.opt.runtimepath:prepend("D:/2zhuomian/app/source/gdshader-nvim-support")

local source = require("gdshader_nvim.syntax.source")
local parser = require("gdshader_nvim.syntax.parser")
local document = require("gdshader_nvim.semantic.document")
local inference = require("gdshader_nvim.semantic.inference")
local semantic_types = require("gdshader_nvim.semantic.types")

print("PARSER SOURCE:", debug.getinfo(parser.parse).source)

local code = "shader_type spatial;\nstruct MyStruct {\n    vec3 position;\n    vec4 color;\n    float weights[4];\n};\nuniform float a, b;\ngroup_uniforms Group {\n    uniform vec4 tint : source_color = vec4(1.0);\n};\nflat varying vec3 normal;\nvoid fragment() {\n    MyStruct s;\n    s.position = vec3(1.0);\n    vec3 x = s.color.rgb;\n}\n"
local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(code, "\n"))
vim.bo[bufnr].filetype = "gdshader"
local lexed = source.get_lexed(bufnr)
local parsed = parser.parse(lexed.tokens or {})
print("DECLS", #(parsed.ast.declarations or {}))
for i, n in ipairs(parsed.ast.declarations or {}) do
    if n.kind == "struct" then
        print("  struct", n.name, #(n.members or {}))
        for _, m in ipairs(n.members or {}) do print("     member", m.name, m.type, m.is_array) end
    elseif n.kind == "declaration" then
        print("  decl", n.declaration_kind, n.data_type, n.name)
    else
        print("  node", n.kind, n.name or "")
    end
end
local doc = document.get(bufnr)
print("doc.structs", #(doc.structs or {}), "doc.globals", #(doc.globals or {}))
print("is_struct", semantic_types.is_struct(bufnr, "MyStruct"))
print("member position", semantic_types.get_struct_member_type(bufnr, "MyStruct", "position"))
print("infer s (l100)", inference.infer_expression_type(bufnr, "s", 100))
print("infer s.position", inference.infer_expression_type(bufnr, "s.position", 100))
print("infer s.color.rgb", inference.infer_expression_type(bufnr, "s.color.rgb", 100))
print("DONE")
