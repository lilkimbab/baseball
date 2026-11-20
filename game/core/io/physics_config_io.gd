class_name PhysicsConfigIO
extends RefCounted
## Loads PhysicsConfig from data/physics.json.

const DEFAULT_PATH := "res://data/physics.json"

static var _default: PhysicsConfig


## The shared default configuration, loaded once.
static func load_default() -> PhysicsConfig:
	if _default == null:
		_default = load_file(DEFAULT_PATH)
	return _default


static func load_file(path: String) -> PhysicsConfig:
	return from_dict(JsonIO.read_object(path))


static func from_dict(d: Dictionary) -> PhysicsConfig:
	var cfg := PhysicsConfig.new()
	var ball: Dictionary = d.get("ball", {})
	var air: Dictionary = d.get("air", {})
	var aero: Dictionary = d.get("aero", {})
	var contact: Dictionary = d.get("contact", {})
	var surfaces: Dictionary = d.get("surfaces", {})

	cfg.ball_mass = ball.get("mass", 0.0)
	cfg.ball_radius = ball.get("radius", 0.0)
	cfg.air_density = air.get("density", 0.0)
	cfg.gravity = air.get("gravity", 0.0)

	cfg.cd0 = aero.get("cd0", 0.0)
	cfg.cd_per_1000_rpm = aero.get("cd_per_1000_rpm", 0.0)
	cfg.cl0 = aero.get("cl0", 0.0)
	cfg.cl1 = aero.get("cl1", 0.0)
	cfg.cl2 = aero.get("cl2", 0.0)
	cfg.spin_decay_tau = aero.get("spin_decay_tau", 0.0)
	var batted: Dictionary = d.get("batted_aero", {})
	cfg.bat_cd0 = batted.get("cd0", cfg.cd0)
	cfg.bat_cd_per_mph = batted.get("cd_per_mph_below_100", 0.0)
	cfg.bat_cd_spin = batted.get("cd_spin", 0.0)
	cfg.bat_cl_a = batted.get("cl_a", 0.0)
	cfg.bat_cl_b = batted.get("cl_b", 0.0)

	cfg.bat_radius = contact.get("bat_radius", 0.0)
	cfg.efficiency_max = contact.get("efficiency_max", 0.0)
	cfg.efficiency_min = contact.get("efficiency_min", 0.0)
	cfg.sweet_spot_from_tip = contact.get("sweet_spot_from_tip", 0.0)
	cfg.sweet_spot_width = contact.get("sweet_spot_width", 0.0)
	cfg.friction_transfer = contact.get("friction_transfer", 0.0)
	cfg.spin_memory = contact.get("spin_memory", 0.0)

	for key: String in surfaces:
		var src: Dictionary = surfaces[key]
		var s := SurfaceParams.new()
		s.restitution = src.get("restitution", 0.0)
		s.friction = src.get("friction", 0.0)
		s.roll_decel = src.get("roll_decel", 0.0)
		s.roll_drag = src.get("roll_drag", 0.0)
		s.is_ground = src.get("ground", true)
		cfg.surfaces[StringName(key)] = s

	cfg.finalize()
	return cfg
