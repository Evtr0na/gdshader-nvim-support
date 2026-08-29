shader_type spatial;

#include "res://shaders/utils.gdshaderinc" // #gdshader-hint-ignore

// #gdshader-hint-type:vec3
var custom = get_data();

// #gdshader-hint-declare:vec4 blend(vec4 a, vec4 b);
// #gdshader-hint-define:MAX 64

void fragment() {
	ALBEDO = vec3(1.0);
}
