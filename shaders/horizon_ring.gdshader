shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// Seamless outer terrain apron starting at the 192 m playable square border.
// Samples only grass and dirt albedos across the inner collar (0 texture reads
// beyond normal detail) so the 192 m seam vanishes, then softly dissolves into
// broad rolling countryside tones and atmospheric horizon haze.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap, repeat_enable;

uniform vec4 grass_tint : source_color = vec4(1.0);
uniform vec4 dirt_tint : source_color = vec4(1.0);
uniform vec4 map_edge_tint : source_color = vec4(0.66, 0.67, 0.62, 1.0);
uniform vec4 haze_color : source_color = vec4(0.68, 0.72, 0.72, 1.0);

uniform float detail_scale : hint_range(0.01, 1.0) = 0.26;
uniform float grass_bias : hint_range(-1.0, 1.0) = 0.0;
uniform float macro_contrast : hint_range(0.0, 1.0) = 0.28;
uniform float grass_roughness : hint_range(0.0, 1.0) = 0.94;
uniform float dirt_roughness : hint_range(0.0, 1.0) = 0.93;
uniform float cloud_shadow_strength : hint_range(0.0, 0.5) = 0.16;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float _val_noise(vec2 np) {
	vec2 ni = floor(np);
	vec2 nf = np - ni;
	vec2 nu = nf * nf * (3.0 - 2.0 * nf);
	vec4 nh = fract(sin(vec4(
			dot(ni, vec2(127.1, 311.7)),
			dot(ni + vec2(1.0, 0.0), vec2(127.1, 311.7)),
			dot(ni + vec2(0.0, 1.0), vec2(127.1, 311.7)),
			dot(ni + vec2(1.0, 1.0), vec2(127.1, 311.7)))) * 43758.5453);
	return mix(mix(nh.x, nh.y, nu.x), mix(nh.z, nh.w, nu.x), nu.y);
}

void fragment() {
	float macro_a = _val_noise(v_world.xz * 0.021);
	float macro_b = _val_noise(v_world.xz * 0.067 + vec2(13.7, 29.3));
	float broad_roll = _val_noise(v_world.xz * 0.0055 + vec2(4.2, -9.1));

	vec2 uv = v_world.xz * detail_scale;
	vec2 uv_warp = vec2(macro_a - 0.5, macro_b - 0.5) * 0.28
			+ vec2(sin(v_world.z * 0.031), cos(v_world.x * 0.029)) * 0.11;
	vec2 uv_grass = vec2(uv.x * 0.927 + uv.y * 0.375, -uv.x * 0.375 + uv.y * 0.927) + uv_warp;
	vec2 uv_dirt = (vec2(uv.x * 0.799 - uv.y * 0.602, uv.x * 0.602 + uv.y * 0.799) + uv_warp * 0.8) * 1.07;

	float edge_grass_w = smoothstep(0.30, 0.74, macro_a * 0.72 + macro_b * 0.28 + grass_bias);
	vec3 tex_grass = texture(grass_albedo, uv_grass).rgb * grass_tint.rgb;
	vec3 tex_dirt = texture(dirt_albedo, uv_dirt).rgb * dirt_tint.rgb;
	float edge_lum = mix(1.0 - macro_contrast * 0.65, 1.0 + macro_contrast * 0.65,
			clamp(macro_a * 0.65 + macro_b * 0.35, 0.0, 1.0));
	vec3 edge_hue = mix(vec3(0.96, 1.02, 0.96), vec3(1.04, 0.99, 0.95), macro_b);
	vec3 seam_albedo = mix((tex_grass * edge_grass_w + tex_dirt * (1.0 - edge_grass_w))
			* edge_lum * edge_hue, map_edge_tint.rgb * edge_lum, 0.14);

	// Analytic linear average of grass_albedo & dirt_albedo avoids tiling far away.
	vec3 mean_grass = vec3(0.192, 0.169, 0.047) * grass_tint.rgb;
	vec3 mean_dirt = vec3(0.068, 0.044, 0.022) * dirt_tint.rgb;
	vec3 far_ground = mix((mean_grass * edge_grass_w + mean_dirt * (1.0 - edge_grass_w))
			* edge_lum * edge_hue, map_edge_tint.rgb * edge_lum, 0.14);
	far_ground = mix(far_ground, COLOR.rgb, 0.32) * mix(0.88, 1.12, broad_roll);

	float edge_metric = max(abs(v_world.x), abs(v_world.z));
	float radial = length(v_world.xz);
	float far_smooth = smoothstep(218.0, 410.0, edge_metric);
	vec3 col = mix(seam_albedo, far_ground, far_smooth);

	// Synchronized cloud shadow drift + subtle distant woodland silhouette darkening
	vec2 cloud_p = v_world.xz * 0.0095 + vec2(TIME * 0.012, TIME * 0.007);
	float cloud_w = (sin(cloud_p.x + cos(cloud_p.y * 0.8)) * 0.5 + 0.5)
			* (cos(cloud_p.y * 1.15 - cloud_p.x * 0.45) * 0.5 + 0.5);
	float cloud_mul = mix(1.0 - cloud_shadow_strength * 0.85, 1.0 + cloud_shadow_strength * 0.2,
			smoothstep(0.18, 0.72, cloud_w));
	float distant_belt = sin(atan(v_world.z, v_world.x) * 5.0 + 1.3) * 0.5 + 0.5;
	float belt_band = smoothstep(330.0, 470.0, radial) * (1.0 - smoothstep(560.0, 780.0, radial));
	col *= cloud_mul * mix(1.0, 0.84, belt_band * smoothstep(0.35, 0.82, broad_roll * 0.65 + distant_belt * 0.35));

	float world_haze = smoothstep(310.0, 920.0, radial) * 0.58;
	col = mix(col, haze_color.rgb, world_haze);

	ALBEDO = col;
	AO = 1.0;
	AO_LIGHT_AFFECT = 0.65;
	ROUGHNESS = mix(grass_roughness * edge_grass_w + dirt_roughness * (1.0 - edge_grass_w), 0.96, far_smooth);
	SPECULAR = mix(0.24, 0.14, far_smooth);
	METALLIC = 0.0;
}
