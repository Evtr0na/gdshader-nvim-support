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

- Completion (via [blink.cmp](https://github.com/Saghen/blink.cmp)) ·
  基于 blink.cmp 的补全
- Diagnostics · 诊断
- Hover · 悬停提示
- Go to definition · 跳转定义
- Find references · 查找引用
- Rename · 重命名

## Requirements · 环境要求

- Neovim >= 0.10
- [blink.cmp](https://github.com/Saghen/blink.cmp)（仅 `completion` 功能需要）
- `gdshader` tree-sitter 语法（可选，推荐；缺失时回退到内置词法分析器处理注释）

## Installation · 安装

### lazy.nvim

```lua
{
  "XiaoDouXd/gdshader-nvim-support",
  config = function()
    require("gdshader_nvim").setup()
  end,
}
```

### blink.cmp 补全源

```lua
require("blink.cmp").setup({
  sources = {
    default = { "gdshader", "lsp", "path", "buffer" },
    providers = {
      gdshader = { name = "GDShader", module = "gdshader_nvim" },
    },
  },
})
```

blink 会通过 `require("gdshader_nvim").new()` 实例化补全源。

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
  },
  diagnostics = { debounce_ms = 150 },
  keymaps = {                                   -- 设为 false 可禁用对应映射
    hover      = "K",
    definition = "gd",
    references = "grr",
    rename     = "grn",
  },
  completion = { trigger_characters = { ".", ":", ",", " " } },
  treesitter = true,
  extra = {},   -- 扩展知识库，见下方“Extending”
})
```

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
