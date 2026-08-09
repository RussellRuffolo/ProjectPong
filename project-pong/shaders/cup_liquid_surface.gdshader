shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 liquid_normal_local = vec3(0.0, 1.0, 0.0);
uniform float liquid_plane_offset = 0.0;
uniform float liquid_radius = 0.036;
uniform vec2 slosh_offset = vec2(0.0, 0.0);
uniform vec4 surface_color : source_color = vec4(0.25, 0.72, 1.0, 0.74);
uniform float wave_strength = 0.003;
uniform float wave_speed = 1.4;
uniform float wave_intensity = 0.0;
uniform float time_offset = 0.0;

varying vec2 surface_uv;
varying float ripple_amount;


void vertex() {
	vec3 plane_normal = normalize(liquid_normal_local);
	float safe_radius = max(liquid_radius, 0.001);
	float slosh_height = dot(VERTEX.xz / safe_radius, slosh_offset);
	float ripple = (
		sin(VERTEX.x * 46.0 + TIME * wave_speed + time_offset)
		+ sin(VERTEX.z * 39.0 - TIME * wave_speed * 1.5 + time_offset)
	) * 0.5 * wave_strength * wave_intensity;
	float plane_height = liquid_plane_offset + slosh_height + ripple;
	float plane_distance = dot(VERTEX, plane_normal) - plane_height;

	VERTEX -= plane_normal * plane_distance;
	NORMAL = plane_normal;
	surface_uv = UV;
	ripple_amount = abs(ripple);
}


void fragment() {
	float radius_from_center = length(surface_uv - vec2(0.5, 0.5)) * 2.0;
	float rim_highlight = smoothstep(0.72, 1.0, radius_from_center);
	float highlight_amount = clamp(rim_highlight * 0.45 + ripple_amount * 16.0, 0.0, 1.0);
	vec3 body_color = surface_color.rgb;
	vec3 highlight_color = vec3(0.75, 0.94, 1.0);

	ALBEDO = mix(body_color, highlight_color, highlight_amount);
	ALPHA = surface_color.a;
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
}
