// Vector borders drawn at a constant on-screen width. Vertices sit on the border polyline;
// UV = offset direction scaled by the desired distance in PIXELS, so VERTEX += UV * mpp.
// COLOR carries colour and the alpha ramp (opaque at the line, transparent at the outer edge of colour bands).
shader_type canvas_item;

uniform float mpp = 30.0;
uniform float fade = 1.0;

void vertex() {
	VERTEX += UV * mpp;
}

void fragment() {
	COLOR = vec4(COLOR.rgb, COLOR.a * fade);
}

