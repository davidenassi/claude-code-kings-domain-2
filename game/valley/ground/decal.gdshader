shader_type canvas_item;
// Soft trodden-earth patches (building yards, work areas). UV in -1..1 of the rectangle.

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(max(abs(p) - vec2(0.55), 0.0)) / 0.45;
	float n = vnoise(UV * 9.0 + COLOR.g * 50.0) * 0.5 + vnoise(UV * 23.0) * 0.5;
	float a = smoothstep(1.0, 0.35, r + (n - 0.5) * 0.7);
	vec3 col = mix(vec3(0.50, 0.42, 0.29), vec3(0.58, 0.49, 0.34), n);
	COLOR = vec4(col, a * COLOR.a);
}
