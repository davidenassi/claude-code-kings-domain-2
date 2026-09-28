// Painterly atlas sprites drawn with MultiMesh. Mesh = unit quad (0..1). Per instance:
// transform = sprite size in metres + ground pivot position, INSTANCE_CUSTOM = atlas rect,
// COLOR.rg = pivot (fraction of the sprite), COLOR.b = small tint variation, COLOR.a = local moisture (regional tone).
shader_type canvas_item;

uniform float icon_scale = 1.0;   // >1 enlarges sprites around their pivot at map zoom
uniform float fade = 1.0;
// shared with the far albedo (data/defs/map_style.json); mountains leave tone_amount at 0
uniform float moisture_dry = 0.36;
uniform float moisture_wet = 0.74;
uniform vec3 foliage_dry = vec3(1.10, 1.04, 0.78);
uniform vec3 foliage_lush = vec3(0.82, 0.95, 0.88);
uniform float tone_amount = 1.0;

varying float tint;
varying vec3 tone;

void vertex() {
	VERTEX = (VERTEX - COLOR.rg) * icon_scale;
	tint = COLOR.b;
	vec3 t = mix(foliage_dry, foliage_lush, smoothstep(moisture_dry, moisture_wet, COLOR.a));
	tone = mix(vec3(1.0), t, tone_amount);
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// a wider range than before (0.84..1.14): stands of darker and lighter crowns read as a wood (Phase 18)
	COLOR = vec4(c.rgb * tone * (0.76 + 0.42 * tint), c.a * fade);
}

