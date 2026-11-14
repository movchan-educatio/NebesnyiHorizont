shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// Cheap terrain variant for the low-end presets (РќРР—Р¬РљРђ / 120 FPS / РџР›РђР’РќРћ).
//
// The full terrain_pbr.gdshader samples 14 textures per pixel (two UV sets for
// four layers, plus two detail maps) and evaluates two fBm noise fields.
// Fragment cost dominated the frame time on Intel UHD.  This variant keeps the
// four-layer blend that gives each map its colour identity but:
//   * samples every albedo once (4 textures instead of 8),
//   * drops the detail-normal and micro-detail samples entirely,
//   * replaces the fBm with the vertex-colour grain,
//   * uses a constant per-layer roughness.
//
// On the ground it reads as the same battlefield from FPV altitude; the loss is
// only visible when hovering a metre above the dirt.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_albedo : source_color, filter_linear_mipmap, repeat_enable;

uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap, repeat_enable;

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
uniform float normal_strength : hint_range(0.0, 2.0) = 0.95;
uniform float grass_roughness : hint_range(0.0, 1.0) = 0.94;
uniform float dirt_roughness : hint_range(0.0, 1.0) = 0.93;
uniform float rock_roughness : hint_range(0.0, 1.0) = 0.86;
uniform float mud_roughness : hint_range(0.0, 1.0) = 0.78;
uniform float macro_contrast : hint_range(0.0, 1.0) = 0.28;

varying vec3 v_world;
varying vec3 v_world_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float macro = COLOR.r;
	float grain = COLOR.g;
	float slope = clamp(max(1.0 - v_world_normal.y, COLOR.b), 0.0, 1.0);
	float ao_baked = COLOR.a;
	float cavity = clamp((0.92 - ao_baked) / 0.70, 0.0, 1.0);
	float ridge = clamp((ao_baked - 0.92) / 0.08, 0.0, 1.0);

	// Dual-scale world-space procedural macro noise (0.021 & 0.067) computed before
	// texture lookups so we can domain-warp & break repeating tiles at altitude
	// with zero extra texture samplers.
	vec2 np1 = v_world.xz * 0.021;
	vec2 ni1 = floor(np1);
	vec2 nf1 = np1 - ni1;
	vec2 nu1 = nf1 * nf1 * (3.0 - 2.0 * nf1);
	vec4 nh1 = fract(sin(vec4(
			dot(ni1, vec2(127.1, 311.7)),
			dot(ni1 + vec2(1.0, 0.0), vec2(127.1, 311.7)),
			dot(ni1 + vec2(0.0, 1.0), vec2(127.1, 311.7)),
			dot(ni1 + vec2(1.0, 1.0), vec2(127.1, 311.7)))) * 43758.5453);
	float macro_a = mix(mix(nh1.x, nh1.y, nu1.x), mix(nh1.z, nh1.w, nu1.x), nu1.y);

	vec2 np2 = v_world.xz * 0.067 + vec2(13.7, 29.3);
	vec2 ni2 = floor(np2);
	vec2 nf2 = np2 - ni2;
	vec2 nu2 = nf2 * nf2 * (3.0 - 2.0 * nf2);
	vec4 nh2 = fract(sin(vec4(
			dot(ni2, vec2(127.1, 311.7)),
			dot(ni2 + vec2(1.0, 0.0), vec2(127.1, 311.7)),
			dot(ni2 + vec2(0.0, 1.0), vec2(127.1, 311.7)),
			dot(ni2 + vec2(1.0, 1.0), vec2(127.1, 311.7)))) * 43758.5453);
	float macro_b = mix(mix(nh2.x, nh2.y, nu2.x), mix(nh2.z, nh2.w, nu2.x), nu2.y);

	// Low-frequency C^1 domain warp + per-layer rotated/scaled UVs eliminate
	// visible field grids from altitude while keeping mip derivatives smooth.
	vec2 uv = v_world.xz * detail_scale;
	vec2 uv_warp = vec2(macro_a - 0.5, macro_b - 0.5) * 0.28
			+ vec2(sin(v_world.z * 0.031), cos(v_world.x * 0.029)) * 0.11;
	vec2 uv_grass = vec2(uv.x * 0.927 + uv.y * 0.375, -uv.x * 0.375 + uv.y * 0.927) + uv_warp;
	vec2 uv_dirt = (vec2(uv.x * 0.799 - uv.y * 0.602, uv.x * 0.602 + uv.y * 0.799) + uv_warp * 0.8) * 1.07;
	vec2 uv_rock = (vec2(uv.x * 0.602 + uv.y * 0.799, -uv.x * 0.799 + uv.y * 0.602) - uv_warp * 0.6) * 0.93;
	vec2 uv_mud = (vec2(uv.x * 0.966 - uv.y * 0.259, uv.x * 0.259 + uv.y * 0.966) + uv_warp * 0.9) * 1.13;

	// ---- layer weights (same thresholds as the full shader) ----------------
	float grass_w = smoothstep(0.30, 0.74, macro * 0.72 + grain * 0.28 + grass_bias);
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

	// ---- albedo: one anti-tiled sample per layer --------------------------
	vec3 albedo = texture(grass_albedo, uv_grass).rgb * grass_tint.rgb * grass_w
			+ texture(dirt_albedo, uv_dirt).rgb * dirt_tint.rgb * dirt_w
			+ texture(rock_albedo, uv_rock).rgb * rock_tint.rgb * rock_w
			+ texture(mud_albedo, uv_mud).rgb * mud_tint.rgb * mud_w;

	float proc_macro = clamp(macro_a * 0.60 + macro_b * 0.40, 0.0, 1.0);
	float micro_wave = 0.5 + 0.5 * sin(v_world.x * 0.31 + v_world.z * 0.27)
			* cos(v_world.z * 0.37 - v_world.x * 0.23);
	float micro_var = clamp(grain * 0.65 + micro_wave * 0.35, 0.0, 1.0);
	float macro_lum = mix(1.0 - macro_contrast, 1.0 + macro_contrast,
			clamp(macro * 0.45 + proc_macro * 0.45 + grain * 0.10, 0.0, 1.0));
	float micro_lum = mix(0.93, 1.07, clamp(proc_macro * 0.65 + micro_var * 0.35, 0.0, 1.0));
	vec3 hue_mod = mix(vec3(0.96, 1.02, 0.96), vec3(1.04, 0.99, 0.95), macro_b);
	albedo *= macro_lum * micro_lum * hue_mod;

	// Baked cavity/trench/crater/roadside-verge AO + damp lowland wetness
	float lowland = 1.0 - smoothstep(wet_height - 0.4, wet_height + 2.6, v_world.y);
	float wet = clamp(mud_w * 1.45 + lowland * (0.45 + cavity * 0.75) * mud_amount, 0.0, 1.0);
	albedo *= mix(1.0, 0.60, wet);
	albedo = mix(albedo, albedo * vec3(0.84, 0.80, 0.76), cavity * 0.52);
	albedo *= mix(1.0, 0.58, cavity) * (1.0 + ridge * 0.05);

	ALBEDO = albedo;
	AO = clamp(mix(1.0, 0.34, cavity), 0.22, 1.0);
	AO_LIGHT_AFFECT = 0.65;

	// Normal mapping: blend normal maps per layer, rotated back to world tangent frame
	vec3 n_grass = texture(grass_normal, uv_grass).rgb * 2.0 - 1.0;
	vec3 n_dirt = texture(dirt_normal, uv_dirt).rgb * 2.0 - 1.0;
	vec3 n_rock = texture(rock_normal, uv_rock).rgb * 2.0 - 1.0;
	vec3 n_mud = texture(mud_normal, uv_mud).rgb * 2.0 - 1.0;
	n_grass.xy = vec2(n_grass.x * 0.927 - n_grass.y * 0.375, n_grass.x * 0.375 + n_grass.y * 0.927);
	n_dirt.xy = vec2(n_dirt.x * 0.799 + n_dirt.y * 0.602, -n_dirt.x * 0.602 + n_dirt.y * 0.799);
	n_rock.xy = vec2(n_rock.x * 0.602 - n_rock.y * 0.799, n_rock.x * 0.799 + n_rock.y * 0.602);
	n_mud.xy = vec2(n_mud.x * 0.966 + n_mud.y * 0.259, -n_mud.x * 0.259 + n_mud.y * 0.966);
	vec3 n = n_grass * grass_w + n_dirt * dirt_w + n_rock * rock_w + n_mud * mud_w;
	n.xy *= normal_strength;
	n.z = max(n.z, 0.25);
	NORMAL_MAP = normalize(n) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.15;

	float base_rough = grass_roughness * grass_w + dirt_roughness * dirt_w
			+ rock_roughness * rock_w + mud_roughness * mud_w;
	float tex_luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	base_rough = clamp(base_rough + (tex_luma - 0.48) * 0.24 - cavity * 0.08, 0.18, 0.98);
	ROUGHNESS = clamp(mix(base_rough, 0.16, wet * 0.84), 0.12, 1.0);
	SPECULAR = mix(0.36, 0.80, wet);
	METALLIC = 0.0;
}

