shader_type canvas_item;
render_mode blend_mix;

// Cinematic finishing grade. One screen fetch, one full-screen quad, no extra
// render target and no second scene pass. Everything below is pure ALU, so the
// cost is identical on a phone GPU and on a desktop card.
//
// The look: gentle S-curve contrast, warm highlights / cool shadows split tone,
// faint halation around hot pixels, organic elliptical vignette, warm light
// leak, fine animated grain and optional anamorphic letterbox. HUD widgets are
// drawn by the caller on top of this rect, so telemetry stays razor sharp.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.34;
uniform float grain_strength : hint_range(0.0, 0.08) = 0.014;
uniform float scanline_strength : hint_range(0.0, 0.08) = 0.0;
uniform float contrast : hint_range(0.5, 2.0) = 1.10;
uniform float saturation : hint_range(0.0, 2.0) = 1.08;
uniform float halation : hint_range(0.0, 0.2) = 0.05;
uniform float light_leak : hint_range(0.0, 1.0) = 0.22;
uniform float letterbox : hint_range(0.0, 0.2) = 0.0;
uniform vec2 resolution = vec2(1920.0, 1080.0);
uniform float render_scale_3d : hint_range(0.25, 1.0) = 1.0;
uniform float sharpen_strength : hint_range(0.0, 1.5) = 0.72;
uniform bool enable_rcas = true;
uniform vec3 highlight_tint : source_color = vec3(1.045, 1.012, 0.945);
uniform vec3 shadow_tint : source_color = vec3(0.945, 0.982, 1.045);

vec3 rcas_sharpen(vec2 uv, vec3 center, vec2 inv_size, float strength) {
	if (strength <= 0.001) {
		return center;
	}
	vec3 n = texture(screen_tex, uv + vec2(0.0, -inv_size.y)).rgb;
	vec3 s = texture(screen_tex, uv + vec2(0.0,  inv_size.y)).rgb;
	vec3 w = texture(screen_tex, uv + vec2(-inv_size.x, 0.0)).rgb;
	vec3 e = texture(screen_tex, uv + vec2( inv_size.x, 0.0)).rgb;
	float nc = dot(center, vec3(0.299, 0.587, 0.114));
	float nn = dot(n, vec3(0.299, 0.587, 0.114));
	float ns = dot(s, vec3(0.299, 0.587, 0.114));
	float nw = dot(w, vec3(0.299, 0.587, 0.114));
	float ne = dot(e, vec3(0.299, 0.587, 0.114));
	float min_l = min(min(min(nn, ns), min(nw, ne)), nc);
	float max_l = max(max(max(nn, ns), max(nw, ne)), nc);
	float hit_min = min_l / max(4.0 * max_l, 0.0001);
	float hit_max = (1.0 - max_l) / min(4.0 * min_l - 4.0, -0.0001);
	float lobe = max(-hit_min, hit_max);
	float w_rcas = clamp(lobe, -0.1875, 0.0) * strength;
	return clamp((center + (n + s + w + e) * w_rcas) / (1.0 + 4.0 * w_rcas), 0.0, 1.0);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_tex, uv).rgb;
	if (enable_rcas && render_scale_3d < 0.95) {
		float upscale_boost = clamp((0.98 - render_scale_3d) * 1.8, 0.28, 1.0);
		vec2 rcas_px = 1.0 / max(resolution * mix(render_scale_3d, 1.0, 0.35), vec2(1.0));
		c = rcas_sharpen(uv, c, rcas_px, sharpen_strength * upscale_boost);
	}

	// 1. Filmic S-curve around middle grey. Lifts the shadow shoulder without
	//    crushing the darks, which is what makes a flat render read as "film".
	c = clamp((c - 0.5) * contrast + 0.5, 0.0, 1.0);

	// 2. Saturation, then warm highlights / cool shadows.
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(luma), c, saturation);
	float tone_mix = smoothstep(0.10, 0.85, luma);
	c *= mix(shadow_tint, highlight_tint, tone_mix);

	// 3. Halation: hot pixels bleed a warm glow into their neighbours. No extra
	//    texture fetch - derived from the same sampled luminance.
	float hot = smoothstep(0.60, 0.98, luma);
	c += vec3(1.0, 0.50, 0.22) * hot * halation;

	// 4. Organic elliptical vignette (smoother than a plain radial falloff).
	vec2 d = (uv - 0.5) * vec2(1.0, 0.92);
	float v = smoothstep(0.26, 0.82, length(d));
	v = v * v * (3.0 - 2.0 * v);
	c *= 1.0 - v * vignette_strength;

	// 5. Warm light leak from the upper-left corner: the "sun in the lens"
	//    cue that sells a golden-hour frame. Pure radial maths, one add.
	if (light_leak > 0.001) {
		vec2 lp = uv - vec2(0.02, 0.94);
		float g = exp(-dot(lp, lp) * 3.2) * light_leak;
		c += vec3(1.0, 0.46, 0.18) * g * 0.16;
	}

	// 6. Very fine animated grain. Slightly stronger in the shadows, where
	//    banding in a baked sky gradient is most visible.
	vec2 gp = floor(uv * resolution * 0.42) + floor(TIME * 24.0) * 17.0;
	float grain = hash21(gp) - 0.5;
	c += grain * grain_strength * (0.55 + 0.45 * (1.0 - smoothstep(0.10, 0.90, luma)));

	// 7. Optional faint scan texture (off by default - not a retro look).
	float scan = sin(uv.y * resolution.y * 1.6) * 0.5 + 0.5;
	c *= 1.0 - scan * scanline_strength;

	// 8. Anamorphic letterbox with a thin warm edge line. Off in gameplay.
	float bar = clamp(step(uv.y, letterbox) + step(1.0 - letterbox, uv.y), 0.0, 1.0);
	c = mix(c, vec3(0.0), bar);
	float edge = (1.0 - smoothstep(0.0, 0.0025, abs(uv.y - letterbox)))
			+ (1.0 - smoothstep(0.0, 0.0025, abs(uv.y - (1.0 - letterbox))));
	c += vec3(0.55, 0.42, 0.28) * edge * step(0.0001, letterbox) * 0.30;

	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
