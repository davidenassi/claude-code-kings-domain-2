shader_type canvas_item;
// Ground shadow of a single sprite. use_red: shadow stored in the red channel (L8 images),
// otherwise in alpha (shadow atlas).

uniform bool use_red = true;
uniform float strength = 0.62;
uniform vec3 shade = vec3(0.10, 0.13, 0.22);

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float a = use_red ? t.r : t.a;
	COLOR = vec4(shade, a * strength);
}
