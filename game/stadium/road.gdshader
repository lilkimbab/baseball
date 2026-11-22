shader_type spatial;
render_mode cull_disabled;
// The streets beyond the park (R2): scanned asphalt, a broken white centre line and solid
// edge lines, worn a little. UV.x runs across the road (0 to 1), UV.y along it in metres.

uniform sampler2D asphalt : source_color, repeat_enable, filter_linear_mipmap;
uniform float lights = 0.0;
uniform float dark = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec3 base = texture(asphalt, vec2(uv.x * 2.5, uv.y / 6.0)).rgb * 0.82;
	// Lines: the centre (broken, 6 m on and 6 off), the edges (solid), and the lane lines.
	float centre = (1.0 - smoothstep(0.006, 0.012, abs(uv.x - 0.5))) * step(0.5, fract(uv.y / 12.0));
	float edges = (1.0 - smoothstep(0.004, 0.009, abs(uv.x - 0.06))) + (1.0 - smoothstep(0.004, 0.009, abs(uv.x - 0.94)));
	float lanes = (1.0 - smoothstep(0.004, 0.008, abs(abs(uv.x - 0.5) - 0.22))) * step(0.65, fract(uv.y / 9.0));
	float paint = clamp(centre + edges + lanes, 0.0, 1.0) * (0.75 + 0.25 * hash(floor(uv * vec2(20.0, 1.0))));
	vec3 colour = mix(base, vec3(0.86, 0.86, 0.82), paint);
	ALBEDO = colour * mix(1.0, 0.15, dark);
	ROUGHNESS = mix(0.92, 0.7, paint);
	SPECULAR = 0.3;
	// Street lamps at night: a faint warm wash.
	EMISSION = vec3(0.9, 0.7, 0.45) * 0.05 * lights * dark;
}
