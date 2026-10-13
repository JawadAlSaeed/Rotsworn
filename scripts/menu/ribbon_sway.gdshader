shader_type canvas_item;
// The ribbon's tails swaying on the title screen (DESIGN.md 7.7): the tails layer of the logo is
// bent by a slow wave that runs from the knot (root) to the ends. Nothing moves at the knot; the
// ends move the most. Numbers come from data/branding/branding.tres (TitleScreen sets them).

uniform vec2 root = vec2(0.52, 0.51);      // the knot, in the texture's UV
uniform float aspect = 1.565;              // texture width / height
uniform float reach = 0.2;                 // distance (in heights) over which the sway grows to full
uniform vec2 amp = vec2(0.0013, 0.0058);   // largest offset, in UV (sideways, up and down)
uniform float speed = 1.65;                // radians per second
uniform float ripple = 5.0;                // radians of wave from the knot to the ends

void fragment() {
	vec2 rel = (UV - root) * vec2(aspect, 1.0);
	float d = clamp(length(rel) / reach, 0.0, 1.0);
	float weight = d * d;
	float phase = TIME * speed - d * ripple;
	vec2 offset = vec2(sin(phase * 0.7 + 1.3) * amp.x, sin(phase) * amp.y) * weight;
	COLOR = texture(TEXTURE, UV - offset);
}
