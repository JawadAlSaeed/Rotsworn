// Fighter and prop sprite (DESIGN.md 7.3): fixed-Y billboard, nearest filtering and alpha-cut
// discard (like a Sprite3D with billboard FIXED_Y, texture_filter NEAREST and alpha_cut DISCARD),
// lit by the scene's sun, ambient light and lamps like the HD-2D games, plus the looks the combat
// presentation needs: white flash, wind-up glow, greyed-out (downed) and self glow (props). The
// node's scale is kept (the enemy's wind-up crouch squashes the body around its feet).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.45, 0.2, 1.0);
uniform float glow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.35;
uniform float grey_amount : hint_range(0.0, 1.0) = 0.0;
// Emission from the sprite's own colours (glowing fungus, lanterns), so bloom catches them.
uniform float self_glow = 0.0;
uniform vec4 self_glow_color : source_color = vec4(1.0);
// How much the lighting normal leans up from facing the camera: up-facing catches the sun from
// above, so a sprite is lit like the ground it stands on rather than only from the front.
uniform float normal_up : hint_range(0.0, 4.0) = 0.8;

varying vec3 world_normal;

void vertex() {
	vec3 facing = normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0)));
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)) * scale.x, 0.0),
			vec4(0.0, scale.y, 0.0, 0.0),
			vec4(facing * scale.z, 0.0),
			MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	world_normal = normalize(facing + vec3(0.0, normal_up, 0.0));
}

void fragment() {
	vec4 texel = texture(sprite_texture, UV);
	if (texel.a < alpha_cut) {
		discard;
	}
	vec3 color = texel.rgb * tint.rgb;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(luma * 0.6), grey_amount);
	ALBEDO = mix(color, flash_color.rgb, flash_amount);
	EMISSION = glow_color.rgb * glow_amount * glow_strength
			+ flash_color.rgb * flash_amount
			+ texel.rgb * self_glow_color.rgb * self_glow;
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	ROUGHNESS = 1.0;
}
