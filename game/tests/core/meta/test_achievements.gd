extends GutTest
## Achievements (the user, 2026-11-22: "add achievements, rewards by difficulty, special items"):
## counted over every game, the harder ones only from games at their difficulty or harder,
## the parks counted once each, the last one when all the others are done, and kept.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _book() -> AchievementBook:
	return AchievementBook.from_data(JsonIO.read_object("res://data/achievements.ko.json"))


func test_the_data_is_whole() -> void:
	var book := _book()
	assert_gte(book.defs.size(), 40, "enough to come back for")
	var ids: Dictionary = {}
	for d: AchievementBook.Def in book.defs:
		assert_false(ids.has(d.id), "%s once" % d.id)
		ids[d.id] = true
		assert_true(d.tier >= 0 and d.tier <= 3)
		assert_true(AchievementBook.CATEGORY_NAMES.has(d.category), d.id)
		if d.item != "":
			assert_true(book.item_names.has(d.item), "%s pays a known item" % d.id)
			assert_gte(d.min_level, Difficulty.Level.ALL_STAR, "special items only at 올스타 or harder")


func test_counts_unlock_in_tiers_and_harder_ones_need_harder_games() -> void:
	var book := _book()
	var got := book.count("wins", 1, Difficulty.Level.PRO, "2026-11-22")
	var names: Array[String] = []
	for d: AchievementBook.Def in got:
		names.append(d.id)
	assert_true(names.has("first_win"))
	assert_false(names.has("allstar_win"), "a win at 프로 is not one at 올스타")
	assert_eq(book.progress(book.def_of("wins_10")), 1)
	got = book.count("wins", 1, Difficulty.Level.LEGEND)
	names.clear()
	for d: AchievementBook.Def in got:
		names.append(d.id)
	assert_true(names.has("allstar_win"), "레전드 counts for 올스타 or harder")
	assert_true(names.has("legend_win"))
	assert_true(book.items().has("gear:가죽 장갑"), "its signature glove")
	assert_eq(book.progress(book.def_of("wins_10")), 2)


func test_parks_count_once_each() -> void:
	var book := _book()
	for park: String in ["a", "a", "b", "c", "c", "d"]:
		book.distinct("parks_won", park, 0)
	assert_eq(book.progress(book.def_of("parks_5")), 4)
	assert_false(book.unlocked.has("parks_5"))
	book.distinct("parks_won", "e", 0)
	assert_true(book.unlocked.has("parks_5"))


func test_the_last_one_comes_with_all_the_others_and_it_is_kept() -> void:
	var book := _book()
	for d: AchievementBook.Def in book.defs:
		if d.key != "*":
			book.reach(d.key, d.target, d.min_level)
	assert_true(book.unlocked.has("moneyball"))
	var tally := book.tally()
	assert_eq(tally[4], book.defs.size())
	var again := _book()
	again.load_dict(JSON.parse_string(JSON.stringify(book.to_dict())))
	assert_eq(again.unlocked.size(), book.unlocked.size())
	assert_eq(again.counters, book.counters)


func test_a_game_counts_what_his_side_did() -> void:
	# A game with the stat resolver, followed event by event as the scene does.
	var teams := F.teams(9)
	var sim := GameSim.create(teams[0], teams[1], RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), Rng.new(5))
	var feats := GameFeats.for_side(1)
	var guard := 0
	while not sim.state.over and guard < GameSim.MAX_EVENTS:
		var e := sim.resolver.next_event(sim.state)
		var out := GameFlow.apply(sim.state, e)
		sim.scorer.record(sim.state, e, out)
		sim.manager.note_change(sim.state, e)
		feats.note(sim.state, e, out)
		guard += 1
	sim.scorer.finish(sim.state)
	var c := feats.counts(sim.state, sim.scorer.book)
	var won := sim.state.score[1] > sim.state.score[0]
	assert_eq(c["games"], 1)
	assert_eq(c["wins"], 1 if won else 0)
	assert_eq(c["hits"], sim.scorer.book.team_batting(1).hits)
	assert_eq(c["strikeouts"], sim.scorer.book.team_pitching(1).strikeouts)
	if won:
		assert_eq(c["shutout"], 1 if sim.state.score[0] == 0 else 0)
	assert_gte(feats.worst_deficit, 0)
	if c.get("walk_off", 0) == 1:
		assert_true(won and not sim.state.top, "a walk-off ends in the bottom half")
