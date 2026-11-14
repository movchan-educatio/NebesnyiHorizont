shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// Lightweight architectural weathering shader for concrete, brick and plaster:
//   * bottom ~1.55 m plinth dampness & earth splash derived from terrain height
//   * world-space multi-scale albedo micro-variation so large facades don't tile
//   * single-sample box-projected UVs with textureGrad (no 3x triplanar tax on iOS)

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D terrain_height_tex : filter_linear, repeat_disable;

uniform bool has_albedo_tex = true;
uniform bool has_normal_tex = false;
uniform bool has_rough_tex = false;
uniform bool has_ao_tex = false;
uniform bool use_triplanar = true;
uniform bool use_vertex_color = false;
uniform bool use_heightmap = false;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float uv_scale = 0.22;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.90;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.0;
uniform float specular_base : hint_range(0.0, 1.0) = 0.24;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.55;

uniform float flat_ground_y = 0.0;
uniform float terrain_half_extent = 192.0;
uniform float height_min = -16.0;
uniform float height_span = 64.0;
uniform float grime_height : hint_range(0.2, 4.0) = 1.55;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.42;
uniform vec3 grime_color : source_color = vec3(0.22, 0.20, 0.16);
uniform float micro_var_strength : hint_range(0.0, 0.4) = 0.11;

varying vec3 v_world;
varying vec3 v_world_normal;
varying vec4 v_vert_col;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
			mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
			u.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_vert_col = COLOR;
}

void fragment() {
	vec2 sample_uv = UV * uv_scale;
	vec2 dux = dFdx(UV) * uv_scale;
	vec2 duy = dFdy(UV) * uv_scale;
	int axis = 1; // 0 = X wall, 1 = Y roof/floor, 2 = Z wall
	vec3 an = abs(v_world_normal);
	if (use_triplanar) {
		vec3 dpx = dFdx(v_world) * uv_scale;
		vec3 dpy = dFdy(v_world) * uv_scale;
		if (an.y >= max(an.x, an.z)) {
			sample_uv = v_world.xz * uv_scale;
			dux = dpx.xz;
			duy = dpy.xz;
			axis = 1;
		} else if (an.x >= an.z) {
			sample_uv = vec2(v_world.z, -v_world.y) * uv_scale;
			dux = vec2(dpx.z, -dpx.y);
			duy = vec2(dpy.z, -dpy.y);
			axis = 0;
		} else {
			sample_uv = vec2(v_world.x, -v_world.y) * uv_scale;
			dux = vec2(dpx.x, -dpx.y);
			duy = vec2(dpy.x, -dpy.y);
			axis = 2;
		}
	}

	vec3 tex_alb = vec3(1.0);
	if (has_albedo_tex) {
		tex_alb = textureGrad(albedo_tex, sample_uv, dux, duy).rgb;
	}
	vec3 base = tex_alb * albedo_color.rgb;
	if (use_vertex_color) {
		base *= v_vert_col.rgb;
	}

	// Subtle multi-scale weathering variation (large plaster/concrete patches + fine dirt)
	vec2 var_p = v_world.xz + vec2(v_world.y * 0.45, -v_world.y * 0.35);
	float n_macro = vnoise2(var_p * 0.14);
	float n_drip = vnoise2(vec2((v_world.x + v_world.z) * 1.15, v_world.y * 0.42));
	vec3 warm_shift = mix(vec3(0.95, 0.96, 0.99), vec3(1.05, 1.03, 0.96), n_macro);
	float lum_mod = mix(1.0 - micro_var_strength, 1.0 + micro_var_strength,
			clamp(n_macro * 0.62 + n_drip * 0.38, 0.0, 1.0));
	base *= warm_shift * lum_mod;

	// Bottom ~1.55 m wall grime & damp splash relative to terrain/street surface
	float ground_y = flat_ground_y;
	if (use_heightmap) {
		vec2 huv = clamp((v_world.xz / max(terrain_half_extent * 2.0, 1.0)) + 0.5,
				vec2(0.002), vec2(0.998));
		ground_y = flat_ground_y + height_min + texture(terrain_height_tex, huv).r * height_span;
	}
	float h_above = v_world.y - ground_y;
	float h_cut = grime_height + (n_drip - 0.5) * 0.52 + (n_macro - 0.5) * 0.24;
	float base_band = (1.0 - smoothstep(-0.18, max(h_cut, 0.25), h_above))
			* smoothstep(-1.2, -0.05, h_above);
	float wall_fac = smoothstep(0.84, 0.28, an.y);
	float grime = clamp(base_band * wall_fac * grime_strength, 0.0, 0.90);

	base = mix(base, base * grime_color * 1.48, grime);
	ALBEDO = base;

	float r = roughness_base;
	if (has_rough_tex) {
		r = mix(roughness_base * 0.6, roughness_base, textureGrad(rough_tex, sample_uv, dux, duy).r);
	}
	ROUGHNESS = clamp(mix(r, 0.38, grime * 0.68), 0.16, 0.98);
	METALLIC = metallic_base;
	SPECULAR = mix(specular_base, 0.54, grime * 0.55);

	float ao_val = 1.0;
	if (has_ao_tex) {
		ao_val = mix(1.0, textureGrad(ao_tex, sample_uv, dux, duy).r, ao_strength);
	}
	AO = clamp(ao_val * (1.0 - grime * 0.38), 0.25, 1.0);
	AO_LIGHT_AFFECT = 0.55;

	if (has_normal_tex) {
		vec3 tn = textureGrad(normal_tex, sample_uv, dux, duy).rgb * 2.0 - 1.0;
		tn.xy *= normal_strength;
		if (use_triplanar) {
			vec3 wn = v_world_normal;
			if (axis == 1) {
				wn = normalize(wn + vec3(tn.x, 0.0, tn.y));
			} else if (axis == 0) {
				wn = normalize(wn + vec3(0.0, -tn.y, tn.x));
			} else {
				wn = normalize(wn + vec3(tn.x, -tn.y, 0.0));
			}
			NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		} else {
			NORMAL_MAP = normalize(tn) * 0.5 + 0.5;
			NORMAL_MAP_DEPTH = clamp(normal_strength, 0.2, 1.6);
		}
	}
}
