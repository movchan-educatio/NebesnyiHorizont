shader_type canvas_item;
render_mode blend_mix;

// Lightweight cinematic grade for the mobile renderer.  Reads the already
// rendered frame through hint_screen_texture: one texture fetch per pixel, no
// extra render target, no second scene pass.  Kept deliberately subtle so HUD
// text in the corners stays readable.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.32;
uniform float grain_strength : hint_range(0.0, 0.08) = 0.010;
uniform float scanline_strength : hint_range(0.0, 0.08) = 0.010;
uniform vec3 highlight_tint : source_color = vec3(1.025, 1.005, 0.965);
uniform vec3 shadow_tint : source_color = vec3(0.965, 0.995, 1.020);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec3 color = texture(screen_tex, SCREEN_UV).rgb;

	// Split tone: warm highlights (golden sun / fire), cool shadows (sky fill).
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	vec3 tone = mix(shadow_tint, highlight_tint, smoothstep(0.18, 0.78, luma));
	color *= tone;

	// Soft elliptical vignette.
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.0, 0.88);
	float v = smoothstep(0.30, 0.78, length(d));
	color *= 1.0 - v * vignette_strength;

	// Very faint analog texture: hides banding in the baked sky gradient.
	float scan = sin(SCREEN_UV.y * 1100.0) * 0.5 + 0.5;
	color *= 1.0 - scan * scanline_strength;
	float grain = hash21(floor(SCREEN_UV * 1024.0) + floor(TIME * 24.0) * 13.7);
	color += (grain - 0.5) * grain_strength;

	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
