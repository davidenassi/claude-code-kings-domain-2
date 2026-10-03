shader_type canvas_item;
// Crop fields. UV = field-local metres (x along the rows, y across). COLOR: r crop id/8, g seed,
// b distance to the field edge (m / 8).

global uniform float cam_zoom;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.55 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.3) * 0.15; }

void fragment() {
	int crop = int(COLOR.r * 8.0 + 0.5);
	float seed = COLOR.g * 100.0;
	float edge = COLOR.b * 8.0;
	vec2 m = UV;
	float detail = smoothstep(0.04, 0.25, cam_zoom);
	float big = fbm(m / 14.0 + seed);
	float mid = fbm(m / 3.0 + seed * 1.7);
	vec3 col;
	float rows;
	if (crop == 0) {            // wheat
		rows = 0.5 + 0.5 * sin(m.y * 6.2832 / 0.55);
		col = mix(vec3(0.70, 0.58, 0.27), vec3(0.80, 0.68, 0.34), big);
		col *= 1.0 + (rows - 0.5) * 0.10 * detail + (mid - 0.5) * 0.10;
	} else if (crop == 1) {     // barley
		rows = 0.5 + 0.5 * sin(m.y * 6.2832 / 0.5);
		col = mix(vec3(0.72, 0.66, 0.42), vec3(0.80, 0.74, 0.50), big);
		col *= 1.0 + (rows - 0.5) * 0.08 * detail + (mid - 0.5) * 0.08;
	} else if (crop == 2) {     // ploughed earth
		rows = 0.5 + 0.5 * sin(m.y * 6.2832 / 0.8 + mid * 1.5);
		col = mix(vec3(0.40, 0.29, 0.20), vec3(0.47, 0.35, 0.24), big);
		col *= 0.80 + rows * 0.32 * mix(0.5, 1.0, detail);
	} else if (crop == 3) {     // vegetables: rows of green clumps on soil
		float r = 0.5 + 0.5 * sin(m.y * 6.2832 / 0.7);
		float clump = smoothstep(0.35, 0.75, r) * smoothstep(0.3, 0.6, vnoise(m * vec2(2.2, 1.0) + seed));
		vec3 soil = vec3(0.36, 0.27, 0.19);
		vec3 leaf = mix(vec3(0.27, 0.42, 0.18), vec3(0.38, 0.52, 0.22), mid);
		col = mix(soil, leaf, mix(0.55, clump, detail));
	} else if (crop == 4) {     // hay meadow with cut swaths
		rows = smoothstep(0.75, 0.95, 0.5 + 0.5 * sin(m.y * 6.2832 / 2.4));
		col = mix(vec3(0.46, 0.50, 0.22), vec3(0.56, 0.56, 0.27), big);
		col = mix(col, vec3(0.66, 0.60, 0.33), rows * 0.6 * detail);
	} else {                    // flax (blue flowers)
		rows = 0.5 + 0.5 * sin(m.y * 6.2832 / 0.45);
		col = mix(vec3(0.38, 0.47, 0.36), vec3(0.45, 0.52, 0.58), big);
		float fl = smoothstep(0.82, 0.95, vnoise(m * 7.0 + seed));
		col = mix(col, vec3(0.50, 0.58, 0.80), fl * detail * 0.7);
		col *= 1.0 + (rows - 0.5) * 0.06 * detail;
	}
	// headland: darker, trampled border
	float hd = smoothstep(0.0, 1.6, edge);
	col = mix(col * vec3(0.78, 0.80, 0.70), col, hd);
	// soft organic outline
	float a = smoothstep(0.0, 0.5 + mid * 0.6, edge);
	COLOR = vec4(col, a);
}
