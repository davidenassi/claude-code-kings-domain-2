shader_type canvas_item;
render_mode blend_mul;
// Slow drifting cloud shadows over the valley (multiply). Fades out when zoomed in close.

global uniform float cam_zoom;
uniform float strength = 0.16;
varying vec2 world;

void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { s += vnoise(p) * a; p = p * 2.03 + 1.7; a *= 0.5; }
	return s;
}


void fragment() {
	vec2 m = vec2(world.x, world.y / 0.766) / 32.0;          // metres
	vec2 drift = vec2(TIME * 2.2, TIME * 0.9);
	float c = fbm((m + drift) / 380.0);
	float cloud = smoothstep(0.52, 0.68, c);
	float fade = 1.0 - smoothstep(0.18, 0.4, cam_zoom);
	float k = cloud * strength * fade;
	COLOR = vec4(vec3(1.0 - k * 0.95, 1.0 - k * 0.9, 1.0 - k * 0.7), 1.0);
}
