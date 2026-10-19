shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D coverage : filter_linear, repeat_disable;
uniform vec3 sand_color : source_color = vec3(0.957, 0.945, 0.910);
uniform vec3 wood_color : source_color = vec3(0.42, 0.33, 0.27);
uniform float map_extent = 16.54;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = vec2(world_position.x / map_extent + 0.5, world_position.z / map_extent + 0.5);
	float cover = texture(coverage, clamp(uv, vec2(0.0), vec2(1.0))).r;
	float grain = sin(world_position.x * 0.35) * sin(world_position.z * 0.27);
	grain = grain * 0.5 + 0.5;
	vec3 sand = sand_color * (0.94 + 0.08 * grain);
	vec3 wood = wood_color * (0.96 + 0.06 * grain);
	ALBEDO = mix(wood, sand, cover);
	ROUGHNESS = mix(0.82, 1.0, cover);
	METALLIC = 0.0;
}
