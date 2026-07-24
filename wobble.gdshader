shader_type spatial;
render_mode specular_disabled, diffuse_lambert;

uniform float snap = 160.0;
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform vec2 tiling = vec2(2.0);
uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness = 0.95;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (clip.w > 0.0001) {
		vec3 ndc = clip.xyz / clip.w;
		ndc.xy = floor(ndc.xy * snap) / snap;
		clip.xyz = ndc * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = texture(tex, UV * tiling).rgb * tint;
	ROUGHNESS = roughness;
}
