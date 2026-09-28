// King's Domain — terrain of the single world, kept deliberately simple (flat 2D look, depth only hinted).
// One quad covers the view; world position = node_origin + local vertex position.
// Near/mid zoom: soft-blended biome colours + light relief shading + flat water with depth tint.
// Far zoom: the illustrated albedo baked by tools/worldgen.
shader_type canvas_item;

uniform sampler2D height_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D moisture_tex : filter_linear, repeat_disable;
uniform sampler2D biome_tex : filter_nearest, repeat_disable;
uniform sampler2D forest_tex : filter_linear, repeat_disable;
uniform sampler2D coast_tex : filter_linear, repeat_disable;
uniform sampler2D water_tex : filter_nearest, repeat_disable;
uniform sampler2D albedo_far_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// map mode overlay: province id raster (RG8, 65535 = none) + per-province colour lookup (RGBA8, x = id)
uniform sampler2D province_tex : filter_nearest, repeat_disable;
uniform sampler2D overlay_tex : filter_nearest, repeat_disable;
uniform float overlay_strength = 0.0;
// the overlay fades out below these zoom levels (the political tint is not wanted on a village street)
uniform vec2 overlay_fade_mpp = vec2(0.0, 0.0);
uniform int selected_id = -1;

uniform vec2 world_size = vec2(112000.0, 72000.0);
uniform vec2 node_origin = vec2(0.0);
// fposmod(node_origin, 1024): noise lookups use scales dividing 1024 m so they stay continuous
uniform vec2 origin_mod = vec2(0.0);
uniform float mpp = 30.0;
uniform vec3 sun_dir = vec3(-0.5, -0.5, 0.71);
uniform float relief = 0.30;       // strength of the hinted relief (0 = flat map)
uniform float far_start = 9.0;
uniform float far_end = 26.0;
// regional colour rules shared with the far albedo (data/defs/map_style.json)
uniform float moisture_dry = 0.36;
uniform float moisture_wet = 0.74;
uniform vec3 ground_dry = vec3(1.10, 1.01, 0.76);
uniform float ground_dry_amount = 0.42;
uniform vec3 ground_wet = vec3(0.86, 1.00, 0.90);
uniform float ground_wet_amount = 0.32;
uniform float valley_depth_m = 220.0;
uniform float valley_light = 0.12;
uniform vec3 valley_cool = vec3(0.90, 0.96, 1.02);
uniform vec3 crest_warm = vec3(1.06, 1.03, 0.94);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

vec3 biome_color(ivec2 c, ivec2 size) {
	int b = int(texelFetch(biome_tex, clamp(c, ivec2(0), size - 1), 0).r * 255.0 + 0.5);
	return texelFetch(palette_tex, ivec2(b, 0), 0).rgb;
}

int province_id(ivec2 c, ivec2 size) {
	vec2 rg = texelFetch(province_tex, clamp(c, ivec2(0), size - 1), 0).rg * 255.0 + 0.5;
	return int(rg.r) + int(rg.g) * 256;
}

vec4 overlay_color(int id) {
	if (id >= 65535) {
		return vec4(0.0);
	}
	return texelFetch(overlay_tex, ivec2(id, 0), 0);
}

vec3 biome_bilinear(vec2 bp, ivec2 size) {
	vec2 f = fract(bp);
	ivec2 c0 = ivec2(floor(bp));
	return mix(mix(biome_color(c0, size), biome_color(c0 + ivec2(1, 0), size), f.x),
		mix(biome_color(c0 + ivec2(0, 1), size), biome_color(c0 + ivec2(1, 1), size), f.x), f.y);
}

void fragment() {
	vec2 wp = node_origin + local_pos;
	vec2 uv = wp / world_size;
	vec2 dp = origin_mod + local_pos;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		COLOR = vec4(0.11, 0.30, 0.50, 1.0);
	} else {
		float far_t = smoothstep(far_start, far_end, mpp);
		vec3 col = vec3(0.0);
		if (far_t < 0.999) {
			vec3 n = texture(noise_tex, dp / 256.0).rgb - 0.5;
			vec3 big = texture(noise_tex, dp / 1024.0).rgb - 0.5;

			// soft biome colours: bilinear blend of palette colours with a small warp
			ivec2 bsize = textureSize(biome_tex, 0);
			vec2 bp = (wp + n.rg * 70.0 + big.rg * 260.0) / world_size * vec2(bsize) - 0.5;
			// four offset bilinear taps (tent filter): no stair-stepped edges along the 64 m cells
			col = 0.25 * (biome_bilinear(bp + vec2(-0.5, -0.5), bsize) + biome_bilinear(bp + vec2(0.5, -0.5), bsize)
				+ biome_bilinear(bp + vec2(-0.5, 0.5), bsize) + biome_bilinear(bp + vec2(0.5, 0.5), bsize));
			col *= 0.95 + 0.10 * big.b;
			col *= 1.0 + 0.05 * n.b;  // paper grain
			// broad soft patches of the grass itself (world art pass): lusher and darker in the hollows, drier and
			// paler on the rises, now and then a warm patch of rich earth showing through. Warped twice, so the
			// shapes are round and flowing, never the cells of a grid. Strongest at the zoom of the villages.
			float patch_t = 1.0 - smoothstep(3.0, 7.0, mpp);
			if (patch_t > 0.001) {
				vec2 warp = (texture(noise_tex, dp / 512.0).rg - 0.5) * 180.0;
				float lush = texture(noise_tex, (dp + warp) / 256.0).b;
				float dry = texture(noise_tex, (dp - warp * 0.7) / 128.0 + vec2(0.37, 0.61)).g;
				vec3 lush_col = col * vec3(0.84, 0.93, 0.82);
				vec3 dry_col = col * vec3(1.10, 1.04, 0.80);
				col = mix(col, lush_col, smoothstep(0.55, 0.78, lush) * 0.75 * patch_t);
				col = mix(col, dry_col, smoothstep(0.58, 0.80, dry) * 0.60 * patch_t);
				float earth = smoothstep(0.70, 0.86, texture(noise_tex, (dp + warp) / 64.0 + vec2(0.13, 0.29)).r);
				col = mix(col, col * vec3(1.12, 0.98, 0.76), earth * 0.35 * patch_t);
			}
			// close up the ground gets a grain of its own: at a metre per pixel a flat wash of green reads
			// as paper, not as a field. Three taps, and only while the camera is down among the houses.
			float close_t = 1.0 - smoothstep(0.7, 3.5, mpp);
			if (close_t > 0.001) {
				vec3 g1 = texture(noise_tex, dp / 16.0).rgb - 0.5;
				vec3 g2 = texture(noise_tex, dp / 4.0).rgb - 0.5;
				col *= 1.0 + close_t * (0.11 * g1.g + 0.06 * g2.b);
				// where the grass thins the earth shows through
				float bare = smoothstep(0.60, 0.88, texture(noise_tex, dp / 32.0).r + 0.30 * g1.r);
				col = mix(col, col * vec3(1.20, 1.03, 0.78), bare * close_t * 0.5);
			}

			// regional character: dry lands turn ochre, wet lowlands deeper green
			float wet_t = smoothstep(moisture_dry, moisture_wet, texture(moisture_tex, uv).r + big.r * 0.06);
			col *= mix(mix(vec3(1.0), ground_dry, ground_dry_amount), mix(vec3(1.0), ground_wet, ground_wet_amount), wet_t);

			// forest floor tint (the tree sprites draw the forest itself)
			float forest = texture(forest_tex, uv).r;
			col = mix(col, col * vec3(0.78, 0.84, 0.74), smoothstep(0.3, 0.6, forest + 0.2 * n.b));

			// hinted relief
			vec2 texel = 1.0 / vec2(textureSize(height_tex, 0));
			float cell = world_size.x * texel.x;
			float hL = textureLod(height_tex, uv - vec2(texel.x, 0.0), 0.0).r;
			float hR = textureLod(height_tex, uv + vec2(texel.x, 0.0), 0.0).r;
			float hU = textureLod(height_tex, uv - vec2(0.0, texel.y), 0.0).r;
			float hD = textureLod(height_tex, uv + vec2(0.0, texel.y), 0.0).r;
			float h = textureLod(height_tex, uv, 0.0).r;
			vec2 grad = vec2(hR - hL, hD - hU) / (2.0 * cell);
			vec3 sd = normalize(sun_dir);
			float lit = clamp(dot(normalize(vec3(-grad * 1.8, 1.0)), sd) / sd.z, 0.4, 1.4);
			col *= mix(1.0, lit, relief);
			// valleys a little darker and cooler, crests lighter and warmer (height minus its blurred mip)
			float local_h = clamp((h - textureLod(height_tex, uv, 3.5).r) / valley_depth_m, -1.0, 1.0);
			col *= (1.0 + valley_light * local_h) * mix(vec3(1.0), local_h < 0.0 ? valley_cool : crest_warm, abs(local_h));

			// bare rock and snow on high ground. The rock carries a grain of its own and takes twice the
			// light: without it a mountain range reads as a smooth pale wash at regional zoom.
			vec3 fine = texture(noise_tex, dp / 64.0).rgb - 0.5;   // 64 divides 1024: no seam when the quad moves
			float rock_t = smoothstep(1300.0, 1800.0, h + n.r * 150.0) * 0.50;
			vec3 rock_col = vec3(0.64, 0.60, 0.50) * (0.82 + 0.30 * fine.b + 0.16 * fine.r);
			col = mix(col, rock_col, rock_t);
			float snow_t = smoothstep(2000.0, 2300.0, h + n.g * 150.0) * 0.72;
			vec3 snow_col = vec3(0.90, 0.91, 0.90) * (0.93 + 0.12 * fine.b);
			col = mix(col, snow_col, snow_t);
			col *= mix(1.0, lit, clamp(relief * (rock_t + snow_t) * 1.6, 0.0, 0.9));

			// water: flat colour, darker with depth, thin light shore line
			float coast_m = (texture(coast_tex, uv).r * 255.0 - 127.5) * 16.0 + n.g * 14.0;
			if (coast_m < 0.0) {
				ivec2 wsize = textureSize(water_tex, 0);
				bool lake = abs(texelFetch(water_tex, ivec2(uv * vec2(wsize)), 0).r * 255.0 - 2.0) < 0.5;
				float depth_t = smoothstep(0.0, lake ? 250.0 : 800.0, -coast_m);
				vec3 shallow = lake ? vec3(0.30, 0.58, 0.68) : vec3(0.27, 0.56, 0.70);
				vec3 deep = lake ? vec3(0.16, 0.38, 0.56) : vec3(0.11, 0.30, 0.50);
				col = mix(shallow, deep, depth_t);
				col = mix(col, vec3(0.72, 0.86, 0.86), (1.0 - smoothstep(0.0, 6.0 + mpp * 1.5, -coast_m)) * 0.5);
			}
		}
		if (far_t > 0.001) {
			col = mix(col, texture(albedo_far_tex, uv).rgb, far_t);
		}
		float ov_strength = overlay_strength * (overlay_fade_mpp.y > 0.0 ? smoothstep(overlay_fade_mpp.x, overlay_fade_mpp.y, mpp) : 1.0);
		if (ov_strength > 0.001 || selected_id >= 0) {
			// bilinear blend over the 4 nearest province cells (soft edges; vector borders draw the crisp line on top)
			vec3 wn = texture(noise_tex, dp / 1024.0).rgb - 0.5;
			ivec2 psize = textureSize(province_tex, 0);
			vec2 pp = (wp + wn.rg * 120.0) / world_size * vec2(psize) - 0.5;
			vec2 f = fract(pp);
			ivec2 c0 = ivec2(floor(pp));
			int i00 = province_id(c0, psize);
			int i10 = province_id(c0 + ivec2(1, 0), psize);
			int i01 = province_id(c0 + ivec2(0, 1), psize);
			int i11 = province_id(c0 + ivec2(1, 1), psize);
			float land = step(0.0, (texture(coast_tex, uv).r * 255.0 - 127.5));
			if (ov_strength > 0.001) {
				vec4 o = mix(mix(overlay_color(i00), overlay_color(i10), f.x), mix(overlay_color(i01), overlay_color(i11), f.x), f.y);
				// tint scaled by terrain brightness keeps the painted relief readable under the colour
				vec3 tinted = mix(col, o.rgb * (0.55 + 0.6 * dot(col, vec3(0.33))), 0.65);
				col = mix(col, tinted, clamp(o.a * land * ov_strength * 1.6, 0.0, 1.0));
			}
			if (selected_id >= 0) {
				float s = mix(mix(float(i00 == selected_id), float(i10 == selected_id), f.x),
					mix(float(i01 == selected_id), float(i11 == selected_id), f.x), f.y);
				col = mix(col, col * 1.12 + vec3(0.05, 0.04, 0.0), s * land);
			}
		}
		COLOR = vec4(col, 1.0);
	}
}

