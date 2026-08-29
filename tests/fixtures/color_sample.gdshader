shader_type spatial;

uniform vec4 tint : source_color = vec4(0.5, 0.2, 0.8, 1.0);
uniform vec3 base : source_color = vec3(0.1, 0.9, 0.3);

void fragment() {
	ALBEDO = base;
	ALPHA = tint.a;
}
