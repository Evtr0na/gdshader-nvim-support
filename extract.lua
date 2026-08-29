local root = "D:/2zhuomian/app/source/gdshader-nvim-support/lua/gdshader_nvim/data/"

-- Collect function names
local funcs = {}
local f = io.open(root .. "builtin_functions.lua", "r")
for line in f:lines() do
  local name = line:match("name%s*=%s*'([%w_]+)'")
  if name then funcs[name] = true end
end
f:close()

-- Collect variable names (all)
local vars = {}
local f2 = io.open(root .. "builtin_variables.lua", "r")
for line in f2:lines() do
  local name = line:match('name%s*=%s*"([%w_]+)"')
  if name then vars[name] = true end
end
f2:close()

local function emit(title, set)
  print("=== " .. title .. " ===")
  local list = {}
  for k in pairs(set) do list[#list+1] = k end
  table.sort(list)
  print("count=" .. #list)
  print(table.concat(list, " "))
end

emit("FUNCTIONS", funcs)
emit("VARIABLES", vars)
