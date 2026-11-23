extends GutTest
## Records into ratings (docs/06 4.3): the builder runs the engine's formula
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


func test_a_small_sample_is_pulled_toward_men_who_played_as_much() -> void:
	# Regulars strike out 15% of the time, reserves 30%: a reserve with a handful of plate
	# appearances is taken for a reserve, not for an average hitter.
	var batting: Array = []
	for i: int in 20:
		batting.append({"id": "r%d" % i, "pa": "600", "h": "160", "2b": "30", "3b": "2", "hr": "20", "bb": "60", "so": "90"})
	for i: int in 40:
		batting.append({"id": "b%d" % i, "pa": "40", "h": "8", "2b": "1", "3b": "0", "hr": "0", "bb": "2", "so": "12"})
	var groups := RosterBuilder.hitter_tiers(batting)
	assert_eq(groups.size(), 2, "two groups have enough plate appearances to speak")
	var mu := RosterBuilder.league_rates(batting)
	var reserve := RosterBuilder.like(groups, 40.0, mu)
	var regular := RosterBuilder.like(groups, 600.0, mu)
	assert_almost_eq(float(reserve["K"]), 0.3, 1e-6)
	assert_almost_eq(float(regular["K"]), 0.15, 1e-6)
	assert_between(float(RosterBuilder.like(groups, 320.0, mu)["K"]), 0.16, 0.29, "in between, in between")
	assert_lt(float(reserve["HR"]), float(regular["HR"]))
	var k := RosterBuilder.coefficients(F.env())["batter"] as Dictionary
	var few := {"id": "x", "pa": "10", "h": "2", "2b": "0", "3b": "0", "hr": "0", "bb": "1", "so": "3"}
	var as_reserve := RosterBuilder.hitter_ratings(few, mu, k, reserve)
	var as_average := RosterBuilder.hitter_ratings(few, mu, k)
	assert_lt(float(as_reserve["contact"]), float(as_average["contact"]) - 3.0, "ten plate appearances: he is taken for a reserve")
	assert_lt(float(as_reserve["power"]), float(as_average["power"]))
	# A full season speaks for itself either way.
	var full := {"id": "y", "pa": "600", "h": "160", "2b": "30", "3b": "2", "hr": "20", "bb": "60", "so": "90"}
	assert_almost_eq(float(RosterBuilder.hitter_ratings(full, mu, k, regular)["contact"]), float(RosterBuilder.hitter_ratings(full, mu, k)["contact"]), 2.5)
	assert_eq(RosterBuilder.like([], 100.0, mu), mu, "no groups: the league's")


func test_a_park_is_taken_out_of_a_record_and_put_back_in_a_game() -> void:
	# Two clubs: one plays in a park that halves home runs, the other in a neutral one.
	var effects := RosterBuilder.park_effects([{"id": "small", "pf_hr": 0.5, "pf_h": 1.0}, {"id": "plain", "pf_hr": 1.0, "pf_h": 1.0}])
	assert_almost_eq(float(effects["small"]["HR"]), 0.75, 1e-6, "half the games at home, half away")
	var row := {"id": "x", "pa": "600", "h": "150", "2b": "30", "3b": "3", "hr": "15", "bb": "60", "so": "100"}
	var n := RosterBuilder.neutral(row, effects["small"])
	assert_almost_eq(float(n["hr"]), 20.0, 1e-6, "15 home runs in a park that takes a quarter of them: 20 anywhere")
	assert_almost_eq(float(n["h"]), 155.0, 1e-6, "the hits with the home runs put back")
	assert_eq(RosterBuilder.park_effects([{"id": "a"}]), {}, "no parks in the tables: none")
	# The resolver: a park that doubles home runs doubles their chance.
	var pack := SeasonPack.new()
	pack.parks = {"home": {"park": "작은 구장", "HR": 2.0, "H": 1.0}}
	assert_eq(pack.park_of("home"), {"HR": 2.0, "1B": 1.0, "2B": 1.0, "3B": 1.0})
	assert_eq(pack.park_of("elsewhere"), {})


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
