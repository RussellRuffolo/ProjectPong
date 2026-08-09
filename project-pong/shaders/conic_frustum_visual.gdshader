shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, unshaded;

uniform vec4 volume_color : source_color = vec4(0.18, 0.78, 1.0, 0.2);
uniform vec4 line_color : source_color = vec4(1.0, 0.94, 0.38, 0.85);
uniform float vertical_line_count = 16.0;
uniform float horizontal_line_count = 5.0;
uniform float line_width = 0.025;

varying vec2 frustum_uv;


void vertex() {
	frustum_uv = UV;
}


float grid_line(float coordinate, float count, float width) {
	float wrapped = fract(coordinate * max(count, 1.0));
	float distance_to_line = min(wrapped, 1.0 - wrapped);
	return 1.0 - smoothstep(width, width * 1.8, distance_to_line);
}


void fragment() {
	float vertical_line = grid_line(frustum_uv.x, vertical_line_count, line_width);
	float horizontal_line = grid_line(frustum_uv.y, horizontal_line_count, line_width);
	float bottom_edge = 1.0 - smoothstep(0.0, 0.08, frustum_uv.y);
	float top_edge = smoothstep(0.92, 1.0, frustum_uv.y);
	float line_amount = max(max(vertical_line, horizontal_line), max(bottom_edge, top_edge));

	vec3 shaded_color = mix(volume_color.rgb, line_color.rgb, line_amount);
	ALBEDO = shaded_color;
	EMISSION = shaded_color * mix(0.12, 0.55, line_amount);
	ALPHA = clamp(volume_color.a + line_amount * line_color.a, 0.0, 1.0);
}
