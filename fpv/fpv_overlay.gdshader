shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float fisheye_strength : hint_range(0.0, 0.5) = 0.12;
uniform float vignette_intensity : hint_range(0.0, 2.0) = 0.4;
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.004;

// Compatibility aliases for existing test suite and analog VTX tuning
uniform float scanline_amount : hint_range(0.0, 0.5) = 0.06;
uniform float noise_amount : hint_range(0.0, 0.25) = 0.025;
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.42;
uniform float aberration : hint_range(0.0, 0.01) = 0.0022;
uniform float barrel : hint_range(0.0, 0.3) = 0.038;

void fragment() {
	// 1. Центрування UV-координат із компенсацією масштабу (zoom),
	// щоб на краях екрана UV ніколи не виходив за [0.0, 1.0] і не розтягував пікселі.
	vec2 uv = SCREEN_UV;
	vec2 centered_uv = uv - 0.5;
	float dist = dot(centered_uv, centered_uv);
	
	float effective_chroma = max(chromatic_aberration, aberration);
	float zoom = 1.0 / (1.0 + 0.5 * fisheye_strength + effective_chroma * 1.5);
	vec2 zoomed_uv = centered_uv * zoom;
	
	// 2. Ефект широкої лінзи FPV (Fisheye Distortion)
	vec2 distorted_uv = 0.5 + zoomed_uv * (1.0 + dist * fisheye_strength);
	
	// 3. Хроматична аберація по краях екрана (RGB Split)
	vec2 uv_r = clamp(distorted_uv + zoomed_uv * effective_chroma, vec2(0.001), vec2(0.999));
	vec2 uv_g = clamp(distorted_uv, vec2(0.001), vec2(0.999));
	vec2 uv_b = clamp(distorted_uv - zoomed_uv * effective_chroma, vec2(0.001), vec2(0.999));
	
	float r = texture(screen_texture, uv_r).r;
	float g = texture(screen_texture, uv_g).g;
	float b = texture(screen_texture, uv_b).b;
	vec3 color = vec3(r, g, b);
	
	// 4. Віньєтування (затемнення по кутах лінзи)
	float vignette = 1.0 - dist * vignette_intensity;
	color *= clamp(vignette, 0.0, 1.0);
	
	// Легка аналогова розгортка VTX
	if (scanline_amount > 0.001) {
		float line = floor(FRAGCOORD.y * 0.5);
		float scan = 0.5 + 0.5 * sin(line * 3.14159265);
		color *= 1.0 - scanline_amount * scan * 0.35;
	}
	
	COLOR = vec4(color, 1.0);
}
