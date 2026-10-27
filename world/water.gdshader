shader_type spatial;
render_mode cull_disabled, depth_draw_always;

// Kept in step with Water.height_at() by water.gd.
uniform vec4 shallow_color : source_color = vec4(0.3, 0.65, 0.95, 0.75);
uniform vec4 deep_color : source_color = vec4(0.0, 0.04, 0.18, 1.0);
// Depth below the surface at which the water is fully deep_color (m).
uniform float deep_depth = 6.0;
uniform vec4 horizon_color : source_color = vec4(0.66, 0.7, 0.6, 1.0);
uniform float horizon_falloff = 6.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform float amplitude = 0.3;
uniform float period = 6.0;
uniform float wavelength = 0.0;
uniform vec2 direction = vec2(1.0, 0.0);
uniform float wave_time = 0.0;
uniform vec4 foam_color : source_color = vec4(0.95, 0.97, 1.0, 0.9);
// How far out from the waterline the foam reaches (m, across the surface).
uniform float foam_width = 0.8;
// How ragged the foam's edge is, 0 for a clean band.
uniform float foam_breakup = 0.6;
// Size of the foam's blotches (m).
uniform float foam_scale = 1.5;
// Distance across the surface to the waterline (m, negative on land), baked by
// water.gd over shore_rect (xy its -X -Z corner, zw its size, m): r with the
// sea at its lowest, g at its highest. Outside it the sea is open.
uniform sampler2D shore_distance : filter_linear, repeat_disable;
uniform vec4 shore_rect = vec4(0.0);
uniform float rest_height = 0.0;

varying vec3 wave_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return 0.5 * value_noise(p) + 0.3 * value_noise(p * 2.03 + 17.0) + 0.2 * value_noise(p * 4.01 + 31.0);
}

float shore_reach(vec2 xz, float level) {
	vec2 uv = (xz - shore_rect.xy) / max(shore_rect.zw, vec2(0.001));
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 1e4;
	}
	vec2 reach = textureLod(shore_distance, uv, 0.0).rg;
	return mix(reach.r, reach.g, level);
}

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
	vec3 surface = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float depth = surface.y - ground_y;
	float deep = smoothstep(0.0, deep_depth, depth);
	vec4 water = mix(shallow_color, deep_color, deep);
	// Seen at a low angle (far off) the water reads pale, like the haze toward
	// the horizon; looking down into it it keeps its own colour.
	vec3 normal = normalize((VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz);
	float grazing = pow(1.0 - clamp(dot(normal, VIEW), 0.0, 1.0), horizon_falloff);
	water.rgb = mix(water.rgb, horizon_color.rgb, grazing);
	// Foam in a band on the water around the shore, foam_width out from the
	// waterline, with a ragged outer edge that drifts. The distance to the
	// waterline is baked from the terrain, so it sits still whatever angle
	// it's seen from and holds on cliffs and flats alike; it's blended
	// between low and high water by how high the wave stands here.
	float level = amplitude > 0.0 ? clamp((surface.y - rest_height) / amplitude * 0.5 + 0.5, 0.0, 1.0) : 0.5;
	float reach = shore_reach(surface.xz, level);
	float shore = 1.0 - clamp(reach / foam_width, 0.0, 1.0);
	vec2 drift = direction * wave_time * 0.15;
	float blotch = fbm(surface.xz / foam_scale + drift) - 0.5;
	float foam = smoothstep(0.45, 0.55, shore + blotch * foam_breakup * 0.5);
	foam *= foam_color.a;
	water = mix(water, vec4(foam_color.rgb, 1.0), foam);
	ALBEDO = water.rgb;
	ALPHA = water.a;
	ROUGHNESS = mix(0.3, 0.9, foam);
	SPECULAR = 0.1;
	NORMAL = normal;
}
