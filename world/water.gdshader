shader_type spatial;
render_mode cull_disabled, depth_draw_always;

// Kept in step with Water.height_at() by water.gd.
uniform vec4 color : source_color = vec4(0.3, 0.65, 0.95, 0.85);
uniform float amplitude = 0.3;
uniform float period = 4.0;
uniform float wavelength = 0.0;
uniform vec2 direction = vec2(1.0, 0.0);
uniform float wave_time = 0.0;

varying vec3 wave_normal;

void vertex() {
	vec3 world =(MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float along = wavelength > 0.0 ? dot(direction, world.xz) / wavelength : 0.0;
	float phase = TAU * (wave_time / period - along);
	VERTEX.y += amplitude * sin(phase);
	vec2 slope = wavelength > 0.0
			? -amplitude * cos(phase) * TAU / wavelength * direction
			: vec2(0.0);
	wave_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ROUGHNESS = 0.3;
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz);
}
