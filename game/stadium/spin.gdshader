shader_type spatial;
// Something that turns about its own centre (a big wheel, a wind turbine's rotor): the mesh
// is built about the hub and turned here, `speed` radians a second about `axis` (world).

uniform vec3 colour : source_color = vec3(0.9);
uniform vec3 axis = vec3(0.0, 0.0, 1.0);
uniform float speed = 0.1;
uniform float glow = 0.0;

vec3 turn(vec3 v, vec3 k, float a) {
	return v * cos(a) + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - cos(a));
}

void vertex() {
	vec3 k = normalize(axis);
	VERTEX = turn(VERTEX, k, TIME * speed);
	NORMAL = turn(NORMAL, k, TIME * speed);
}

void fragment() {
	ALBEDO = colour;
	ROUGHNESS = 0.5;
	METALLIC = 0.3;
	EMISSION = colour * glow;
}
