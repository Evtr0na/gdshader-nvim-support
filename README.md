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
  },
  completion = { trigger_characters = { ".", ":", ",", " " } },
  color = { decorate = false, debounce_ms = 200, editor = "auto" },  -- 行内色块；editor: auto|builtin|ccc
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
- `:GDShaderEditColor` — 编辑光标处颜色（浮动窗口输入 R/G/B/A 或 HEX，回车写回缓冲区）
- `:GDShaderEditColor` — 编辑光标处颜色（浮动窗口输入 R/G/B/A，回车写回缓冲区）

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

## Health · 健康检查

运行 `:checkhealth gdshader_nvim` 检查插件、blink.cmp 以及可选的 `gdshader`
tree-sitter 语法是否就绪。

## License · 许可证

[MIT](./LICENSE) © XiaoDouXd and contributors
