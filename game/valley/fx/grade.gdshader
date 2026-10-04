shader_type canvas_item;
// In-game colour grade (part of the renderer, applied every frame, not a retouch of the screenshots):
// warm late-morning light, slightly richer colour and contrast, a light vignette - the look of the
// illustrated references. Tuned against the measured palettes of references B/C/D.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float saturation = 1.08;
uniform float contrast = 1.07;
uniform vec3 warm = vec3(1.045, 1.0, 0.93);
uniform float vignette = 0.28;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	c *= warm;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.45) * contrast + 0.45;
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - vignette * dot(d, d) * 1.6;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
