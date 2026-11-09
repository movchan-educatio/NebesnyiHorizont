shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Cheap, reliable light shaft used inside the big halls.  Volumetric fog does
// the physical work; these cones guarantee a visible beam on every quality
// preset and keep the reference's hard shafts even when shadows are cheap.

uniform vec4 ray_color : source_color = vec4(1.0, 0.84, 0.62, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.34;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.35;
uniform float speed : hint_range(0.0, 2.0) = 0.06;
uniform float dust_strength : hint_range(0.0, 1.0) = 0.22;

varying vec2 v_uv;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_uv = UV;
}

void fragment() {
	// Fade the cone's silhouette and its far end so the additive geometry does
	// not read as a solid tube.
	float around = sin(v_uv.x * 3.14159265);
	around = smoothstep(0.0, edge_softness, around);
	float length_fade = smoothstep(0.0, 0.18, v_uv.y)
			* (1.0 - smoothstep(0.62, 1.0, v_uv.y));
	float streak = 0.72 + 0.28 * hash12(floor(v_uv * vec2(18.0, 32.0))
			+ floor(TIME * speed * 40.0));
	float alpha = intensity * around * length_fade * mix(1.0, streak, dust_strength);
	// Alpha-mixed translucent shaft; additive blending on this cylindrical
	// shell turned into a solid white ribbon on Intel GPUs.
	ALBEDO = ray_color.rgb;
	ALPHA = clamp(alpha, 0.0, 0.24);
}
