shader_type canvas_item;
// A panel, a button, a tab or an orb of the menus (docs/05 section 5, the third look): one
// rounded (or slanted, or round) shape with a top-to-bottom gradient, a border with a light
// line inside it, a glossy band over its upper part, an optional heading strip, fine diagonal
// stripes, and a soft shadow round it. Drawn on a rectangle `pad` pixels larger on every side
// than the shape (the shadow needs the room).

uniform vec2 size = vec2(200.0, 100.0);   // the shape, pixels
uniform float pad = 16.0;
uniform float radius = 10.0;
uniform float skew = 0.0;                 // how far the top leans right of the bottom, pixels
uniform vec4 top : source_color = vec4(0.14, 0.32, 0.62, 0.96);
uniform vec4 bottom : source_color = vec4(0.04, 0.1, 0.24, 0.97);
uniform vec4 border : source_color = vec4(0.75, 0.86, 1.0, 0.85);
uniform float border_width = 2.0;
uniform vec4 inner : source_color = vec4(1.0, 1.0, 1.0, 0.22);
uniform float gloss = 0.35;
uniform float head = 0.0;                 // height of the heading strip, pixels (0: none)
uniform vec4 head_top : source_color = vec4(0.24, 0.5, 0.9, 1.0);
uniform vec4 head_bottom : source_color = vec4(0.1, 0.26, 0.58, 1.0);
uniform float hatch = 0.0;
uniform float shadow = 0.45;
uniform float glow = 0.0;                 // a light round the shape (chosen, hovered)
uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float cut = 0.0;                  // top-left and bottom-right corners cut off, pixels
uniform float bar_height = 0.0;           // a line of `bar` along the foot (the chosen tab)
uniform vec4 bar : source_color = vec4(0.88, 0.13, 0.17, 1.0);

float shape(vec2 p) {
	vec2 c = p - size * 0.5;
	c.x += c.y / max(size.y, 1.0) * skew;
	vec2 half = size * 0.5 - vec2(abs(skew) * 0.5, 0.0);
	float r = min(radius, min(half.x, half.y));
	vec2 q = abs(c) - half + vec2(r);
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	if (cut > 0.0) {
		float k = half.x + half.y - cut;
		d = max(d, max(-c.x - c.y - k, c.x + c.y - k) * 0.7071);
	}
	return d;
}

void fragment() {
	vec2 full = size + vec2(pad * 2.0);
	vec2 p = UV * full - vec2(pad);
	float d = shape(p);
	float v = clamp(p.y / max(size.y, 1.0), 0.0, 1.0);
	vec4 col = mix(top, bottom, v);
	if (head > 0.0 && p.y < head) {
		col = mix(head_top, head_bottom, clamp(p.y / head, 0.0, 1.0));
		// A dark line under the strip, a light one below it.
		col.rgb *= 1.0 - 0.5 * smoothstep(head - 2.5, head - 1.0, p.y);
	} else if (head > 0.0) {
		col.rgb += vec3(0.1) * (1.0 - smoothstep(head, head + 1.5, p.y));
	}
	// Gloss: a lighter band over the upper part, ending in a shallow curve.
	float bend = 0.42 + 0.1 * sin(UV.x * 3.14159);
	float band = (1.0 - smoothstep(bend - 0.03, bend, v)) * (0.55 + 0.45 * (1.0 - v / bend));
	col.rgb += vec3(gloss * 0.3) * band;
	// Fine diagonal stripes.
	float stripes = step(0.5, fract((p.x + p.y) / 12.0));
	col.rgb += vec3(hatch * 0.05) * stripes;
	if (bar_height > 0.0 && p.y > size.y - bar_height) {
		col = bar;
	}
	// The border and the light line just inside it.
	float edge = smoothstep(-border_width - 1.0, -border_width, d);
	float line = smoothstep(-border_width - 2.5, -border_width - 1.5, d) * (1.0 - edge);
	col.rgb = mix(col.rgb, inner.rgb, line * inner.a);
	col = mix(col, vec4(border.rgb, max(col.a, border.a)), edge * border.a);
	float body = 1.0 - smoothstep(-1.0, 0.0, d);
	// Outside: the shadow (down a little) and the glow.
	float sd = shape(p - vec2(0.0, pad * 0.3));
	float dark = shadow * (1.0 - smoothstep(-2.0, pad * 0.9, sd));
	float light = glow * (1.0 - smoothstep(0.0, pad * 0.8, d));
	vec4 outside = vec4(mix(vec3(0.0), glow_color.rgb, clamp(light * 1.5, 0.0, 1.0)), max(dark * (1.0 - light), light * 0.9));
	COLOR = mix(outside, col, body);
}
