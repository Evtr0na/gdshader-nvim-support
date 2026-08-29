shader_type canvas_item;

// 对齐：内置函数调用参数数量 / 类型检查（vscode 不查内置函数，此处强化）
// 期望：
//   - texture(tex)                       -> arg-count（期望 2，给 1）
//   - texture(vec3(1.0), vec2(0.0))      -> arg-type（第1参 sampler2D 收 vec3）
//   - sin()                             -> arg-count（期望 1，给 0）
//   - dot(vec3, vec3) / texture(tex,uv) -> 正确，无诊断
uniform sampler2D tex;

void fragment() {
    // 正确调用：2 个参数，类型匹配 -> 无诊断
    vec4 c1 = texture(tex, vec2(0.0));

    // 参数数量不符：只给 1 个 -> arg-count
    vec4 c2 = texture(tex);

    // 参数类型不符：第 1 个参数应为 sampler2D，却给 vec3 -> arg-type
    vec4 c3 = texture(vec3(1.0), vec2(0.0));

    // 泛型内置（dot(T, T)）：类型不查，数量正确 -> 无诊断
    float d = dot(vec3(1.0), vec3(1.0));

    // 数量不符：sin 期望 1 个，给 0 个 -> arg-count
    float s = sin();

    COLOR = c1;
}
