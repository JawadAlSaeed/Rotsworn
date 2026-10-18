// A piece of ground laid on the floor (DESIGN.md 8.12): a road, a trail, mud, moss, planks or
// water. The texture tiles in world space like the floor's, so pieces line up with it; the edge is
// eaten away by value noise measured per art pixel, so it stays ragged and pixel-sharp, and a
// land piece's rim dithers away into the floor instead of ending in a cut line. Water
// scrolls its texture in two layers (downstream, for a stream), darkens toward the middle, keeps a
// dark muddy rim at the shore that stipples into the water, spreads a ripple ring now and then and
// throws a few sparkles.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D ground_texture : source_color, filter_nearest, repeat_enable;
uniform float tile_world = 1.6;
// Art pixels per texture tile (the edge and the water are snapped to this grid).
uniform float tile_px = 32.0;
uniform vec4 tint : source_color = vec4(1.0);
// Half the piece's size (x, z) in its own frame, and its shape.
uniform vec2 half_size = vec2(2.0);
uniform bool round_shape = false;
// How deep (world units) the noise bites into the edge.
uniform float edge_noise = 0.4;
uniform bool water = false;
uniform vec4 deep_color : source_color = vec4(0.04, 0.1, 0.09, 1.0);
uniform vec4 shore_color : source_color = vec4(0.1, 0.09, 0.06, 1.0);
// Water: how fast the two layers drift (tiles a second), and the sparkles' share.
uniform float flow = 0.06;
uniform float sparkle = 0.04;
// Water: a stream's flow (world x, z, in tiles a second; zero: the still drift above), and the
// share of spots where a ripple ring spreads now and then (card #232).
uniform vec2 flow_dir = vec2(0.0);
uniform float ripple = 0.0;
// The rim fades into the floor this many art pixels deep (dithered); the outer two pixels are
// shaded by edge_shade.
uniform float fringe_px = 4.0;
uniform float edge_shade = 0.9;

varying vec3 world_pos;
varying vec2 local_pos;

// A hash without sin(): sin() of large numbers loses precision on some GPUs and shows blocks.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 4x4 ordered dither thresholds in (0, 1): a tidy pixel-art stipple, not noise.
const float BAYER[16] = float[16](0.03, 0.53, 0.16, 0.66, 0.78, 0.28, 0.91, 0.41,
		0.22, 0.72, 0.09, 0.59, 0.97, 0.47, 0.84, 0.34);

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_pos = VERTEX.xz;
}

void fragment() {
	float px_world = tile_world / tile_px;
	// The art pixel this fragment is in (world grid) and the same in the piece's own frame.
	vec2 cell = floor(world_pos.xz / px_world);
	vec2 local_cell = (floor(local_pos / px_world) + 0.5) * px_world;
	float inside;
	if (round_shape) {
		vec2 q = local_cell / max(half_size, vec2(0.001));
		inside = (1.0 - length(q)) * min(half_size.x, half_size.y);
	} else {
		inside = min(half_size.x - abs(local_cell.x), half_size.y - abs(local_cell.y));
	}
	float bite = value_noise(cell * 0.11) * 0.65 + value_noise(cell * 0.37) * 0.35;
	float edge = inside - bite * edge_noise;
	if (edge < 0.0) {
		discard;
	}
	vec2 uv = world_pos.xz / tile_world;
	vec3 color;
	if (water) {
		bool stream = dot(flow_dir, flow_dir) > 0.0;
		// A stream: both layers run downstream, the second a little slower and across.
		vec2 drift_a = stream ? -flow_dir : vec2(flow, flow * 0.55);
		vec2 drift_b = stream ? -flow_dir * 0.6 + vec2(-flow_dir.y, flow_dir.x) * 0.12 : vec2(-flow * 0.7, flow * 0.4);
		vec2 a_uv = floor((uv * 0.8 + TIME * drift_a) * tile_px) / tile_px;
		vec2 b_uv = floor((uv * 1.25 + TIME * drift_b) * tile_px) / tile_px;
		vec3 a = texture(ground_texture, a_uv).rgb;
		vec3 b = texture(ground_texture, b_uv).rgb;
		float depth = clamp(edge / 1.6, 0.0, 1.0);
		color = mix((a + b) * 0.5 * tint.rgb, deep_color.rgb, depth * 0.55);
		// A muddy rim at the shore, two art pixels wide, then two more where wet mud and water
		// mix in a stipple: the shore is soft, not a cut line.
		int bi = int(mod(cell.y, 4.0)) * 4 + int(mod(cell.x, 4.0));
		if (edge < px_world * 2.0 || (edge < px_world * 4.0 && BAYER[bi] > (edge / px_world - 2.0) * 0.5)) {
			color = mix(shore_color.rgb, color, edge < px_world * 2.0 ? 0.0 : 0.35);
		}
		// Ripples: in each 3 m cell a ring now and then spreads from a spot and fades.
		float ring = 0.0;
		if (ripple > 0.0) {
			vec2 rc = floor(world_pos.xz / 3.0);
			float phase = TIME / 4.0 + hash(rc);
			float k = floor(phase);
			float grow = fract(phase);
			vec2 centre = (rc + vec2(hash(rc + k), hash(rc + k + 17.0))) * 3.0;
			float d = length((cell + 0.5) * px_world - centre);
			ring = step(abs(d - grow * 0.9), px_world * 0.6) * (1.0 - grow) * step(hash(rc + k * 3.1), ripple)
					* step(px_world * 4.0, edge);
			color = mix(color, color * 1.6 + vec3(0.05), ring);
		}
		float twinkle = step(1.0 - sparkle, hash(floor(a_uv * tile_px) + floor(TIME * 1.7)));
		EMISSION = color * 0.12 + vec3(twinkle) * 0.35 * (1.0 - depth * 0.5) + vec3(ring) * 0.08;
	} else {
		vec4 texel = texture(ground_texture, uv);
		// Sparse pieces (lily pads, scattered leaves) leave their clear pixels out.
		if (texel.a < 0.5) {
			discard;
		}
		color = texel.rgb * tint.rgb;
		// The rim thins out into the floor (ordered dither, so the pixels stay tidy), and what is
		// left of it is a touch darker: a piece sits in the floor rather than on it.
		float fringe = fringe_px * px_world;
		if (edge < fringe) {
			int bi = int(mod(cell.y, 4.0)) * 4 + int(mod(cell.x, 4.0));
			if (BAYER[bi] > edge / fringe) {
				discard;
			}
		}
		if (edge < px_world * 2.0) {
			color *= edge_shade;
		}
	}
	ALBEDO = color;
	ROUGHNESS = 1.0;
}
