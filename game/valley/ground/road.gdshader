shader_type canvas_item;
// Roads and paths. UV.x = across (0..1), UV.y = metres along. COLOR: r kind (0 path, 0.5 lane, 1 main),
// g = width in m / 10, b = cobbled (1) or earth (0).

global uniform float cam_zoom;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float kind = COLOR.r;
	float width = COLOR.g * 10.0;
	float cob = COLOR.b;
	vec2 m = vec2((UV.x - 0.5) * width, UV.y);           // metres: x across from the centre
	float d = abs(UV.x - 0.5) * 2.0;                       // 0 centre .. 1 edge
	float n = vnoise(m * vec2(1.3, 0.35)) * 0.6 + vnoise(m * 3.1) * 0.4;
	float detail = smoothstep(0.05, 0.3, cam_zoom);
	vec3 dirt = mix(vec3(0.56, 0.46, 0.32), vec3(0.64, 0.54, 0.38), n);
	// wheel ruts on main roads and lanes
	float rut = 0.0;
	if (kind > 0.25) {
		float rw = width * 0.22;
		rut = smoothstep(0.35, 0.0, abs(abs(m.x) - rw)) * 0.5;
	}
	vec3 col = dirt * (1.0 - rut * 0.18 * detail);
	// pebbles
	float peb = smoothstep(0.86, 0.92, vnoise(m * 6.0));
	col = mix(col, vec3(0.70, 0.66, 0.58), peb * 0.5 * detail);
	// cobbles
	if (cob > 0.5) {
		vec2 c = m * vec2(3.2, 2.6);
		c.x += floor(c.y) * 0.5;
		vec2 f = fract(c) - 0.5;
		float stone = smoothstep(0.5, 0.36, max(abs(f.x), abs(f.y)));
		vec3 sc = mix(vec3(0.52, 0.50, 0.46), vec3(0.62, 0.58, 0.52), hash(floor(c)));
		col = mix(mix(vec3(0.36, 0.33, 0.29), sc, stone), col, 1.0 - detail * 0.85);
		col = mix(col, vec3(0.55, 0.52, 0.47), 1.0 - detail);
	}
	// grass creeping in at the edges, darker worn border
	float edge = smoothstep(0.62 + n * 0.25, 1.0, d);
	col = mix(col, col * vec3(0.82, 0.84, 0.74), smoothstep(0.4, 0.9, d) * 0.6);
	float a = 1.0 - edge;
	if (kind < 0.25) a *= 0.85;
	COLOR = vec4(col, a);
}
