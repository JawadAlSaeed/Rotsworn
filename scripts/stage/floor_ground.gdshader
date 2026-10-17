// The open floor of a place (card #186). One 32x32 tile laid over 90x90 units repeats about 56
// times a side and reads as wallpaper, so the floor breaks the repeat up at three sizes while
// staying pixel-crisp (nearest sampling, every decision made per art pixel):
//   1. Regions (a few world units wide, ragged edges): each picks one of up to three drawn
//      variants of the tile (they share a palette and tone) and mirrors it. A region keeps the
//      tile's own seamless pattern, so only the region's edge shows a change, and that edge
//      follows a noise contour, never a straight tile line.
//   2. Tone drift (about ten units wide): the floor steps a little lighter or darker in a few
//      steps, so wide areas are not one even brightness.
// Lit like a plain material (sun, lamps, shadows from blocks). All numbers come from the place's
// StageLook (data/looks/*.tres).
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D tile_a : source_color, filter_nearest, repeat_enable;
uniform sampler2D tile_b : source_color, filter_nearest, repeat_enable;
uniform sampler2D tile_c : source_color, filter_nearest, repeat_enable;
// How many of the three tiles are real (1 to 3).
uniform int variants = 1;
uniform float tile_world = 1.6;
// Art pixels along one side of a tile.
uniform float tile_px = 32.0;
// Region size in world units; 0 turns the regions off (always tile a, never mirrored).
uniform float region_world = 7.0;
// How far the noise bends a region's edge, as a share of the region size.
uniform float region_warp = 0.5;
uniform bool mirror = true;
// Tone drift: noise size in world units, +- brightness share (0 = off), and how many steps.
uniform float tone_world = 9.0;
uniform float tone_strength = 0.07;
uniform float tone_steps = 4.0;

varying vec3 world_pos;

// A hash without sin(): sin() of large numbers loses precision on some GPUs and shows blocks.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float px_world = tile_world / tile_px;
	// The centre of the art pixel (on the world grid) this fragment is in.
	vec2 snapped = (floor(world_pos.xz / px_world) + 0.5) * px_world;
	vec2 uv = world_pos.xz / tile_world;
	int pick = 0;
	if (region_world > 0.0) {
		vec2 r = snapped / region_world;
		vec2 bend = vec2(value_noise(r * 2.1 + vec2(3.7, 9.1)), value_noise(r * 2.1 + vec2(17.3, 5.3))) - 0.5;
		vec2 cell = floor(r + bend * region_warp * 2.0);
		pick = min(int(floor(hash(cell) * float(variants))), variants - 1);
		if (mirror) {
			if (hash(cell + vec2(41.0, 7.0)) > 0.5) {
				uv.x = -uv.x;
			}
			if (hash(cell + vec2(13.0, 59.0)) > 0.5) {
				uv.y = -uv.y;
			}
		}
	}
	vec3 a = texture(tile_a, uv).rgb;
	vec3 b = texture(tile_b, uv).rgb;
	vec3 c = texture(tile_c, uv).rgb;
	vec3 color = pick == 0 ? a : (pick == 1 ? b : c);
	if (tone_strength > 0.0 && tone_world > 0.0) {
		float n = value_noise(snapped / tone_world + vec2(31.0, 4.0));
		float stepped = (floor(n * tone_steps) + 0.5) / tone_steps - 0.5;
		color *= 1.0 + stepped * 2.0 * tone_strength;
	}
	ALBEDO = color;
	ROUGHNESS = 1.0;
}
