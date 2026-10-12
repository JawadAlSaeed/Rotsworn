// Fight transition (DESIGN.md 7.4): a frozen picture of the screen twists into its middle, zooms in
// and darkens, with a short white flash at the start.
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
// Twist at the middle by the end, in radians.
uniform float turns = 7.0;
uniform float flash : hint_range(0.0, 1.0) = 0.6;
// Width / height of the screen, so the twist stays round.
uniform float aspect = 1.7778;

void fragment() {
	vec2 c = UV - vec2(0.5);
	c.x *= aspect;
	float r = length(c);
	float twist = turns * progress * progress * (1.0 - smoothstep(0.0, 0.9, r));
	float s = sin(twist);
	float co = cos(twist);
	c = mat2(vec2(co, -s), vec2(s, co)) * c;
	c *= 1.0 - 0.45 * progress;
	c.x /= aspect;
	vec4 col = texture(TEXTURE, clamp(c + vec2(0.5), vec2(0.0), vec2(1.0)));
	col.rgb = mix(col.rgb, vec3(1.0), flash * clamp(1.0 - progress * 5.0, 0.0, 1.0));
	col.rgb *= 1.0 - smoothstep(0.45, 1.0, progress);
	COLOR = vec4(col.rgb, 1.0);
}
