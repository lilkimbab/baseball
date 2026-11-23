shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, sss_mode_skin;
// Skin: the painted MakeHuman skin, with what makes it read as a
// person's and not a doll's, on the face and the arms, hands and neck alike. The maps are
// baked by tools/blender/make_player.py (bake_skin_maps):
//  - relief: the painted skin's grain and creases and the tendons of the hands and wrists
//    (the x and y of a normal map), and how fine-grained the skin is there (its third channel:
//    1 on the face, little on the arms, where the same grain is twice the size);
//  - the veins and tendons of the arms and hands are not in a map (the arms' part of the
//    texture is too coarse for them): they are drawn here, from the arm's own coordinates in
//    the model and the table of where they run (match/skin_veins.gd), as fine as the screen
//    is, and different on every player;
//  - shading in the creases (eyes, nostrils, ears, mouth, fingers) and in the hollows between
//    the muscles (shoulders, arms, neck, collarbones, knuckles);
//  - roughness: where skin shines (forehead, nose) and where it is matte;
//  - the beard area, for stubble; the scalp, for cropped hair drawn on the skin.
// On top: pores (a fine tiling normal), the skin's own broad highlight (tighter where it is
// oily or sweaty), light scattering under the skin, and a soft sheen at the edges (fine hair).

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
// (Not hinted as normal maps: their third channels carry other things.)
uniform sampler2D relief_texture : filter_linear_mipmap_anisotropic;
// A row for each vein: R its path, G how well it shows, B its slope, A its half-width (mm).
uniform sampler2D vein_table : filter_linear, repeat_disable;
// How much each vein of the arm wanders (rad).
uniform float vein_wander[8];
// R creases and hollows, G roughness, B beard area, A 1 - half the scalp's hair.
uniform sampler2D detail_texture : hint_default_white, filter_linear_mipmap;
uniform sampler2D pore_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_detail = false;
uniform bool has_relief = false;
// The model carries arm coordinates (vertex colour and second UV map).
uniform bool has_limbs = false;
uniform float relief_strength : hint_range(0.0, 2.0) = 0.45;
uniform float pore_tiling = 70.0;
uniform float pore_strength : hint_range(0.0, 1.0) = 0.05;
uniform float occlusion : hint_range(0.0, 1.0) = 0.95;
uniform float scatter : hint_range(0.0, 1.0) = 0.22;

// Per player (SkinnedPuppet.set_face): complexion (a multiplier on the painted skin: sun,
// tan), how much beard shadow, how sweaty, how much his veins show (lean men's more), and
// the colour of his hair.
instance uniform vec3 tone : source_color = vec3(0.9, 0.81, 0.74);
instance uniform float stubble = 0.35;
instance uniform float sweat = 0.3;
instance uniform float veins = 0.5;
instance uniform float vein_seed = 0.0;
instance uniform vec3 hair_tint : source_color = vec3(0.05, 0.045, 0.04);
// A long-sleeved undershirt: 1 covers the arms to the wrists in its colour.
instance uniform float sleeve = 0.0;
instance uniform vec3 sleeve_tint : source_color = vec3(0.08, 0.1, 0.2);

const int ARM_VEINS = 7;
const int HAND_VEINS = 5;
const float TABLE_ROWS = 16.0;
// A vein at its fullest stands this far out of the skin, a tendon this far (m).
const float VEIN_HEIGHT = 0.0014;
const float TENDON_HEIGHT = 0.0009;
const float HAND_VEIN_HALF = 0.002;
const float TENDON_HALF = 0.0026;

// Along the arm (packed), cos and sin of the angle round it, how much of an arm this is.
varying vec4 limb;
// Across the back of the hand (packed).
varying vec2 limb_hand;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth irregular drift (about -1..1): what makes a vein meander and come and go.
float wander(float x, float seed) {
	return (sin(x * 7.1 + seed * 1.7) + 0.55 * sin(x * 16.3 + seed * 4.1) + 0.3 * sin(x * 31.7 + seed * 9.3)) / 1.85;
}

float ridge(float across, float half_width) {
	return exp(-(across * across) / (half_width * half_width));
}

// How far the veins and tendons raise the skin here (m); `blue` is how much vein there is
// (for its colour through the skin).
float under_skin(out float blue) {
	blue = 0.0;
	float weight = limb.a;
	if (weight < 0.02) {
		return 0.0;
	}
	float t = limb.r * 3.0 - 1.0;
	float vein = 0.0;
	float tint = 0.0;
	float cord = 0.0;
	if (t < 1.0) {
		float angle = atan(limb.b * 2.0 - 1.0, limb.g * 2.0 - 1.0);
		float radius = t < 0.0 ? 0.05 + 0.004 * clamp(-t, 0.0, 1.0) : 0.046 - 0.017 * clamp(t, 0.0, 1.0);
		float along = t < 0.0 ? 0.3 : 0.27;
		for (int i = 0; i < ARM_VEINS; i++) {
			vec4 row = textureLod(vein_table, vec2((t + 1.0) * 0.5, (float(i) + 0.5) / TABLE_ROWS), 0.0);
			float seed = vein_seed + float(i) * 3.7;
			float path = row.r + vein_wander[i] * wander(t, seed);
			float slope = row.b * radius / along;
			float across = (mod(angle - path + PI, TAU) - PI) * radius / sqrt(1.0 + slope * slope);
			// It comes and goes along its length as the flesh over it thickens, and no two
			// men's show alike.
			float seen = row.g * clamp(0.72 + 0.4 * wander(t * 1.9 + 3.0, seed + 20.0), 0.25, 1.0) * mix(0.35, 1.0, hash(vec2(seed, 7.0)));
			float half_width = row.a * 0.001 * (0.8 + 0.25 * seen);
			vein = max(vein, seen * ridge(across, half_width));
			// Its colour shows through the skin wider than it stands out of it.
			tint = max(tint, seen * ridge(across, half_width * 1.7));
		}
		// The wrist is where the hand's coordinates take over: nothing drawn across it.
		vein *= 1.0 - smoothstep(0.94, 1.0, t);
		tint *= 1.0 - smoothstep(0.94, 1.0, t);
		// The two cords inside the wrist.
		float near_wrist = smoothstep(0.72, 0.9, t) * (1.0 - smoothstep(0.94, 1.0, t));
		cord = near_wrist * max(ridge((mod(angle + 1.22 + PI, TAU) - PI) * radius, TENDON_HALF),
				ridge((mod(angle + 1.66 + PI, TAU) - PI) * radius, TENDON_HALF));
	} else {
		float th = t - 1.0;
		float u = (limb_hand.x - 0.5) / 5.0;
		for (int i = 0; i < HAND_VEINS; i++) {
			vec4 row = textureLod(vein_table, vec2(th, (float(ARM_VEINS + i) + 0.5) / TABLE_ROWS), 0.0);
			float seed = vein_seed + float(i) * 5.3 + 40.0;
			float line = row.r + 0.0012 * wander(th * 2.0, seed);
			float seen = row.g * clamp(0.8 + 0.3 * wander(th * 2.3, seed + 5.0), 0.3, 1.0) * mix(0.5, 1.0, hash(vec2(seed, 3.0)));
			vein = max(vein, seen * ridge(u - line, HAND_VEIN_HALF));
			tint = max(tint, seen * ridge(u - line, HAND_VEIN_HALF * 1.7));
		}
		// The arch across the back of the hand that they run into.
		float arch = 0.44 + 0.045 * (1.0 - pow(u / 0.022, 2.0)) + 0.01 * wander(u * 40.0, vein_seed + 17.0);
		vein = max(vein, 0.55 * step(abs(u), 0.022) * ridge((th - arch) * 0.09, HAND_VEIN_HALF));
		tint = max(tint, 0.55 * step(abs(u), 0.022) * ridge((th - arch) * 0.09, HAND_VEIN_HALF * 1.7));
		vein *= smoothstep(0.0, 0.08, th);
		tint *= smoothstep(0.0, 0.08, th);
		// The tendons to the knuckles stand out most just behind them.
		float behind = smoothstep(0.25, 0.75, th) * (1.0 - smoothstep(0.93, 1.0, th));
		cord = ridge(u - mix(0.007, 0.0285, th), TENDON_HALF);
		cord = max(cord, ridge(u - mix(0.002, 0.0095, th), TENDON_HALF));
		cord = max(cord, ridge(u - mix(-0.003, -0.0085, th), TENDON_HALF));
		cord = max(cord, ridge(u - mix(-0.007, -0.0255, th), TENDON_HALF));
		cord *= behind;
	}
	blue = tint * weight;
	return (vein * VEIN_HEIGHT * veins + cord * TENDON_HEIGHT) * weight;
}

void vertex() {
	limb = COLOR;
	limb_hand = UV2;
}

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb;
	// The painted skin is a little more saturated than skin in daylight.
	base = mix(vec3(dot(base, vec3(0.3, 0.59, 0.11))), base, 0.85) * tone;
	vec4 d = has_detail ? texture(detail_texture, UV) : vec4(1.0, 0.5, 0.0, 1.0);
	float ao = mix(1.0, d.r, occlusion);
	// Stubble: dark points where the beard grows, evening out to a shadow when too small to see.
	vec2 cell = UV * 3072.0;
	float spread = length(fwidth(cell));
	float dots = mix(step(0.55, hash(floor(cell))), 0.45, clamp(spread - 0.5, 0.0, 1.0));
	float beard = d.b * stubble;
	base = mix(base, base * vec3(0.42, 0.45, 0.5), clamp(beard * (0.45 + 0.75 * dots), 0.0, 1.0));
	// Creases are a little darker and redder (light goes deeper into the skin there).
	base *= mix(vec3(0.82, 0.74, 0.72), vec3(1.0), ao);
	// The veins and tendons under the skin: a little blue-grey where a vein is, and the
	// surface tilted by their height (fading out where a pixel covers more than they are wide).
	// The undershirt's sleeve over the arm, down to a cuff at the wrist: cloth, not skin.
	float cloth = 0.0;
	if (has_limbs && sleeve > 0.5) {
		float along = limb.r * 3.0 - 1.0;
		cloth = smoothstep(0.02, 0.2, limb.a) * (1.0 - smoothstep(0.915, 0.925, along));
	}
	float blue = 0.0;
	float raised = has_limbs ? under_skin(blue) * (1.0 - cloth) : 0.0;
	blue *= 1.0 - cloth;
	vec3 across_x = dFdx(VERTEX);
	vec3 across_y = dFdy(VERTEX);
	float sharp = 1.0 - smoothstep(0.0012, 0.004, max(length(across_x), length(across_y)));
	base = mix(base, base * vec3(0.74, 0.86, 0.96), blue * veins * 0.5 * (0.5 + 0.5 * sharp));
	if (has_limbs) {
		vec3 flat_normal = normalize(NORMAL);
		vec3 r1 = cross(across_y, flat_normal);
		vec3 r2 = cross(flat_normal, across_x);
		float det = dot(across_x, r1);
		vec3 slope = sign(det) * (dFdx(raised) * r1 + dFdy(raised) * r2);
		// Only where something is raised: elsewhere the surface is left exactly as it was
		// (and where a pixel's footprint is degenerate there is nothing to normalise).
		if (dot(slope, slope) > 0.0 && abs(det) > 0.0) {
			NORMAL = normalize(abs(det) * flat_normal - slope * 2.2 * sharp);
		}
	}
	// Cropped hair on the scalp (under a cap it is all that shows): strands close up,
	// evening out to the hair's colour, thinning to stubble at the hairline.
	float scalp = has_detail ? clamp((1.0 - d.a) * 2.0, 0.0, 1.0) : 0.0;
	vec2 strand = UV * vec2(4096.0, 1536.0);
	float strands = mix(step(0.2, hash(floor(strand))), 0.95, clamp(length(fwidth(strand)) - 0.5, 0.0, 1.0));
	// The hairline is not a line: hairs thin out over a few millimetres, unevenly.
	float edge = scalp + (hash(floor(UV * 1400.0)) - 0.5) * 0.3 * (1.0 - clamp(length(fwidth(UV * 1400.0)) - 0.5, 0.0, 1.0));
	float hair = smoothstep(0.3, 0.62, edge) * (0.72 + 0.28 * strands);
	base = mix(base, hair_tint, hair);
	base = mix(base, sleeve_tint * (0.92 + 0.08 * ao), cloth);
	ALBEDO = base;
	AO = ao;
	AO_LIGHT_AFFECT = 0.5;

	vec3 relief = has_relief ? texture(relief_texture, UV).xyz : vec3(0.5, 0.5, 1.0);
	vec3 pores = texture(pore_texture, UV * pore_tiling).xyz * 2.0 - 1.0;
	vec2 tilt = (relief.xy * 2.0 - 1.0) * relief_strength + pores.xy * pore_strength * relief.z;
	NORMAL_MAP = normalize(vec3(tilt, 1.0)) * 0.5 + 0.5;

	float rough = has_detail ? d.g : 0.55;
	// (The arms and legs a little more matte than the face: with the face's sheen a forearm
	// in the sun showed one long white streak, like plastic.)
	ROUGHNESS = clamp(mix(rough, rough * 0.7, sweat) + (1.0 - ao) * 0.25 + beard * 0.15 + hair * 0.3 + (1.0 - relief.z) * 0.1, 0.42, 0.9);
	// Skin reflects about 2.8% straight on (0.35 here; 0.5 is 4%), less in the creases.
	SPECULAR = 0.35 * mix(0.4, 1.0, ao);
	// No second (clear coat) highlight for sweat: the engine draws that layer mirror-sharp
	// whatever its roughness, and on skin it broke up into single white pixels under the eyes
	// and down the cheeks, like tears. Sweat is the lower roughness above.
	ROUGHNESS = mix(ROUGHNESS, 0.82, cloth);
	SPECULAR = mix(SPECULAR, 0.3, cloth);
	SSS_STRENGTH = scatter * (1.0 - hair) * (1.0 - cloth);
	RIM = 0.18 * (1.0 - hair);
	RIM_TINT = 0.7;
}
