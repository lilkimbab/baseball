shader_type spatial;
render_mode cull_disabled;
// The crowd (docs/06 7, docs/13 S14): instanced people without bones. The vertex shader moves
// them: a little sway in their seats, standing up, clapping and arms up to the beat of the
// cheering, by zone. The fan meshes carry what part a vertex is in UV2.x (0 legs, 1 torso, 2
// head, 3 upper arm, 4 forearm and hand, 5 cheering stick, 6 hair) and how far along its limb
// in UV2.y. The far crowd is flat cut-outs (`cutout`): an atlas with two frames, seated and
// arms up, whose red, green and blue say shirt, skin and hair.
//
// Per instance: COLOR.rgb the shirt, COLOR.a the skin tone; INSTANCE_CUSTOM.x a phase, .y the
// zone, .z 1 when he has a cheering stick, .w the hair and trousers shade.

uniform bool cutout = false;
uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
// Beats of the cheering so far (the songs run at about two a second).
uniform float beat = 0.0;
// Each zone's state: 0 seated, 1 standing, 2 standing with arms up, 3 seated clapping.
uniform float zone_state[8];

varying vec3 v_shirt;
varying float v_skin;
varying float v_shade;
varying float v_part;
varying float v_cheer;
varying float v_along;

const float RISE = 0.42;

void vertex() {
	int zone = int(INSTANCE_CUSTOM.y + 0.5);
	float st = zone_state[clamp(zone, 0, 7)];
	float stand = clamp(st, 0.0, 1.0) * step(st, 2.5);
	float cheer = clamp(st - 1.0, 0.0, 1.0) * step(st, 2.5);
	float clap = step(2.5, st);
	float phase = INSTANCE_CUSTOM.x;
	// Not everyone gets up at once.
	stand *= smoothstep(0.0, 0.35, fract(phase * 7.3) * 0.3 + 0.7);
	v_shirt = COLOR.rgb;
	v_skin = COLOR.a;
	v_shade = INSTANCE_CUSTOM.w;
	v_cheer = cheer;
	float pump = 0.5 + 0.5 * sin((beat + phase * 0.25) * 6.2832);
	vec3 v = VERTEX;
	if (cutout) {
		v.y += RISE * stand + 0.03 * pump * cheer;
		v_part = 0.0;
		v_along = 0.0;
	} else {
		float part = UV2.x;
		float along = UV2.y;
		v_part = part;
		v_along = along;
		float side = sign(v.x + 0.0001);
		// Sitting he sways a little.
		v.x += sin(TIME * 1.1 + phase * 6.2832) * 0.012 * v.y * (1.0 - stand);
		if (part < 0.5) {
			// Legs: from bent at the seat to straight down from the hip.
			vec3 upright = vec3(v.x, 0.87 * (1.0 - along), 0.02);
			v = mix(v, upright, stand);
		} else {
			v.y += RISE * stand;
		}
		if (part > 2.5 && part < 5.5) {
			// Arms: up over the head with the beat when cheering; together in front for a clap.
			vec3 shoulder = vec3(side * 0.2, 0.93 + RISE * stand, 0.0);
			float reach = along * 0.62;
			vec3 raised = shoulder + vec3(side * 0.06 * along, reach + 0.06 * pump * along, -0.08 * along);
			if (part > 4.5) {
				raised = shoulder + vec3(side * 0.08, 0.62 + 0.06 * pump + (along - 1.0) * 0.0, -0.1) + vec3(0.0, (v.y - 0.55) * 1.0, 0.0);
			}
			v = mix(v, raised, cheer);
			float together = clap * (0.5 + 0.5 * cos(beat * 6.2832 * 2.0));
			if (part > 3.5 && part < 4.5) {
				v.x = mix(v.x, v.x * 0.25, together * along);
				v.y += 0.2 * clap * along;
				v.z -= 0.08 * clap * along;
			}
		}
		if (part > 4.5 && part < 5.5 && INSTANCE_CUSTOM.z < 0.5) {
			// No cheering stick: fold it away inside the hand.
			v = vec3(side * 0.15, 0.55 + RISE * stand, -0.25);
		}
	}
	VERTEX = v;
}

void fragment() {
	vec3 skin = mix(vec3(0.93, 0.76, 0.62), vec3(0.55, 0.38, 0.27), v_skin);
	vec3 hair = mix(vec3(0.04, 0.035, 0.03), vec3(0.32, 0.22, 0.12), v_shade);
	vec3 trousers = mix(vec3(0.1, 0.11, 0.16), vec3(0.32, 0.33, 0.36), v_shade);
	vec3 colour;
	if (cutout) {
		vec2 uv = vec2(UV.x * 0.5 + (v_cheer > 0.5 ? 0.5 : 0.0), UV.y);
		vec4 mask = texture(atlas, uv);
		if (mask.a < 0.5) {
			discard;
		}
		colour = v_shirt * mask.r + skin * mask.g + hair * mask.b;
	} else if (v_part < 0.5) {
		colour = trousers;
	} else if (v_part < 1.5) {
		colour = v_shirt;
	} else if (v_part < 2.5) {
		colour = skin;
	} else if (v_part < 3.5) {
		colour = v_shirt;
	} else if (v_part < 4.5) {
		colour = mix(v_shirt, skin, step(0.9, v_along));
	} else if (v_part < 5.5) {
		colour = vec3(1.0, 0.85, 0.15) * (0.6 + 0.4 * v_shirt);
	} else {
		colour = hair;
	}
	ALBEDO = colour;
	ROUGHNESS = 0.85;
}
