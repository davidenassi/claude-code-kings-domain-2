shader_type canvas_item;
// Banner on a pole: the cloth (right of the pole) ripples, the pole stays still.
// pole_u = pole position in UV.x of the sprite; the further from the pole, the larger the wave.

uniform float pole_u = 0.2;
uniform float amount = 0.018;

void fragment() {
	float k = smoothstep(pole_u + 0.02, pole_u + 0.25, UV.x);
	float w = sin(TIME * 2.6 - UV.x * 14.0 + UV.y * 6.0) * 0.6 + sin(TIME * 4.1 - UV.x * 23.0) * 0.4;
	vec2 uv = UV + vec2(0.0, w * amount * k);
	vec4 c = texture(TEXTURE, uv);
	c.rgb *= 1.0 + w * 0.08 * k;
	COLOR = c * COLOR;
}
