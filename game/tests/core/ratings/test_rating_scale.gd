extends GutTest
## How high a rating goes: made and trained within 99, a career's own growth on to 130 at a
## steep price, the engine's effects carried on gently past 99, shown one for one past 99 in
## the diamond tier, and the tiers' colours from black to diamond.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _career() -> CareerPlayer:
	var s := PlayerCreator.Spec.new()
	s.position = "2B"
	s.type_id = "contact"
	return PlayerCreator.create(s, CareerIO.load_default(), F.catalog())


func test_the_effects_go_on_gently_past_99() -> void:
	assert_eq(RatingScale.norm(0.0), 0.0)
	assert_almost_eq(RatingScale.norm(49.5), 0.5, 1e-6)
	assert_almost_eq(RatingScale.norm(99.0), 1.0, 1e-6, "as it always was up to 99")
	assert_almost_eq(RatingScale.norm(130.0), 1.0 + 31.0 / 99.0 * 0.5, 1e-6)
	assert_eq(RatingScale.norm(160.0), RatingScale.norm(130.0), "no further than the top")


func test_shown_past_99_one_for_one_to_130() -> void:
	assert_almost_eq(UiTheme.shown(99.0), 99.0, 1e-6)
	assert_lt(UiTheme.shown(98.0), 99.0)
	assert_almost_eq(UiTheme.shown(112.0), 112.0, 1e-6)
	assert_almost_eq(UiTheme.shown(130.0), 130.0, 1e-6)
	assert_almost_eq(UiTheme.shown(150.0), 130.0, 1e-6)


func test_the_tiers_run_from_black_to_diamond() -> void:
	var raw_for := func(shown_value: float) -> float:
		# (The engine's value that shows as `shown_value`.)
		return shown_value - 18.0 if shown_value <= 83.0 else (65.0 + (shown_value - 83.0) * 34.0 / 16.0 if shown_value <= 99.0 else shown_value)
	var seen: Array[Color] = []
	for shown_value: float in [50.0, 65.0, 75.0, 85.0, 95.0, 115.0]:
		var c := UiTheme.rating_color(raw_for.call(shown_value))
		assert_false(seen.has(c), "a tier of its own at %d" % shown_value)
		seen.append(c)
	assert_lt(seen[0].get_luminance(), 0.2, "the lowest is black")
	assert_gt(UiTheme.ink_edge(seen[0]).a, 0.0, "and edged so it can be read")
	assert_eq(UiTheme.ink_edge(seen[3]).a, 0.0)
	assert_gt(seen[1].r, seen[1].g, "60s red")
	assert_gt(seen[2].g, seen[2].r, "70s green")
	assert_gt(seen[3].b, seen[3].r, "80s blue")
	assert_gt(seen[4].r, seen[4].b, "90s gold")
	assert_gt(seen[5].b, 0.9, "past 99 diamond")


func test_training_stops_at_99_and_a_career_goes_on_to_130() -> void:
	var c := _career()
	var p := c.player
	p.batting.contact_r = 98.0
	p.batting.contact_l = 98.0
	Training.grow(p, PackedStringArray(["contact"]), 5.0)
	assert_eq(p.batting.contact_r, 99.0, "a club's training keeps to 99")
	var rules := CareerIO.load_default()
	var curve := func(v: float) -> float: return rules.cost_base * pow(1.0 + (v - 40.0) / 20.0, 2.0) * (1.0 - rules.type_discount)
	assert_almost_eq(Growth.cost(c, "contact", rules), curve.call(99.0) * pow(2.0, 0.1), 1e-3)
	p.batting.contact_r = 109.0
	p.batting.contact_l = 109.0
	assert_almost_eq(Growth.cost(c, "contact", rules), curve.call(109.0) * pow(2.0, 1.1), 1e-3, "past 99 the price doubles every ten")
	p.batting.contact_r = 99.0
	p.batting.contact_l = 99.0
	c.gp["batting"] = 1e9
	assert_true(Growth.raise(c, "contact", rules), "his own work takes him past 99")
	assert_almost_eq(p.batting.contact_r, 100.0, 1e-6)
	p.batting.contact_r = 130.0
	p.batting.contact_l = 130.0
	assert_false(Growth.raise(c, "contact", rules), "but not past 130")
	# A day's form does not cut a 120 down to 99.
	p.batting.power_r = 120.0
	var today := p.with_form(1.0, {})
	assert_almost_eq(today.batting.power_r, 120.0, 1e-6)


func test_no_one_is_made_past_99() -> void:
	var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), 7)
	for i: int in 10:
		var t := gen.team(i, 70.0)
		for p: Player in t.players:
			assert_lte(p.batting.contact_r, 99.0)
			assert_lte(p.batting.power_r, 99.0)
			assert_lte(p.fielding.range, 99.0)
			if p.pitching != null:
				assert_lte(p.pitching.control, 99.0)
