class_name ParkLighting
extends Node3D
## The light a game is played in (docs/13 S13-7): the sky, the sun and the stadium lights for
## a day game (14:00), one at dusk (17:00), a night game (18:30 start, under the lights) or one
## under a dome. The sun stands where it would over Seoul in the season, turned by the way the
## park faces, so it is behind the batter as parks are built to have it.

const TIMES: Array[StringName] = [&"day", &"dusk", &"night"]
## Seoul, and the sun's declination over a season (April to October, near its middle).
const LATITUDE := 37.5
const DECLINATION := 12.0
## Solar noon in Korean time at Seoul's longitude.
const SOLAR_NOON := 12.6
const HOURS := {&"day": 14.0, &"dusk": 17.0, &"night": 20.5}

var def: StadiumDef
var time: StringName = &"day"
var environment: Environment
var sun: DirectionalLight3D
## The towers' lights (night and dusk) or the dome's (always under a roof).
var lamps: Array[DirectionalLight3D] = []


func _init(park: StadiumDef = null, time_of_day: StringName = &"day") -> void:
	def = park if park != null else StadiumDef.standard()
	time = time_of_day if TIMES.has(time_of_day) else &"day"


## Under a dome it is always the dome's light.
func indoor() -> bool:
	return def.roof == &"dome"


func lights_on() -> bool:
	return indoor() or time != &"day"


## Where the sun is: elevation and compass bearing (degrees) at `hour`, Korean time.
static func sun_position(hour: float) -> Vector2:
	var h := deg_to_rad((hour - SOLAR_NOON) * 15.0)
	var lat := deg_to_rad(LATITUDE)
	var dec := deg_to_rad(DECLINATION)
	var elevation := asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h))
	var bearing := rad_to_deg(atan2(sin(h), cos(h) * sin(lat) - tan(dec) * cos(lat))) + 180.0
	return Vector2(rad_to_deg(elevation), fposmod(bearing, 360.0))


## The direction toward the sun in field coordinates (x first base, y centre field, z up).
func sun_direction() -> Vector3:
	var sp := sun_position(float(HOURS[time]))
	var rel := deg_to_rad(sp.y - def.orientation_deg)
	var el := deg_to_rad(sp.x)
	return Vector3(cos(el) * sin(rel), cos(el) * cos(rel), sin(el))


func _ready() -> void:
	environment = _environment()
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	add_child(_reflections())
	var dir := sun_direction()
	if not indoor() and dir.z > 0.0:
		sun = _light(dir, _sun_colour(), 1.35 if time == &"day" else 1.0, true)
		sun.light_angular_distance = 0.6
	if lights_on():
		# The towers (or the roof's banks) light the field from several sides at once: soft
		# shadows in more than one direction.
		var energy := 0.5 if indoor() else (0.42 if time == &"night" else 0.18)
		var i := 0
		for az: float in [150.0, -150.0, 60.0, -60.0]:
			var a := deg_to_rad(az)
			var from := Vector3(sin(a) * cos(deg_to_rad(48.0)), cos(a) * cos(deg_to_rad(48.0)), sin(deg_to_rad(48.0)))
			# One casts shadows (soft, in its own direction); the rest only light.
			var lamp := _light(from, Color(1.0, 0.97, 0.92), energy, i == 0 and sun == null)
			if lamp.shadow_enabled:
				lamp.shadow_opacity = 0.45
			lamps.append(lamp)
			i += 1


## What glossy things reflect (helmets, eyes, wet skin, the bat): the park itself, captured
## once from beside home plate at head height, over the whole field. Without it they mirror
## only the sky, which is what made the helmets look like plastic toys.
func _reflections() -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.name = "ParkReflections"
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(260.0, 60.0, 260.0)
	# The box covers the field; the capture point is at the plate, 1.6 m up.
	probe.position = Field.to_world(Vector3(0.0, 60.0, 20.0))
	probe.origin_offset = Field.to_world(Vector3(0.0, -60.0, 1.6 - 20.0)) - Field.to_world(Vector3.ZERO)
	probe.max_distance = 300.0
	probe.intensity = 1.0
	probe.enable_shadows = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	return probe


func _sun_colour() -> Color:
	return Color(1.0, 0.94, 0.84) if time == &"day" else Color(1.0, 0.72, 0.5)


func _light(toward: Vector3, colour: Color, energy: float, shadows: bool) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.light_color = colour
	light.light_energy = energy
	light.shadow_enabled = shadows
	light.shadow_blur = 1.4
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = 140.0
	add_child(light)
	var world := Field.to_world(toward) - Field.to_world(Vector3.ZERO)
	var up := Vector3.FORWARD if absf(world.normalized().y) > 0.99 else Vector3.UP
	light.look_at_from_position(Vector3.ZERO, -world, up)
	return light


func _environment() -> Environment:
	var sky_material := ProceduralSkyMaterial.new()
	var env := Environment.new()
	match time if not indoor() else &"dome":
		&"day":
			sky_material.sky_top_color = Color(0.16, 0.34, 0.68)
			sky_material.sky_horizon_color = Color(0.62, 0.74, 0.88)
			sky_material.ground_horizon_color = Color(0.5, 0.56, 0.6)
			sky_material.ground_bottom_color = Color(0.2, 0.22, 0.24)
			sky_material.energy_multiplier = 0.8
			# Less fill than before: the sunlit side and the shadow side of a face or a fold
			# differ the way they do in a broadcast picture.
			env.ambient_light_energy = 0.72
			env.ambient_light_color = Color(0.62, 0.56, 0.48)
			env.fog_light_color = Color(0.68, 0.76, 0.86)
		&"dusk":
			sky_material.sky_top_color = Color(0.18, 0.26, 0.5)
			sky_material.sky_horizon_color = Color(0.95, 0.6, 0.38)
			sky_material.ground_horizon_color = Color(0.55, 0.42, 0.36)
			sky_material.ground_bottom_color = Color(0.16, 0.14, 0.14)
			sky_material.energy_multiplier = 0.75
			env.ambient_light_energy = 0.75
			env.ambient_light_color = Color(0.62, 0.5, 0.42)
			env.fog_light_color = Color(0.85, 0.62, 0.48)
		&"night":
			sky_material.sky_top_color = Color(0.01, 0.015, 0.04)
			sky_material.sky_horizon_color = Color(0.1, 0.12, 0.18)
			sky_material.ground_horizon_color = Color(0.08, 0.08, 0.1)
			sky_material.ground_bottom_color = Color(0.02, 0.02, 0.03)
			sky_material.energy_multiplier = 0.6
			env.ambient_light_energy = 0.7
			env.ambient_light_color = Color(0.4, 0.42, 0.46)
			env.fog_light_color = Color(0.16, 0.17, 0.22)
		&"dome":
			sky_material.sky_top_color = Color(0.35, 0.36, 0.38)
			sky_material.sky_horizon_color = Color(0.3, 0.31, 0.33)
			sky_material.ground_horizon_color = Color(0.3, 0.31, 0.33)
			sky_material.ground_bottom_color = Color(0.2, 0.2, 0.22)
			sky_material.energy_multiplier = 0.5
			env.ambient_light_energy = 0.95
			env.ambient_light_color = Color(0.5, 0.5, 0.52)
			env.fog_light_color = Color(0.4, 0.41, 0.44)
	sky_material.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Shadows lit by the blue sky alone look cold on skin (docs/13 S11-3): part of the ambient
	# light is the warm light bounced off the grass, dirt and stands.
	env.ambient_light_sky_contribution = 0.6
	# AgX keeps skin and bright colours from going orange and flat the way ACES does, and
	# the picture is not pushed (the reference is muted, not saturated).
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.12 if time == &"day" or indoor() else 1.3
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	# Fine contact shade (under the cap brim, in the folds, between the arm and the body), a
	# little of it in sunlight too.
	env.ssao_detail = 1.2
	env.ssao_light_affect = 0.12
	env.glow_enabled = true
	env.glow_intensity = 0.35 if time == &"day" else 0.55
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_density = 0.0009 if not indoor() else 0.0004
	env.fog_sun_scatter = 0.15
	env.fog_sky_affect = 0.2
	env.adjustment_enabled = true
	# A little more contrast and a little less colour: the reference pictures are muted and
	# deep, not bright.
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 0.9
	return env
