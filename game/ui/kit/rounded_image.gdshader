shader_type canvas_item;
// A picture in a card: its corners rounded, darker toward the foot (where the words go), and
// a light sweep across it when the card is lit.
uniform vec2 size = vec2(300.0, 200.0);
uniform float radius = 3.0;
uniform float cut = 16.0;
uniform float shade = 0.75;
uniform float lit = 0.0;
uniform vec4 tint : source_color = vec4(0.1, 0.3, 0.7, 1.0);

void fragment() {
	vec2 p = UV * size;
	vec2 q = abs(p - size * 0.5) - size * 0.5 + vec2(radius);
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	vec2 c = p - size * 0.5;
	float k = size.x * 0.5 + size.y * 0.5 - cut;
	d = max(d, max(-c.x - c.y - k, c.x + c.y - k) * 0.7071);
	vec4 col = texture(TEXTURE, UV);
	// Toward the foot the picture goes into the club or mode colour, then dark.
	float foot = smoothstep(0.35, 1.0, UV.y);
	col.rgb *= 1.0 - foot * shade * 0.85;
	col.rgb *= 0.82 + 0.26 * lit;
	float sweep = smoothstep(0.0, 0.08, UV.x + UV.y * 0.4 - (lit * 1.8 - 0.4)) * (1.0 - smoothstep(0.08, 0.2, UV.x + UV.y * 0.4 - (lit * 1.8 - 0.4)));
	col.rgb += vec3(0.25) * sweep * step(0.01, lit) * step(lit, 0.99);
	col.a *= 1.0 - smoothstep(-1.0, 0.0, d);
	COLOR = col;
}
