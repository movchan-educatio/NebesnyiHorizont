// ocean_water.gdshader - lightweight mobile ocean for Godot 4
// Two scrolling wave-normal layers, Fresnel deep->turquoise, procedural
// sun glitter and baked foam near concrete columns. No SSR, no refraction,
// no screen-space sampling: 3 texture fetches per pixel.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D wave_a;
uniform sampler2D wave_b;
uniform sampler2D foam_mask;
uniform vec3 deep_color : source_color = vec3(0.010, 0.060, 0.120);
uniform vec3 shallow_color : source_color = vec3(0.030, 0.400, 0.430);
uniform vec3 foam_color : source_color = vec3(0.86, 0.95, 0.96);
uniform vec3 sun_dir = vec3(-0.42, 0.78, -0.30);
uniform float wave_speed = 0.032;
uniform float world_size = 2400.0; // foam mask covers +/-1200 m

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = distance(CAMERA_POSITION_WORLD, v_world);
	vec2 uv1 = v_world.xz * 0.014 + vec2(TIME * wave_speed, TIME * wave_speed * 0.55);
	vec2 uv2 = v_world.xz * 0.026 + vec2(-TIME * wave_speed * 0.72, TIME * wave_speed * 0.41);
	vec3 a = texture(wave_a, uv1).rgb * 2.0 - 1.0;
	vec3 b = texture(wave_b, uv2).rgb * 2.0 - 1.0;
	vec3 wn_raw = normalize(vec3(a.x + b.x, 2.6, a.y + b.y));
	float ripple_att = 1.0 - smoothstep(220.0, 2200.0, dist);
	vec3 wn = normalize(mix(vec3(0.0, 1.0, 0.0), wn_raw, ripple_att));

	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world);
	float facing = clamp(dot(vec3(0.0, 1.0, 0.0), V), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.2);
	vec3 col = mix(deep_color, shallow_color, clamp(0.10 + fres * 0.86, 0.0, 1.0));
	col = mix(col, vec3(0.54, 0.72, 0.88), fres * 0.42);

	vec3 L = normalize(sun_dir);
	vec3 H = normalize(L + V);
	float spec = pow(max(dot(wn, H), 0.0), 128.0) * (0.25 + 0.75 * ripple_att);
	col += vec3(1.0, 0.95, 0.84) * spec * 1.15;

	vec2 fuv = v_world.xz / world_size + vec2(0.5);
	float foam = texture(foam_mask, fuv).r;
	foam *= 0.72 + 0.28 * sin(TIME * 1.6 + v_world.x * 0.06 + v_world.z * 0.05);
	foam *= (1.0 - smoothstep(900.0, 1200.0, max(abs(v_world.x), abs(v_world.z))));
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0) * 0.92);

	float horizon_fade = smoothstep(1550.0, 2750.0, dist);
	vec3 horizon_col = vec3(0.20, 0.31, 0.42);
	col = mix(col, horizon_col, horizon_fade);

	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = mix(0.12, 0.92, horizon_fade);
	METALLIC = mix(0.06, 0.0, horizon_fade);
	SPECULAR = 1.0 - horizon_fade;
	ALPHA = 1.0 - smoothstep(2100.0, 2900.0, dist);
}
