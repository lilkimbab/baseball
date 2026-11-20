extends GutTest
## Game ratings, medals and reward boxes (docs/13 S8-7).

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _career(position: String) -> CareerPlayer:
	var s := PlayerCreator.Spec.new()
	s.position = position
	s.type_id = CareerIO.load_default().types_for(position)[0].id
	return PlayerCreator.create(s, CareerIO.load_default(), F.catalog())


func test_a_big_game_rates_high_and_a_bad_one_low() -> void:
	var r := CareerIO.load_default()
	var big := BattingLine.new()
	big.pa = 5
	big.ab = 4
	big.hits = 3
	big.home_runs = 2
	big.rbi = 4
	big.runs = 2
	big.walks = 1
	var bad := BattingLine.new()
	bad.pa = 4
	bad.ab = 4
	bad.strikeouts = 3
	var high := GameRating.rate(big, null, 2, 0, true, 1, r)
	var low := GameRating.rate(bad, null, 0, 1, false, 0, r)
	assert_gte(high, 9.0)
	assert_lt(low, 5.0)
	assert_eq(GameRating.medal(high, r), 3, "gold")
	assert_eq(GameRating.medal(low, r), 0)
	assert_eq(GameRating.medal(6.5, r), 1, "bronze")
	var gem := PitchingLine.new()
	gem.outs = 24
	gem.strikeouts = 9
	gem.hits = 3
	gem.wins = 1
	assert_gte(GameRating.rate(null, gem, 1, 0, true, 0, r), 9.0)


func test_a_reward_box_gives_something_for_a_medal_and_nothing_without() -> void:
	var r := CareerIO.load_default()
	var c := _career("SS")
	assert_eq(GameRating.open_box(c, 0, r, Rng.new(1)), "")
	var seen: Dictionary[String, bool] = {}
	for i: int in 30:
		var got := GameRating.open_box(c, 3, r, Rng.new(i))
		assert_ne(got, "")
		seen[got.split(":")[0].split(" +")[0]] = true
	assert_gte(seen.size(), 2, "points, growth points or gear")
	assert_gt(c.points + int(c.gp["batting"] + c.gp["fielding"] + c.gp["running"]) + c.gear.size(), 0)
	for name: String in c.gear:
		assert_ne(r.field_of(c.gear[name]), "pitching", "no pitching gear for a shortstop")
