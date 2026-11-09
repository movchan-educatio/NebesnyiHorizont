shader_type canvas_item;

// Cheap screen-space motion blur for the FPV camera.
// The pass is hidden while the drone is stationary, so it costs nothing on the
// ground and on the menu.  Samples are taken from the previous screen position
// (toward the centre for forward flight, opposite lateral velocity for strafes).

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float max_radius : hint_range(0.0, 0.08) = 0.035;
uniform vec2 screen_dir = vec2(0.0, 0.0);
uniform float radial_amount : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec2 uv = SCREEN_UV;
	if (strength < 0.002) {
		COLOR = vec4(textureLod(screen_texture, uv, 0.0).rgb, 1.0);
	} else {
		vec2 center = uv - 0.5;
		vec2 offset = (screen_dir * 0.55 - center * radial_amount) * max_radius * strength;
		vec3 col = textureLod(screen_texture, uv, 0.0).rgb;
		float total = 1.0;
		for (int i = 1; i <= 5; i++) {
			float f = float(i) / 5.0;
			col += textureLod(screen_texture, uv - offset * f, 0.0).rgb;
			total += 1.0;
		}
		COLOR = vec4(col / total, 1.0);
	}
}
