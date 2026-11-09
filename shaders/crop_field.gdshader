shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// Cultivated field patch for the open maps.
//
// The geometry is a terrain-conforming grid (UV = field-local metres, UV2 =
// world metres).  Rows, furrows, tramlines and stubble are drawn procedurally
// in the fragment shader, so the field does not need thousands of boxes and
// follows the hills instead of floating above them.

uniform vec4 crop_color : source_color = vec4(0.58, 0.48, 0.24, 1.0);
uniform vec4 soil_color : source_color = vec4(0.28, 0.21, 0.14, 1.0);
uniform vec4 straw_color : source_color = vec4(0.70, 0.58, 0.30, 1.0);
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float row_spacing : hint_range(0.4, 8.0) = 1.4;
uniform float row_width : hint_range(0.0, 1.0) = 0.65;
uniform float stubble : hint_range(0.0, 1.0) = 0.0;
uniform float plowed : hint_range(0.0, 1.0) = 0.0;
uniform float tramlines : hint_range(0.0, 1.0) = 1.0;
uniform float variation : hint_range(0.0, 1.0) = 0.35;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.92;
uniform vec2 field_size = vec2(100.0, 60.0);

varying vec3 v_world;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
	return value_noise(p) * 0.62 + value_noise(p * 2.03 + 7.31) * 0.38;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Field-local metres.  Rows run along local Z, spaced along local X.
	vec2 p = UV;
	float across = p.x;
	float along = p.y;

	// Gentle waviness so the rows do not read as a printed barcode.
	across += sin(along * 0.085 + 1.7) * 0.22 + sin(along * 0.027) * 0.45;
	float row_phase = across / max(row_spacing, 0.01);
	// Anti-aliased row band: 1 inside the crop strip, 0 in the furrow.
	float fw = fwidth(row_phase) * 1.15 + 0.002;
	float band = smoothstep(0.5 - row_width * 0.5 - fw,
			0.5 - row_width * 0.5 + fw, fract(row_phase));
	band *= 1.0 - smoothstep(0.5 + row_width * 0.5 - fw,
			0.5 + row_width * 0.5 + fw, fract(row_phase));

	// Crop gaps / lodged patches along the row.
	float gap_noise = fbm2(vec2(across * 0.22, along * 0.31));
	float gaps = smoothstep(0.18, 0.45, gap_noise);
	band *= mix(1.0, gaps, 0.20 + stubble * 0.45);

	// Headland: the last 4 m of every field is a trampled turn strip, so the
	// patch does not end on a razor-straight colour seam in the middle of a
	// meadow.
	vec2 half_size = field_size * 0.5;
	float edge_dist = min(min(UV.x + half_size.x, half_size.x - UV.x),
			min(UV.y + half_size.y, half_size.y - UV.y));
	float headland = smoothstep(0.0, 4.5, edge_dist);
	band *= headland;

	// Tramlines: two bare wheel ruts every ~14 m.
	float tram = 1.0;
	if (tramlines > 0.5) {
		float tram_phase = fract(across / 14.0);
		float tram_w = fwidth(across / 14.0) * 1.2 + 0.004;
		float t1 = smoothstep(0.02 - tram_w, 0.02 + tram_w, tram_phase)
				* (1.0 - smoothstep(0.08 - tram_w, 0.08 + tram_w, tram_phase));
		float t2 = smoothstep(0.92 - tram_w, 0.92 + tram_w, tram_phase);
		tram = 1.0 - max(t1, t2);
	}
	band *= mix(1.0, tram, 0.85);
	// Plowed fields have no crop band at all.
	band *= 1.0 - plowed;

	// ---- albedo -----------------------------------------------------------
	// One octave is enough for the large, soft tint variation.  The old code
	// ran fbm2() (eight hash12 calls) for every tint; at 720p five large crop
	// fields covered most of the screen, and the hashes were a measurable part
	// of the UHD fragment budget.  Single-octave noise is visually identical
	// at the 30-300 m distances where fields are actually seen.
	vec2 det_uv = UV2 * 0.23;
	vec3 ground = texture(dirt_albedo, det_uv).rgb;
	ground *= mix(0.78, 1.18, value_noise(UV2 * 0.05));
	vec3 crop = crop_color.rgb * mix(0.82, 1.12, value_noise(UV2 * 0.10));
	// Sun-bleached straw highlights on the crop strip.
	crop = mix(crop, straw_color.rgb, stubble * 0.18
			+ smoothstep(0.55, 0.9, value_noise(UV2 * 0.14)) * 0.12);
	vec3 furrow = soil_color.rgb * mix(0.80, 1.06, value_noise(UV2 * 0.09));
	// Keep the contrast gentle: from 30-100 m a real crop field is a texture,
	// not a high-contrast barcode.  The band is biased towards the furrow
	// colour and then broken up by noise.
	vec3 albedo = mix(furrow, crop, mix(band, 0.52, 0.34));
	vec3 headland_col = mix(furrow, crop_color.rgb * 0.82, 0.18);
	albedo = mix(headland_col, albedo, headland);

	// Micro grain from the underlying dirt texture keeps the patch from
	// looking like untextured vertex paint up close.
	albedo *= mix(0.86, 1.12, value_noise(UV2 * 0.9));
	ALBEDO = albedo;

	// ---- normals ----------------------------------------------------------
	vec3 n1 = texture(dirt_normal, det_uv).rgb * 2.0 - 1.0;
	vec3 n2 = texture(grass_normal, UV2 * 0.55).rgb * 2.0 - 1.0;
	vec3 n = normalize(n1 * 0.65 + n2 * 0.35);
	// Furrows lean the normal toward the centre of each row.
	float row_sign = sign(sin(row_phase * 6.28318));
	n.x += row_sign * row_width * 0.18 * band;
	n.xy *= normal_strength;
	NORMAL_MAP = normalize(n) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// ---- roughness --------------------------------------------------------
	ROUGHNESS = mix(roughness_base, 0.75, stubble * 0.15);
	SPECULAR = 0.28;
	METALLIC = 0.0;
}
