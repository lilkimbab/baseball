shader_type spatial;
// The buildings beyond the park: boxes wearing photographs of real building
// fronts (CC0, ambientCG "Facade" sets), one picture every `tile` metres, tinted a little per
// building; flat roofs of concrete. When the park's lights are on, windows glow (a
// photograph of a front at night). Per instance: COLOR the tint, INSTANCE_CUSTOM.xyz the
// box's size in metres.

uniform sampler2D front : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D night_front : source_color, repeat_enable, filter_linear_mipmap;
uniform float tile = 20.0;
uniform float lights = 0.0;
// How dark it is out there: 0 day, about 0.5 at dusk, 1 at night (the park's lights do not
// reach the town).
uniform float dark = 0.0;

varying vec3 local;
varying vec3 face;
varying vec3 box;

void vertex() {
	box = INSTANCE_CUSTOM.xyz;
	local = VERTEX * box;
	face = NORMAL;
}

void fragment() {
	float side = step(0.5, abs(face.x));
	float roof = step(0.5, abs(face.y));
	// From the ground up, and from one corner along, so floors sit level and whole.
	vec2 uv = vec2(mix(local.x + box.x * 0.5, local.z + box.z * 0.5, side), -(local.y + box.y * 0.5)) / tile;
	vec3 wall = texture(front, uv).rgb * COLOR.rgb * 1.5;
	// The roof seen from above: membrane sheets in 5 m runs with darker seams, some stained,
	// lighter along the parapet.
	vec2 roof_at = local.xz + box.xz * 0.5;
	vec2 sheet = floor(roof_at / 5.0);
	float stain = fract(sin(dot(sheet + floor(box.xz), vec2(12.9898, 78.233))) * 43758.5453);
	float seam = max(step(0.94, fract(roof_at.x / 5.0)), step(0.94, fract(roof_at.y / 5.0)));
	float rim = 1.0 - smoothstep(0.0, 1.2, min(min(roof_at.x, box.x - roof_at.x), min(roof_at.y, box.z - roof_at.y)));
	vec3 top = vec3(0.34, 0.35, 0.36) * COLOR.rgb * (0.88 + 0.2 * stain) * (1.0 - 0.18 * seam) + vec3(0.08) * rim;
	ALBEDO = mix(wall, top, roof) * mix(1.0, 0.1, dark);
	ROUGHNESS = mix(0.55, 0.9, roof);
	SPECULAR = 0.4;
	vec3 glow = texture(night_front, uv * 0.7 + box.xy * 0.013).rgb;
	EMISSION = glow * lights * (1.0 - roof) * (0.35 + 1.5 * dark);
}
