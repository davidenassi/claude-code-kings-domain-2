shader_type canvas_item;
// King's Domain — valley terrain chunk: baked lit colour + close-up detail textures + animated water.
// TEXTURE = baked terrain colour (sRGB). Companion maps share the same layout/UVs:
//   mat_tex   R rock  G bare soil  B snow  A forest floor   (grass = remainder)
//   light_tex lighting factor / 2 (gamma 2.2) — shadows/relief, reused to shade the water
//   water_tex R sqrt(depth/16)  G,B screen-space flow (0.5 = none, length = speed/4)  A foam

global uniform float cam_zoom;

uniform sampler2D mat_tex : filter_linear_mipmap;
uniform sampler2D light_tex : filter_linear_mipmap;
uniform sampler2D water_tex : filter_linear_mipmap;
uniform bool has_water = false;

uniform sampler2D d_grass : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D d_forest : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D d_soil : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D d_rock : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D d_snow : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D water_normal : filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;

uniform float sin_el = 0.766;
uniform float px_per_m = 32.0;
uniform float detail_strength = 1.0;
uniform vec3 water_deep = vec3(0.10, 0.22, 0.26);     // teal, measured on the reference images
uniform vec3 water_mid = vec3(0.16, 0.34, 0.36);
uniform vec3 water_shallow = vec3(0.30, 0.46, 0.42);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec3 flow_sample(sampler2D tex, vec2 uv, vec2 flow, float t) {
	// two-phase flow mapping: no infinite stretching, seamless loop
	float p0 = fract(t);
	float p1 = fract(t + 0.5);
	float w = abs(p0 - 0.5) * 2.0;
	vec3 a = texture(tex, uv - flow * p0).rgb;
	vec3 b = texture(tex, uv - flow * p1 + vec2(0.37, 0.21)).rgb;
	return mix(a, b, w);
}

void fragment() {
	vec3 base = texture(TEXTURE, UV).rgb;
	vec4 m = texture(mat_tex, UV);
	// ground metres in screen-uniform coordinates (keeps detail density on slopes)
	vec2 g = vec2(world.x, world.y / sin_el) / px_per_m;

	// ---------------- close-up detail ----------------
	float fade = smoothstep(0.05, 0.30, cam_zoom) * detail_strength;
	if (fade > 0.001) {
		// two rotated samples blended by a slow mask: hides the tile repetition
		vec2 g2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * g * 1.37 + vec2(13.1, 7.7);
		float tb = smoothstep(0.35, 0.65, texture(water_normal, g / 37.0).b);
		vec3 dg = mix(texture(d_grass, g / 5.0).rgb, texture(d_grass, g2 / 5.0).rgb, tb);
		vec3 df = mix(texture(d_forest, g / 5.0).rgb, texture(d_forest, g2 / 5.0).rgb, tb);
		vec3 ds = mix(texture(d_soil, g / 4.5).rgb, texture(d_soil, g2 / 4.5).rgb, tb);
		vec3 dr = texture(d_rock, g / 14.0).rgb * 0.6 + texture(d_rock, g2 / 8.0 + 0.3).rgb * 0.4;
		dr = mix(vec3(0.5), dr, 0.75);
		vec3 dn = texture(d_snow, g / 11.0).rgb;
		float wg = clamp(1.0 - m.r - m.g - m.b - m.a, 0.0, 1.0);
		vec3 d = dg * wg + df * m.a + ds * m.g + dr * m.r + dn * m.b;
		d /= max(wg + m.r + m.g + m.b + m.a, 0.001);
		base *= mix(vec3(1.0), d * 2.0, fade);
	}
	// ---------------- middle distance: broad painterly grass tufts and soil patches ----------------
	float mfade = smoothstep(0.035, 0.11, cam_zoom) * detail_strength;
	if (mfade > 0.001) {
		float wgm = clamp(1.0 - m.r - m.g - m.b - m.a, 0.0, 1.0);
		vec2 gm = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * g;
		float t1 = dot(texture(d_grass, gm / 23.0).rgb, vec3(0.3333));
		float t2 = dot(texture(d_soil, g / 31.0 + 0.5).rgb, vec3(0.3333));
		float t3 = dot(texture(d_forest, gm / 19.0 + 0.2).rgb, vec3(0.3333));
		base *= 1.0 + ((t1 - 0.5) * 0.5 * wgm + (t2 - 0.5) * 0.3 * m.g + (t3 - 0.5) * 0.4 * m.a) * mfade;
	}
	vec3 col = base;

	// ---------------- water ----------------
	if (has_water) {
		vec4 w = texture(water_tex, UV);
		if (w.r > 0.003) {
			float depth = w.r * w.r * 16.0;
			vec2 flow = (w.gb - 0.5) * 2.0;
			float speed = length(flow) * 4.0;
			vec2 dir = flow / max(length(flow), 0.0001);
			vec3 L = pow(texture(light_tex, UV).rgb, vec3(2.2)) * 2.0;
			float lit = clamp(dot(L, vec3(0.3333)) / 1.55, 0.0, 1.15);

			float dd = 1.0 - exp(-depth * 0.6);
			vec3 wc = mix(water_shallow, water_mid, smoothstep(0.0, 0.55, dd));
			wc = mix(wc, water_deep, smoothstep(0.55, 1.0, dd));

			// ripples advected along the flow (rivers) + slow wind ripples (lake)
			vec2 uvw = g / 28.0;
			float fs = clamp(speed, 0.0, 4.0);
			vec3 n1 = flow_sample(water_normal, uvw, dir * fs * 0.12, TIME * (0.10 + fs * 0.12));
			vec3 n2 = texture(water_normal, g / 11.0 + vec2(TIME * 0.009, TIME * 0.005)).rgb;
			vec2 nrm = (n1.xy - 0.5) * 2.0 * 0.75 + (n2.xy - 0.5) * 2.0 * 0.35;
			float shade = dot(nrm, normalize(vec2(-0.85, -0.5)));
			wc *= 1.0 + shade * 0.07;
			float glint = pow(clamp(shade, 0.0, 1.0), 8.0);
			wc += vec3(0.85, 0.9, 0.95) * glint * 0.16;
			// broad, slow brightness variation (current lines, sky reflection)
			float broad = texture(water_normal, g / 90.0 + vec2(TIME * 0.002, 0.0)).b - 0.5;
			wc *= 1.0 + broad * 0.18;
			// painterly wave crests: sparse light strokes, across the current (rivers) or the wind (lake)
			// (advected noise, not sin(dot(g, dir)): with g in the thousands of metres, a direction that changes
			// from texel to texel of the flow map made the phase jump -> blocky crests)
			float cr = flow_sample(water_normal, g / 7.0, dir * fs * 0.2, TIME * (0.12 + fs * 0.15)).b;
			float mask = smoothstep(0.45, 0.7, texture(water_normal, g / 31.0 + vec2(0.0, TIME * 0.004)).b);
			float crest = smoothstep(0.72, 0.88, cr) * mask * smoothstep(0.4, 1.2, depth);
			float close = smoothstep(0.25, 0.8, cam_zoom);
			wc = mix(wc, vec3(0.62, 0.78, 0.84) * mix(0.6, 1.0, lit), crest * mix(0.35, 0.55, close));
			// sun caustics on the bed of the shallows (bright web, close views)
			float cau = smoothstep(0.66, 0.9, texture(water_normal, g / 3.2 + vec2(TIME * 0.05, -TIME * 0.035)).b)
				* smoothstep(0.66, 0.9, texture(water_normal, g / 4.1 - vec2(TIME * 0.04, TIME * 0.02)).b);
			wc += vec3(0.20, 0.26, 0.22) * cau * (1.0 - dd) * close * lit;
			wc *= mix(0.5, 1.0, clamp(lit, 0.0, 1.0));

			// transparency over the bed in the shallows, opaque in the deep
			float a = clamp(0.22 + dd * 1.2, 0.0, 1.0);
			// soft shoreline
			a *= smoothstep(0.003, 0.06, w.r);
			col = mix(base, wc, a);

			// lapping foam line along the shore (breathes slowly)
			float lap = 1.0 - smoothstep(0.03, 0.10, w.r);
			float pulse = 0.55 + 0.45 * sin(TIME * 0.9 + texture(water_normal, g / 9.0).b * 12.0);
			col = mix(col, vec3(0.86, 0.90, 0.90) * mix(0.7, 1.0, lit), lap * smoothstep(0.003, 0.03, w.r) * pulse * 0.55);
			// foam: shore lines, rapids, waterfalls
			float fn = flow_sample(foam_tex, g / 6.0, dir * fs * 0.25, TIME * (0.15 + fs * 0.2)).r;
			float foam = w.a * smoothstep(0.35, 0.75, fn + w.a * 0.35);
			foam += smoothstep(0.75, 1.0, w.a) * 0.5;
			float fall = smoothstep(2.6, 3.4, speed);
			foam *= 1.0 - fall * 0.85;
			col = mix(col, vec3(0.93, 0.96, 0.98) * mix(0.75, 1.0, lit), clamp(foam, 0.0, 0.92));
			// falling water: streaks running down the flow, darker gaps showing the rock behind
			if (fall > 0.0) {
				vec2 across = vec2(-dir.y, dir.x);
				float turb = texture(water_normal, g / 4.0 + vec2(0.0, -TIME * 0.25)).b;
				vec2 sv = vec2(dot(g, across) * 1.2 + turb * 0.9, dot(g, dir) * 0.09 - TIME * 1.3);
				float st = texture(foam_tex, sv).r * 0.5 + texture(foam_tex, sv * vec2(2.7, 1.9) + 0.31).r * 0.3
					+ texture(foam_tex, g / 2.5 + vec2(0.0, -TIME * 0.8)).r * 0.2;
				// ropes and sheets of water across the fall, white spray where they break
				float rope = texture(water_normal, vec2(dot(g, across) / 7.0, 0.37)).b;
				float streak = smoothstep(0.12, 0.62, st + (rope - 0.5) * 0.5);
				vec3 fallc = mix(vec3(0.50, 0.63, 0.70), vec3(0.97, 0.98, 1.0), streak) * mix(0.75, 1.05, lit);
				float cover = smoothstep(0.004, 0.06, w.r) * (0.65 + 0.35 * streak);
				col = mix(col, fallc, fall * cover);
				col = mix(col, vec3(0.92, 0.95, 0.97), fall * 0.10);
			}
		}
	}
	COLOR = vec4(col, 1.0);
}
