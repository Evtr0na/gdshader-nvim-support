local vars = {}
local f = io.open("lua/gdshader_nvim/data/builtin_variables.lua")
local excl = { PI = true, TAU = true, E = true }
for line in f:lines() do
  local n = line:match('name%s*=%s*"([%w_]+)"')
  if n and not excl[n] then vars[n] = true end
end
f:close()
local l = {}
for k in pairs(vars) do l[#l + 1] = k end
table.sort(l)
print(table.concat(l, " "))
