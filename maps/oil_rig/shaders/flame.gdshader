// Animated gas-flare flame for Godot 4 / mobile.
// Additive, unshaded, no screen-space effects. Turbulence is generated with
// a 2D value-noise driven by TIME, so the flame flickers and rolls upward.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec3 hot_color : source_color = vec3(1.0, 0.92, 0.55);
uniform vec3 tip_color : source_color = vec3(1.0, 0.20, 0.015);
uniform float flame_base = 74.0;
uniform float flame_height = 14.0;
uniform float speed = 2.4;

varying float v_h;
varying float v_u;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_h = clamp((VERTEX.y - flame_base) / max(flame_height, 0.1), 0.0, 1.0);
	float ang = atan(VERTEX.z, VERTEX.x - 55.0);
	v_u = sin(ang) * 1.6 + cos(ang) * 1.1;
	float h2 = v_h * v_h;
	float sway = sin(TIME * 3.1 + VERTEX.y * 0.45) * 0.55 * h2;
	float puff = cos(TIME * 4.3 + VERTEX.y * 0.7) * 0.35 * h2;
	VERTEX.x += sway;
	VERTEX.z += puff;
}

void fragment() {
	float t = TIME * speed;
	float n = vnoise(vec2(v_h * 5.0 + v_u, v_u * 1.5 - t));
	float n2 = vnoise(vec2(v_u * 3.0 - t * 0.6, v_h * 8.0 + t * 0.4));
	float turb = (n - 0.5) * 0.32 + (n2 - 0.5) * 0.16;
	float h = clamp(v_h + turb - 0.05, 0.0, 1.0);
	vec3 col = mix(hot_color, tip_color, pow(h, 0.8));
	float alpha = (1.0 - h) * (0.58 + 0.42 * n);
	ALBEDO = col;
	EMISSION = col * (2.6 + 2.2 * (1.0 - h));
	ALPHA = clamp(alpha, 0.0, 1.0);
}
