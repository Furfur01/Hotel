shader_type canvas_item;

uniform sampler2D fog_mask : filter_linear, repeat_disable;
uniform vec4 graphite_color : source_color = vec4(0.12, 0.085, 0.055, 1.0);

float mist_noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 map_color = texture(TEXTURE, UV);
	float explored = smoothstep(0.08, 0.82, texture(fog_mask, UV).r);
	float grain = mist_noise(floor(UV * 90.0) + floor(TIME * 0.35));
	float value = dot(map_color.rgb, vec3(0.299, 0.587, 0.114));
	float structure = smoothstep(0.055, 0.42, value);
	float pencil_line = structure * explored * 0.72;
	float fog_wash = (1.0 - explored) * (0.13 + grain * 0.035);
	// Both the revealed plan and the unexplored fog are translucent graphite so
	// the generated paper texture remains visible underneath.
	COLOR = vec4(graphite_color.rgb, clamp(pencil_line + fog_wash, 0.0, 0.82));
}
