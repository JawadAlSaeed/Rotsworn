// Screen vignette (DESIGN.md 7.3): the edges of the picture darken toward `tint`, the HD-2D frame.
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.45;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.02, 1.0);
// Where the darkening starts and where it is full, as a distance from the middle in UV units
// (the corners are about 0.71 away).
uniform float inner = 0.35;
uniform float outer = 0.85;

void fragment() {
	float r = length(UV - vec2(0.5));
	COLOR = vec4(tint.rgb, smoothstep(inner, outer, r) * strength);
}
