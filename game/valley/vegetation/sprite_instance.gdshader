shader_type canvas_item;
// MultiMesh2D instance of an atlas sprite: INSTANCE_CUSTOM = atlas rect (u, v, w, h), COLOR = tint.
// From far away crowns are averaged by mipmaps with their own dark interior: compensate so that
// forests keep their teal-green mass instead of turning black.

global uniform float cam_zoom;

void vertex() {
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float far = 1.0 - smoothstep(0.035, 0.32, cam_zoom);
	vec3 rgb = c.rgb * COLOR.rgb;
	rgb = rgb * mix(1.0, 1.75, far) + vec3(0.0, 0.012, 0.03) * far;
	COLOR = vec4(rgb, c.a);
}
