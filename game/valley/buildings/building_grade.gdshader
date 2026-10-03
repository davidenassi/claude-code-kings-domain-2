shader_type canvas_item;
// Shared colour grade of the pre-rendered buildings: warmer, a little more saturated and contrasted,
// to sit in the illustrated palette of the valley (warm terracotta roofs, warm stone).
// One material for every building -> no effect on batching.

uniform float saturation = 1.22;
uniform float contrast = 1.06;
uniform vec3 warm = vec3(1.05, 1.0, 0.93);

void fragment() {
	vec4 c = COLOR;            // already texel x modulate
	float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	vec3 rgb = mix(vec3(l), c.rgb, saturation);
	rgb = (rgb - 0.45) * contrast + 0.45;
	rgb *= warm;
	COLOR = vec4(clamp(rgb, 0.0, 1.0), c.a);
}
