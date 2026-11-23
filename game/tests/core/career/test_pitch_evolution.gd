extends GutTest
## Pitches that evolve and pitches learned.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _pitcher(type_id: String) -> CareerPlayer:
	var s := PlayerCreator.Spec.new()
	s.position = "SP"
	s.type_id = type_id
	return PlayerCreator.create(s, CareerIO.load_default(), F.catalog())


func test_a_slider_thrown_enough_with_movement_becomes_a_sweeper() -> void:
	var r := CareerIO.load_default()
	# (The power arm starts with his fastball and a slider.)
	var c := _pitcher("power_arm")
	var slider: ArsenalPitch = null
	for a: ArsenalPitch in c.player.pitching.arsenal:
		if a.type == &"slider":
			slider = a
	assert_not_null(slider)
	# A slider with a big break, from an arm under the hard slider's line (147 km/h: a harder
	# thrower's slider grows into a hard slider instead).
	slider.movement = 60.0
	for a: ArsenalPitch in c.player.pitching.arsenal:
		if a.type == &"four_seam":
			a.velo_avg = 142.0
	c.pitch_uses[&"slider"] = 100
	assert_true(PitchEvolution.check(c, r, F.catalog()).is_empty(), "not thrown enough yet")
	c.pitch_uses[&"slider"] = 260
	var speed := slider.velo_avg
	var changes := PitchEvolution.check(c, r, F.catalog())
	assert_eq(changes, PackedStringArray(["슬라이더 → 스위퍼"]))
	assert_eq(slider.type, &"sweeper")
	assert_almost_eq(slider.velo_avg, speed - 4.0, 0.01, "a sweeper is a little slower")


func test_a_hard_thrower_s_slider_becomes_a_hard_slider_and_his_fastball_rises() -> void:
	var r := CareerIO.load_default()
	var c := _pitcher("power_arm")
	c.player.pitching.arsenal[0].velo_avg = 150.0
	c.pitch_uses[&"slider"] = 300
	c.pitch_uses[&"four_seam"] = 500
	var changes := PitchEvolution.check(c, r, F.catalog())
	assert_true(changes.has("포심 패스트볼 → 라이징 패스트볼"))
	assert_true(changes.has("슬라이더 → 고속 슬라이더"))


func test_learning_a_pitch_costs_points_and_stops_at_six() -> void:
	var r := CareerIO.load_default()
	var c := _pitcher("power_arm")
	assert_false(PitchEvolution.learn(c, &"changeup", r, F.catalog()), "no points")
	c.gp["pitching"] = 2000.0
	assert_true(PitchEvolution.learn(c, &"changeup", r, F.catalog()))
	assert_eq(c.player.pitching.arsenal.size(), 3)
	var usage := 0.0
	for a: ArsenalPitch in c.player.pitching.arsenal:
		usage += a.usage
	assert_almost_eq(usage, 1.0, 0.02)
	assert_false(PitchEvolution.learnable(c, r).has(&"changeup"), "he has it now")
	var guard := 0
	while not PitchEvolution.learnable(c, r).is_empty() and guard < 10:
		assert_true(PitchEvolution.learn(c, PitchEvolution.learnable(c, r)[0], r, F.catalog()))
		guard += 1
	assert_eq(c.player.pitching.arsenal.size(), r.max_pitches)


func test_a_game_s_pitches_count_toward_proficiency() -> void:
	# (The finesse pitcher starts with his fastball and a curve.)
	var c := _pitcher("finesse")
	var curve_share := 0.0
	var fastball_share := 0.0
	for a: ArsenalPitch in c.player.pitching.arsenal:
		if a.type == &"curve":
			curve_share = a.usage
		if a.type == &"four_seam":
			fastball_share = a.usage
	PitchEvolution.note_game(c, 100, {} as Dictionary[StringName, int])
	assert_eq(int(c.pitch_uses[&"four_seam"]), roundi(100 * fastball_share))
	var seen: Dictionary[StringName, int] = {&"curve": 12}
	PitchEvolution.note_game(c, 30, seen)
	assert_eq(int(c.pitch_uses[&"curve"]), roundi(100 * curve_share) + 12)
