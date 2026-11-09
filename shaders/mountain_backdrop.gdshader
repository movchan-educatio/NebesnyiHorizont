shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

// Distant mountain backdrop.  The colour is a per-pixel vertical gradient in
// world space, not a vertex-colour interpolation: the old per-triangle colours
// produced visible diagonal bands on the ridges.
uniform vec3 color_low : source_color = vec3(0.15, 0.20, 0.15);
uniform vec3 color_high : source_color = vec3(0.36, 0.42, 0.44);
uniform vec3 color_haze : source_color = vec3(0.72, 0.78, 0.84);
uniform float haze_amount = 0.30;
uniform float base_y = -60.0;
uniform float top_y = 260.0;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float t = clamp((world_y - base_y) / (top_y - base_y), 0.0, 1.0);
	vec3 c = mix(color_low, color_high, t);
	c = mix(c, color_haze, haze_amount * (0.30 + 0.70 * t));
	ALBEDO = c;
}
