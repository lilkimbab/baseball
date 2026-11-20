extends GutTest


func test_default_config_loads_every_section() -> void:
	var cfg := PhysicsConfigIO.load_default()
	assert_almost_eq(cfg.ball_mass, 0.145, 0.0001)
	assert_almost_eq(cfg.ball_radius, 0.0366, 0.0001)
	assert_almost_eq(cfg.gravity, 9.81, 0.001)
	assert_gt(cfg.cd0, 0.0)
	assert_gt(cfg.cl2, 0.0)
	assert_gt(cfg.efficiency_max, 0.0)
	assert_almost_eq(cfg.aero_k, 0.01742, 0.0002, "rho A / 2m")


func test_all_surfaces_used_by_the_field_are_defined() -> void:
	var cfg := PhysicsConfigIO.load_default()
	for surface_name: StringName in [&"grass", &"dirt", &"turf", &"track", &"wall_pad", &"wall_hard", &"net", &"base"] as Array[StringName]:
		assert_true(cfg.surfaces.has(surface_name), "missing surface %s" % surface_name)
	assert_true(cfg.surface(&"grass").is_ground)
	assert_false(cfg.surface(&"wall_pad").is_ground)


func test_restitution_and_friction_are_physical() -> void:
	var cfg := PhysicsConfigIO.load_default()
	for surface_name: StringName in cfg.surfaces:
		var s := cfg.surface(surface_name)
		assert_between(s.restitution, 0.0, 1.0, "%s restitution" % surface_name)
		assert_between(s.friction, 0.0, 1.5, "%s friction" % surface_name)


func test_load_default_returns_the_same_object() -> void:
	assert_same(PhysicsConfigIO.load_default(), PhysicsConfigIO.load_default())
