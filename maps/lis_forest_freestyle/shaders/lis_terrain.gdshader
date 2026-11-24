shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Lightweight mobile forest floor shader for lis_forest_freestyle (3 texture fetches).
// Uses terrain slope, height, shoreline wetness, and macro patch modulation to prevent
// sandy tiling/moire while matching the olive-moss forest reference palette.
uniform sampler2D tex_floor : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_moss : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_cliff : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 floor_tint : source_color = vec3(0.56, 0.66, 0.44);
uniform vec3 moss_tint : source_color = vec3(0.46, 0.62, 0.36);
uniform vec3 cliff_tint : source_color = vec3(0.62, 0.60, 0.56);
uniform float water_level = -12.0;

varying vec3 v_world;
varying vec3 v_world_nrm;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 wuv = v_world.xz * 0.095;
	vec3 col_floor = texture(tex_floor, wuv).rgb * floor_tint;
	vec3 col_moss = texture(tex_moss, wuv * 0.78).rgb * moss_tint;
	vec3 col_cliff = texture(tex_cliff, v_world.xz * 0.07 + vec2(v_world.y * 0.06, 0.0)).rgb * cliff_tint;

	// Macro forest clearing variation + gentle elevation tinting
	float macro_a = sin(v_world.x * 0.031 + v_world.z * 0.023) * cos(v_world.z * 0.037 - v_world.x * 0.019);
	float moss_w = clamp(0.46 + macro_a * 0.38 + smoothstep(4.0, 26.0, v_world.y) * 0.16, 0.08, 0.92);
	vec3 ground = mix(col_floor, col_moss, moss_w);

	// Distance moire softening on distant horizon slopes
	float dist = distance(CAMERA_POSITION_WORLD, v_world);
	float far_fade = smoothstep(140.0, 420.0, dist);
	vec3 macro_earth = mix(vec3(0.24, 0.29, 0.19), vec3(0.28, 0.34, 0.22), moss_w);
	ground = mix(ground, macro_earth, far_fade * 0.55);

	// Steep slope & rocky riverbank blend
	float slope = clamp(v_world_nrm.y, 0.0, 1.0);
	float rock_w = smoothstep(0.84, 0.54, slope);
	float shore_rock = 1.0 - smoothstep(water_level - 1.0, water_level + 4.5, v_world.y);
	rock_w = clamp(max(rock_w, shore_rock * 0.65), 0.0, 1.0);
	vec3 col = mix(ground, col_cliff, rock_w);

	// Wet shoreline darkening
	float wet = 1.0 - smoothstep(water_level - 0.5, water_level + 2.2, v_world.y);
	col = mix(col, col * vec3(0.45, 0.46, 0.42), wet * 0.80);

	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.30, wet * 0.85);
	METALLIC = 0.0;
	SPECULAR = mix(0.25, 0.65, wet);
}
