extends GutTest
## The crowd (docs/13 S14): in the seats the park lays out, three levels of detail, the club
## colours in the cheering sections, and only the batting side's section on its feet.

const MATCH := preload("res://match/match.tscn")


func _park(id: String) -> StadiumBuilder:
	var park := StadiumBuilder.new(StadiumIO.load_park(id))
	add_child_autofree(park)
	return park


func test_the_parks_lay_out_their_seats_in_zones() -> void:
	var park := _park("grand_park")
	assert_gt(park.seat_pos.size(), 20000, "a big park seats over twenty thousand")
	var per_zone := {}
	for z: int in park.seat_zone:
		per_zone[z] = int(per_zone.get(z, 0)) + 1
	for zone: int in [Crowd.Zone.BEHIND_HOME, Crowd.Zone.FIRST, Crowd.Zone.THIRD, Crowd.Zone.OUTFIELD, Crowd.Zone.UPPER, Crowd.Zone.HOME_CHEER, Crowd.Zone.AWAY_CHEER]:
		assert_gt(int(per_zone.get(zone, 0)), 200, "zone %d has seats" % zone)
	# The home cheering section is on the first-base side.
	for i: int in park.seat_pos.size():
		if park.seat_zone[i] == Crowd.Zone.HOME_CHEER:
			assert_gt(Field.to_field(park.seat_pos[i]).x, 0.0)
			break


func test_twenty_thousand_are_drawn_at_full_density_in_three_levels() -> void:
	var park := _park("grand_park")
	var crowd := Crowd.new(park)
	crowd.fill = 1.0
	crowd.density = 1.0
	add_child_autofree(crowd)
	var total := crowd.counts.x + crowd.counts.y + crowd.counts.z
	assert_gt(total, 20000)
	assert_between(crowd.counts.x, 300, 1500, "near: the rows behind home and over the dugouts")
	assert_between(crowd.counts.y, 2500, 9000, "mid: the rest of the lower bowl")
	assert_gt(crowd.counts.z, crowd.counts.y, "far: the most of them")
	var thin := Crowd.new(park)
	thin.fill = 1.0
	thin.density = 0.3
	add_child_autofree(thin)
	assert_almost_eq(float(thin.counts.x + thin.counts.y + thin.counts.z) / total, 0.3, 0.03, "the low quality setting draws three in ten")


func test_the_cheering_sections_wear_their_club_s_colours() -> void:
	# (The test renderer keeps no per-instance data, so the choice itself is checked.)
	var crowd := Crowd.new(null)
	crowd.home_colours = [Color(0.9, 0.1, 0.1)] as Array[Color]
	crowd.away_colours = [Color(0.1, 0.1, 0.9)] as Array[Color]
	var rng := Rng.new(4)
	var share := func(zone: int, colour: Color) -> float:
		var n := 0
		for i: int in 2000:
			if crowd._shirt(zone, rng) == colour:
				n += 1
		return n / 2000.0
	assert_gt(share.call(Crowd.Zone.HOME_CHEER, Color(0.9, 0.1, 0.1)), 0.75, "the home section in home colours")
	assert_lt(share.call(Crowd.Zone.HOME_CHEER, Color(0.1, 0.1, 0.9)), 0.06)
	assert_gt(share.call(Crowd.Zone.AWAY_CHEER, Color(0.1, 0.1, 0.9)), 0.7, "the visitors' in theirs")
	assert_between(share.call(Crowd.Zone.UPPER, Color(0.9, 0.1, 0.1)), 0.15, 0.35, "a mix elsewhere")
	crowd.free()


func test_only_the_batting_side_s_cheering_section_stands() -> void:
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = -1
	scene.innings = 3
	scene.seed_value = 17
	scene.use_motion = false
	add_child_autofree(scene)
	var checked := [false, false]
	var ticks := 0
	while not (checked[0] and checked[1]) and ticks < 60000 and not scene.game.over:
		scene.step(1.0 / 120.0)
		scene.refresh(1.0 / 120.0)
		ticks += 1
		if scene.state != DuelScene.State.PRE_PITCH or scene._cheer_left > 0.0:
			continue
		var home_bats := scene.game.batting() == GameState.HOME
		var mine := Crowd.Zone.HOME_CHEER if home_bats else Crowd.Zone.AWAY_CHEER
		var theirs := Crowd.Zone.AWAY_CHEER if home_bats else Crowd.Zone.HOME_CHEER
		assert_eq(scene.crowd.zone_state(mine), Crowd.State.STANDING, "the batting side's section is up")
		assert_true(scene.crowd.zone_state(theirs) in [Crowd.State.SEATED, Crowd.State.CLAPPING], "the other is down")
		assert_eq(scene.crowd.zone_state(Crowd.Zone.BEHIND_HOME), Crowd.State.SEATED)
		checked[1 if home_bats else 0] = true
	assert_true(checked[0] and checked[1], "seen with each side at bat")
