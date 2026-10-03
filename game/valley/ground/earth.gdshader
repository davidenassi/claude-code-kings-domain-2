shader_type canvas_item;
// Ground worn by a settlement: patches of bare earth and trampled grass. UV = metres,
// COLOR.b = distance to the border (m / 8) for a wide soft edge.

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.5 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 + 1.1) * 0.2; }

void fragment() {
	vec2 m = UV;
	float light = pow(max(COLOR.a * 1.5, 0.0), 0.4545);
	float n = fbm(m / 9.0);
	float fine = fbm(m * 0.9);
	vec3 earth = mix(vec3(0.47, 0.39, 0.27), vec3(0.55, 0.46, 0.32), fine);
	vec3 grass = mix(vec3(0.38, 0.42, 0.21), vec3(0.45, 0.47, 0.24), fine);
	float bare = smoothstep(0.38, 0.62, n);
	vec3 col = mix(grass, earth, bare);
	float e = COLOR.b * 8.0;
	float a = smoothstep(0.0, 5.5 + n * 2.5, e) * mix(0.72, 0.95, bare);
	COLOR = vec4(col * light, a);
}
