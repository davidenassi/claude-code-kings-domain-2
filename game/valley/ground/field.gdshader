shader_type canvas_item;
// Crop fields. UV = field-local metres (x along the rows, y across). COLOR: r crop id/8, g seed,
// b distance to the field edge (m / 8), a ground light / 1.5 (sun, cast shadows, occlusion).
//
// Readability at every zoom: fine crop rows when close, broad painterly bands (drill lines, swaths,
// uneven ripening) at middle distance; every periodic pattern is band-limited with fwidth so it fades
// out instead of aliasing when the field becomes small on screen.

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.55 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.3) * 0.15; }

// band-limited stripes: 0..1 wave of the given period across y, faded when the period is < ~3 px
float stripes(float y, float period, float sharp) {
	float w = fwidth(y) / period;
	float s = 0.5 + 0.5 * sin(y * 6.2832 / period);
	s = mix(s, smoothstep(0.5 - sharp, 0.5 + sharp, s), 0.6);
	return mix(s, 0.5, smoothstep(0.18, 0.4, w));
}

void fragment() {
	int crop = int(COLOR.r * 8.0 + 0.5);
	float seed = COLOR.g * 100.0;
	float edge = COLOR.b * 8.0;
	float light = pow(max(COLOR.a * 1.5, 0.0), 0.4545);
	vec2 m = UV;
	float big = fbm(m / 16.0 + seed);
	float mid = fbm(m / 4.0 + seed * 1.7);
	float patchy = smoothstep(0.35, 0.75, fbm(m / 9.0 + seed * 3.1));
	float fine = stripes(m.y, 0.6, 0.2);
	float broad = stripes(m.y + (mid - 0.5) * 0.8, 3.2, 0.25);
	vec3 col;
	if (crop == 0) {            // wheat: golden, ripening unevenly, drill lines
		col = mix(vec3(0.74, 0.60, 0.26), vec3(0.84, 0.71, 0.35), big);
		col = mix(col, vec3(0.62, 0.58, 0.26), patchy * 0.35);
		col *= 1.0 + (broad - 0.5) * 0.16 + (fine - 0.5) * 0.10 + (mid - 0.5) * 0.10;
	} else if (crop == 1) {     // barley: paler, silky
		col = mix(vec3(0.74, 0.69, 0.43), vec3(0.83, 0.77, 0.52), big);
		col = mix(col, vec3(0.62, 0.64, 0.38), patchy * 0.3);
		col *= 1.0 + (broad - 0.5) * 0.12 + (fine - 0.5) * 0.08 + (mid - 0.5) * 0.08;
	} else if (crop == 2) {     // ploughed earth: strong furrows
		float fur = stripes(m.y + mid * 0.6, 0.9, 0.3);
		col = mix(vec3(0.40, 0.28, 0.19), vec3(0.50, 0.37, 0.25), big);
		col *= 0.78 + fur * 0.30 + (broad - 0.5) * 0.14;
		col = mix(col, vec3(0.36, 0.40, 0.22), smoothstep(0.7, 0.9, mid) * 0.25);
	} else if (crop == 3) {     // vegetables: rows of green clumps on soil
		float r = stripes(m.y, 1.4, 0.3);
		float clump = smoothstep(0.35, 0.75, r) * smoothstep(0.3, 0.6, vnoise(m * vec2(1.6, 0.8) + seed));
		vec3 soil = vec3(0.38, 0.28, 0.19);
		vec3 leaf = mix(vec3(0.26, 0.44, 0.17), vec3(0.40, 0.56, 0.22), mid);
		float lw = fwidth(m.y);
		col = mix(soil, leaf, mix(clump, 0.6, smoothstep(0.3, 0.8, lw)));
	} else if (crop == 4) {     // hay meadow with cut swaths
		float sw = stripes(m.y, 4.0, 0.15);
		col = mix(vec3(0.44, 0.50, 0.20), vec3(0.56, 0.58, 0.26), big);
		col = mix(col, vec3(0.70, 0.64, 0.36), smoothstep(0.55, 0.85, sw) * 0.7);
		col *= 1.0 + (mid - 0.5) * 0.10;
	} else {                    // flax in bloom: green with a light lilac-blue haze
		col = mix(vec3(0.36, 0.46, 0.25), vec3(0.42, 0.50, 0.33), big);
		float fl = smoothstep(0.62, 0.9, vnoise(m * 2.5 + seed));
		col = mix(col, vec3(0.50, 0.55, 0.66), fl * 0.35);
		col *= 1.0 + (broad - 0.5) * 0.12 + (fine - 0.5) * 0.06;
	}
	// headland: a strip of grass and trodden soil around the crop, darker at the very border
	float grass = 1.0 - smoothstep(0.6, 1.6 + mid * 0.8, edge);
	vec3 margin = mix(vec3(0.34, 0.40, 0.18), vec3(0.44, 0.40, 0.25), vnoise(m * 0.7 + seed));
	col = mix(col, margin, grass * 0.85);
	col *= mix(0.82, 1.0, smoothstep(0.0, 0.7, edge));
	float a = smoothstep(0.0, 0.45 + mid * 0.4, edge);
	COLOR = vec4(col * light, a);
}
