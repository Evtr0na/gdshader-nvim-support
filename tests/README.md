# Regression fixtures

Hand-picked `.gdshader` samples that exercise each diagnostic category of
gdshader-nvim-support. Open any file in Neovim (with the plugin set up) and
confirm the diagnostics / decorations match the expectation noted in its
header comment.

| Fixture | Expects |
| --- | --- |
| spatial_clean.gdshader | no diagnostics |
| missing_shader_type.gdshader | error: missing shader_type |
| invalid_shader_type.gdshader | error: unknown shader type |
| invalid_processor.gdshader | warning: processor not valid for shader_type |
| discard_in_vertex.gdshader | error: discard not allowed in processor |
| readonly_builtin.gdshader | error: built-in variable read-only |
| unmatched_delimiter.gdshader | error: unmatched delimiter |
| missing_semicolon.gdshader | warning: missing semicolon |
| return_in_processor.gdshader | error: return in processor |
| duplicate_decl.gdshader | error: duplicate declaration |
| unclosed_cond.gdshader | error: unclosed #if |
| hint_comments.gdshader | no diagnostics (hint comments recognised) |
| color_sample.gdshader | inline swatches on vec3/vec4; :GDShaderEditColor works |
| param_shadow.gdshader | warning: parameter shadowing (local var 'idx' shadows param 'idx') |
| type_mismatch.gdshader | error: type mismatch (decl init `float x = vec3(...)`; assignment `vec3 = float`) |
| call_args.gdshader | error: arg-count (combine expects 2, got 1); error: arg-type (param 'b' float, got vec3) |
| builtin_call_args.gdshader | error: arg-count (texture/sin 缺参); error: arg-type (texture 第1参 sampler2D 收 vec3); dot 泛型无误报 |

A future harness can parse `:GDShader...` diagnostics programmatically; for now
these files serve as a manual regression checklist and as inputs for any
automated test you wire up (e.g. via `nvim --headless` + a diagnostic dumper).