shader_type spatial;
// The sea beside a park (docs/13 S13-8): deep water whose small waves — two layers of ripples
// sliding across each other — catch the sky and the sun.

uniform sampler2D ripples : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 deep : source_color = vec3(0.03, 0.12, 0.17);
uniform vec3 shallow : source_color = vec3(0.07, 0.24, 0.28);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 a = texture(ripples, p * 0.021 + vec2(TIME * 0.011, TIME * 0.006)).rgb;
	vec3 b = texture(ripples, p * 0.057 - vec2(TIME * 0.016, -TIME * 0.009)).rgb;
	NORMAL_MAP = normalize(a + b - vec3(1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.9;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep, shallow, fresnel * 0.6);
	ROUGHNESS = 0.07;
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
