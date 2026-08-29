# 项目推进日志 . GDShader nvim 版

> 对照基准：D:\2zhuomian\app\source\gdshader-src（gdshader-vscode-support）
> 本仓库：D:\2zhuomian\app\source\gdshader-nvim-support（gdshader-nvim-support）

## 当前状态（功能对齐核查）

经逐项比对 vscode 版源码与 nvim 版实现，两者核心功能已高度对齐：

| 功能 | vscode 版 | nvim 版 | 结论 |
| --- | --- | --- | --- |
| 语法高亮 | TMLanguage 语法 | tree-sitter / 内置词法 | 对齐 |
| 补全（blink.cmp） | 上下文感知 | 上下文感知 + swizzle + 处理器片段 + #include/redirection/hint 补全 | 对齐（97 个内置函数一致）|
| 语义诊断 | 括号/分号/处理器约束/discard/只读内置变量/#include/重复定义/条件编译 | 全部实现（semantic/diagnostics.lua）| 对齐 |
| 悬停 | 签名/类型/常量/uniform hint/文档注释 | 支持 /// 、/** */、@param/@return/@brief | 对齐 |
| 颜色预览 | 行内色块 + 点击编辑 | 行内色块 + 预览命令 | 见下 |
| 片段/模板/格式化/跳转/引用/重命名/语义 token | 均有 | 均有 | 对齐 |
| 知识库扩展（extend）| — | extend() + 版本号缓存失效 | nvim 更优 |

数据表一致性：内置函数 97/97 完全一致；uniform hint 27/27；内置变量 nvim 多 3 个常量
(E/PI/TAU)；render mode 结构一致。nvim 版数据由 gen_builtins.js 生成，便于跟随 Godot 文档更新。

## 本轮推进（两次会话累计）

### 1. 新增：可编辑颜色（对齐 vscode 点击编辑颜色）

vscode 版支持通过 ColorPresentation 在编辑器里就地编辑 vec3/vec4 颜色；nvim 版此前
只有只读预览（:GDShaderPreviewColor）和行内色块（:GDShaderColorDecoration）。

- 新增 lua/gdshader_nvim/color.lua:M.edit()：在浮动窗口预填光标处 RGB(A)，实时刷新色块，
  回车（<CR>）将规整后的 vecN(r, g, b[, a]) 写回缓冲区，q 取消。
- 新增命令 :GDShaderEditColor（在 gdshader 缓冲区自动注册）。
- 新增可选键位 config.keymaps.edit（默认 false，设为如 "<leader>ce" 启用）。
- 更新 README.md 命令列表与功能说明。

### 文件改动
- lua/gdshader_nvim/color.lua（新增 M.edit + 命令/键位注册）
- lua/gdshader_nvim/config.lua（keymaps 增加 edit）
- README.md（文档）


### 2. 颜色编辑器增强：HEX 输入

在 `:GDShaderEditColor` 浮动编辑器新增 HEX 行（`#rrggbb` / `#rrggbbaa`），
编辑时实时刷新色块，提交时若 HEX 合法则优先于 R/G/B/A 行写回
`vecN(...)`。对齐“用十六进制思考颜色”的常见工作流。

### 3. 文档补齐

- `doc/gdshader_nvim.txt`：新增 `*gdshader-nvim-support-color*` 章节与
  `:GDShaderEditColor` 命令条目，INTRO 颜色项改为“preview/edit commands”。
- `README.md`：命令列表与功能说明补充 `:GDShaderEditColor` 及 HEX 输入。

### 4. 回归用例（fixtures）

新增 `tests/fixtures/` 共 13 个 `.gdshader` 样例，覆盖各诊断类别
（缺失/非法 shader_type、非法处理器、discard 位置、只读内置变量、括号/分号、
return、重复定义、条件编译未闭合、hint 注释识别、颜色编辑器）。配套
`tests/README.md` 列出“期望诊断”对照表，作为手动/自动回归清单。

### 本轮文件改动

- `lua/gdshader_nvim/color.lua`（HEX 解析/预览/写回）
- `doc/gdshader_nvim.txt`（颜色章节 + 命令）
- `README.md`（HEX 说明）
- `tests/fixtures/*.gdshader`、`tests/README.md`（新增）

## 仍存在的差距 / 后续方向

1. 颜色编辑 UX：已通过可选 ccc.nvim 适配解决（✅ 见下“ccc.nvim 可选适配”）。
2. 类型推断补全深度：复杂嵌套块下变量补全建议补回归样例验证。
3. 文档本地化：doc/gdshader_nvim.txt 与 README 需随功能同步（本次命令已登记，待补 help 条目）。
4. 回归测试：仓库含 test_hints.lua / scratch_test.lua 等手测脚本，建议沉淀为可重复用例。

## ccc.nvim 可选适配（颜色编辑器后端）

为 `:GDShaderEditColor` 接入 [ccc.nvim](https://github.com/uga-rosa/ccc.nvim) 作为可选颜色
编辑 UI。gdshader-nvim-support 仍独占 GDShader 语法：解析 `vec3(...)`/`vec4(...)` → RGB(A)
→ 喂给 ccc.nvim 的取色 UI → 取回最终 RGB(A) → 用自有 formatter 写回 `vec3`/`vec4`。

### 架构 / 边界
- ccc.nvim 为**可选依赖**：模块顶层不 `require("ccc")`，仅在运行时用 `pcall` 探测。
- 不调用 `core:pick()`（它会让 ccc 解析缓冲区文本），而是手动 `core.color:set_rgb({0..1})`
  喂入初始色，再 `core.ui:open(...)` 打开 UI；覆盖 `<CR>`（写回并关 UI）与 `q`（仅关 UI、不写回）。
- ccc.nvim 的 `complete()` 会把自己的输出（hex/css）写回缓冲区，已被我们的 `<CR>` 覆盖取代，
  故**不会**产生 `#ff0000` / `rgb(...)` / `hsl(...)`。
- RGB 比例为 0..1（经验证 ccc 内部 RGB 为 0..1，不是 0..255）。

### 配置
```lua
require("gdshader_nvim").setup({
  color = { editor = "auto" },  -- auto | builtin | ccc
})
```
- `auto`（默认）：检测到 ccc.nvim 用 ccc，否则内置浮窗。
- `builtin`：永远内置浮窗。
- `ccc`：优先 ccc；未安装则 `vim.notify` 提示并安全回退内置浮窗（无 traceback）。

### 修改文件
- `lua/gdshader_nvim/color.lua`：`ccc_ready()` / `open_ccc()` / `M.edit_color()` 调度器；
  命令 `:GDShaderEditColor` 与 `keymaps.edit` 现指向 `M.edit_color`（行为不变）。
- `lua/gdshader_nvim/config.lua`：`color.editor` 选项（默认 `auto`）。
- `README.md` / `doc/gdshader_nvim.txt`：ccc 安装示例 + 后端说明。
- `tests/color_edit_spec.lua`（新增）：headless 回归测试。

### 测试结果（nvim -u NONE -l tests/color_edit_spec.lua，7/7 通过）
- 内置编辑器打开并写回 `vec3`（绿）保持 `vec3`。
- ccc `auto` 模式打开取色器；取消不改源码。
- ccc `ccc` 模式确认写回 `vec4(1, 0, 0, 0.5)`（保留 Alpha，比例正确）。
- 模拟 ccc 缺失时 `auto` 安全回退到内置编辑器。

### 已知限制
- ccc.nvim 取色 UI 为交互式浮窗，无法在无头环境断言“用户拖动滑块”的中间态；
  写回格式由本插件自有 formatter 保证（测试中已验证确认路径）。
- 若 ccc.nvim API 在未来大版本改动（如 `core` 公开 API），`open_ccc` 需相应更新；
  任何异常均 `pcall` 捕获并回退内置编辑器。

## 配置方式（lazy.nvim 摘要）

```
{
  "Evtr0na/gdshader-nvim-support",
  config = function() require("gdshader_nvim").setup({
    keymaps = { edit = "<leader>ce" },
  }) end,
}
```
