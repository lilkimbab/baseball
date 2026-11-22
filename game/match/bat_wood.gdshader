shader_type spatial;
// SEE_THROUGH
// A bat turned from a billet of ash (docs/12): pale wood whose growth rings run its length,
// showing as long dark lines close together on one side (the edge grain) and broad flames on
// the face; fine pores along the grain; a satin lacquer; pine tar worked into the handle
// above the grip. The mesh lies along its y axis, centred, the knob at the bottom
// (tools/blender/make_props.py).

uniform vec3 pale : source_color = vec3(0.83, 0.67, 0.44);
uniform vec3 late : source_color = vec3(0.52, 0.35, 0.19);
uniform vec3 tar : source_color = vec3(0.16, 0.10, 0.06);
uniform float length_m = 0.851;
uniform float alpha = 1.0;

varying vec3 local;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	float along = local.y + length_m * 0.5;
	// The tree's heart is well off to one side of the billet: the rings cross the bat as
	// nearly straight lines, wandering a little along it.
	vec2 heart = local.xz + vec2(0.085, 0.03);
	float wander = (noise(vec2(along * 2.4, atan(heart.y, heart.x) * 4.0)) - 0.5) * 0.010
		+ (noise(vec2(along * 11.0, 7.3)) - 0.5) * 0.0018;
	float ring = (length(heart) + wander) / 0.0042;
	float line = 1.0 - smoothstep(0.0, 0.38, abs(fract(ring) - 0.5) * 2.0);
	// Pores: fine dark dashes a few centimetres long, lying along the grain.
	float around = atan(local.z, local.x);
	float pores = noise(vec2(around * 150.0, along * 9.0)) * noise(vec2(around * 60.0 + 3.0, along * 4.0));
	float streak = noise(vec2(around * 7.0, along * 3.0));
	vec3 wood = mix(pale, late, line * 0.6);
	wood *= 0.9 + 0.13 * streak;
	wood *= 1.0 - 0.16 * smoothstep(0.35, 0.7, pores);
	// Pine tar: dark and sticky from a hand's width above the knob up toward the label.
	float smear = smoothstep(0.24, 0.34, along) * (1.0 - smoothstep(0.42, 0.56, along + (streak - 0.5) * 0.08));
	smear *= 0.45 + 0.4 * noise(vec2(atan(local.z, local.x) * 5.0, along * 30.0));
	ALBEDO = mix(wood, tar, smear * 0.75);
	ROUGHNESS = mix(0.36 + 0.1 * line, 0.75, smear);
	SPECULAR = 0.5;
#ifdef SEE_THROUGH
	ALPHA = alpha;
#endif
}
