shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 liquid_normal_local = vec3(0.0, 1.0, 0.0);
uniform float liquid_plane_offset = 0.0;
uniform float liquid_radius = 0.036;
uniform vec2 slosh_offset = vec2(0.0, 0.0);
uniform vec4 liquid_color : source_color = vec4(0.05, 0.44, 1.0, 0.58);
uniform float edge_softness = 0.006;
uniform float wave_strength = 0.003;
uniform float wave_speed = 1.4;
uniform float wave_intensity = 0.0;
uniform float time_offset = 0.0;

varying vec3 local_pos;


void vertex() {
	local_pos = VERTEX;
}


void fragment() {
	vec3 plane_normal = normalize(liquid_normal_local);
	float safe_radius = max(liquid_radius, 0.001);
	float slosh_height = dot(local_pos.xz / safe_radius, slosh_offset);
	float ripple = (
		sin(local_pos.x * 42.0 + TIME * wave_speed + time_offset)
		+ sin(local_pos.z * 37.0 - TIME * wave_speed * 1.3 + time_offset)
	) * 0.5 * wave_strength * wave_intensity;
	float plane_height = liquid_plane_offset + slosh_height + ripple;
	float plane_distance = dot(local_pos, plane_normal) - plane_height;

	if (plane_distance > edge_softness) {
		discard;
	}

	float edge_fade = 1.0 - smoothstep(0.0, edge_softness, max(plane_distance, 0.0));
	float depth_tint = clamp(-plane_distance * 12.0, 0.0, 1.0);
	vec3 deep_color = liquid_color.rgb * vec3(0.55, 0.72, 1.0);
	vec3 shallow_color = liquid_color.rgb * vec3(1.25, 1.15, 1.0);

	ALBEDO = mix(shallow_color, deep_color, depth_tint);
	ALPHA = liquid_color.a * edge_fade;
	ROUGHNESS = 0.16;
	SPECULAR = 0.65;
}
