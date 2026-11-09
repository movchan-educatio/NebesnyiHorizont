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
	vec2 uv = v_world.xz * detail_scale;

	float macro = COLOR.r;
	float grain = COLOR.g;
	float slope = clamp(max(1.0 - v_world_normal.y, COLOR.b), 0.0, 1.0);

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

	// ---- albedo: one sample per layer -------------------------------------
	vec3 albedo = texture(grass_albedo, uv).rgb * grass_tint.rgb * grass_w
			+ texture(dirt_albedo, uv).rgb * dirt_tint.rgb * dirt_w
			+ texture(rock_albedo, uv).rgb * rock_tint.rgb * rock_w
			+ texture(mud_albedo, uv).rgb * mud_tint.rgb * mud_w;

	// Broad patch contrast from the vertex colour instead of fBm noise.
	float macro_lum = mix(1.0 - macro_contrast, 1.0 + macro_contrast,
			clamp(macro * 0.75 + grain * 0.25, 0.0, 1.0));
	float micro_lum = mix(0.92, 1.08, grain);
	albedo *= macro_lum * micro_lum;

	float wet = clamp(mud_w * 1.5 + (1.0 - smoothstep(wet_height, wet_height + 1.2,
			v_world.y)) * mud_amount, 0.0, 1.0);
	albedo *= mix(1.0, 0.62, wet);

	ALBEDO = albedo;

	// Normal mapping: blend normal maps per layer for 3D ground relief
	vec3 n_grass = texture(grass_normal, uv).rgb * 2.0 - 1.0;
	vec3 n_dirt = texture(dirt_normal, uv).rgb * 2.0 - 1.0;
	vec3 n_rock = texture(rock_normal, uv).rgb * 2.0 - 1.0;
	vec3 n_mud = texture(mud_normal, uv).rgb * 2.0 - 1.0;
	vec3 n = n_grass * grass_w + n_dirt * dirt_w + n_rock * rock_w + n_mud * mud_w;
	n.xy *= normal_strength;
	n.z = max(n.z, 0.25);
	NORMAL_MAP = normalize(n) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.15;

	float base_rough = grass_roughness * grass_w + dirt_roughness * dirt_w
			+ rock_roughness * rock_w + mud_roughness * mud_w;
	float tex_luma = dot(albedo, vec3(0.299, 0.587, 0.114));
	base_rough = clamp(base_rough + (tex_luma - 0.48) * 0.24, 0.18, 0.98);
	ROUGHNESS = clamp(mix(base_rough, 0.18, wet * 0.82), 0.0, 1.0);
	SPECULAR = mix(0.35, 0.75, wet);
	METALLIC = 0.0;
}

