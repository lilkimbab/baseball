extends GutTest
## The one-line play-by-play (docs/13 S6-7): scorebook words, the way a strikeout ended.


func test_a_called_third_strike_is_a_looking_strikeout() -> void:
	assert_eq(Commentary.key_for(PaResult.Kind.STRIKEOUT, PitchDuel.Result.CALLED_STRIKE), "strikeout_looking")
	assert_eq(Commentary.key_for(PaResult.Kind.STRIKEOUT, PitchDuel.Result.SWINGING_STRIKE), "strikeout_swinging")
	assert_eq(Commentary.key_for(PaResult.Kind.DROPPED_THIRD_STRIKE, PitchDuel.Result.SWINGING_STRIKE), "dropped_third_strike")


func test_lines_fill_in_the_play_and_the_runs() -> void:
	var c := CommentaryIO.load_default()
	var line := c.line("double_play", 0, "김타자", "유격수 땅볼 병살 (6-4-3)", "6-4-3")
	assert_string_contains(line, "6-4-3")
	assert_string_contains(line, "김타자")
	var with_runs := c.line("single", 0, "이타자", "좌전 안타", "", 2)
	assert_string_contains(with_runs, "2점")
	var looking := c.line("strikeout_looking", 0, "박타자")
	assert_string_contains(looking, "삼진")
	assert_false(looking.contains("{"), "no placeholder left: " + looking)


func test_every_result_has_lines() -> void:
	var c := CommentaryIO.load_default()
	for kind: int in PaResult.Kind.values():
		var key := Commentary.key_for(kind as PaResult.Kind, PitchDuel.Result.SWINGING_STRIKE)
		if key == "":
			continue
		assert_true(c.templates.has(key), "lines for %s" % key)


func test_the_particle_follows_the_name() -> void:
	assert_eq(Commentary.josa("김윤민", "을", "를"), "을", "ends in ㄴ")
	assert_eq(Commentary.josa("가르시아", "을", "를"), "를", "ends in a vowel")
	assert_eq(Commentary.josa("이도", "이", "가"), "가")
	var c := CommentaryIO.load_default()
	for pick: int in 8:
		var a := c.line("strikeout_swinging_escape", pick, "가르시아")
		assert_false(a.contains("가르시아을"), a)
		var b := c.line("strikeout_swinging_escape", pick, "김윤민")
		assert_false(b.contains("김윤민를"), b)


func test_the_situation_picks_its_own_lines() -> void:
	var c := CommentaryIO.load_default()
	assert_eq(c.best_key("home_run", 4, false, true, false, false), "home_run_grand_slam", "a grand slam before a lead taken")
	assert_eq(c.best_key("home_run", 1, true, true, false, false), "home_run_walk_off")
	assert_eq(c.best_key("single", 1, true, true, false, false), "walk_off", "any walk-off")
	assert_eq(c.best_key("double", 2, false, true, false, false), "hit_go_ahead")
	assert_eq(c.best_key("single", 1, false, false, true, false), "hit_tying")
	assert_eq(c.best_key("single", 1, false, false, false, false), "single_rbi")
	assert_eq(c.best_key("home_run", 1, false, false, false, false), "home_run_solo")
	assert_eq(c.best_key("walk", 1, false, false, false, false), "walk_rbi", "forced in with the bases loaded")
	assert_eq(c.best_key("strikeout_swinging", 0, false, false, false, true), "strikeout_swinging_escape")
	assert_eq(c.best_key("double_play", 0, false, false, false, true), "double_play_escape")
	assert_eq(c.best_key("ground_out", 0, false, false, false, false), "ground_out")
	# A line that tells its runs gets no second count of them.
	for pick: int in 6:
		var l := c.line("single_rbi", pick, "김타자", "좌전 안타", "", 2)
		assert_eq(l.count("2점"), 1 if l.contains("2점") else 0, l)
		assert_false(l.contains("{"), l)
	# Every line of every situation fills in.
	for key: String in c.templates:
		for pick: int in c.templates[key].size():
			var l := c.line(key, pick, "김타자", "좌전 안타", "6-4-3", 1, "박주자", 2)
			assert_false(l.contains("{"), "%s: %s" % [key, l])
