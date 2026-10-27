shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// UV is the supplied model's original unwrap. UV2 is generated from island
// coordinates solely for the gameplay road/beach masks; trees and rocks keep
// the textures painted by the model's author.
uniform sampler2D base_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D metal_rough_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D layout_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D litter_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 island_position;
varying vec3 island_normal;

void vertex() {
	island_position = VERTEX;
	island_normal = NORMAL;
}

void fragment() {
	vec4 layout = texture(layout_mask, UV2);
	vec3 painted_color = texture(base_tex, UV).rgb;
	vec3 mr = texture(metal_rough_tex, UV).rgb;
	vec2 ground_uv = island_position.xz * 0.5;
	// Only paint nearly horizontal ground, not the sides of the baked-in trees.
	float flat_ground = smoothstep(0.68, 0.9, abs(normalize(island_normal).y));
	float shore = smoothstep(0.15, 0.95, layout.b) * flat_ground;
	float trail = smoothstep(0.05, 0.7, layout.g) * flat_ground;
	float road = smoothstep(0.05, 0.6, layout.r) * flat_ground;
	// Keep the supplied albedo visible, with subtle fine ground detail to
	// match the rest of the game's more realistic vegetation and lighting.
	vec3 grass_detail = mix(texture(grass_tex, ground_uv).rgb, texture(litter_tex, ground_uv * 0.8).rgb, 0.28);
	vec3 color = mix(painted_color, grass_detail, 0.40 * flat_ground);
	color = mix(color, texture(sand_tex, ground_uv * 0.7).rgb, shore * 0.45);
	color = mix(color, texture(dirt_tex, ground_uv * 0.8).rgb, trail * 0.72);
	color = mix(color, texture(asphalt_tex, ground_uv * 0.67).rgb * vec3(0.82, 0.85, 0.82), road * 0.82);
	float overlay = max(road, max(trail, shore * 0.45));
	ALBEDO = color;
	ROUGHNESS = mix(mr.g, 0.94, overlay);
	METALLIC = mix(mr.b, 0.0, overlay);
	NORMAL_MAP = mix(texture(normal_tex, UV).rgb, vec3(0.5, 0.5, 1.0), overlay);
}
