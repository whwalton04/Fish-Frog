shader_type sky;
// A clear sky, deep blue overhead and lighter lower down, with a thin
// near-white haze along the horizon and a bright sun disc with a soft glow.

// The blue deepens from low_color just above the haze to top_color overhead.
uniform vec3 top_color : source_color = vec3(0.03, 0.13, 0.4);
uniform vec3 low_color : source_color = vec3(0.2, 0.4, 0.78);
// How quickly the blue deepens going up; lower turns deep sooner.
uniform float gradient_curve : hint_range(0.1, 4.0) = 0.6;
// The near-white haze along the horizon, and how high it reaches (as the
// height of the view direction, 0.1 is about 6 degrees).
uniform vec3 horizon_color : source_color = vec3(0.9, 0.94, 0.98);
uniform float haze_height : hint_range(0.005, 0.5) = 0.07;
uniform vec3 below_color : source_color = vec3(0.6, 0.72, 0.85);

uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
// Sun disc size (degrees across).
uniform float sun_size : hint_range(0.1, 10.0) = 2.0;
// How bright the disc is, independent of the light's energy. Above 1 it
// blooms to white through the tonemapper, as the real sun does.
uniform float sun_brightness : hint_range(0.0, 50.0) = 12.0;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.6;
// How far the glow reaches from the disc (degrees).
uniform float sun_glow_size : hint_range(0.5, 45.0) = 6.0;

void sky() {
	vec3 dir = EYEDIR;
	float up = max(dir.y, 0.0);
	vec3 color = mix(low_color, top_color, pow(up, gradient_curve));
	color = mix(color, horizon_color, exp(-up / haze_height));
	color = mix(color, below_color, smoothstep(0.0, -0.1, dir.y));

	if (LIGHT0_ENABLED) {
		float angle = acos(clamp(dot(dir, LIGHT0_DIRECTION), -1.0, 1.0));
		float radius = radians(sun_size) * 0.5;
		color += sun_color * sun_glow * exp(-angle / radians(sun_glow_size));
		// The disc, darker toward its rim, with a slightly soft edge.
		float r = clamp(angle / radius, 0.0, 1.0);
		float limb = mix(0.6, 1.0, sqrt(1.0 - r * r));
		float disc = 1.0 - smoothstep(0.85, 1.0, angle / radius);
		color = mix(color, sun_color * sun_brightness * limb, disc);
	}

	COLOR = color;
}
