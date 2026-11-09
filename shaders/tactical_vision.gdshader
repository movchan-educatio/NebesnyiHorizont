shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform int vision_mode : hint_range(0, 3) = 0; // 0=NORMAL, 1=NVG, 2=FLIR_WHITE_HOT, 3=FLIR_BLACK_HOT
uniform float nvg_gain : hint_range(1.0, 5.0) = 2.4;
uniform float thermal_sensitivity : hint_range(0.5, 3.0) = 1.6;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.25;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.10;

float pseudo_noise(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 src = texture(screen_texture, uv);
	vec3 c = src.rgb;

	if (vision_mode == 0) {
		// Normal daylight RGB
		COLOR = src;
	}
	else {
		float lum = dot(c, vec3(0.299, 0.587, 0.114));
		float dist_from_center = distance(uv, vec2(0.5, 0.5));
		float time_val = TIME * 25.0;
		float noise = (pseudo_noise(uv * 320.0 + fract(time_val)) - 0.5) * noise_strength;
		float scanline = sin(uv.y * 650.0) * scanline_strength * 0.08;

		if (vision_mode == 1) {
			// NVG: Night Vision Goggles (Green Phosphor)
			float amplified = clamp(lum * nvg_gain + noise - scanline, 0.0, 1.0);
			float vignette = smoothstep(0.72, 0.42, dist_from_center);
			vec3 nvg_tint = vec3(0.18, 0.96, 0.28) * amplified * vignette;
			if (amplified > 0.85) {
				nvg_tint += vec3(0.25, 0.75, 0.25) * (amplified - 0.85) * 2.0;
			}
			COLOR = vec4(nvg_tint, 1.0);
		}
		else if (vision_mode == 2) {
			// FLIR White Hot: High temperature targets glow bright white
			float heat_boost = max(0.0, c.r - (c.g + c.b) * 0.5) * 1.6;
			float thermal = clamp(pow(lum, 1.0 / thermal_sensitivity) + heat_boost + noise * 0.4 - scanline, 0.0, 1.0);
			float vig = clamp(1.0 - dist_from_center * 0.35, 0.0, 1.0);
			vec3 white_hot = vec3(thermal * vig);
			// Subtle iron-bow hint on hottest spots
			if (thermal > 0.90) {
				white_hot += vec3(0.12, 0.05, 0.0) * (thermal - 0.90) * 4.0;
			}
			COLOR = vec4(clamp(white_hot, vec3(0.0), vec3(1.0)), 1.0);
		}
		else if (vision_mode == 3) {
			// FLIR Black Hot: Inverted thermal palette
			float heat_boost = max(0.0, c.r - (c.g + c.b) * 0.5) * 1.6;
			float thermal = clamp(pow(lum, 1.0 / thermal_sensitivity) + heat_boost, 0.0, 1.0);
			float black_hot = 1.0 - thermal;
			float vig = clamp(1.0 - dist_from_center * 0.30, 0.0, 1.0);
			vec3 col = vec3((black_hot + noise * 0.3 + scanline) * vig);
			COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
		}
	}
}
