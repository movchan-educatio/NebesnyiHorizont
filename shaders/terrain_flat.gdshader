shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_back;

// LOWSPEC terrain: a deliberately cheap, stylised ground shader.
//
// One albedo texture, one UV set, no normal maps, no PBR layers, no fBm and no
// specular lobe.  The vertex colour still carries the grass/dirt macro mask,
// so the map keeps its colour identity and the silhouettes stay readable.
// This is the "mobile FPV sim" look: flat, bright and very cheap per pixel.

uniform sampler2D ground_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 grass_tint : source_color = vec4(1.0);
uniform vec4 dirt_tint : source_color = vec4(1.0);
uniform float detail_scale : hint_range(0.01, 1.0) = 0.18;
uniform float macro_contrast : hint_range(0.0, 1.0) = 0.22;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_world.xz * detail_scale;
	vec3 tex = texture(ground_albedo, uv).rgb;
	float macro = clamp(COLOR.r, 0.0, 1.0);
	float grain = clamp(COLOR.g, 0.0, 1.0);
	vec3 tint = mix(dirt_tint.rgb, grass_tint.rgb,
			smoothstep(0.30, 0.72, macro + (grain - 0.5) * 0.24));
	// Keep most of the texture's own colour; the tints only grade it.
	tint = mix(vec3(1.0), tint, 0.45);
	vec3 col = tex * tint;
	col *= mix(1.0 - macro_contrast, 1.0 + macro_contrast, macro);
	col *= mix(0.94, 1.06, grain);
	col *= 1.05;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
