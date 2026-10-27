shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// The character's rest-pose vertex colours carry clothing masks, not light:
// red = shirt, green = trousers, blue = shoes, alpha = visible skin.
// As they are attached to the vertices they follow the skeletal animation.
uniform sampler2D skin_texture : source_color, filter_linear_mipmap;
uniform vec4 skin_tint : source_color = vec4(1.0);
uniform vec4 shirt_tint : source_color = vec4(0.28, 0.34, 0.30, 1.0);
uniform vec4 pants_tint : source_color = vec4(0.20, 0.21, 0.19, 1.0);
uniform vec4 shoes_tint : source_color = vec4(0.14, 0.13, 0.11, 1.0);

void fragment() {
	vec3 skin = texture(skin_texture, UV).rgb;
	float fabric_detail = 0.85 + 0.30 * texture(skin_texture, UV * 2.73).r;
	vec3 shirt = shirt_tint.rgb * fabric_detail;
	vec3 pants = pants_tint.rgb * fabric_detail;
	vec3 shoes = shoes_tint.rgb * (0.91 + 0.12 * fabric_detail);
	ALBEDO = shirt * COLOR.r + pants * COLOR.g + shoes * COLOR.b + skin * skin_tint.rgb * COLOR.a;
	ROUGHNESS = 0.96;
}
