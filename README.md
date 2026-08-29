# gdshader-nvim-support

GDShader language support for Neovim — completion, diagnostics, hover, goto
definition, references and rename — powered by a self-contained GDShader
lexer/parser with an optional tree-sitter backend.

This is the Neovim port of
[gdshader-vscode-support](https://github.com/XiaoDouXd/gdshader-vscode-support).

---

# gdshader-nvim-support

Neovim 版 GDShader 语言支持插件，提供补全、诊断、悬停、跳转定义、查找引用与重命名，
基于自带的 GDShader 词法/语法分析器，并可选用 tree-sitter 作为后端。

本插件是
[gdshader-vscode-support](https://github.com/XiaoDouXd/gdshader-vscode-support)
的 Neovim 移植版本。

## Features · 功能

与 VSCode 版（gdshader-vscode-support）功能对齐：

- Completion (via [blink.cmp](https://github.com/Saghen/blink.cmp)) ·
  基于 blink.cmp 的上下文感知补全（含 swizzle、uniform hint、处理器函数片段等）
- Diagnostics · 语义级诊断
- Hover · 悬停提示（含文档注释 `///`、`/** */`）
- Go to definition · 跳转定义（变量 / 函数 / `#include`）
- Find references · 查找引用
- Rename · 重命名
- Color preview · 颜色预览（`vec3`/`vec4` 色块与命令）
  - 编辑：`:GDShaderEditColor` 在浮动窗口修改 RGB(A) 或 HEX 并写回（对应 VSCode 的点击编辑颜色）
- Formatting · 文档格式化（缩进规整，可接入 conform 或保存时自动格式化）
- Snippets · 片段（`shader_spatial`、`uniform_range`、`func_fragment` 等）
- Template · 着色器模板插入命令
- Semantic tokens · 自定义 `struct` 类型名高亮
- Hint comments · 支持 `#gdshader-hint-*` 提示注释与文档注释

## Requirements · 环境要求

- Neovim >= 0.10
- [blink.cmp](https://github.com/Saghen/blink.cmp)（仅 `completion` 功能需要）
- `gdshader` tree-sitter 语法（可选，推荐；缺失时回退到内置词法分析器处理注释）

## Installation · 安装

### lazy.nvim

```lua
{
  "Evtr0na/gdshader-nvim-support",
  config = function()
    require("gdshader_nvim").setup()
  end,
}
```

### 可选：ccc.nvim 颜色编辑器

:GDShaderEditColor 默认使用内置浮窗编辑器。若想用功能更丰富的
[ccc.nvim](https://github.com/uga-rosa/ccc.nvim) 取色器（支持 RGB / HSL / Alpha
滑块调节）来编辑 GDShader 颜色，把 ccc.nvim 作为可选依赖自行安装即可：

```lua
{
  "Evtr0na/gdshader-nvim-support",
  config = function()
    require("gdshader_nvim").setup()
  end,
},
-- 可选：ccc.nvim 不是本插件的必需依赖
{
  "uga-rosa/ccc.nvim",
  config = function()
    require("ccc").setup({})
  end,
}
```

安装并 setup 后，:GDShaderEditColor 会自动改用 ccc.nvim 的取色 UI；
未安装时回退到内置编辑器。gdshader-nvim-support 只负责解析
vec3(...) / vec4(...) 与写回，ccc.nvim 仅作颜色编辑 UI，不会解析
GDShader 语法，也不替换现有行内颜色装饰（:GDShaderColorDecoration）。


### blink.cmp 补全源

```lua
require("blink.cmp").setup({
  sources = {
    default = { "gdshader", "lsp", "path", "buffer" },
    per_filetype = {
      gdshader = { "gdshader", "path", "snippets", "buffer" },
      gdshaderinc = { "gdshader", "path", "snippets", "buffer" },
    },
    providers = {
      gdshader = { name = "GDShader", module = "gdshader_nvim" },
    },
  },
})
```

blink 会通过 `require("<module>").new()` 实例化补全源。`module` 可填
`gdshader_nvim`（本仓库文档示例），也可以使用随附的别名模块 `gdshader_blink`
（部分配置示例中使用）。两者等价。

## Configuration · 配置

```lua
require("gdshader_nvim").setup({
  filetypes = { "gdshader", "gdshaderinc" },   -- 处理的文件类型
  features = {                                  -- 各功能开关
    completion  = true,
    diagnostics = true,
    hover       = true,
    definition  = true,
    references  = true,
    rename      = true,
    color       = true,
    format      = true,
    template    = true,
    semantic_tokens = true,   -- struct 类型名高亮
  },
  diagnostics = { debounce_ms = 150 },
  keymaps = {                                   -- 设为 false 可禁用对应映射
    hover      = "K",
    definition = "gd",
    references = "grr",
    rename     = "grn",
    edit       = false,   -- 设为如 "<leader>ce" 可在颜色上直接打开编辑浮窗
  },
  completion = { trigger_characters = { ".", ":", ",", " " } },
  color = {
    editor           = "auto",   -- 颜色编辑器后端: auto | builtin | ccc
    decorate         = false,    -- 常驻行内色块（也可用 :GDShaderColorDecoration 临时开关）
    debounce_ms      = 200,      -- 编辑防抖（毫秒）
    swatch           = "■",      -- 色块符号（文本字形；空串回退 "■"）
    swatch_pad_left  = 0,        -- 色块前的空格数
    swatch_pad_right = 0,        -- 色块后的空格数
  },
  semantic_tokens = { hl_group = "GdshaderStructType", debounce_ms = 200 },
  format = { on_save = false },          -- 保存时自动格式化（与 conform 二选一）
  references = { picker = "auto" },      -- auto | telescope | quickfix
  treesitter = true,
  extra = {},   -- 扩展知识库，见下方“Extending”
})
```

### 命令

每个 gdshader 缓冲区会自动注册以下命令：

- `:GDShaderHover` — 悬停信息（`K`）
- `:GDShaderDefinition` — 跳转定义（`gd`）
- `:GDShaderReferences` — 查找引用（`gr` / `grr`）
- `:GDShaderRename [new]` — 重命名（`grn`）
- `:GDShaderFormat` — 格式化
- `:GDShaderInsertTemplate` — 插入着色器模板
- `:GDShaderPreviewColor` — 预览光标处颜色
- `:GDShaderColorDecoration` — 切换行内颜色色块
- `:GDShaderEditColor` — 编辑光标处颜色（浮动窗口输入 R/G/B/A 或 HEX，回车写回缓冲区；可用 `keymaps.edit` 绑定快捷键）

### 颜色编辑器后端（Color editor backend）

:GDShaderEditColor 支持两种后端，通过 color.editor 选择：

- "auto"（默认）：检测到 ccc.nvim 就使用它，否则用内置浮窗。
- "builtin"：永远使用内置浮窗。
- "ccc"：优先使用 ccc.nvim；若未安装会提示并安全回退到内置浮窗。

无论哪种后端，最终都写回合法的 GDShader：vec3(r, g, b) / vec4(r, g, b, a)
（数值范围 0.0~1.0；vec3 不会因编辑变成 vec4，vec4 保留 Alpha）。
取消操作不会修改源代码。

```lua
require("gdshader_nvim").setup({
  color = { editor = "auto" },
})
```

## 颜色功能详解 · Color

所有颜色功能只对 GDShader 缓冲区（`gdshader` / `gdshaderinc`）生效，且只有
`vec3(...)` / `vec4(...)` 且**每个分量都在 `[0,1]`** 内才会被当作颜色（与 VSCode 一致）。

### 1. 行内色块（Decoration）

在每个颜色字面量**前方**显示一个纯色小方块（前景字符着色，背景透明）。

- 默认关闭。两种开启方式：
  - 配置常驻：`color.decorate = true`
  - 缓冲区临时开关：`:GDShaderColorDecoration`（在 on/off 间切换并即时刷新）
- 编辑时随改动自动刷新（默认 200ms 防抖，`color.debounce_ms` 可调）。

### 2. 色块符号与间距

| 选项 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `color.swatch` | string | `"■"` | 色块符号。空串回退 `"■"`。建议用**文本字形**（`■` / `●` / `#`），不要用彩色 emoji（如 `⬛️`，多数终端会忽略前景色自行上色）。 |
| `color.swatch_pad_left` | number | `0` | 色块**前**的空格数（透明间隙，不参与着色）。 |
| `color.swatch_pad_right` | number | `0` | 色块**后**的空格数。 |

实现上，色块由前景字符（`swatch`）的 `fg` 上色、背景透明（`bg = "NONE"`），
因此方块是单一纯色、无“背景色 + 反色内方块”的双层效果。左右 padding 为透明空格，
不影响方块自身颜色。

```lua
require("gdshader_nvim").setup({
  color = {
    decorate         = true,
    swatch           = "■",    -- 也可改为 "●" / "#" 等文本字形
    swatch_pad_left  = 1,      -- 方块前留 1 格
    swatch_pad_right = 4,      -- 方块后留 4 格
  },
})
```

运行时修改（无需重启）：

```lua
local cfg = require("gdshader_nvim.config").get()
cfg.color.swatch           = "●"
cfg.color.swatch_pad_left  = 2
cfg.color.swatch_pad_right = 2
-- 然后 :GDShaderColorDecoration（关→开）或编辑缓冲区触发刷新即可生效
```

### 3. 颜色预览（Preview）

光标停在某个 `vec3/vec4` 颜色字面量上，执行：

```
:GDShaderPreviewColor
```

弹出浮窗显示 `HEX / ARGB / RGBA` 与一个纯色色块，4 秒后自动关闭。

### 4. 颜色编辑（Edit）

光标放到 `vec3(...)` / `vec4(...)` 颜色字面量上，执行：

```
:GDShaderEditColor
```

打开浮动编辑器，预填 `R/G/B`（vec4 还有 `A`）与 `HEX` 行；改任意行实时刷新色块，
`<CR>` 把规整后的 `vecN(...)` 写回源码，`q` 取消不写回。HEX 合法时优先于 R/G/B/A。

- 绑定快捷键（默认不绑定）：`keymaps.edit = "<leader>ce"`，之后在颜色上按该键即编辑。
- 后端由 `color.editor` 控制：`"auto"`（默认，装了 ccc.nvim 用它，否则内置）、
  `"builtin"`（永远内置浮窗）、`"ccc"`（优先 ccc.nvim，未安装回退并提示）。
- 写回保证合法 GDShader：`vec3(r,g,b)` / `vec4(r,g,b,a)`，数值 0~1；vec3 不会因编辑变 vec4，vec4 保留 Alpha。取消不修改源文件。

## Ecosystem · 生态适配

- **conform.nvim**：插件会自动注册名为 `gdshader` 的 formatter。
  在你的 conform 配置里加入即可启用（含 `format_on_save`）：

  ```lua
  formatters_by_ft = {
    gdshader = { "gdshader" },
    gdshaderinc = { "gdshader" },
  },
  ```

  若不使用 conform，可开启 `format.on_save = true`，或用 `:GDShaderFormat`。

- **telescope.nvim**：`references.picker = "telescope"`（默认 `auto`）时，
  `gr` / `grr` 会用你已配置的 telescope 展示引用列表。由于 gdshader 没有 LSP
  server，插件会在 gdshader 缓冲区里把 `gd` / `gr` 等键位指向自身实现，
  避免落到无数据的 LSP picker。

- **inc-rename.nvim**：把 `<leader>rn` 在 gdshader 缓冲区指向 `:GDShaderRename`
  即可（见下方示例）；或在 gdshader 中用 `grn`。

- **Snippets**：仓库附带 `snippets/gdshader.json` 与 `snippets/gdshaderinc.json`，
  配合 [friendly-snippets](https://github.com/rafamadriz/friendly-snippets)
  或任意加载 `runtimepath/snippets/*.json` 的引擎即可获得片段补全。

## Extending · 扩展知识库

运行时合并自定义 GDShader 知识：

```lua
require("gdshader_nvim").extend({
  types = { "my_type" },
  shader_types = { "my_shader" },
  builtin_functions = {
    {
      name = "foo",
      signature = "foo(x)",
      snippet = "foo(${1:x})",
      description = "My custom function.",
      return_type = { kind = "same_as_argument", index = 1 },
    },
  },
  uniform_hints = {
    { name = "my_hint", types = { vec3 = true }, description = "..." },
  },
  builtin_variables = {
    spatial = {
      fragment = {
        { name = "MY_VAR", type = "vec3", mode = "out", detail = "..." },
      },
    },
  },
  processors = {
    spatial = {
      { name = "my_processor", detail = "...", allow_discard = false },
    },
  },
  render_modes = {
    spatial = { "my_render_mode" },
  },
})
```

也可通过 `setup({ extra = {...} })` 传入同样的表。知识库带有版本号，每次
`extend()` 都会自增版本以使缓存失效、自动重建查找表。

## API 参考 · API Reference

### Lua 模块函数

#### `require("gdshader_nvim").setup(opts)`

初始化插件。`opts` 会与默认值**深度合并**（列表拼接、表递归合并）。常用键见上文
“Configuration · 配置” 的完整示例，要点：

| 键 | 说明 |
| --- | --- |
| `filetypes` | 处理的文件类型，默认 `{ "gdshader", "gdshaderinc" }` |
| `features` | 各功能总开关（`completion` / `diagnostics` / `hover` / `definition` / `references` / `rename` / `color` / `format` / `template` / `semantic_tokens`） |
| `diagnostics.debounce_ms` | 诊断防抖（毫秒） |
| `keymaps` | `hover` / `definition` / `references` / `rename` / `edit`，设为 `false` 禁用，字符串则作为键位 |
| `completion.trigger_characters` | 触发补全的字符 |
| `color` | 见“颜色功能详解”（`editor` / `decorate` / `debounce_ms` / `swatch` / `swatch_pad_left` / `swatch_pad_right`） |
| `semantic_tokens` | `hl_group` / `debounce_ms` |
| `format.on_save` | 保存时自动格式化（与 conform 二选一） |
| `references.picker` | `auto` / `telescope` / `quickfix` |
| `treesitter` | 是否优先用 tree-sitter 处理注释 |
| `extra` | 扩展知识库（同 `extend` 的表结构） |

```lua
require("gdshader_nvim").setup({
  features = { color = true },
  color = { decorate = true, swatch = "■" },
  keymaps = { edit = "<leader>ce" },
})
```

#### `require("gdshader_nvim").extend(extra)`

运行时合并自定义 GDShader 知识库，自增版本号使缓存失效、重建查找表。
`extra` 结构同 `setup({ extra = {...} })`：

```lua
require("gdshader_nvim").extend({
  types = { "my_type" },
  shader_types = { "my_shader" },
  builtin_functions = {
    { name = "foo", signature = "foo(x)", snippet = "foo(${1:x})",
      description = "My custom function.",
      return_type = { kind = "same_as_argument", index = 1 } },
  },
  uniform_hints = { { name = "my_hint", types = { vec3 = true }, description = "..." } },
  builtin_variables = { spatial = { fragment = { { name = "MY_VAR", type = "vec3", mode = "out" } } } },
  processors = { spatial = { { name = "my_processor", detail = "...", allow_discard = false } } },
  render_modes = { spatial = { "my_render_mode" } },
})
```

### 命令（每个 gdshader 缓冲区自动注册）

| 命令 | 参数 | 说明 |
| --- | --- | --- |
| `:GDShaderHover` | 无 | 悬停信息（签名/类型/常量/uniform hint/文档注释）。等价键位 `K`。 |
| `:GDShaderDefinition` | 无 | 跳转定义（变量 / 函数 / `#include`）。等价键位 `gd`。 |
| `:GDShaderReferences` | 无 | 查找引用，结果用 telescope（若可用）或 quickfix 展示。等价键位 `grr`。 |
| `:GDShaderRename` | `[new]` | 重命名光标符号；可带新名称参数，或交互输入。等价键位 `grn`。 |
| `:GDShaderFormat` | 无 | 格式化当前缓冲区（缩进规整）。 |
| `:GDShaderInsertTemplate` | 无 | 插入着色器模板（如 `shader_spatial` / `uniform_range` / `func_fragment`）。 |
| `:GDShaderPreviewColor` | 无 | 预览光标处 `vec3/vec4` 颜色的 `HEX / ARGB / RGBA`，4 秒后自动关闭。 |
| `:GDShaderColorDecoration` | 无 | 切换行内颜色色块（on/off 并即时刷新）。 |
| `:GDShaderEditColor` | 无 | 编辑光标处颜色：浮动窗口输入 `R/G/B(/A)` 或 `HEX`，`<CR>` 写回、`q` 取消。可经 `keymaps.edit` 绑定快捷键（默认 `<leader>ce` 之类未绑定）。 |

> 颜色相关命令仅在光标位于合法 `vec3/vec4`（`[0,1]` 分量）颜色字面量上才有输出；
> 否则会 `vim.notify` 提示“no color literal on this line”。

## Health · 健康检查

运行 `:checkhealth gdshader_nvim` 检查插件、blink.cmp 以及可选的 `gdshader`
tree-sitter 语法是否就绪。

## License · 许可证

[MIT](./LICENSE) © XiaoDouXd and contributors
