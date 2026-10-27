shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 0.3) = 0.0;

void fragment() {
	// Measure radius in screen space so curvature is consistent across aspects.
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 centered = (SCREEN_UV - vec2(0.5)) * vec2(aspect, 1.0);
	vec2 corner = vec2(aspect, 1.0) * 0.5;
	float radius_squared = dot(centered, centered) / dot(corner, corner);
	// Outward source sampling creates a barrel bulge in the displayed image.
	// Normalize by the corner scale to keep the whole frame filled, without
	// black borders or wrapping. At zero strength this is an identity mapping.
	float scale = (1.0 + strength * radius_squared) / (1.0 + strength);
	vec2 sample_uv = vec2(0.5) + centered * scale / vec2(aspect, 1.0);
	COLOR = textureLod(screen_texture, sample_uv, 0.0);
}
