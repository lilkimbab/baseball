shader_type spatial;
// Playing surface drawn from field coordinates instead of a painted texture: mown grass with
// stripes, infield dirt, warning track, foul lines and batter's boxes. Edges stay sharp at any
// distance, and changing the fence profile moves the warning track with it.

uniform sampler2D grain : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grain_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
// Fence distance from home (m) for azimuth -45..+45 degrees in one-degree steps.
uniform float fence_dist[91];
uniform float track_width = 4.5;
// Half the width of a chalk line. Lines are 3 inches wide (Field.LINE_WIDTH).
uniform float line_half_width = 0.0381;
uniform vec3 grass_light : source_color = vec3(0.19, 0.43, 0.14);
uniform vec3 grass_dark : source_color = vec3(0.14, 0.36, 0.11);
uniform vec3 dirt : source_color = vec3(0.56, 0.38, 0.24);
uniform vec3 chalk : source_color = vec3(0.94, 0.94, 0.90);
uniform vec3 apron : source_color = vec3(0.30, 0.31, 0.33);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 where |d| < half_width, with an edge aa wide.
float band(float d, float half_width, float aa) {
	return 1.0 - smoothstep(half_width - aa, half_width + aa, abs(d));
}

void fragment() {
	// Field coordinates: x toward first base, y toward centre field.
	vec2 f = vec2(wpos.x, -wpos.z);
	float aa = clamp(length(fwidth(f)), 0.002, 2.0);
	float r = length(f);
	float az = clamp(degrees(atan(f.x, f.y)) + 45.0, 0.0, 90.0);
	int i0 = int(floor(az));
	int i1 = min(i0 + 1, 90);
	float fence = mix(fence_dist[i0], fence_dist[i1], fract(az));
	float fair = smoothstep(-aa, aa, f.y - abs(f.x));

	// Dirt: around home, the mound, the infield skin and the warning track.
	float home = 1.0 - smoothstep(3.96 - aa, 3.96 + aa, length(f - vec2(0.0, 0.2)));
	float mound = 1.0 - smoothstep(2.74 - aa, 2.74 + aa, length(f - vec2(0.0, 17.98)));
	float arc = 1.0 - smoothstep(28.96 - aa, 28.96 + aa, length(f - vec2(0.0, 18.44)));
	float side = smoothstep(-aa, aa, f.y - abs(f.x) + 3.0);
	float diamond = 1.0 - smoothstep(18.4 - aa, 18.4 + aa, abs(f.x) + abs(f.y - 19.397));
	float skin = arc * side * (1.0 - diamond);
	float track = fair * smoothstep(fence - track_width - aa, fence - track_width + aa, r);
	float dirt_mask = clamp(max(max(home, mound), max(skin, track)), 0.0, 1.0);
	float beyond = fair * smoothstep(fence - aa, fence + aa, r);

	// Grass: mowing stripes (diagonal in the outfield, straight in the infield) plus patchy
	// and fine variation so it is never one flat colour.
	vec2 g = vec2(f.x + f.y, f.y - f.x) * 0.7071;
	float soft = clamp(aa * 0.25, 0.04, 0.5);
	float stripe_out = smoothstep(0.5 - soft, 0.5 + soft, abs(fract(g.x / 11.0) - 0.5) * 2.0);
	float stripe_in = smoothstep(0.5 - soft, 0.5 + soft, abs(fract(f.y / 5.0) - 0.5) * 2.0);
	float stripe = mix(stripe_out, stripe_in, diamond);
	float patches = texture(grain, f * 0.03).r;
	float blades = texture(grain, f * 0.85).r;
	vec3 grass = mix(grass_dark, grass_light, stripe) * (0.84 + 0.26 * patches) * (0.88 + 0.24 * blades);

	float clumps = texture(grain, f * 0.11 + vec2(3.7, 1.3)).r;
	float grit = texture(grain, f * 1.9).r;
	vec3 soil = dirt * (0.82 + 0.26 * clumps) * (0.88 + 0.24 * grit);
	vec3 colour = mix(grass, soil, dirt_mask);

	// Chalk: foul lines out to the fence, and the two batter's boxes.
	float in_play = 1.0 - smoothstep(fence - aa, fence + aa, r);
	// The foul lines' outer edges run through the apex of home plate.
	float half_line = line_half_width;
	float foul_line = band((abs(f.x) - f.y) * 0.7071 + half_line, half_line, aa) * step(0.3, f.y) * in_play;
	// Batter's boxes: 4 ft by 6 ft, 6 in from the plate, centred on its middle.
	vec2 q = abs(vec2(abs(f.x) - 0.978, f.y - 0.216)) - vec2(0.61, 0.915);
	float box_edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
	float boxes = band(box_edge + half_line, half_line, aa);
	// Catcher's box: 43 in wide, from the back of the batter's boxes to 8 ft behind the apex.
	float behind = step(f.y, -0.699) * step(-2.438, f.y);
	float catcher = band(abs(f.x) - 0.546 + half_line, half_line, aa) * behind;
	catcher = max(catcher, band(f.y + 2.438 - half_line, half_line, aa) * step(abs(f.x), 0.546));
	colour = mix(colour, chalk * (0.9 + 0.1 * grit), clamp(max(max(foul_line, boxes), catcher), 0.0, 1.0) * 0.9);
	colour = mix(colour, apron, beyond);

	ALBEDO = colour;
	ROUGHNESS = mix(0.9, 0.97, dirt_mask);
	NORMAL_MAP = texture(grain_normal, f * 0.7).rgb;
	NORMAL_MAP_DEPTH = mix(0.9, 0.5, dirt_mask);
}
