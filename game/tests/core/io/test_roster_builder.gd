extends GutTest
## Records into ratings (docs/07 4.3, docs/13 S17): the builder runs the engine's formula
## backwards, so a man's rating gives back his rate; a small sample is pulled to the average;
## a club built from tables has its men with their numbers, positions and ratings.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func test_a_rating_gives_back_the_rate_it_came_from() -> void:
	var env := F.env()
	var mu := 0.2
	for rate: float in [0.1, 0.2, 0.35]:
		var r := RosterBuilder.invert(rate, mu, float(env.batter_k["K"]["contact"]))
		var back := mu * exp(float(env.batter_k["K"]["contact"]) * (r - 50.0) / 15.0)
		assert_almost_eq(back, rate, 1e-6)
	assert_lt(RosterBuilder.invert(0.3, 0.2, -0.28), 50.0, "more strikeouts: less contact")
	assert_gt(RosterBuilder.invert(0.15, 0.09, 0.3), 50.0, "more walks: a better eye")
	# Ten plate appearances say little; six hundred say most.
	assert_almost_eq(RosterBuilder.regress(4.0, 10.0, 0.2, 100.0), (4.0 + 20.0) / 110.0, 1e-9)
	assert_gt(RosterBuilder.regress(240.0, 600.0, 0.2, 100.0), 0.37)


func test_a_club_is_built_from_its_tables() -> void:
	var teams := [{"id": "x1", "name": "테스트 베어스", "short": "테스트", "primary": "#102040"}]
	var players := [
		{"id": "h1", "team": "x1", "name": "홍길동", "number": "7", "born": "1998", "bats": "L", "throws": "R", "positions": "SS/2B", "registered": "1"},
		{"id": "h2", "team": "x1", "name": "김둘", "number": "33", "born": "1993", "bats": "R", "throws": "R", "positions": "1B", "registered": "1"},
		{"id": "p1", "team": "x1", "name": "박셋", "number": "18", "born": "1995", "bats": "R", "throws": "L", "positions": "SP", "registered": "1"},
	]
	var batting := [
		{"id": "h1", "pa": "600", "h": "170", "2b": "30", "3b": "8", "hr": "5", "bb": "40", "hbp": "5", "so": "70", "sb": "30", "cs": "8"},
		{"id": "h2", "pa": "600", "h": "150", "2b": "30", "3b": "1", "hr": "35", "bb": "80", "hbp": "5", "so": "150", "sb": "1", "cs": "1"},
	]
	var pitching := [{"id": "p1", "g": "30", "gs": "30", "outs": "540", "bf": "760", "so": "190", "bb": "40", "hr": "15"}]
	var built := RosterBuilder.build(teams, players, batting, pitching, F.env(), F.catalog(), RosterIO.load_names())
	assert_eq(built.size(), 1)
	var t := built[0]
	assert_eq(t.name, "테스트 베어스")
	var h1 := t.player("h1")
	var h2 := t.player("h2")
	assert_eq(h1.name, "홍길동")
	assert_eq(h1.number, 7)
	assert_eq(h1.bats, &"L")
	assert_eq(h1.primary_position(), Position.Kind.SS)
	assert_gt(h1.batting.contact(), h2.batting.contact(), "fewer strikeouts")
	assert_gt(h2.batting.power(), h1.batting.power() + 15.0, "35 home runs against 5")
	assert_gt(h2.batting.eye, h1.batting.eye, "twice the walks")
	assert_gt(h1.batting.speed, h2.batting.speed, "triples and steals")
	var p1 := t.player("p1")
	assert_true(p1.is_pitcher())
	assert_eq(p1.role(), &"SP")
	assert_gte(p1.pitching.stamina, 55.0, "six innings a start")
	assert_true(t.is_registered("h1"))
