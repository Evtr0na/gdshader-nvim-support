shader_type spatial;

// 声明初始化类型不匹配：float 被赋 vec3
// 对齐 vscode analyzer.typeMismatch
void fragment() {
    float wrong = vec3(1.0, 2.0, 3.0);
    ALBEDO = vec3(wrong);
}

// 赋值语句类型不匹配：vec3 变量被赋 float
void vertex() {
    vec3 col = vec3(1.0);
    float f = 1.0;
    col = f;
    VERTEX = col;
}
