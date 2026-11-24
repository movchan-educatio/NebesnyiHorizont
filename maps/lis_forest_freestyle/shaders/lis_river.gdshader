shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// Lightweight mobile mountain-river water shader for lis_forest_freestyle (2 texture fetches).
// Scrolls along river UV.y with soft bank-edge foam, replacing blocky river_foam.
uniform sampler2D wave_norm : filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.032, 0.088, 0.082);
uniform vec3 shallow_color : source_color = vec3(0.11, 0.23, 0.21);
uniform vec3 sky_refl_color : source_color = vec3(0.46, 0.58, 0.64);
uniform vec3 foam_color : source_color = vec3(0.84, 0.90, 0.92);
uniform vec3 sun_dir = vec3(-0.42, 0.72, -0.35);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = distance(CAMERA_POSITION_WORLD, v_world);
	vec2 uv1 = v_world.xz * 0.045 + vec2(0.0, TIME * 0.14);
	vec2 uv2 = v_world.xz * 0.075 + vec2(TIME * 0.04, TIME * 0.21);
	vec3 n1 = texture(wave_norm, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(wave_norm, uv2).rgb * 2.0 - 1.0;
	float ripple_att = 1.0 - smoothstep(120.0, 480.0, dist);
	vec3 wn = normalize(mix(vec3(0.0, 1.0, 0.0), normalize(vec3(n1.x + n2.x, 3.0, n1.y + n2.y)), ripple_att));

	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world);
	float facing = clamp(dot(vec3(0.0, 1.0, 0.0), V), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.0);

	float edge = clamp(min(UV.x, 1.0 - UV.x), 0.0, 0.5);
	float bank_t = 1.0 - smoothstep(0.02, 0.24, edge);
	vec3 water_col = mix(deep_color, shallow_color, bank_t * 0.75 + fres * 0.35);
	water_col = mix(water_col, sky_refl_color, fres * 0.55);

	vec3 L = normalize(sun_dir);
	vec3 H = normalize(L + V);
	float spec = pow(max(dot(wn, H), 0.0), 96.0) * (0.2 + 0.8 * ripple_att);
	water_col += vec3(1.0, 0.94, 0.84) * spec * 0.75;

	float ripple_foam = (n1.x * 0.5 + n2.y * 0.5 + 0.35) * bank_t;
	float foam = smoothstep(0.32, 0.72, bank_t * 0.78 + ripple_foam * 0.38);
	water_col = mix(water_col, foam_color, foam * 0.65);

	ALBEDO = water_col;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = 0.14;
	METALLIC = 0.04;
	SPECULAR = 0.9;
}
