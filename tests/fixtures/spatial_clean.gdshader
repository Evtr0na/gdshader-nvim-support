shader_type spatial;
render_mode blend_mix;

uniform vec4 albedo : source_color = vec4(1.0);

void vertex() {
	VERTEX = vec3(0.0);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
}

void light() {
	DIFFUSE_LIGHT = vec3(0.0);
}
