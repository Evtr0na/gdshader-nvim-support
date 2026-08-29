shader_type spatial;

// 用户函数：用于校验调用参数数量 / 类型
// 对齐 vscode analyzer.checkCallArgs
vec3 combine(vec3 a, float b) {
    return a * b;
}

void fragment() {
    // 正确调用：2 个参数，类型匹配
    vec3 good = combine(vec3(1.0), 2.0);

    // 参数数量不符：只给 1 个 -> arg-count
    vec3 bad1 = combine(vec3(1.0));

    // 参数类型不符：第二个参数应为 float，却给 vec3 -> arg-type（L17 报 'b' float got vec3）
    vec3 bad2 = combine(vec3(1.0), vec3(1.0));

    ALBEDO = good;
}
