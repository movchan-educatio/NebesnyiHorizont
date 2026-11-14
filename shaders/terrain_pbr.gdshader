shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// Photoreal ground shader for the procedural frontline maps.
//
// Four PBR materials (grass / dirt / rock / mud) are blended per pixel:
//   * slope drives rock exposure,
//   * height above the local water line drives mud / wet ground,
//   * vertex COLOR.r (broad 22 m patches) drives grass vs dirt,
//   * vertex COLOR.g (3 m grain) breaks up the transitions.
//
// World-space UVs keep the texel density constant across the 1 km clipmap and
// every layer uses anisotropic mipmapped sampling, so the ground stays clean at
// FPV dive speeds instead of sparkling.  Detail normals fade out with distance
// to kill the far-field shimmer on low-end GPUs.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec4 grass_tint : source_color = vec4(1.0);
uniform vec4 dirt_tint : source_color = vec4(1.0);
uniform vec4 rock_tint : source_color = vec4(1.0);
uniform vec4 mud_tint : source_color = vec4(1.0);

uniform float detail_scale : hint_range(0.01, 1.0) = 0.16;
uniform float macro_scale : hint_range(0.001, 0.2) = 0.02;
uniform float grass_bias : hint_range(-1.0, 1.0) = 0.0;
uniform float mud_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wet_height = -999.0;
uniform float wet_falloff : hint_range(0.5, 30.0) = 4.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;
uniform float grass_roughness : hint_range(0.0, 1.0) = 0.94;
uniform float dirt_roughness : hint_range(0.0, 1.0) = 0.93;
uniform float rock_roughness : hint_range(0.0, 1.0) = 0.86;
uniform float mud_roughness : hint_range(0.0, 1.0) = 0.78;
uniform float macro_contrast : hint_range(0.0, 1.0) = 0.28;
uniform float micro_strength : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_world;
varying vec3 v_world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
	return value_noise(p) * 0.62 + value_noise(p * 2.03 + 7.31) * 0.38;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = v_world.xz * detail_scale;
	// Second, rotated and differently-scaled UV set.  Blending the two breaks
	// the 6 m texture repeat so no tile grid is visible from the air.
	vec2 uv_b = vec2(v_world.x * 0.115 + v_world.z * 0.052,
			v_world.z * 0.115 - v_world.x * 0.052);
	// Close-range grain: 0.6 m tiles.  Without this third UV set the ground
	// became a smooth painted surface at FPV altitude even though it had
	// colour detail at 4-8 m.
	vec2 uv_c = vec2(v_world.x * 1.15 + v_world.z * 0.35,
			v_world.z * 1.15 - v_world.x * 0.35);
	vec2 macro_uv = v_world.xz * macro_scale;

	float macro = COLOR.r;
	float grain = COLOR.g;
	float slope = clamp(max(1.0 - v_world_normal.y, COLOR.b), 0.0, 1.0);
	float ao_baked = COLOR.a;
	float cavity = clamp((0.92 - ao_baked) / 0.70, 0.0, 1.0);
	float ridge = clamp((ao_baked - 0.92) / 0.08, 0.0, 1.0);
	float broad = fbm2(macro_uv * 3.0);
	float fine = fbm2(vec2(v_world.x + v_world.z * 0.7, v_world.z - v_world.x * 0.35) * 0.55);
	float view_dist = length(v_world - CAMERA_POSITION_WORLD);
	float micro_fade = 1.0 - smoothstep(25.0, 140.0, view_dist);

	// ---- layer weights -----------------------------------------------------
	float grass_w = smoothstep(0.30, 0.74, macro * 0.72 + broad * 0.28 + grass_bias);
	float dirt_w = (1.0 - grass_w) * (0.35 + grain * 0.65);
	float rock_w = smoothstep(0.18, 0.52, slope + (grain - 0.5) * 0.12);
	float mud_w = (1.0 - smoothstep(wet_height, wet_height + wet_falloff, v_world.y)) * mud_amount;

	grass_w *= 1.0 - rock_w;
	dirt_w *= 1.0 - rock_w;

	float sum_w = grass_w + dirt_w + rock_w + mud_w + 0.0001;
	grass_w /= sum_w;
	dirt_w /= sum_w;
	rock_w /= sum_w;
	mud_w /= sum_w;

	// ---- albedo ------------------------------------------------------------
	// Two-scale sampling: the second UV set is rotated and uses a different
	// tile size, so the repeat pattern dissolves instead of forming a grid.
	vec3 c_grass = mix(texture(grass_albedo, uv).rgb, texture(grass_albedo, uv_b).rgb, 0.32) * grass_tint.rgb;
	vec3 c_dirt = mix(texture(dirt_albedo, uv).rgb, texture(dirt_albedo, uv_b).rgb, 0.32) * dirt_tint.rgb;
	vec3 c_rock = mix(texture(rock_albedo, uv).rgb, texture(rock_albedo, uv_b).rgb, 0.32) * rock_tint.rgb;
	vec3 c_mud = mix(texture(mud_albedo, uv).rgb, texture(mud_albedo, uv_b).rgb, 0.32) * mud_tint.rgb;

	vec3 albedo = c_grass * grass_w + c_dirt * dirt_w + c_rock * rock_w + c_mud * mud_w;
	vec3 micro = texture(dirt_albedo, uv_c).rgb;
	float micro_l = dot(micro, vec3(0.299, 0.587, 0.114));
	albedo *= mix(1.0, mix(0.90, 1.10, micro_l), micro_strength * micro_fade);
	// Two scales of luminance variation + dual-scale anti-tiling world noise (0.021 & 0.067).
	float macro_a = value_noise(v_world.xz * 0.021);
	float macro_b = value_noise(v_world.xz * 0.067 + vec2(13.7, 29.3));
	float proc_macro = clamp(macro_a * 0.60 + macro_b * 0.40, 0.0, 1.0);
	float macro_lum = mix(1.0 - macro_contrast, 1.0 + macro_contrast,
			clamp(macro * 0.35 + broad * 0.25 + proc_macro * 0.40, 0.0, 1.0));
	float micro_lum = mix(0.93, 1.07, clamp(proc_macro * 0.55 + fine * 0.45, 0.0, 1.0));
	vec3 hue_mod = mix(vec3(0.96, 1.02, 0.96), vec3(1.04, 0.99, 0.95), macro_b);
	albedo *= macro_lum * micro_lum * hue_mod;

	// Wet ground is darker and slightly more saturated, like real marsh mud.
	float lowland = 1.0 - smoothstep(wet_height - 0.4, wet_height + 2.6, v_world.y);
	float wet = clamp(mud_w * 1.45 + lowland * (0.45 + cavity * 0.75) * mud_amount, 0.0, 1.0);
	albedo *= mix(1.0, 0.60, wet);
	albedo = mix(albedo, albedo * vec3(0.84, 0.80, 0.76), cavity * 0.50);
	albedo *= mix(1.0, 0.58, cavity) * (1.0 + ridge * 0.05);

	ALBEDO = albedo;
	AO = clamp(mix(1.0, 0.34, cavity), 0.22, 1.0);
	AO_LIGHT_AFFECT = 0.65;

	// ---- normals -----------------------------------------------------------
	float detail_fade = 1.0 - smoothstep(120.0, 700.0, view_dist);
	vec3 n_grass = texture(grass_normal, uv).rgb * 2.0 - 1.0;
	vec3 n_dirt = texture(dirt_normal, uv).rgb * 2.0 - 1.0;
	vec3 n_rock = texture(rock_normal, uv).rgb * 2.0 - 1.0;
	vec3 n_mud = texture(mud_normal, uv).rgb * 2.0 - 1.0;
	vec3 n = n_grass * grass_w + n_dirt * dirt_w + n_rock * rock_w + n_mud * mud_w;
	vec3 n_micro = texture(dirt_normal, uv_c).rgb * 2.0 - 1.0;
	n += n_micro * micro_strength * micro_fade * 0.85;
	n.xy *= normal_strength * detail_fade;
	n.z = max(n.z, 0.25);
	NORMAL_MAP = normalize(n) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.35;

	// ---- roughness / specular ---------------------------------------------
	float rough = grass_roughness * grass_w + dirt_roughness * dirt_w
			+ rock_roughness * rock_w + mud_roughness * mud_w;
	rough += (fine - 0.5) * 0.08;
	// Dynamic micro-roughness derived from surface luminance for crisp tactile depth
	float tex_luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	rough = clamp(rough + (tex_luma - 0.48) * 0.28 - cavity * 0.08, 0.18, 0.98);
	ROUGHNESS = clamp(mix(rough, 0.15, wet * 0.86), 0.12, 1.0);
	SPECULAR = mix(0.40, 0.85, wet);
	METALLIC = 0.0;
}
