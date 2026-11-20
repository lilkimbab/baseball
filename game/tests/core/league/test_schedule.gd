extends GutTest
## The season calendar (docs/13 S7-1).


func _ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for i: int in 10:
		ids.append("t%02d" % i)
	return ids


func test_every_length_gives_each_club_its_games_and_equal_home_and_away() -> void:
	for length: int in Schedule.LENGTHS:
		var s := Schedule.make(_ids(), length, Rng.new(7))
		assert_eq(s.games.size(), length * 10 / 2, "%d games: total" % length)
		for id: String in _ids():
			var home := 0
			var away := 0
			var against: Dictionary[String, Vector2i] = {}
			for g: ScheduledGame in s.games_of(id):
				var other := g.opponent_of(id)
				var v: Vector2i = against.get(other, Vector2i.ZERO)
				if g.home == id:
					home += 1
					v.x += 1
				else:
					away += 1
					v.y += 1
				against[other] = v
			assert_eq(home + away, length, "%d games: %s plays them all" % [length, id])
			assert_eq(home, away, "%d games: %s home and away" % [length, id])
			assert_eq(against.size(), 9)
			for other: String in against:
				assert_eq(against[other].x, against[other].y, "%d games: %s vs %s split" % [length, id, other])
				assert_eq(against[other].x + against[other].y, length / 9)


func test_nobody_plays_twice_a_day_and_monday_is_off() -> void:
	var s := Schedule.make(_ids(), 144, Rng.new(3))
	var seen: Dictionary[String, bool] = {}
	for g: ScheduledGame in s.games:
		assert_false(Schedule.is_off_day(g.day), "no game on day %d" % g.day)
		for id: String in [g.away, g.home]:
			var key := "%d:%s" % [g.day, id]
			assert_false(seen.has(key), "%s plays once on day %d" % [id, g.day])
			seen[key] = true
	# Six game days a week: 144 game days take 24 weeks less the last Monday.
	assert_eq(s.days, 24 * 7 - 1)
	assert_eq(s.games_on(0).size(), 5)
	assert_eq(s.games_on(6).size(), 0, "first Monday off")


func test_series_are_three_games_where_they_fit() -> void:
	assert_eq(Schedule.series_lengths(8), PackedInt32Array([3, 3, 2]))
	assert_eq(Schedule.series_lengths(4), PackedInt32Array([2, 2]))
	assert_eq(Schedule.series_lengths(2), PackedInt32Array([2]))
	var s := Schedule.make(_ids(), 144, Rng.new(5))
	var by_series: Dictionary[int, Array] = {}
	for g: ScheduledGame in s.games:
		if not by_series.has(g.series):
			by_series[g.series] = []
		by_series[g.series].append(g)
	var threes := 0
	for k: int in by_series:
		var series: Array = by_series[k]
		var first: ScheduledGame = series[0]
		for i: int in series.size():
			var g: ScheduledGame = series[i]
			assert_eq(g.home, first.home, "a series stays at one park")
			assert_eq(g.away, first.away)
			assert_eq(g.game_in_series, i + 1)
		if series.size() == 3:
			threes += 1
	# Per pair 16 meetings in four series of three and two of two.
	assert_eq(threes, 45 * 4)
	assert_eq(by_series.size(), 45 * 6)


func test_the_same_seed_gives_the_same_season_and_another_does_not() -> void:
	var a := Schedule.make(_ids(), 72, Rng.new(11))
	var b := Schedule.make(_ids(), 72, Rng.new(11))
	var c := Schedule.make(_ids(), 72, Rng.new(12))
	var same := true
	var differs := false
	for i: int in a.games.size():
		if a.games[i].home != b.games[i].home or a.games[i].away != b.games[i].away:
			same = false
		if a.games[i].home != c.games[i].home or a.games[i].away != c.games[i].away:
			differs = true
	assert_true(same)
	assert_true(differs)


func test_next_game_and_finish() -> void:
	var s := Schedule.make(_ids(), 36, Rng.new(1))
	var first := s.next_game_of("t03")
	assert_not_null(first)
	first.finish(3, 5)
	assert_eq(first.winner(), first.home)
	assert_ne(s.next_game_of("t03"), first)
	assert_false(s.finished())
	for g: ScheduledGame in s.games:
		g.finish(1, 1)
	assert_true(s.finished())
	assert_null(s.next_game_of("t03"))
	assert_eq(s.games[0].winner(), "", "a tie has no winner")
