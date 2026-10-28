shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec4 deep_color : source_color = vec4(0.08, 0.20, 0.22, 1.0);
uniform vec4 light_color : source_color = vec4(0.21, 0.36, 0.34, 1.0);
uniform float wave_scale = 1.0;

void fragment() {
	vec2 p = UV * wave_scale;
	float wave_a = sin(p.x * 21.0 + p.y * 8.0 + TIME * 0.64);
	float wave_b = sin(p.y * 27.0 - p.x * 7.0 - TIME * 0.46);
	float ripple = wave_a * 0.55 + wave_b * 0.45;
	ALBEDO = mix(deep_color.rgb, light_color.rgb, clamp(0.48 + ripple * 0.18, 0.0, 1.0));
	ROUGHNESS = 0.26;
	METALLIC = 0.04;
	NORMAL_MAP = vec3(0.5 + wave_a * 0.045, 0.5 + wave_b * 0.045, 1.0);
}
