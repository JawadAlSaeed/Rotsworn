shader_type canvas_item;
// The worn edges of the title screen's letters, alive (DESIGN.md 7.7): the letters layer holds
// clean gold (cracks only); this eats pits and chips out of the edges and scatters flakes just
// outside them, like the logo's printed wear, but the pattern jumps a few times a second like
// static. Part of the wear stays still (1 - motion) so the letters keep their shape.
// edge_map: 0.5 on a letter's edge, rising to 1 edge_range px inside, falling to 0 outside.
// Numbers come from data/branding/branding.tres (TitleScreen sets them).

uniform sampler2D edge_map : filter_linear;
uniform vec2 tex_size = vec2(2251.0, 1483.0);
uniform float edge_range = 24.0;
uniform float fps = 9.0;
uniform float motion = 0.6;
uniform float wear = 1.0;
uniform float specks = 1.0;
uniform vec4 speck_color : source_color = vec4(0.84, 0.70, 0.48, 0.85);

// Feature sizes in texture pixels; the same shapes as tools/branding/minimal_branding.py.
const float PIT_CELL = 3.3;
const float CHIP_CELL = 10.5;
const float NEAR_PX = 7.5;
const float SPECK_RANGE = 12.0;
const float SPECK_CELL = 1.8;

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

float fbm(vec2 p, int octaves) {
	float total = 0.0;
	float amp = 1.0;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		total += noise(p) * amp;
		norm += amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return total / norm;
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float sd = (texture(edge_map, UV).r - 0.5) * 2.0 * edge_range;   // + inside, - outside
	vec2 p = UV * tex_size;
	float frame = floor(TIME * fps);
	vec2 jump = vec2(hash(vec2(frame, 3.1)), hash(vec2(7.7, frame))) * 517.0;
	float pit_n = mix(fbm(p / PIT_CELL, 2), fbm(p / PIT_CELL + jump, 2), motion);
	float chip_n = mix(fbm(p / CHIP_CELL + 91.0, 3), fbm(p / CHIP_CELL + 91.0 + jump * 0.37, 3), motion);
	float near = exp(-max(sd, 0.0) / NEAR_PX);
	float pit = pit_n * (0.55 + 0.75 * near) - (0.74 - 0.08 * wear);
	float chip = chip_n * near - (0.42 - 0.06 * wear);
	// Blend each cut over about a screen pixel, so the logo drawn small (the main menu) shimmers
	// softly instead of sparkling.
	float pw = max(fwidth(pit), 0.015);
	float cw = max(fwidth(chip), 0.015);
	float keep = (1.0 - smoothstep(-pw, pw, pit)) * (1.0 - smoothstep(-cw, cw, chip));
	float a = col.a * keep;
	// flakes just off the edges
	float flake = 0.0;
	if (sd < 0.0 && sd > -SPECK_RANGE) {
		float s = mix(noise(p / SPECK_CELL + 33.0), noise(p / SPECK_CELL + 33.0 + jump), motion);
		flake = smoothstep(0.8, 0.84, s) * (1.0 + sd / SPECK_RANGE) * specks;
	}
	COLOR = a > 0.001 ? vec4(col.rgb, a) : vec4(speck_color.rgb, speck_color.a * flake);
}
