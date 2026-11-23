shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
// The crowd (docs/06 7, docs/13 S14): every fan is a picture of a real-looking person
// (tools/blender/make_crowd.py renders them from Microsoft Rocketbox's people, MIT licence)
// on a card. Eight pictures a person — four ways of sitting, four of standing — and the
// zone's state, the beat of the cheering and the person's own number pick which one shows,
// so a section is never all in one attitude: no bones, one draw for thousands.
// A card turns about its foot toward whoever is looking (never edge-on), is flipped left to
// right for half the people, and each person is a little taller or shorter than the next.
// From behind (a camera at the back of the stands) the picture is the person's back: the fans
// face the game, not the camera (the user, 2026-11-23).
//
// Per instance: COLOR.rgb the club colour his top is dyed in, INSTANCE_CUSTOM.x a phase, .y
// the zone, .z 1 when his top is dyed (the cheering sections), .w which person (0..1).

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// White where each picture's top (shirt, jacket) is.
uniform sampler2D mask : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform int people = 13;
// The first `fans` people are fans; the rest are cheerleaders, on the stages only.
uniform int fans = 13;
uniform int poses = 8;
uniform int columns = 8;
uniform int rows = 13;
// 2 when the atlas has each person from the back too (the fronts, then the backs).
uniform int views = 1;
uniform vec2 card = vec2(1.0, 2.0);
// Beats of the cheering so far (the songs run at about two a second).
uniform float beat = 0.0;
// Each zone's state: 0 seated, 1 standing, 2 cheering with arms up, 3 seated clapping.
uniform float zone_state[8];

// The pictures of a person, in the atlas's order.
const int SEATED = 0;
const int LEAN = 1;
const int ARMS = 2;
const int CLAP = 3;
const int STAND = 4;
const int STAND_CLAP = 5;
const int CHEER = 6;
const int CHEER_ONE = 7;
// With something in hand (an atlas of 14 pictures a person): fried chicken, a beer, a phone,
// thunder sticks up and struck together, the club's towel held up.
const int EAT = 8;
const int DRINK = 9;
const int PHONE = 10;
const int STICKS_UP = 11;
const int STICKS_HIT = 12;
const int TOWEL = 13;

varying flat vec2 v_cell;
varying flat float v_flip;
varying vec3 v_tint;
varying float v_dyed;

void vertex() {
	int zone = int(INSTANCE_CUSTOM.y + 0.5);
	float st = zone_state[clamp(zone, 0, 7)];
	float phase = INSTANCE_CUSTOM.x;
	float who = fract(INSTANCE_CUSTOM.w * 57.31 + phase * 13.7);
	int person = int(INSTANCE_CUSTOM.w * float(people)) % people;
	float b = beat + phase * 0.6;
	int pose = SEATED;
	float bounce = 0.0;
	bool props = poses >= 14;
	if (person >= fans) {
		// A cheerleader: the routine, a step a beat through the six pictures of the dance, all
		// of them together (on the beat itself, not each fan's own lag).
		int step = int(floor(beat)) % 8;
		pose = (step == 0 || step == 2 || step == 6) ? 0 : (step == 1 ? 1 : (step == 3 ? 2 : (step == 4 ? 3 : (step == 5 ? 4 : 5))));
		bounce = 0.05 * abs(sin(beat * 3.14159));
	} else if (zone == 7) {
		// The cheer leader on the stage: both arms up and one arm, on the beat, leading them.
		pose = fract(beat * 0.5) < 0.5 ? CHEER : CHEER_ONE;
		bounce = 0.06 * abs(sin(beat * 3.14159));
	} else if (st > 2.5) {
		// Clapping: hands together on the beat, apart between; a few just watch.
		pose = who < 0.8 ? (fract(b) < 0.5 ? CLAP : SEATED) : LEAN;
	} else if (st > 1.5) {
		// Cheering: arms up, thunder sticks up and struck on the beat, a towel held up, one
		// arm, or clapping on their feet.
		if (who < 0.3) {
			pose = CHEER;
		} else if (who < 0.5) {
			pose = props ? (fract(b) < 0.5 ? STICKS_UP : STICKS_HIT) : CHEER;
		} else if (who < 0.58) {
			pose = props ? TOWEL : CHEER;
		} else if (who < 0.78) {
			pose = fract(b * 0.5) < 0.5 ? CHEER_ONE : STAND_CLAP;
		} else {
			pose = fract(b) < 0.5 ? STAND_CLAP : STAND;
		}
		bounce = 0.07 * abs(sin(b * 3.14159));
	} else if (st > 0.5) {
		// On their feet singing: at ease, clapping along, now and then an arm in the air, a
		// phone up to film, the sticks.
		if (who < 0.35) {
			pose = STAND;
		} else if (who < 0.65) {
			pose = fract(b) < 0.5 ? STAND_CLAP : STAND;
		} else if (who < 0.75) {
			pose = fract(b * 0.5) < 0.4 ? CHEER_ONE : STAND;
		} else if (who < 0.83) {
			pose = props ? PHONE : STAND;
		} else if (who < 0.93) {
			pose = props ? (fract(b) < 0.5 ? STICKS_HIT : STICKS_UP) : STAND;
		} else {
			pose = STAND;
		}
	} else {
		// Sitting: upright, leaning on the knees, arms folded; eating and drinking, a bite or a
		// sip now and then.
		if (who < 0.4) {
			pose = SEATED;
		} else if (who < 0.58) {
			pose = LEAN;
		} else if (who < 0.7 || !props) {
			pose = ARMS;
		} else if (who < 0.82) {
			pose = fract(TIME * 0.25 + phase * 3.0) < 0.55 ? EAT : SEATED;
		} else if (who < 0.92) {
			pose = fract(TIME * 0.15 + phase * 3.0) < 0.3 ? DRINK : SEATED;
		} else {
			pose = ARMS;
		}
	}
	int f = person * poses + pose;
	// Seen from behind (the eye on the far side of where he faces, the field): his back.
	// (The card's z axis points away from the field — a node faces along its -Z — so the way
	// he faces is minus it. With the sign the other way every fan showed his back to the
	// field's cameras and his face to the one behind the stands.)
	vec3 facing_field = -normalize(MODEL_MATRIX[2].xyz * vec3(1.0, 0.0, 1.0));
	vec3 eye_dir = CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz;
	eye_dir.y = 0.0;
	if (views > 1 && dot(facing_field, normalize(eye_dir)) < -0.2) {
		f += people * poses;
	}
	v_cell = vec2(float(f % columns), float(f / columns));
	// (Cheerleaders are never mirrored: the routine stays the same for all of them.)
	v_flip = person >= fans ? 0.0 : step(0.5, fract(phase * 7.77 + INSTANCE_CUSTOM.w * 3.1));
	v_tint = COLOR.rgb;
	v_dyed = INSTANCE_CUSTOM.z;

	// The card about its foot: turned toward the eye (most of the way; it keeps a little
	// of facing the field), each person his own height.
	vec3 foot = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz) * (0.94 + 0.12 * fract(phase * 5.3 + 0.37));
	vec3 own = normalize(MODEL_MATRIX[2].xyz * vec3(1.0, 0.0, 1.0));
	vec3 to_eye = CAMERA_POSITION_WORLD - foot;
	to_eye.y = 0.0;
	vec3 facing = normalize(mix(own, normalize(to_eye), 0.8));
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), facing));
	vec2 local = vec2((UV.x - 0.5) * card.x, (1.0 - UV.y) * card.y) * size;
	VERTEX = foot + side * local.x + vec3(0.0, local.y + bounce, 0.0);
	if (st < 0.5) {
		VERTEX += side * sin(TIME * 0.8 + phase * 6.2832) * 0.01 * (1.0 - UV.y);
	}
	// Lit as something upright facing the eye and the sky.
	NORMAL = normalize(facing + vec3(0.0, 0.6, 0.0));
}

void fragment() {
	vec2 in_cell = vec2(mix(UV.x, 1.0 - UV.x, v_flip), UV.y);
	vec2 uv = (v_cell + in_cell) / vec2(float(columns), float(rows));
	vec4 c = texture(atlas, uv);
	if (c.a < 0.5) {
		discard;
	}
	float m = texture(mask, uv).r * v_dyed;
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	vec3 dyed = v_tint * (0.3 + 1.4 * lum);
	vec3 colour = mix(c.rgb, dyed, m);
	// Down among the seats and the people in front it is darker than up by the head.
	colour *= mix(0.62, 1.0, smoothstep(0.0, 0.55, 1.0 - UV.y));
	ALBEDO = colour;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
