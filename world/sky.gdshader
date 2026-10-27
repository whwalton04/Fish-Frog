shader_type sky;
// A clear gradient sky, deep blue overhead and paler toward the horizon, with
// a sun disc.

uniform vec3 top_color : source_color = vec3(0.057, 0.219, 0.502);
uniform vec3 horizon_color : source_color = vec3(0.306, 0.469, 0.851);
uniform vec3 below_color : source_color = vec3(0.45, 0.6, 0.75);
// How quickly the sky darkens from the horizon up; higher keeps the pale band
// thinner.
uniform float gradient_curve : hint_range(0.1, 4.0) = 0.6;

uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
// Sun disc size (degrees across).
uniform float sun_size : hint_range(0.1, 10.0) = 2.5;
uniform float sun_glow : hint_range(0.0, 1.0) = 0.3;

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

	COLOR = color;
}
