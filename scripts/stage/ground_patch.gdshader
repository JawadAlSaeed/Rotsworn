// A piece of ground laid on the floor (DESIGN.md 8.12): a road, a trail, mud, moss, planks or
// water. The texture tiles in world space like the floor's, so pieces line up with it; the edge is
// eaten away by value noise measured per art pixel, so it stays ragged and pixel-sharp. Water
// scrolls its texture in two layers, darkens toward the middle, keeps a dark muddy rim at the
// shore and throws a few sparkles.
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

varying vec3 world_pos;
varying vec2 local_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

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
		vec2 a_uv = floor((uv * 0.8 + vec2(TIME * flow, TIME * flow * 0.55)) * tile_px) / tile_px;
		vec2 b_uv = floor((uv * 1.25 + vec2(-TIME * flow * 0.7, TIME * flow * 0.4)) * tile_px) / tile_px;
		vec3 a = texture(ground_texture, a_uv).rgb;
		vec3 b = texture(ground_texture, b_uv).rgb;
		float depth = clamp(edge / 1.6, 0.0, 1.0);
		color = mix((a + b) * 0.5 * tint.rgb, deep_color.rgb, depth * 0.55);
		// A muddy rim at the shore, one or two art pixels wide.
		if (edge < px_world * 2.0) {
			color = shore_color.rgb;
		}
		float twinkle = step(1.0 - sparkle, hash(floor(a_uv * tile_px) + floor(TIME * 1.7)));
		EMISSION = color * 0.12 + vec3(twinkle) * 0.35 * (1.0 - depth * 0.5);
	} else {
		vec4 texel = texture(ground_texture, uv);
		// Sparse pieces (lily pads, scattered leaves) leave their clear pixels out.
		if (texel.a < 0.5) {
			discard;
		}
		color = texel.rgb * tint.rgb;
		// The edge pixels a step darker, so a piece sits in the floor rather than on it.
		if (edge < px_world) {
			color *= 0.78;
		}
	}
	ALBEDO = color;
	ROUGHNESS = 1.0;
}
