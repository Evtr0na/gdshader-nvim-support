shader_type spatial;

#ifdef EXTRA
uniform float extra = 1.0;

void fragment() {
	ALBEDO = vec3(1.0);
}
