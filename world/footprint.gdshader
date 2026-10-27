shader_type spatial;
// One crab footprint in the sand, drawn by Footprints. Shaded as a round bowl
// with sand pushed up into a lip around it, lit from light_dir: walls facing
// the light come out lighter than the sand around, the far walls darker, and
// the centre a little darker still. Blended as a black or white tint over the
// sand, so it suits whatever light the sand is in.
//
// INSTANCE_CUSTOM.r is when the print was made, .g a random 0..1 per print.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

// As fractions of the print's radius: where the bowl ends, and where the lip
// peaks and how wide it is.
const float BOWL_RADIUS = 0.6;
const float LIP_RADIUS = 0.68;
const float LIP_WIDTH = 0.14;
// The bowl's depth over the print's radius.
const float STEEPNESS = 0.35;

uniform float now = 0.0;
uniform float lifetime = 12.0;
uniform float darkness = 0.15;
uniform float shading = 0.3;
uniform float lip = 0.1;
uniform vec3 light_dir = vec3(0.0, 1.0, 0.0);  // world space, toward the light

varying float fade;
varying float seed;
varying vec2 local_xz;  // -1..1 across the print
varying vec3 world_x;
varying vec3 world_y;
varying vec3 world_z;

void vertex() {
	float age = now - INSTANCE_CUSTOM.r;
	// Holds a while, then eases out.
	fade = 1.0 - smoothstep(0.3, 1.0, age / lifetime);
	seed = INSTANCE_CUSTOM.g;
	local_xz = VERTEX.xz * 2.0;
	world_x = normalize((MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	world_y = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	world_z = normalize((MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
}

void fragment() {
	if (fade <= 0.0) {
		discard;
	}
	float d = length(local_xz);
	// Bowl: height -q² with q = 1 - (d / BOWL_RADIUS)², in bowl depths.
	float q = max(1.0 - d * d / (BOWL_RADIUS * BOWL_RADIUS), 0.0);
	float depth = q * q;
	float slope = 4.0 * q * d / (BOWL_RADIUS * BOWL_RADIUS);  // d(height)/d(radius)
	// Lip: a ring `lip` bowl depths high.
	float t = (d - LIP_RADIUS) / LIP_WIDTH;
	float ring = exp(-t * t);
	slope -= lip * ring * 2.0 * t / LIP_WIDTH;
	// The shading softens from the middle of the bowl outward, so the rim
	// fades into the sand rather than ending on a hard ring.
	float edge = 1.0 - smoothstep(0.35, 0.95, d);

	vec2 gradient = slope * STEEPNESS * local_xz / max(d, 1e-4);
	vec3 n = normalize(world_y - gradient.x * world_x - gradient.y * world_z);
	vec3 l = normalize(light_dir);
	float lit = shading * (dot(n, l) - dot(world_y, l));

	float tint = (lit - darkness * depth) * edge * fade * (0.85 + 0.3 * seed);
	ALBEDO = tint > 0.0 ? vec3(1.0, 0.98, 0.92) : vec3(0.0);
	ALPHA = clamp(abs(tint), 0.0, 1.0);
}
