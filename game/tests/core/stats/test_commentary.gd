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
