shader_type canvas_item;
// Neutral meadow backdrop for the galleries (same palette + grass detail as the valley).
uniform sampler2D d_grass : filter_linear_mipmap, repeat_enable;
uniform vec3 base = vec3(0.47, 0.50, 0.23);
varying vec2 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
void fragment() {
	vec2 g = vec2(world.x, world.y / 0.766) / 32.0;
	vec3 d = texture(d_grass, g / 5.0).rgb * 2.0;
	float n = vnoise(g / 12.0) * 0.6 + vnoise(g / 3.0) * 0.4;
	vec3 col = base * (0.9 + n * 0.2) * d;
	COLOR = vec4(col, 1.0);
}
