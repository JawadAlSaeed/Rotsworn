shader_type canvas_item;
// The chosen menu choice in worn gold (DESIGN.md 7.7): like the logo's letters, brushed gold with
// edges that crumble and flicker like static, but gentler so a word stays readable. Put on a
// Label without an outline. Numbers come from data/presentation/ui_fonts.tres (ListMenu sets them).

uniform float fps = 9.0;
uniform float motion = 0.6;
uniform float wear = 1.0;
// How much of the static shows: 1 = all of it, 0 = none (clean letters, the brushed gold stays).
uniform float strength = 1.0;

// Feature sizes in screen pixels.
const float PIT_CELL = 1.4;
const float CHIP_CELL = 4.0;

varying vec4 font_color;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return (noise(p) + noise(p * 2.03) * 0.5) / 1.5;
}

void vertex() {
	font_color = COLOR;
}

void fragment() {
	float cover = texture(TEXTURE, UV).a;
	// Near an edge when a neighbour (1.5 atlas pixels away) is less covered.
	vec2 o = TEXTURE_PIXEL_SIZE * 1.5;
	float around = min(min(texture(TEXTURE, UV + vec2(o.x, 0.0)).a, texture(TEXTURE, UV - vec2(o.x, 0.0)).a),
			min(texture(TEXTURE, UV + vec2(0.0, o.y)).a, texture(TEXTURE, UV - vec2(0.0, o.y)).a));
	float near = 1.0 - around;
	vec2 p = FRAGCOORD.xy;
	float frame = floor(TIME * fps);
	vec2 jump = vec2(hash(vec2(frame, 3.1)), hash(vec2(7.7, frame))) * 517.0;
	float pit_n = mix(fbm(p / PIT_CELL), fbm(p / PIT_CELL + jump), motion);
	float chip_n = mix(fbm(p / CHIP_CELL + 91.0), fbm(p / CHIP_CELL + 91.0 + jump * 0.37), motion);
	float pit = pit_n * (0.4 + 0.8 * near) - (0.8 - 0.08 * wear);
	float chip = chip_n * near - (0.52 - 0.06 * wear);
	float keep = (1.0 - smoothstep(-0.02, 0.02, pit)) * (1.0 - smoothstep(-0.02, 0.02, chip));
	keep = mix(1.0, keep, strength);
	// brushed streaks across the gold
	float streak = noise(vec2(p.x / 40.0, p.y / 1.3));
	vec3 rgb = font_color.rgb * (0.8 + 0.4 * streak);
	COLOR = vec4(rgb, font_color.a * cover * keep);
}
