shader_type spatial;
render_mode cull_disabled;
// A flag on its pole (docs/13 S13): the cloth waves from the hoist (UV.x = 0) outward, more
// the harder the wind blows. Per instance: COLOR the flag's colour.

uniform float wind : hint_range(0.0, 2.0) = 1.0;

void vertex() {
	float phase = dot(MODEL_MATRIX[3].xyz, vec3(0.37, 0.11, 0.23));
	float out_ = UV.x;
	float wave = sin(TIME * (3.5 + 2.5 * wind) - out_ * 7.0 + phase) * 0.16 + sin(TIME * 5.3 - out_ * 13.0 + phase * 1.7) * 0.05;
	VERTEX.z += wave * out_ * (0.4 + 0.6 * wind);
	// A slack flag hangs: its fly end droops when the wind is light.
	VERTEX.y -= out_ * out_ * (1.0 - clamp(wind, 0.0, 1.0)) * 0.9;
}

void fragment() {
	// A band of white along the middle third: a pennant's stripe.
	float stripe = step(0.36, UV.y) * step(UV.y, 0.64);
	ALBEDO = mix(COLOR.rgb, vec3(0.95), stripe * 0.9);
	ROUGHNESS = 0.85;
}
