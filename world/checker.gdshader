shader_type spatial;
// World-space checker so movement is easy to read on flat ground.

uniform vec4 color_a : source_color = vec4(0.78, 0.72, 0.56, 1.0);
uniform vec4 color_b : source_color = vec4(0.70, 0.64, 0.49, 1.0);
uniform float cell_size = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cell = floor(world_pos / cell_size + 0.0013);
	float checker = mod(cell.x + cell.y + cell.z, 2.0);
	ALBEDO = mix(color_a.rgb, color_b.rgb, checker);
	ROUGHNESS = 0.9;
}
