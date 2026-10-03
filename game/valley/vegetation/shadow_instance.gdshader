shader_type canvas_item;
// Shadows of instanced sprites: same atlas layout, alpha = shadow. Cool, slightly blue shade.
// Fade with distance: overlapping shadows of dense forests would otherwise read as black.

global uniform float cam_zoom;
uniform float strength = 0.62;
uniform vec3 shade = vec3(0.10, 0.13, 0.22);

void vertex() {
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	float far = 1.0 - smoothstep(0.035, 0.3, cam_zoom);
	COLOR = vec4(shade, a * strength * mix(1.0, 0.4, far));
}
