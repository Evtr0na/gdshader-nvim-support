shader_type spatial;

// 局部变量遮蔽参数名 'idx'：应报 param-shadow warning
// （对齐 vscode analyzer.shadowParam）
void fragment(int idx) {
    float idx = 1.0;
    vec3 col = vec3(idx);
    ALBEDO = col;
}

// 参数未被遮蔽：不应报任何诊断
void vertex(float time) {
    vec3 pos = vec3(time);
    VERTEX = pos;
}
