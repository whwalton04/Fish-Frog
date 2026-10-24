shader_type spatial;
render_mode cull_disabled, depth_draw_always;

// Kept in step with Water.height_at() by water.gd.
uniform vec4 shallow_color : source_color = vec4(0.3, 0.65, 0.95, 0.75);
uniform vec4 deep_color : source_color = vec4(0.0, 0.04, 0.18, 1.0);
// Depth below the surface at which the water is fully deep_color (m).
uniform float deep_depth = 6.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
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
	// How far below the surface the ground seen through this pixel is. With
	// nothing behind the water (open sea) that's the far plane, so it's deep.
	float raw = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, raw) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
#endif
	vec4 behind = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float ground_y = (INV_VIEW_MATRIX * vec4(behind.xyz / behind.w, 1.0)).y;
	float surface_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float deep = smoothstep(0.0, deep_depth, surface_y - ground_y);
	vec4 water = mix(shallow_color, deep_color, deep);
	ALBEDO = water.rgb;
	ALPHA = water.a;
	ROUGHNESS = 0.3;
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz);
}
