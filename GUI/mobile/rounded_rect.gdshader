shader_type canvas_item;

uniform float radius = 24.0;
uniform vec2 rect_size = vec2(100.0, 100.0);

void fragment() {
	vec2 p = UV * rect_size;
	vec2 half_size = rect_size * 0.5;
	vec2 q = abs(p - half_size) - (half_size - vec2(radius));
	float dist = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	if (dist > 0.0) {
		discard;
	}
	COLOR = texture(TEXTURE, UV) * COLOR;
}
