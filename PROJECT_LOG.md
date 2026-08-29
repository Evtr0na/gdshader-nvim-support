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

## 修复：parser `is_type` 前向引用导致 LSP 崩溃

### 现象
LSP 客户端 `gdscript` 以 `exit code 1` 退出，日志报：
```
vim.schedule callback: ...dshader-nvim-support/lua/gdshader_nvim/syntax/parser.lua:168:
attempt to call global 'is_type' (a nil value)
```
调用链：`parse → parse_document → is_declarable_type → is_type`。

### 根因（关键）
`is_type` 是一个 `local function`，原始定义在文件靠后（~第 217 行），
而 `Parser:is_declarable_type`（~第 168 行）在它**之前**调用了它。
Lua 的 `local` 函数只在定义语句处才完成绑定，定义点之前的引用看到的是尚未赋值的 `nil`。

### 第一次修复尝试（错误，记录以避坑）
曾尝试在使用前加前向声明：
```lua
local is_type  -- forward declaration
```
但随后仍保留 `local function is_type(item)` 定义。问题在于 `local function f()`
等价于 `local f; f = function() end`——它会**再声明一个同名但不同的 local 变量**。
于是 `is_declarable_type` 的闭包捕获的是前向声明那个（永不赋值、始终为 `nil`）的 `is_type`，
而函数体被绑定到了另一个同名的局部变量上，运行时依旧报
`attempt to call upvalue 'is_type' (a nil value)`。**前向声明 + 保留 `local function` 定义无效。**

### 正确修复
直接把 `local function is_type(item)` 的定义**整体移到**首次使用之前：
- 删除原位于「-- Type --」注释段下的 `local function is_type(item) ... end`。
- 在 `is_user_type` / `is_declarable_type` 之前插入该定义（现第 163 行）。
- 这样只存在**一个** `local is_type`，且在使用点之前完成绑定，闭包捕获的即为其本身。

### 改动文件
- `lua/gdshader_nvim/syntax/parser.lua`
  - 第 163 行新增 `local function is_type(item)`（上移）。
  - 删除原靠后的重复定义（原 ~217–219 行）。
  - 无逻辑改动，仅调整定义顺序。

### 验证
重新加载 nvim 配置 / 重启 LSP 客户端后，确认 `Client gdscript quit with exit code 1`
不再出现，诊断（diagnostics）可正常刷新。

## 增强：颜色色块显示在字面量前且符号可配置

### 需求
用户希望行内色块（decoration swatch）显示在每个 `vec3` / `vec4` 颜色字面量**之前**（而非行尾），
且方块符号可通过配置改成其他字符（如 `⬛` `#` `●` 等）。

### 改动
- `lua/gdshader_nvim/config.lua`：`color` 表新增 `swatch = "■"`（空串回退为 `■`）。
- `lua/gdshader_nvim/color.lua`（`M.refresh`）：
  - 读取 `config.color.swatch`（空/缺失则回退 `■`）。
  - extmark 列由 `match.end_col` 改为 `match.start_col`（即 `vecN` 之前），
    `virt_text_pos` 由 `"eol"` 改为 `"inline"`，从而把符号内联到字面量前方。

### 使用
```lua
require("gdshader_nvim").setup({
  color = {
    decorate = true,       -- 常驻行内色块
    swatch = "■",          -- 可改为 "⬛" / "#" / "●" 等，改后重开/重编辑即生效
  },
})
```
运行时改符号：`require("gdshader_nvim.config").get().color.swatch = "⬛"` 后
执行 `:GDShaderColorDecoration`（关→开）或编辑缓冲区触发刷新即可生效。

### 改动文件
- `lua/gdshader_nvim/config.lua`（新增 `color.swatch`）
- `lua/gdshader_nvim/color.lua`（`M.refresh` 读取符号 + 改为 inline 前置）

### 验证
decorate 开启后，每个 [0,1] 区间内的 `vec3/vec4` 字面量前出现对应颜色的方块；
修改 `swatch` 配置后刷新即显示新符号。

## 增强：色块前后间距可分别配置

### 需求
用户希望方块与前后内容之间的**间距可独立控制**，而非固定紧贴字面量。例如：
- `vec3 color =⬛️vec3(1,1,1);`（`pad_left=0, pad_right=0`）
- `vec3 color =         ⬛️        vec3(1,1,1);`（`pad_left=9, pad_right=8`）

### 改动
- `lua/gdshader_nvim/config.lua`：`color` 表新增 `swatch_pad_left` / `swatch_pad_right`（整数，空格数，默认 0；负值回退为 0）。
- `lua/gdshader_nvim/color.lua`（`M.refresh`）：读取两个 padding；
  以 `string.rep(" ", n)` 在 `swatch` 符号**前后**各插入对应空格（用空高亮组 `""`，即透明间隙，不参与着色），
  再一起作为 `virt_text` 列表传入 inline extmark。padding 为 0 时不插入对应 chunk。

### 使用
```lua
require("gdshader_nvim").setup({
  color = {
    decorate = true,
    swatch = "⬛️",
    swatch_pad_left = 9,    -- 方块前空格数
    swatch_pad_right = 8,   -- 方块后空格数
  },
})
```
运行时改间距：`require("gdshader_nvim.config").get().color.swatch_pad_left = 4` 后
`:GDShaderColorDecoration`（关→开）或编辑缓冲区触发刷新即生效。

### 改动文件
- `lua/gdshader_nvim/config.lua`（新增 `color.swatch_pad_left` / `swatch_pad_right`）
- `lua/gdshader_nvim/color.lua`（`M.refresh` 组装含前后空格的 `virt_text`）

### 验证
decorate 开启后，方块按配置的左右空格数显示间距；该间距为透明空白，不影响方块自身的颜色填充。

## 修复：色块为单一纯色（消除“目标色背景 + 反色内方块”双层效果）

### 现象
`vec3(1,1,1)` 白色显示为“白色矩形里嵌黑色小方块”；紫色 `vec3(0.4667,0.1529,0.749)`
显示为“紫色矩形里嵌白色小方块”。并非期望的单一纯色色块。

### 根因
`swatch_hl()` 同时设置：
- `bg = 实际颜色`（字符格背景被染成目标色）
- `fg = 按亮度算出的黑/白对比色`（前景字符 `■` 被染成对比色）

`■` 是真实前景字符，于是字符本身呈对比色、所在字符格背景呈目标色，形成双层反色方块。

### 修复
将 `swatch_hl()` 改为 `fg = bg = 目标颜色 hex`：
- 字符格背景 = 目标色，前景 `■` 也是同色 → 单一纯色色块，无内层反色方块。
- 不再按亮度取对比色（装饰性色块无需可读文字）。
- padding 空格使用空高亮组 `""`，保持透明间隙，不受影响。
- 预览相关高亮（`GDShaderColorSwatchPreview` / `...PreviewEdit`）本就 `fg=bg=hex`，
  与此保持一致。

### 改动文件
- `lua/gdshader_nvim/color.lua`（`swatch_hl`：`fg` 与 `bg` 均设为 `hex`，移除亮度对比逻辑）

### 验证
白色 `vec3(1,1,1)` 显示纯白色块；紫色显示纯紫色块；无内部黑/白小方块；
不修改真实 buffer；仍用 extmark / virtual text；vec3/vec4 解析、刷新、防抖逻辑不变。

## 调整：色块用前景(fg)着色、背景透明

### 需求（接续上一条）
上一条把 `fg` 与 `bg` 都设为目标色，得到单一纯色块。但用户进一步要求：
**背景透明，色块仅由前景字符（fg）构成**，即 `bg` 不应铺色，方块应是 `fg` 的 `■` 字形本身。

### 改动
- `lua/gdshader_nvim/color.lua`（`swatch_hl`）：`bg` 改为 `"NONE"`（透明/继承），
  `fg` 保持目标颜色 hex。色块完全由前景字符 `swatch` 的字形与 fg 颜色形成。

### 注意：符号须为文本字形
前景着色只对**文本字形**生效（如 `■` / `●` / `#`）。彩色 emoji（如 `⬛️`）在多数终端
会忽略 `fg`、自行渲染颜色，可能出现“不受控的 emoji 方块”。因此 `color.swatch` 建议
保持默认 `"■"`（U+25A0 BLACK SQUARE）这类纯文本方块，以保证 fg 着色可控。

### 改动文件
- `lua/gdshader_nvim/color.lua`（`swatch_hl`：`bg = "NONE"`，仅 `fg = hex`）

### 验证
decorate 开启后，色块为前景字符着色的透明背景小方块：白色显示为前景白色方块、
紫色显示为前景紫色方块；背景不再铺色；不修改真实 buffer；解析/刷新/防抖逻辑不变。

## 文档：更新 README.md（颜色 API + 各 API 详细用法）

### 内容
- 修复命令列表中重复的 `:GDShaderEditColor` 条目。
- 配置示例补全：`keymaps.edit` 与完整 `color` 表
  （`editor` / `decorate` / `debounce_ms` / `swatch` / `swatch_pad_left` / `swatch_pad_right`）。
- 新增「颜色功能详解 · Color」章节：行内色块、色块符号与间距（含 fg 着色/透明背景说明、
  文本字形建议、运行时修改示例）、颜色预览、颜色编辑（后端/HEX/vec3-vec4 保留）。
- 新增「API 参考 · API Reference」章节：
  - `setup(opts)` / `extend(extra)` 的键表与示例；
  - 全部命令（`GDShaderHover` / `Definition` / `References` / `Rename` / `Format` /
    `InsertTemplate` / `PreviewColor` / `ColorDecoration` / `EditColor`）的参数与说明对照表。
- 说明颜色命令仅在 `[0,1]` 区间的 `vec3/vec4` 上有效。

### 改动文件
- `README.md`（命令去重、配置补全、颜色详解章节、API 参考章节）
