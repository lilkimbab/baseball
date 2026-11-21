extends GutTest
## The veins and tendons of the arms (match/skin_veins.gd, match/skin.gdshader; the user: "the
## veins on the arms are too artificial ... model them as in life").


func test_the_table_has_a_row_for_every_vein() -> void:
	var image := SkinVeins.table().get_image()
	assert_eq(image.get_width(), SkinVeins.COLUMNS)
	assert_gte(image.get_height(), SkinVeins.ARM.size() + SkinVeins.HAND.size())
	assert_eq(SkinVeins.ARM.size(), 7, "the shader counts seven arm veins")
	assert_eq(SkinVeins.HAND.size(), 5, "and five on the back of the hand")


func test_veins_are_a_few_millimetres_wide_and_run_smoothly() -> void:
	for vein: Dictionary in SkinVeins.ARM:
		assert_between(float(vein["half"]), 0.0015, 0.0035, "%s: half-width (m)" % vein["name"])
		var path: Array = vein["path"]
		var from := float(path[0][0])
		var to := float(path[path.size() - 1][0])
		var last := SkinVeins.sample(vein, from).x
		for i: int in range(1, 101):
			var here := SkinVeins.sample(vein, lerpf(from, to, i / 100.0)).x
			assert_lt(absf(here - last), 0.12, "%s does not jump" % vein["name"])
			last = here
		assert_eq(SkinVeins.sample(vein, from - 0.2).y, 0.0, "%s is not drawn before it starts" % vein["name"])


func test_the_long_veins_run_from_the_wrist_past_the_elbow() -> void:
	var cephalic := SkinVeins.ARM[0]
	var basilic := SkinVeins.ARM[1]
	assert_gt(SkinVeins.sample(cephalic, 0.9).y, 0.3, "the cephalic shows at the wrist")
	assert_gt(SkinVeins.sample(cephalic, 0.05).y, 0.3, "and at the elbow")
	assert_gt(SkinVeins.sample(cephalic, -0.3).y, 0.1, "and on up the biceps")
	# They start on the back of the wrist either side and wind to the inner side of the elbow.
	assert_gt(SkinVeins.sample(cephalic, 1.0).x, SkinVeins.sample(cephalic, 0.35).x, "the cephalic winds forward")
	assert_gt(SkinVeins.sample(basilic, 0.05).x, SkinVeins.sample(basilic, 1.0).x + 1.0, "the basilic winds round the back of the forearm")
	# The cubital vein joins the two across the hollow of the elbow.
	var cubital := SkinVeins.ARM[2]
	assert_almost_eq(SkinVeins.sample(cubital, 0.19).x, SkinVeins.sample(cephalic, 0.19).x, 0.2, "it leaves the cephalic")


func test_the_model_carries_arm_coordinates_and_the_skin_reads_them() -> void:
	var puppet := SkinnedPuppet.new()
	add_child_autofree(puppet)
	puppet.repaint()
	var body := puppet.find_child("Body", true, false) as MeshInstance3D
	var arrays := body.mesh.surface_get_arrays(0)
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_gt(colours.size(), 0, "vertex colours (run ./dev model)")
	var on_arm := 0
	for c: Color in colours:
		if c.a > 0.5:
			on_arm += 1
	assert_gt(on_arm, 200, "the arms' vertices are marked")
	assert_lt(on_arm, colours.size() / 2, "and only the arms'")
	var skin := body.get_surface_override_material(0) as ShaderMaterial
	assert_true(bool(skin.get_shader_parameter(&"has_limbs")), "the skin shader draws from them")
	assert_not_null(skin.get_shader_parameter(&"vein_table"))


func test_lean_arms_show_their_veins_more_than_heavy_ones() -> void:
	var shown := {}
	for build: StringName in [&"lean", &"heavy"]:
		var total := 0.0
		for i: int in 12:
			var puppet := SkinnedPuppet.new()
			puppet.build = build
			add_child_autofree(puppet)
			total += puppet.set_face("p%d" % i)["veins"]
		shown[build] = total / 12.0
	assert_gt(shown[&"lean"], shown[&"heavy"] + 0.3, "lean %.2f, heavy %.2f" % [shown[&"lean"], shown[&"heavy"]])
