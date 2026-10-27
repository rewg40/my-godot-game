shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// The supplied island has neither UVs nor textures. The game generates planar
// map UVs from its real vertices and projects the photographic materials in 3D,
// so cliffs and building walls are textured as well as the horizontal ground.
uniform sampler2D layout_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D litter_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wood_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D metal_tex : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 island_position;
varying vec3 island_normal;

void vertex() {
	// The supplied model's transform is baked into its mesh in metres.
	island_position = VERTEX;
	island_normal = NORMAL;
}

float ground_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float ground_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(ground_hash(cell), ground_hash(cell + vec2(1.0, 0.0)), f.x);
	float b = mix(ground_hash(cell + vec2(0.0, 1.0)), ground_hash(cell + vec2(1.0, 1.0)), f.x);
	return mix(a, b, f.y);
}

vec3 project_texture(sampler2D surface, vec3 pos, vec3 weights, float frequency) {
	vec3 along_x = texture(surface, pos.zy * frequency).rgb;
	vec3 along_y = texture(surface, pos.xz * frequency).rgb;
	vec3 along_z = texture(surface, pos.xy * frequency).rgb;
	return along_x * weights.x + along_y * weights.y + along_z * weights.z;
}

void fragment() {
	vec4 layout = texture(layout_mask, UV);
	vec3 n = normalize(island_normal);
	vec3 weights = pow(abs(n), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	vec2 ground_uv = island_position.xz * 0.5;
	float macro = ground_noise(island_position.xz * 0.11);
	float patches = smoothstep(0.28, 0.72, ground_noise(ground_uv * 0.72));
	vec3 grass_a = texture(grass_tex, ground_uv).rgb;
	vec3 grass_b = texture(grass_tex, ground_uv.yx * 0.57 + vec2(0.31, 0.17)).rgb;
	vec3 grass = mix(grass_a, grass_b, 0.25 + macro * 0.2);
	vec3 litter = texture(litter_tex, ground_uv * 0.83 + vec2(0.37, 0.2)).rgb;
	vec3 forest = texture(forest_tex, ground_uv * 0.8).rgb;
	vec3 dirt = texture(dirt_tex, ground_uv * 0.8).rgb;
	grass = mix(grass, mix(litter, dirt, 0.40), 0.18 + patches * 0.45);
	grass = mix(grass, forest, smoothstep(0.5, 0.8, macro) * 0.22);
	grass *= mix(vec3(0.52, 0.60, 0.46), vec3(0.65, 0.69, 0.53), macro);

	float built_area = smoothstep(0.52, 0.80, layout.b);
	float shore = smoothstep(0.04, 0.38, layout.b) * (1.0 - built_area);
	vec3 sand = texture(sand_tex, ground_uv * 0.7).rgb * 0.82;
	vec3 terrain = mix(grass, sand, shore);
	terrain = mix(terrain, dirt * 0.85, smoothstep(0.05, 0.65, layout.g));
	vec3 asphalt = texture(asphalt_tex, ground_uv * 0.67).rgb;
	terrain = mix(terrain, asphalt * vec3(0.72, 0.77, 0.78), smoothstep(0.05, 0.52, layout.r));

	// Height and slope distinguish the island's baked-in cliffs from its base.
	// Triplanar projection avoids stretched texture stripes on vertical faces.
	vec3 rock = project_texture(rock_tex, island_position, weights, 0.38) * vec3(0.85, 0.86, 0.79);
	float steepness = 1.0 - smoothstep(0.42, 0.83, abs(n.y));
	float raised = smoothstep(0.7, 2.6, island_position.y);
	float cliff = clamp(max(raised, steepness * 0.88), 0.0, 1.0);
	terrain = mix(terrain, rock, cliff);

	// The original is one material, so a separate footprint mask identifies
	// its buildings while leaving the original geometry completely intact.
	float building = built_area * smoothstep(0.35, 1.8, island_position.y);
	vec3 wood = project_texture(wood_tex, island_position, weights, 0.48) * vec3(0.76, 0.74, 0.67);
	vec3 metal = project_texture(metal_tex, island_position, weights, 0.45) * vec3(0.74, 0.73, 0.67);
	vec3 structure = mix(wood, metal, smoothstep(0.50, 0.85, abs(n.y)));
	terrain = mix(terrain, structure, building);

	ALBEDO = terrain;
	ROUGHNESS = 0.96;
	METALLIC = 0.0;
}
