local s = "// #gdshader-hint-declare:vec4 blend_overlay(vec4 base, vec4 overlay);"
local def_raw = s:match("//%s*#gdshader%-hint%-(declare|def)%s*:%s*(.+)")
print("def_raw=", def_raw)
local raw = def_raw:gsub(";%s*$","")
print("raw=", raw)
local type_name, name, params_str = raw:match("^(%w+)%s+(%w+)%s*%(([^)]*)%)")
print("tn=", type_name, "name=", name, "params=", params_str)
