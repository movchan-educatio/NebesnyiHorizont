shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

// Distant mountain backdrop.  The colour is a per-pixel vertical gradient in
// world space, not a vertex-colour interpolation: the old per-triangle colours
// produced visible diagonal bands on the ridges.
uniform vec3 color_low : source_color = vec3(0.15, 0.20, 0.15);
uniform vec3 color_high : source_color = vec3(0.36, 0.42, 0.44);
uniform vec3 color_haze : source_color = vec3(0.72, 0.78, 0.84);
uniform float haze_amount = 0.30;
uniform float base_y = -60.0;
uniform float top_y = 260.0;
uniform vec3 sun_dir = vec3(-0.62, 0.38, -0.68);
uniform float scatter_strength : hint_range(0.0, 1.0) = 0.55;
uniform vec3 sun_scatter_color : source_color = vec3(1.0, 0.84, 0.62);
uniform vec3 shadow_tint : source_color = vec3(0.48, 0.60, 0.78);
// Night dimmer: the backdrop is unshaded, so weather/night must scale it here
// or the ridges stay daylight-bright under a dark sky (BigLevel sets this).
uniform float night_dim : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = clamp((v_world_pos.y - base_y) / max(top_y - base_y, 1.0), 0.0, 1.0);
	vec3 grad_c = mix(color_low, color_high, t);
	vec3 c = mix(grad_c, COLOR.rgb, 0.32);
	c = mix(c, color_haze, haze_amount * (0.28 + 0.72 * t));

	// Directional solar atmospheric scatter (zero textures): warm hazy backlight
	// towards the sun vs deeper cool blue-grey ridges in opposite shadow.
	vec3 view_dir = normalize(v_world_pos - CAMERA_POSITION_WORLD);
	vec3 sdir = normalize(sun_dir);
	float mu = dot(view_dir, sdir);
	float fwd_broad = pow(clamp(mu * 0.5 + 0.5, 0.0, 1.0), 2.5);
	float fwd_halo = pow(clamp(mu, 0.0, 1.0), 6.0);
	float anti_sun = clamp(-mu, 0.0, 1.0);

	c = mix(c, c * shadow_tint + color_haze * shadow_tint * 0.22,
			anti_sun * scatter_strength * 0.48 * (0.25 + 0.75 * t));
	vec3 sun_haze = mix(color_haze, sun_scatter_color, 0.68);
	c = mix(c, sun_haze, scatter_strength * (0.34 * fwd_broad + 0.42 * fwd_halo) * (0.35 + 0.65 * t));
	// Soft ground-hugging valley mist & drifting cloud shadow across distant slopes.
	float valley_mist = (1.0 - smoothstep(0.0, 0.44, t)) * 0.52;
	float ridge_cloud = sin(v_world_pos.x * 0.0042 + v_world_pos.z * 0.0038 + TIME * 0.01) * 0.5 + 0.5;
	c = mix(c * mix(0.88, 1.04, ridge_cloud), mix(color_haze, sun_haze, 0.28), valley_mist);
	ALBEDO = c * night_dim;
}
