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
	assert_eq(c.best_key("single", 1, true, true, false, false), "single_walk_off", "a walk-off single has its own lines")
	assert_eq(c.best_key("fielders_choice", 1, true, true, false, false), "walk_off", "any other walk-off")
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


# --- After real KBO calls (2026-11-23) ---


func test_where_the_ball_went_reads_as_a_caster_says_it() -> void:
	var left := Commentary.direction_slots(7, false)
	assert_eq(left["field"], "좌익수")
	assert_eq(left["wall"], "좌측 담장")
	assert_eq(left["swing"], "잡아당겼습니다", "a right-handed batter to left pulls it")
	assert_eq(Commentary.direction_slots(7, true)["swing"], "밀어쳤습니다", "a left-handed one pushes it")
	assert_eq(Commentary.direction_slots(9, true)["swing"], "잡아당겼습니다")
	assert_eq(Commentary.direction_slots(8, false)["swing"], "받아쳤습니다")
	assert_eq(Commentary.direction_slots(8, false)["side"], "가운데")
	assert_false(Commentary.direction_slots(6, false).has("wall"), "no wall in the infield")
	assert_true(Commentary.direction_slots(0, false).is_empty())
	assert_eq(Commentary.pitch_word(1), "초구")
	assert_eq(Commentary.pitch_word(3), "3구째")


func test_a_line_needs_what_it_tells() -> void:
	var c := CommentaryIO.load_default()
	var with_season := false
	for pick: int in 40:
		var plain := c.line("home_run", pick, "김타자", "좌월 홈런")
		assert_false(plain.contains("시즌"), "no season count without a season: " + plain)
		assert_false(plain.contains("{"), plain)
		var counted := c.line("home_run", pick, "김타자", "좌월 홈런", "", 1, "", 0, {"hr": "12", "wall": "좌측 담장", "field": "좌익수", "swing": "잡아당겼습니다", "pitch": "초구", "pitcher": "박투수"})
		assert_false(counted.contains("{"), counted)
		with_season = with_season or counted.contains("시즌 12호")
	assert_true(with_season, "the season's count is told when it is known")


func test_particles_follow_every_name_slot() -> void:
	assert_eq(Commentary.fill("{side}으로 빠집니다", {"side": "가운데"}), "가운데로 빠집니다")
	assert_eq(Commentary.fill("{side}으로 빠집니다", {"side": "왼쪽"}), "왼쪽으로 빠집니다")
	assert_eq(Commentary.fill("{field}이 잡습니다", {"field": "좌익수"}), "좌익수가 잡습니다")
	assert_eq(Commentary.fill("{field}이 잡습니다", {"field": "유격수"}), "유격수가 잡습니다")
	assert_eq(Commentary.fill("{team}이 이깁니다", {"team": "다솜"}), "다솜이 이깁니다")
	assert_eq(Commentary.fill("{pitch}를 쳤습니다", {"pitch": "초구"}), "초구를 쳤습니다")


func test_every_line_fills_with_every_slot_known() -> void:
	var c := CommentaryIO.load_default()
	var all := {"pitch": "3구째", "field": "중견수", "side": "가운데", "wall": "가운데 담장", "swing": "받아쳤습니다", "score": "5대 3",
		"team": "다솜", "inning": "9회말", "pitcher": "박투수", "hr": "21", "k": "7", "out": "최타자", "homer": "투런"}
	for key: String in c.templates:
		for pick: int in c.templates[key].size():
			var l := c.line(key, pick, "김타자", "중전 안타", "6-4-3", 2, "박주자", 2, all)
			assert_false(l.contains("{"), "%s: %s" % [key, l])
	assert_gt(c.templates.size(), 60, "situations")


func test_the_caster_calls_the_ball_by_its_flight() -> void:
	var play := PlayResult.new()
	play.result = PaResult.Kind.HOME_RUN
	play.direction = 7
	assert_eq(MatchSound.call_group(play), "call_deep")
	play.result = PaResult.Kind.FLY_OUT
	play.short_of_fence = 40.0
	assert_eq(MatchSound.call_group(play), "", "an ordinary fly: no call")
	play.short_of_fence = 5.0
	assert_eq(MatchSound.call_group(play), "call_deep", "a fly to the wall builds as a home run would")
	play.result = PaResult.Kind.SINGLE
	assert_eq(MatchSound.call_group(play), "call_single")
	play.direction = 6
	assert_eq(MatchSound.call_group(play), "call_infield")
	var c := CommentaryIO.load_default()
	for group: String in Commentary.CALL_KEYS:
		assert_true(c.templates.has(group), group)
		for pick: int in 12:
			var l := c.call_line(group, pick, Commentary.direction_slots(8, false) if group != "call_infield" else Commentary.direction_slots(6, false))
			assert_false(l.contains("{"), l)
