// Rivers as vector ribbons. Vertices sit on the centre line; the vertex shader pushes them sideways by
// max(real half width, minimum screen width) so rivers stay readable at map zoom.
// COLOR.rg = normal (0..1), COLOR.b = width in metres / 255. UV.x = metres along the course, UV.y = side (-1/+1).
//
// Close to the ground the ribbon is wider than the water: the outer part is the bank (silt and gravel), the
// water carries a slow ripple and a line of light on the lit side. From the map height it goes back to being
// the plain blue line of a drawn map.
shader_type canvas_item;

uniform float mpp = 30.0;
uniform float min_px = 1.6;
uniform float bank_widen = 1.34;   // how much wider than the water the ribbon is drawn close up (= WorldData.RIVER_BANK_WIDEN)
// beyond the gravel, a fringe of damp grass (only drawn: nothing in the game uses it)
uniform float damp_widen = 1.9;

varying float side;
varying float along;
varying float close_t;

void vertex() {
	vec2 n = COLOR.rg * 2.0 - 1.0;
	float half_w = max(COLOR.b * 255.0 * 0.5, min_px * mpp * 0.5);
	close_t = 1.0 - smoothstep(1.6, 7.0, mpp);
	VERTEX += n * UV.y * half_w * mix(1.0, damp_widen, close_t);
	side = UV.y;
	along = UV.x;
}

void fragment() {
	// side runs -1..1 over the whole ribbon: water, gravel bank, damp grass (from the map height, water only)
	float t = abs(side) * mix(1.0, damp_widen, close_t);   // 0..damp_widen in units of the water's half width
	// the bank is not the same all along the river: wider gravel on the inside of the bends, a thin line of
	// mud elsewhere, a stretch of sand now and then
	float wander = 0.5 + 0.5 * sin(along * 0.021 + side * 0.4) * sin(along * 0.0063 + 1.7);
	float bank_out = mix(1.0, mix(1.08, bank_widen, wander), close_t);
	float edge = 1.0;
	float water = 1.0 - smoothstep(edge * 0.90, edge, t);
	vec3 shallow = vec3(0.32, 0.60, 0.71);
	vec3 deep = vec3(0.17, 0.43, 0.62);
	vec3 col = mix(shallow, deep, 1.0 - t * t);
	// a slow ripple down the course, and a thread of light on the north-west side
	float ripple = sin(along * 0.9 + side * 3.1) * 0.5 + 0.5;
	col *= 1.0 - 0.05 * close_t * ripple;
	col += vec3(0.10, 0.12, 0.10) * close_t * smoothstep(0.5, 0.88, -side * mix(1.0, damp_widen, close_t)) * (0.6 + 0.4 * ripple);
	// the bank: wet silt at the water's edge, gravel or sand outside, then damp grass that fades into the meadow
	float sand = smoothstep(0.75, 0.95, 0.5 + 0.5 * sin(along * 0.011 + 2.3));
	vec3 bank = mix(vec3(0.44, 0.40, 0.29), mix(vec3(0.60, 0.56, 0.43), vec3(0.72, 0.66, 0.50), sand),
		smoothstep(edge, bank_out, t));
	vec3 damp = vec3(0.30, 0.42, 0.22);
	float in_bank = 1.0 - smoothstep(bank_out - 0.04, bank_out + 0.02, t);
	col = mix(mix(damp, bank, in_bank), col, water);
	float damp_alpha = (1.0 - smoothstep(bank_out, damp_widen, t)) * 0.55 * close_t;
	float alpha = t <= bank_out ? smoothstep(0.0, max(fwidth(side) * 1.5, 0.001), bank_out * 1.0 - t + 0.02) : damp_alpha;
	if (close_t < 0.001) {
		alpha = smoothstep(0.0, max(fwidth(side) * 1.5, 0.001), 1.0 - abs(side));
	}
	COLOR = vec4(col, alpha);
}

