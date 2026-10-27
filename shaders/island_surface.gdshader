shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// The layout is an original, hand-authored mask; the repeatable surfaces are
// CC0 photo textures. UV is the existing island/map coordinate system.
uniform sampler2D layout_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D litter_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap, repeat_enable;

void fragment() {
	vec4 layout = texture(layout_mask, UV);
	vec2 world_uv = UV * vec2(64.0, 44.0); // roughly 2 m per grass tile
	vec3 grass_a = texture(grass_tex, world_uv).rgb;
	vec3 grass_b = texture(grass_tex, world_uv.yx * 0.57 + vec2(0.31, 0.17)).rgb;
	// Large-scale variations break up the repeating detail into uneven patches
	// of green growth and dry leaf litter, rather than a single flat lawn.
	float macro = 0.5 + 0.5 * sin(UV.x * 47.0 + sin(UV.y * 21.0)) * sin(UV.y * 37.0);
	float patches = smoothstep(0.18, 0.48, texture(litter_tex, UV * vec2(5.3, 3.7)).r);
	vec3 grass = mix(grass_a, grass_b, 0.25 + macro * 0.20);
	vec3 litter = texture(litter_tex, world_uv * 0.83 + vec2(0.37, 0.2)).rgb;
	grass = mix(grass, litter, 0.32 + patches * 0.35);
	vec3 forest = texture(forest_tex, world_uv * 0.8).rgb;
	float forest_mask = clamp(layout.b * 2.7, 0.0, 1.0) * (1.0 - smoothstep(0.45, 0.7, layout.b));
	grass = mix(grass, forest, forest_mask * 0.62);
	grass *= mix(vec3(0.47, 0.56, 0.42), vec3(0.60, 0.65, 0.48), macro);

	vec3 dirt = texture(dirt_tex, world_uv * 0.8).rgb;
	vec3 sand = texture(sand_tex, world_uv * 0.7).rgb;
	float sand_mask = smoothstep(0.42, 0.75, layout.b);
	float dirt_mask = smoothstep(0.05, 0.85, layout.g);
	vec3 terrain = mix(grass, sand * 0.82, sand_mask);
	terrain = mix(terrain, dirt * 0.82, dirt_mask);

	vec3 asphalt = texture(asphalt_tex, world_uv * 0.67).rgb;
	float road = smoothstep(0.05, 0.5, layout.r);
	terrain = mix(terrain, asphalt * vec3(0.68, 0.74, 0.77), road);
	float marking = smoothstep(0.72, 0.92, layout.r);
	terrain = mix(terrain, vec3(0.50, 0.49, 0.42), marking * 0.65);

	// The sea extends beyond the terrain mesh; colour the perimeter consistently
	// without changing the collision or the legacy map coordinates.
	vec3 shore_water = vec3(0.075, 0.16, 0.18);
	ALBEDO = mix(shore_water, terrain, layout.a);
	ROUGHNESS = mix(0.42, 0.96, layout.a);
	METALLIC = 0.0;
}
