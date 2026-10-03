shader_type canvas_item;
// MultiMesh2D instance of an atlas sprite: INSTANCE_CUSTOM = atlas rect (u, v, w, h), COLOR = tint.
// Note: in fragment() COLOR already holds tint x texel (Godot multiplies the texture in) - it must not be
// multiplied by texture(TEXTURE, UV) again.

global uniform float cam_zoom;
uniform float atlas_width = 4096.0;

void vertex() {
	// gentle sway of the crowns (top of the sprite moves, the base stays), only noticeable up close
	// the quad is in sprite units (0..1), the instance transform scales it: amplitude in px / sprite width
	float top = 1.0 - UV.y;
	float close = smoothstep(0.2, 0.6, cam_zoom);
	float sway = COLOR.a > 0.9995 ? 1.0 : 0.0;       // rocks, fences and props carry alpha 0.998: no sway
	COLOR.a = 1.0;
	float width_px = max(INSTANCE_CUSTOM.z * atlas_width, 8.0);
	float phase = float(INSTANCE_ID) * 0.6180339 * 6.2831853;
	VERTEX.x += sin(TIME * 1.15 + phase) * (1.8 / width_px) * top * top * close * sway;
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}

void fragment() {
	// far away the crowns are averaged with their own shaded interior by the mipmaps: a light lift keeps
	// the forests a readable teal-green mass
	float far = 1.0 - smoothstep(0.035, 0.32, cam_zoom);
	COLOR.rgb = COLOR.rgb * mix(1.0, 1.12, far) + vec3(0.0, 0.006, 0.015) * far;
}
