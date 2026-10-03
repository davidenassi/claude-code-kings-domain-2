shader_type canvas_item;
// MultiMesh2D instance of an atlas sprite: INSTANCE_CUSTOM = atlas rect (u, v, w, h), COLOR = tint.
// Note: in fragment() COLOR already holds tint x texel (Godot multiplies the texture in) - it must not be
// multiplied by texture(TEXTURE, UV) again.

global uniform float cam_zoom;

void vertex() {
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}

void fragment() {
	// far away the crowns are averaged with their own shaded interior by the mipmaps: a light lift keeps
	// the forests a readable teal-green mass
	float far = 1.0 - smoothstep(0.035, 0.32, cam_zoom);
	COLOR.rgb = COLOR.rgb * mix(1.0, 1.12, far) + vec3(0.0, 0.006, 0.015) * far;
}
