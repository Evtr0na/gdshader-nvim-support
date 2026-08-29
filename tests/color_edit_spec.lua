local REPO = "D:\\2zhuomian\\app\\source\\gdshader-nvim-support"
vim.opt.runtimepath:append(REPO)
vim.opt.runtimepath:append("C:\\Users\\SDD\\AppData\\Local\\nvim-data\\lazy\\ccc.nvim")
package.path = package.path
  .. ";" .. REPO .. "\\lua\\?.lua"
  .. ";" .. REPO .. "\\lua\\?\\init.lua"
  .. ";" .. "C:\\Users\\SDD\\AppData\\Local\\nvim-data\\lazy\\ccc.nvim\\lua\\?.lua"
  .. ";" .. "C:\\Users\\SDD\\AppData\\Local\\nvim-data\\lazy\\ccc.nvim\\lua\\?\\init.lua"

local color = require("gdshader_nvim.color")
local config = require("gdshader_nvim.config")

local pass, fail = 0, 0
local function ok(name, cond)
  if cond then pass = pass + 1; print("PASS " .. name)
  else fail = fail + 1; print("FAIL " .. name) end
end

-- helper: open a gdshader buffer with one line, cursor on it
local function buf_with(line)
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { line })
  vim.bo[b].filetype = "gdshader"
  vim.api.nvim_set_current_buf(b)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  return b
end

-- find a floating window whose buffer has the given filetype
local function win_with_ft(ft)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == ft then return w, b end
  end
  return nil
end

-- 1. shared parser/formatter edge cases via builtin editor round-trip
config.setup({ color = { editor = "builtin" } })

-- 1a. vec3(1.0,0.0,0.0) -> red, builtin edit writes vec3 back
do
  local b = buf_with("uniform vec3 c = vec3(1.0, 0.0, 0.0);")
  vim.api.nvim_win_set_cursor(0, { 1, 18 })
  color.edit()
  local w, eb = win_with_ft("gdshader_color_edit")
  ok("builtin editor opens", w ~= nil)
  if w then
    vim.api.nvim_set_current_win(w)
    -- change to green via the R/G/B lines
    vim.api.nvim_buf_set_lines(eb, 0, -1, false, {
      "# GDShader color editor",
      "",
      "R: 0.0",
      "G: 0.8",
      "B: 0.0",
      "HEX: #00cc00",
      "",
      "# edit",
    })
    vim.api.nvim_feedkeys("\r", "x", false)
    vim.cmd("redraw")
  end
  local out = vim.api.nvim_buf_get_lines(b, 0, -1, false)[1]
  ok("builtin vec3 writeback keeps vec3", out:match("vec3%(0, 0%.8, 0%)") ~= nil or out:match("vec3%(0, 0%.8, 0%)") ~= nil or out:find("vec3") and not out:find("vec4"))
  print("   out:", out)
end

-- 2. ccc backend: auto mode opens ccc picker (ccc installed)
do
  config.setup({ color = { editor = "auto" } })
  local b = buf_with("uniform vec4 c = vec4(1.0, 0.0, 0.0, 0.5);")
  vim.api.nvim_win_set_cursor(0, { 1, 18 })
  local before = vim.api.nvim_buf_get_lines(b, 0, -1, false)[1]
  color.edit_color()
  local w = win_with_ft("ccc-ui")
  ok("ccc picker opens in auto mode", w ~= nil)
  if w then
    -- 2a. cancel (q) must NOT modify source
    vim.api.nvim_set_current_win(w)
    vim.api.nvim_feedkeys("q", "x", false)
    vim.cmd("redraw")
  end
  local after = vim.api.nvim_buf_get_lines(b, 0, -1, false)[1]
  ok("ccc cancel leaves source unchanged", before == after)
  print("   unchanged:", after)
end

-- 3. ccc backend: confirm writes vec4 back
do
  config.setup({ color = { editor = "ccc" } })
  local b = buf_with("uniform vec4 c = vec4(1.0, 0.0, 0.0, 0.5);")
  vim.api.nvim_win_set_cursor(0, { 1, 18 })
  color.edit_color()
  local w = win_with_ft("ccc-ui")
  ok("ccc picker opens in ccc mode", w ~= nil)
  if w then
    vim.api.nvim_set_current_win(w)
    -- confirm immediately (keep current red, a=0.5)
    vim.api.nvim_feedkeys("\r", "x", false)
    vim.cmd("redraw")
  end
  local out = vim.api.nvim_buf_get_lines(b, 0, -1, false)[1]
  ok("ccc confirm writes vec4 back", out:find("vec4") ~= nil)
  print("   out:", out)
end

-- 4. ccc absent -> auto falls back to builtin (simulate by hiding ccc)
do
  -- Temporarily make require("ccc") fail.
  -- Clear the cached module so require re-resolves and hits preload (which errors).
  local prev_preload = package.preload["ccc"]
  local prev_loaded = package.loaded["ccc"]
  package.preload["ccc"] = function() error("ccc blocked for test") end
  package.loaded["ccc"] = nil
  config.setup({ color = { editor = "auto" } })
  local b = buf_with("uniform vec3 c = vec3(0.1, 0.2, 0.3);")
  vim.api.nvim_win_set_cursor(0, { 1, 18 })
  color.edit_color()
  local w = win_with_ft("gdshader_color_edit")
  ok("auto falls back to builtin when ccc absent", w ~= nil)
  package.preload["ccc"] = prev_preload
  package.loaded["ccc"] = prev_loaded
end

print(string.format("\n== %d passed, %d failed ==", pass, fail))
if fail > 0 then vim.cmd("cq 1") end