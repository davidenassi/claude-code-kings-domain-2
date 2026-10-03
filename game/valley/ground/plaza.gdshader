shader_type canvas_item;
// Cobbled square. UV = metres, COLOR.b = distance to the border (m / 8).

global uniform float cam_zoom;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 m = UV;
	float detail = smoothstep(0.05, 0.3, cam_zoom);
	// irregular setts (jittered rows), warm sandy joints, worn earth patches
	vec2 c = m * vec2(3.4, 3.8);
	float row = floor(c.y);
	c.x += row * 0.5 + hash(vec2(row, 1.0)) * 0.6;
	vec2 cell = floor(c);
	vec2 f = fract(c) - 0.5;
	float jag = (hash(cell + 3.0) - 0.5) * 0.12;
	float stone = smoothstep(0.5, 0.36, max(abs(f.x) * 0.95, abs(f.y)) + jag);
	vec3 sc = mix(vec3(0.58, 0.54, 0.47), vec3(0.68, 0.63, 0.54), hash(cell));
	vec3 col = mix(vec3(0.50, 0.44, 0.34), sc, stone * 0.9);
	col = mix(vec3(0.60, 0.56, 0.48), col, detail * 0.85);
	float n = vnoise(m * 0.18) * 0.6 + vnoise(m * 0.6) * 0.4;
	float worn = smoothstep(0.55, 0.8, n);
	col = mix(col, vec3(0.53, 0.45, 0.33), worn * 0.55);
	col *= 0.94 + vnoise(m * 0.09) * 0.12;
	float e = COLOR.b * 8.0;
	float a = smoothstep(0.0, 1.2 + n, e);
	COLOR = vec4(col, a);
}
