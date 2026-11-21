shader_type spatial;
render_mode cull_disabled;
// The crowd (docs/06 7, docs/13 S14): every fan is a picture of a real-looking person
// (tools/blender/make_crowd.py renders them from Microsoft Rocketbox's people, MIT licence)
// on a card facing the field. Four pictures a person — seated, standing, arms up, clapping —
// and the zone's state and the beat of the cheering pick which one shows: no bones, one draw
// for thousands.
//
// Per instance: COLOR.rgb the club colour his top is dyed in, INSTANCE_CUSTOM.x a phase, .y
// the zone, .z 1 when his top is dyed (the cheering sections), .w which person (0..1).

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// White where each picture's top (shirt, jacket) is.
uniform sampler2D mask : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform int people = 13;
uniform int poses = 4;
uniform int columns = 8;
uniform int rows = 7;
// Beats of the cheering so far (the songs run at about two a second).
uniform float beat = 0.0;
// Each zone's state: 0 seated, 1 standing, 2 cheering with arms up, 3 seated clapping.
uniform float zone_state[8];

varying flat vec2 v_cell;
varying vec3 v_tint;
varying float v_dyed;

void vertex() {
	int zone = int(INSTANCE_CUSTOM.y + 0.5);
	float st = zone_state[clamp(zone, 0, 7)];
	float phase = INSTANCE_CUSTOM.x;
	int person = int(INSTANCE_CUSTOM.w * float(people)) % people;
	float b = beat + phase * 0.6;
	int pose = 0;
	if (st > 2.5) {
		// Clapping: hands together on the beat, apart between.
		pose = fract(b) < 0.5 ? 3 : 0;
	} else if (st > 1.5) {
		pose = 2;
		VERTEX.y += 0.06 * abs(sin(b * 3.14159));
	} else if (st > 0.5) {
		// On their feet singing; some punch the air on the beat.
		pose = (phase < 0.35 && fract(b * 0.5) < 0.5) ? 2 : 1;
	} else {
		VERTEX.x += sin(TIME * 0.8 + phase * 6.2832) * 0.01;
	}
	int f = person * poses + pose;
	v_cell = vec2(float(f % columns), float(f / columns));
	v_tint = COLOR.rgb;
	v_dyed = INSTANCE_CUSTOM.z;
}

void fragment() {
	vec2 uv = (v_cell + UV) / vec2(float(columns), float(rows));
	vec4 c = texture(atlas, uv);
	if (c.a < 0.5) {
		discard;
	}
	float m = texture(mask, uv).r * v_dyed;
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	vec3 dyed = v_tint * (0.3 + 1.4 * lum);
	ALBEDO = mix(c.rgb, dyed, m);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
