shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
// The crowd (docs/06 7, docs/13 S14): every fan is a picture of a real-looking person
// (tools/blender/make_crowd.py renders them from Microsoft Rocketbox's people, MIT licence)
// on a card. Eight pictures a person — four ways of sitting, four of standing — and the
// zone's state, the beat of the cheering and the person's own number pick which one shows,
// so a section is never all in one attitude: no bones, one draw for thousands.
// A card turns about its foot toward whoever is looking (never edge-on), is flipped left to
// right for half the people, and each person is a little taller or shorter than the next.
//
// Per instance: COLOR.rgb the club colour his top is dyed in, INSTANCE_CUSTOM.x a phase, .y
// the zone, .z 1 when his top is dyed (the cheering sections), .w which person (0..1).

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// White where each picture's top (shirt, jacket) is.
uniform sampler2D mask : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform int people = 13;
uniform int poses = 8;
uniform int columns = 8;
uniform int rows = 13;
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
	if (st > 2.5) {
		// Clapping: hands together on the beat, apart between; a few just watch.
		pose = who < 0.8 ? (fract(b) < 0.5 ? CLAP : SEATED) : LEAN;
	} else if (st > 1.5) {
		// Cheering: arms up, one arm, or clapping on their feet, each to the beat.
		pose = who < 0.45 ? CHEER : (who < 0.75 ? (fract(b * 0.5) < 0.5 ? CHEER_ONE : STAND_CLAP) : (fract(b) < 0.5 ? STAND_CLAP : STAND));
		bounce = 0.07 * abs(sin(b * 3.14159));
	} else if (st > 0.5) {
		// On their feet singing: at ease, clapping along, now and then an arm in the air.
		pose = who < 0.4 ? STAND : (who < 0.75 ? (fract(b) < 0.5 ? STAND_CLAP : STAND) : (fract(b * 0.5) < 0.4 ? CHEER_ONE : STAND));
	} else {
		pose = who < 0.5 ? SEATED : (who < 0.75 ? LEAN : ARMS);
	}
	int f = person * poses + pose;
	v_cell = vec2(float(f % columns), float(f / columns));
	v_flip = step(0.5, fract(phase * 7.77 + INSTANCE_CUSTOM.w * 3.1));
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
