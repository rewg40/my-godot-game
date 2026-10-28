shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// UV is the supplied model's original unwrap. UV2 is generated from island
// coordinates solely for the gameplay road/beach masks; trees and rocks keep
// the textures painted by the model's author.
//
// Biome sectors: the island is split into four quadrants around its centre,
// each painted with its own ground texture. Quadrant borders are wobbled by
// fbm noise so the transition lines look organic rather than drawn:
//   north-west  — snow (hotel ruins, frozen lake)
//   north-east  — radioactive ground (airfield crash site, glowing cracks)
//   south-west  — grass (starting shore, village, boat)
//   south-east  — desert (lighthouse dunes)
uniform sampler2D base_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D metal_rough_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D layout_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D litter_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D desert_tex : source_color, filter_linear_mipmap, repeat_enable;
// RGB: dark contaminated soil, A: glow mask consumed by EMISSION below.
uniform sampler2D rad_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 island_size = vec2(256.0, 176.0);
uniform float biome_edge = 16.0;  // width of the blend band, metres
uniform float biome_noise = 10.0; // amplitude of the border wobble, metres
uniform vec3 rad_glow_color : source_color = vec3(0.62, 1.0, 0.28);
uniform float rad_glow_energy = 1.35;

varying vec3 island_position;
varying vec3 island_normal;

float hash12(vec2 p) {
        vec3 p3 = fract(vec3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        float a = hash12(i);
        float b = hash12(i + vec2(1.0, 0.0));
        float c = hash12(i + vec2(0.0, 1.0));
        float d = hash12(i + vec2(1.0, 1.0));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
        float v = 0.0;
        float amp = 0.5;
        for (int k = 0; k < 4; k++) {
                v += amp * vnoise(p);
                p = p * 2.03 + vec2(17.1, 9.7);
                amp *= 0.5;
        }
        return v;
}

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

        // --- Biome sector weights (exact partition: they always sum to 1) ---
        vec2 centre = island_size * 0.5;
        vec2 q = island_position.xz - centre;
        // Large fbm swings shape the border, a finer octave breaks up the
        // straight quadrant cross so the sectors look like natural terrain.
        q.x += (fbm(island_position.xz * 0.02) - 0.47) * 2.0 * biome_noise
                        + (vnoise(island_position.xz * 0.07) - 0.5) * 12.0;
        q.y += (fbm(island_position.xz * 0.02 + vec2(31.7, 11.3)) - 0.47) * 2.0 * biome_noise
                        + (vnoise(island_position.xz * 0.07 + vec2(19.3, 5.1)) - 0.5) * 12.0;
        float half_edge = biome_edge * 0.5;
        // smoothstep() is not guaranteed for edge0 > edge1, so keep both edges
        // ascending and invert the result.
        float west = 1.0 - smoothstep(-half_edge, half_edge, q.x);
        float east = 1.0 - west;
        float north = 1.0 - smoothstep(-half_edge, half_edge, q.y);
        float south = 1.0 - north;
        float w_grass = west * south;
        float w_snow = west * north;
        float w_rad = east * north;
        float w_desert = east * south;

        // Retain the supplied colour on steep geometry, but layer photographic
        // ground textures at two scales. The broader mottling prevents large,
        // uniformly bright areas when viewed from the camera.
        vec3 grass_detail = mix(texture(grass_tex, ground_uv).rgb, texture(litter_tex, ground_uv * 0.8).rgb, 0.28);
        vec3 macro_litter = texture(litter_tex, island_position.xz * 0.055).rgb;
        grass_detail = mix(grass_detail, macro_litter, 0.24) * vec3(0.91, 0.95, 0.89);

        // Snow: two drifting scales, colder in the dips.
        vec3 snow_detail = texture(snow_tex, ground_uv * 0.55).rgb;
        snow_detail = mix(snow_detail, texture(snow_tex, ground_uv * 0.21).rgb, 0.35) * vec3(0.97, 0.99, 1.03);
        // Desert: warm ripples plus a coarse dune scale.
        vec3 desert_detail = mix(texture(desert_tex, ground_uv * 0.7).rgb, texture(desert_tex, ground_uv * 0.23).rgb, 0.30);
        // Radioactive: contaminated soil, glow cracks arrive via the alpha mask.
        vec4 rad_sample = texture(rad_tex, ground_uv * 0.75);
        vec3 rad_detail = mix(rad_sample.rgb, texture(rad_tex, ground_uv * 0.3).rgb, 0.30);

        vec3 biome_color = grass_detail;
        biome_color = mix(biome_color, snow_detail, w_snow);
        biome_color = mix(biome_color, desert_detail, w_desert);
        biome_color = mix(biome_color, rad_detail, w_rad);

        vec3 color = mix(painted_color, biome_color, 0.78 * flat_ground);
        color = mix(color, texture(sand_tex, ground_uv * 0.7).rgb, shore * 0.45);
        color = mix(color, texture(dirt_tex, ground_uv * 0.8).rgb, trail * 0.72);
        color = mix(color, texture(asphalt_tex, ground_uv * 0.67).rgb * vec3(0.82, 0.85, 0.82), road * 0.82);
        float overlay = max(road, max(trail, shore * 0.45));
        float ground_material = max(overlay, flat_ground * 0.72);
        ALBEDO = color;
        float biome_rough = w_grass * 0.94 + w_snow * 0.60 + w_desert * 0.97 + w_rad * 0.90;
        ROUGHNESS = mix(mr.g, biome_rough, ground_material);
        METALLIC = mix(mr.b, 0.0, ground_material);
        NORMAL_MAP = mix(texture(normal_tex, UV).rgb, vec3(0.5, 0.5, 1.0), overlay);
        // Contaminated ground glows on its own; roads and trails stay dark.
        EMISSION = rad_glow_color * rad_sample.a * (w_rad * flat_ground * rad_glow_energy);
}
