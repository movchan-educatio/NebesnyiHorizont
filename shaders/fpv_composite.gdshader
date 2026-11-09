shader_type canvas_item;

// ---------------------------------------------------------------------------
// Single-pass FPV downlink composite.
//
// One full-screen pass replaces the old stack of separate post-process layers:
//   * ANALOG 5.8 GHz  - PAL/NTSC snow, H/V sync tears, motor EMI bands,
//                       signal-loss desaturation;
//   * DIGITAL O3      - bitrate-driven H.265 macroblocks, packet corruption,
//                       latency-spike frame hold / vertical roll;
//   * FLIR            - white-hot / black-hot thermal ramp with hot-spot
//                       emphasis for engines, exhausts and barrels.
//
// Every visual is driven by uniforms fed from combat/reb_system.gd, so the
// picture degrades exactly when the radio link degrades.
// ---------------------------------------------------------------------------

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
// Set from fpv_overlay.gd every frame. CanvasItem shaders cannot rely on
// SCREEN_PIXEL_SIZE on every renderer, so the pixel grid is passed in.
uniform vec2 screen_size = vec2(1920.0, 1080.0);

// ---- lens / analog compatibility aliases (existing tuning UI + tests) ------
uniform float fisheye_strength : hint_range(0.0, 0.5) = 0.12;
uniform float vignette_intensity : hint_range(0.0, 2.0) = 0.4;
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.004;
uniform float scanline_amount : hint_range(0.0, 0.5) = 0.06;
uniform float noise_amount : hint_range(0.0, 0.25) = 0.025;
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.42;
uniform float aberration : hint_range(0.0, 0.01) = 0.0022;
uniform float barrel : hint_range(0.0, 0.3) = 0.038;
uniform float desaturation : hint_range(0.0, 1.0) = 0.06;
uniform float flicker : hint_range(0.0, 1.0) = 0.015;
uniform vec3 tint = vec3(0.96, 1.0, 0.98);

// ---- live link state (set by reb_system.gd) --------------------------------
uniform int video_mode : hint_range(0, 3) = 0; // 0 analog, 1 digital, 2 white-hot, 3 black-hot
uniform float link_quality : hint_range(0.0, 1.0) = 1.0;
uniform float signal_strength : hint_range(0.0, 1.0) = 1.0;
uniform float bitrate_mbps : hint_range(1.0, 50.0) = 50.0;
uniform float packet_loss : hint_range(0.0, 1.0) = 0.0;
uniform float latency_spike : hint_range(0.0, 1.0) = 0.0;
uniform float throttle : hint_range(0.0, 1.0) = 0.0;
uniform float tear_amount : hint_range(0.0, 1.0) = 0.0;
uniform float interference : hint_range(0.0, 1.0) = 0.0;

// ---- thermal ---------------------------------------------------------------
uniform float thermal_contrast : hint_range(0.5, 4.0) = 1.7;
uniform float thermal_sensitivity : hint_range(0.5, 3.0) = 1.0;
uniform float thermal_noise : hint_range(0.0, 0.3) = 0.045;
uniform float thermal_scanlines : hint_range(0.0, 1.0) = 0.18;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

vec2 barrel_warp(vec2 uv, float k) {
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	return 0.5 + c * (1.0 + k * r2 * 2.0);
}

vec3 sample_screen(vec2 uv, float chroma) {
	vec2 dir = uv - 0.5;
	vec3 col;
	col.r = texture(screen_texture, 0.5 + dir * (1.0 + chroma)).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, 0.5 + dir * (1.0 - chroma)).b;
	return col;
}

// --- ANALOG 5.8 GHz ---------------------------------------------------------
vec3 analog_pass(vec2 uv, vec3 base) {
	vec2 size = screen_size;
	float sig = clamp(signal_strength * 0.78 + link_quality * 0.22, 0.0, 1.0);
	float snow = hash12(floor(uv * size * 0.85) + vec2(TIME * 61.0, TIME * 37.0));
	float snow_amount = noise_amount + (1.0 - sig) * 0.42 + interference * 0.16;
	vec3 col = base;

	// Motor EMI: horizontal rolling bands when the throttle is opened hard.
	float emi = smoothstep(0.72, 1.0, throttle) * interference;
	float band = sin(uv.y * 520.0 + TIME * 71.0) * 0.5 + 0.5;
	float roll = sin((uv.y + TIME * 0.22) * 6.28318) * 0.5 + 0.5;
	col += vec3(0.10, 0.075, 0.03) * (band * 0.7 + roll * 0.3) * emi;

	// REB hum: wide horizontal bars and a slow rolling bright band, visible
	// even at idle throttle when the drone enters an EW dome.
	float jam_bars = smoothstep(0.55, 1.0,
			sin((uv.y + TIME * 0.18) * 38.0) * 0.5 + 0.5);
	col += vec3(0.075, 0.065, 0.045) * jam_bars * interference;
	float jam_roll = step(0.86, fract(uv.y * 6.0 - TIME * 0.55));
	col += vec3(0.05, 0.045, 0.03) * jam_roll * interference;

	// Snow and horizontal sync tears grow as the signal drops.
	col = mix(col, vec3(snow), snow_amount * (0.25 + (1.0 - sig) * 0.9));
	float tear_band = floor(uv.y * 140.0);
	float tear_gate = hash11(tear_band * 1.37 + floor(TIME * 21.0) * 5.13);
	if (tear_gate < tear_amount * 0.38) {
		float shift = (hash11(tear_band * 7.1 + floor(TIME * 21.0)) - 0.5);
		col = mix(col, texture(screen_texture, uv + vec2(shift * tear_amount * 0.18, 0.0)).rgb,
				clamp(tear_amount, 0.0, 0.85));
	}

	// Full colour -> black & white at critical link level.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float desat = clamp(desaturation + (1.0 - sig) * 1.35, 0.0, 1.0);
	col = mix(col, vec3(lum), desat);

	// PAL/NTSC line structure.
	float lines = 576.0;
	float scan = sin(uv.y * lines * 3.14159) * 0.5 + 0.5;
	col *= 1.0 - scanline_amount * scan;

	// Weak signal adds a slow brightness breathing.
	col *= 1.0 + sin(TIME * 7.3) * (1.0 - sig) * 0.10;
	return col;
}

// --- DIGITAL O3 / Walksnail -------------------------------------------------
vec3 digital_pass(vec2 uv, vec3 base) {
	vec2 size = screen_size;
	float rate = clamp(bitrate_mbps / 50.0, 0.02, 1.0);
	float block_px = mix(1.0, 30.0, pow(1.0 - rate, 2.15));
	vec2 blocks = max(floor(size / block_px), vec2(1.0));
	vec2 block_uv = (floor(uv * blocks) + 0.5) / blocks;

	// Latency spikes roll the image and hold a duplicated band.
	vec2 jitter_uv = block_uv;
	float spike = latency_spike;
	jitter_uv.y += sin(TIME * 2.1) * spike * 0.018;
	jitter_uv.x += (hash11(floor(TIME * 11.0)) - 0.5) * spike * 0.006;

	vec3 col = texture(screen_texture, jitter_uv).rgb;
	float block_hash = hash12(floor(uv * blocks) + floor(TIME * 9.0));

	// Packet loss: whole macroblocks repeat a neighbour, go grey or tear.
	if (block_hash < packet_loss * 0.55) {
		vec2 corrupted = block_uv + vec2(
				(hash12(floor(uv * blocks) + 17.0) - 0.5) * 0.12,
				(hash12(floor(uv * blocks) + 41.0) - 0.5) * 0.05);
		vec3 other = texture(screen_texture, corrupted).rgb;
		col = mix(col, other, 0.65);
		col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), 0.35);
	}

	// H.265 ringing / mosquito noise around edges at low bitrate.
	float edge = abs(col.r - base.r) + abs(col.g - base.g) + abs(col.b - base.b);
	float mosquito = hash12(floor(uv * size * 0.5) + TIME) * (1.0 - rate);
	col += (mosquito - 0.5) * (0.025 + edge * 0.35) * (1.0 - rate);

	// Short freeze: repeat the last block row for a couple of scanlines.
	if (spike > 0.45) {
		float freeze_row = floor(uv.y * 32.0) / 32.0;
		vec3 frozen = texture(screen_texture, vec2(uv.x, freeze_row + 0.015)).rgb;
		col = mix(col, frozen, (spike - 0.45) * 0.9);
	}
	return col;
}

// --- FLIR white-hot / black-hot --------------------------------------------
vec3 thermal_palette(float t, bool black_hot) {
	float v = clamp(t, 0.0, 1.0);
	vec3 col;
	if (black_hot) {
		col = vec3(1.0 - v);
		col = mix(col, vec3(1.0 - v * 0.92, 1.0 - v * 0.96, 1.0 - v), 0.3);
	} else {
		col = vec3(v);
		col = mix(col, vec3(v, v * 0.94, v * 0.86), 0.35);
	}
	// Warm mid-tones keep the FLIR look readable instead of flat grey.
	col = mix(col, vec3(0.98, 0.72, 0.40), smoothstep(0.55, 0.9, v) * 0.10);
	return col;
}

vec3 thermal_pass(vec2 uv, vec3 base, bool black_hot) {
	vec2 size = screen_size;
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	// Map the tonemapped image into a sensor window instead of stretching
	// everything to white: ambient ground sits mid-grey, sky is cooler and
	// only engines/exhausts saturate.
	float temp = clamp((lum - 0.18) * 1.5, 0.0, 1.0);
	temp = pow(temp, 1.15) * thermal_sensitivity;

	// Hot spots: engines, exhausts, recently fired barrels.
	float hot = smoothstep(0.80, 0.99, lum);
	temp = clamp(temp + hot * 0.50, 0.0, 1.0);

	// A little spatial edge heat so silhouettes read like a real sensor.
	vec2 px = 2.0 / screen_size;
	float edge = abs(texture(screen_texture, uv + vec2(px.x, 0.0)).r - base.r)
			+ abs(texture(screen_texture, uv - vec2(px.x, 0.0)).r - base.r)
			+ abs(texture(screen_texture, uv + vec2(0.0, px.y)).r - base.r)
			+ abs(texture(screen_texture, uv - vec2(0.0, px.y)).r - base.r);
	temp = clamp(temp + edge * 0.22, 0.0, 1.0);

	float grain = hash12(floor(uv * size * 0.7) + vec2(TIME * 19.0));
	temp = clamp(temp + (grain - 0.5) * thermal_noise, 0.0, 1.0);
	vec3 col = thermal_palette(temp, black_hot);

	float scan = sin(uv.y * 420.0 * 3.14159) * 0.5 + 0.5;
	col *= 1.0 - thermal_scanlines * scan * 0.12;
	return col;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 size = screen_size;

	// Lens: barrel distortion + chromatic aberration, shared by all modes.
	vec2 warped = barrel_warp(uv, barrel);
	float chroma = max(chromatic_aberration, aberration);
	vec3 base = sample_screen(warped, chroma);

	vec3 col;
	if (video_mode == 0) {
		col = analog_pass(uv, base);
	} else if (video_mode == 1) {
		col = digital_pass(warped, base);
	} else {
		col = thermal_pass(warped, base, video_mode == 3);
	}

	// Common lens falloff and sensor character.
	vec2 centered = uv - 0.5;
	float vig = 1.0 - dot(centered, centered) * (vignette_amount + vignette_intensity * 0.5);
	col *= clamp(vig, 0.0, 1.0);
	col *= tint;
	col *= 1.0 + sin(TIME * 47.0) * flicker * 0.5;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
