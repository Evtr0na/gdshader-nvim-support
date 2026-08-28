package.path = "lua/?.lua;" .. package.path
local ok, h = pcall(require, "gdshader_nvim.syntax.hints")
if not ok then print("REQUIRE FAIL", h) return end
local src = [[
#include "res://foo/bar.gdshaderinc" // #gdshader-hint-redirection:./bar.gdshaderinc
#include "missing.gdshaderinc" // #gdshader-hint-ignore
shader_type spatial;
// #gdshader-hint-type:vec3
vec3 custom_data = get_data();
// #gdshader-hint-declare:vec4 blend_overlay(vec4 base, vec4 overlay);
// #gdshader-hint-define:SQR(x) ((x)*(x))
void fragment() {
  ALBEDO = custom_data;
}
]]
local r = h.scan(src)
print("includes:", #r.includes, "typeHints:", #r.typeHints, "defHints:", #r.defHints, "macros:", #r.macros)
for _, inc in ipairs(r.includes) do print("  include", inc.path, "ignore="..tostring(inc.isIgnored), "redirect="..tostring(inc.redirectPath)) end
for _, t in ipairs(r.typeHints) do print("  type", t.line, t.typeName) end
for _, d in ipairs(r.defHints) do print("  declare", d.name, d.typeName, "fn="..tostring(d.isFunction)) end
for _, m in ipairs(r.macros) do print("  macro", m.name, "fn="..tostring(m.isFunction)) end
