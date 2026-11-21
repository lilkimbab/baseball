shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, sss_mode_skin;
// Skin (docs/13 S11-3, S14): the painted MakeHuman skin, with what makes it read as a
// person's and not a doll's, on the face and the arms, hands and neck alike. The maps are
// baked by tools/blender/make_player.py (bake_skin_maps):
//  - relief: the painted skin's grain and creases, and the raised veins of the forearms and
//    the backs of the hands, as a normal map;
//  - shading in the creases (eyes, nostrils, ears, mouth, fingers) and in the hollows between
//    the muscles (shoulders, arms, neck, collarbones, knuckles);
//  - roughness: where skin shines (forehead, nose) and where it is matte;
//  - the beard area, for stubble; the veins, for their colour.
// On top: pores (a fine tiling normal), two highlights — the skin's own broad one and a sharp
// one from oil and sweat (the clear coat) — light scattering under the skin, and a soft sheen
// at the edges (fine hair).

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D relief_texture : hint_normal, filter_linear_mipmap_anisotropic;
// R creases and hollows, G roughness, B beard area, A 1 - half the veins' height.
uniform sampler2D detail_texture : hint_default_white, filter_linear_mipmap;
uniform sampler2D pore_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_detail = false;
uniform float relief_strength : hint_range(0.0, 2.0) = 0.45;
uniform float pore_tiling = 70.0;
uniform float pore_strength : hint_range(0.0, 1.0) = 0.05;
uniform float occlusion : hint_range(0.0, 1.0) = 0.8;
uniform float scatter : hint_range(0.0, 1.0) = 0.22;

// Per player (SkinnedPuppet.set_face): complexion (a multiplier on the painted skin: sun,
// tan), how much beard shadow, and how sweaty.
instance uniform vec3 tone : source_color = vec3(0.9, 0.81, 0.74);
instance uniform float stubble = 0.35;
instance uniform float sweat = 0.3;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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
	// Veins show through the skin a little blue-grey.
	float vein = has_detail ? clamp((1.0 - d.a) * 2.0, 0.0, 1.0) : 0.0;
	base = mix(base, base * vec3(0.78, 0.8, 0.9), vein * 0.6);
	ALBEDO = base;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;

	vec3 relief = texture(relief_texture, UV).xyz * 2.0 - 1.0;
	vec3 pores = texture(pore_texture, UV * pore_tiling).xyz * 2.0 - 1.0;
	vec3 n = normalize(vec3(relief.xy * relief_strength + pores.xy * pore_strength, max(relief.z, 0.2)));
	NORMAL_MAP = n * 0.5 + 0.5;

	float rough = has_detail ? d.g : 0.55;
	ROUGHNESS = clamp(mix(rough, rough * 0.7, sweat) + (1.0 - ao) * 0.25 + beard * 0.15, 0.42, 0.9);
	// Skin reflects about 2.8% straight on (0.35 here; 0.5 is 4%), less in the creases.
	SPECULAR = 0.35 * mix(0.4, 1.0, ao);
	// A broad soft sheen, not glints: on the pores' bumps a sharp second highlight broke up
	// into white specks under the eyes.
	CLEARCOAT = (0.03 + 0.14 * sweat) * ao * (1.0 - beard);
	CLEARCOAT_ROUGHNESS = 0.55;
	SSS_STRENGTH = scatter;
	RIM = 0.18;
	RIM_TINT = 0.7;
}
