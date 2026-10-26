shader_type sky;
// A gradient sky with a sun disc and soft clouds drifting across a flat layer
// overhead.

uniform vec3 top_color : source_color = vec3(0.22, 0.47, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.85, 0.97);
uniform vec3 below_color : source_color = vec3(0.45, 0.6, 0.75);
// How quickly the sky darkens from the horizon up; higher keeps the pale band
// thinner.
uniform float gradient_curve : hint_range(0.1, 4.0) = 0.6;

uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
// Sun disc size (degrees across).
uniform float sun_size : hint_range(0.1, 10.0) = 2.5;
uniform float sun_glow : hint_range(0.0, 1.0) = 0.3;

uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.72, 0.78, 0.86);
// Fraction of the sky with cloud.
uniform float coverage : hint_range(0.0, 1.0) = 0.45;
// Edge softness: low is crisp, high is wispy.
uniform float softness : hint_range(0.01, 0.5) = 0.15;
// Size of the cloud shapes; higher makes bigger clouds.
uniform float cloud_scale : hint_range(0.05, 5.0) = 1.0;
// Drift direction and speed across the sky.
uniform vec2 wind = vec2(0.01, 0.004);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		sum += amp * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return sum;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = max(dir.y, 0.0);
	vec3 color = mix(horizon_color, top_color, pow(up, gradient_curve));
	color = mix(color, below_color, smoothstep(0.0, -0.1, dir.y));

	if (LIGHT0_ENABLED) {
		float angle = acos(clamp(dot(dir, LIGHT0_DIRECTION), -1.0, 1.0));
		float radius = radians(sun_size) * 0.5;
		color += sun_color * sun_glow * exp(-angle * 6.0) * LIGHT0_ENERGY;
		color = mix(color, sun_color * 4.0 * LIGHT0_ENERGY, 1.0 - smoothstep(radius * 0.8, radius, angle));
	}

	if (dir.y > 0.0) {
		// Project onto a flat layer overhead, so clouds shrink toward the horizon.
		vec2 uv = dir.xz / (dir.y + 0.15) / cloud_scale + wind * TIME;
		float density = fbm(uv * 2.0);
		float cloud = smoothstep(1.0 - coverage - softness, 1.0 - coverage + softness, density);
		// Thicker parts are shaded, as their undersides would be.
		vec3 tint = mix(cloud_color, cloud_shade, smoothstep(0.5, 1.0, density));
		cloud *= smoothstep(0.0, 0.08, dir.y);  // fade into the horizon haze
		color = mix(color, tint, cloud);
	}

	COLOR = color;
}
