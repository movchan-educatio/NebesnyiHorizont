shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// Lightweight surface weathering & ground-contact AO for vertex-coloured props
// (tents, barriers, concrete shelters, crates, wrecks, watchtowers).
// Uses zero textures or screen/depth reads so mobile MultiMesh batching stays single-draw.

uniform float roughness_base : hint_range(0.1, 1.0) = 0.86;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.04;
uniform float specular_base : hint_range(0.0, 1.0) = 0.24;
uniform float grain_strength : hint_range(0.0, 0.35) = 0.14;
uniform float grime_height : hint_range(0.1, 2.0) = 0.75;
uniform float grime_strength : hint_range(0.0, 0.8) = 0.42;
uniform vec3 grime_tint : source_color = vec3(0.24, 0.21, 0.16);
uniform bool use_heightmap = false;
uniform sampler2D terrain_height_tex : filter_linear, repeat_disable;
uniform float terrain_half_extent = 480.0;
uniform float flat_ground_y = 0.0;
uniform float height_min = -16.0;
uniform float height_span = 64.0;

varying vec3 v_world;
varying vec3 v_local;
varying vec3 v_world_normal;
varying vec4 v_color;

float _hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float _noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
			mix(_hash21(i), _hash21(i + vec2(1.0, 0.0)), u.x),
			mix(_hash21(i + vec2(0.0, 1.0)), _hash21(i + vec2(1.0, 1.0)), u.x),
			u.y);
}

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_color = COLOR;
}

void fragment() {
	vec2 wp = v_world.xz + vec2(v_world.y * 0.65, -v_world.y * 0.45);
	float n_broad = _noise2(wp * 0.85);
	float n_fine = _noise2(wp * 5.6 + vec2(11.3, 7.1));
	float wear = mix(1.0 - grain_strength, 1.0 + grain_strength, clamp(n_broad * 0.58 + n_fine * 0.42, 0.0, 1.0));
	vec3 col = v_color.rgb * wear;

	// Bottom contact splash + AO near the ground plane (heightmap-aware after batching)
	float rel_y = v_local.y;
	if (use_heightmap) {
		vec2 h_uv = clamp(v_world.xz / (terrain_half_extent * 2.0) + vec2(0.5), vec2(0.002), vec2(0.998));
		float ground_y = flat_ground_y + height_min + texture(terrain_height_tex, h_uv).r * height_span;
		rel_y = v_world.y - ground_y;
	}
	float base_fac = 1.0 - smoothstep(-0.08, max(grime_height, 0.2), rel_y + (n_fine - 0.5) * 0.22);
	float side_fac = smoothstep(0.85, 0.25, abs(v_world_normal.y));
	float grime = clamp(base_fac * (0.45 + 0.55 * side_fac) * grime_strength, 0.0, 0.85);
	col = mix(col, col * grime_tint * 1.45, grime);

	ALBEDO = col;
	AO = clamp(1.0 - grime * 0.52, 0.35, 1.0);
	AO_LIGHT_AFFECT = 0.60;
	ROUGHNESS = clamp(roughness_base + (n_fine - 0.5) * 0.10 - grime * 0.12, 0.22, 0.98);
	METALLIC = metallic_base * (1.0 - grime * 0.65);
	SPECULAR = specular_base;
}
