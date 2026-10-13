shader_type canvas_item;
// Slow drifting fog for the title screen (DESIGN.md 7.7): two layers of soft noise moving at
// different speeds, thicker near the bottom of the screen. Fills the rect it is drawn on.

uniform vec4 fog_color : source_color = vec4(0.42, 0.5, 0.3, 0.32);
uniform float speed = 0.018;
uniform float aspect = 1.777;

// A hash without sin(): sin() of large numbers loses precision on some GPUs and shows blocks.
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
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		total += noise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 uv = vec2(UV.x * aspect, UV.y);
	float t = TIME * speed;
	float far = fbm(uv * 2.2 + vec2(t * 1.0, t * 0.3));
	float near = fbm(uv * 3.6 + vec2(-t * 1.7, t * 0.5) + far);
	float fog = smoothstep(0.35, 0.95, (far + near) * 0.62);
	// Thicker low down, thin at the top.
	fog *= mix(0.25, 1.0, smoothstep(0.0, 1.0, UV.y));
	COLOR = vec4(fog_color.rgb, fog_color.a * fog);
}
