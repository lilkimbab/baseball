class_name PhysicsConfig
extends RefCounted
## Physical constants for the ball, air, bat contact and playing surfaces.
## Values live in data/physics.json; PhysicsConfigIO fills this object.

var ball_mass := 0.0
var ball_radius := 0.0
var air_density := 0.0
var gravity := 0.0

var cd0 := 0.0
var cd_per_1000_rpm := 0.0
var cl0 := 0.0
var cl1 := 0.0
var cl2 := 0.0
var spin_decay_tau := 0.0
## Batted balls (docs/04 section 4.2): Nathan's fit to Statcast.
var bat_cd0 := 0.0
var bat_cd_per_mph := 0.0
var bat_cd_spin := 0.0
var bat_cl_a := 0.0
var bat_cl_b := 0.0

var bat_radius := 0.0
var efficiency_max := 0.0
var efficiency_min := 0.0
var sweet_spot_from_tip := 0.0
var sweet_spot_width := 0.0
var friction_transfer := 0.0
var spin_memory := 0.0

var surfaces: Dictionary[StringName, SurfaceParams] = {}

## rho * A / (2 m): multiplies Cd |v| v and Cl |v|^2. Set by finalize().
var aero_k := 0.0

var _fallback_surface := SurfaceParams.new()


## A separate copy (for a different day's air, say).
func duplicate_config() -> PhysicsConfig:
	var c := PhysicsConfig.new()
	for prop: Dictionary in get_property_list():
		var name: String = prop["name"]
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			c.set(name, get(name))
	return c


## Computes derived values. Call once after the fields are filled.
func finalize() -> void:
	aero_k = air_density * PI * ball_radius * ball_radius / (2.0 * ball_mass)


func surface(surface_name: StringName) -> SurfaceParams:
	var found: SurfaceParams = surfaces.get(surface_name)
	if found == null:
		push_error("PhysicsConfig: unknown surface '%s'" % surface_name)
		return _fallback_surface
	return found


## Collision efficiency of the bat at a point `along_bat` metres from the tip (docs/04, 7.2).
func bat_efficiency(along_bat: float) -> float:
	var off := (along_bat - sweet_spot_from_tip) / sweet_spot_width
	return clampf(efficiency_max * (1.0 - off * off), efficiency_min, efficiency_max)
