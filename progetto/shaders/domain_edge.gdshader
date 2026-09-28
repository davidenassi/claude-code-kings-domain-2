// King's Domain — the rim of the valley (Rebirth, Phase 1): past the edge of the homeland the world is not known,
// and it is drawn as mist, not as more map. A band of drifting cloud inside the edge, opaque beyond it.
// One quad covers the view; world position (valley metres) = node_origin + local vertex position.
shader_type canvas_item;

uniform vec2 domain_size = vec2(8064.0, 6144.0);
uniform vec2 node_origin = vec2(0.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float band_m = 620.0;          // width of the misty band inside the valley's edge
uniform vec3 mist_light = vec3(0.90, 0.89, 0.84);
uniform vec3 mist_shadow = vec3(0.66, 0.68, 0.66);
uniform float drift = 0.0;             // seconds, for a very slow movement of the clouds

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 wp = node_origin + local_pos;
	vec2 d2 = min(wp, domain_size - wp);
	float inside = min(d2.x, d2.y);                        // metres from the nearest edge, negative outside
	vec2 flow = vec2(drift * 3.0, drift * 1.2);
	// large, soft cloud banks: three octaves, the finest one weak (fine noise reads as gravel, not as cloud)
	float n1 = texture(noise_tex, (wp + flow) / 3100.0).r;
	float n2 = texture(noise_tex, (wp - flow * 0.6) / 1150.0).g;
	float n3 = texture(noise_tex, (wp + flow * 0.3) / 430.0).b;
	float billow = n1 * 0.62 + n2 * 0.28 + n3 * 0.10;
	// the edge of the mist wanders in and out of the valley like the edge of a cloud bank
	float edge = inside - (billow - 0.45) * band_m * 1.5;
	float fog = 1.0 - smoothstep(-band_m * 0.15, band_m, edge);
	// light tops and grey bellies of the clouds, a warm haze where they thin out over the land
	float lit = smoothstep(0.30, 0.80, n2 * 0.7 + n3 * 0.3);
	vec3 col = mix(mist_shadow, mist_light, lit);
	col = mix(col, vec3(0.93, 0.90, 0.82), (1.0 - fog) * 0.5);
	COLOR = vec4(col, clamp(fog, 0.0, 1.0) * (inside < -band_m * 0.3 ? 1.0 : 0.96));
}
