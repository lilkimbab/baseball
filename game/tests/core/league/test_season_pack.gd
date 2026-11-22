extends GutTest
## Seasons of the past (docs/08 R7): a pack gives the clubs, that year's rules and what really
## happened; a season started from it is played with them in one league, its scenario sets
## the club and the goal, and the end compares this season with the real one.

func before_each() -> void:
	LeagueSession.season = null


func after_all() -> void:
	LeagueSession.season = null


func _pack() -> SeasonPack:
	var pack := SeasonPack.by_id("fiction-2025")
	assert_not_null(pack, "the game's example pack is there")
	return pack


func test_a_pack_gives_its_clubs_rules_and_the_real_outcome() -> void:
	var pack := _pack()
	assert_eq(pack.year, 2025)
	assert_eq(pack.team_ids.size(), 10)
	assert_eq(pack.clubs().size(), 10)
	assert_eq(pack.standings.size(), 10)
	assert_true(pack.team_ids.has(pack.champion))
	var r := pack.rule_set()
	assert_eq(r.extra_inning_limit, 12)
	assert_eq(r.registered_roster, 28)
	assert_eq(r.asia_quota, 0)
	assert_eq(pack.scenarios.size(), 3)
	var last := pack.actual_of(str(pack.standings[9][0]))
	assert_eq(int(last[0]), 10, "places from the real table")


func test_a_scenario_season_is_played_with_that_year_s_rules() -> void:
	var pack := _pack()
	var s := LeagueSession.start_history(pack, "climb", "", 4)
	var sc := pack.scenario("climb")
	assert_eq(s.my_team, sc.team, "the scenario's club")
	assert_eq(s.divisions.size(), 1, "one league")
	assert_eq(s.games_per_team, pack.games)
	assert_eq(s.season_year, 2025)
	assert_eq(s.rules.extra_inning_limit, 12)
	for t: Team in s.teams.values():
		assert_eq(t.registered.size(), 28, "that year's first-team size")
	assert_null(s.farm, "no second teams' league for a season of the past")
	s.play_to_end()
	assert_eq(s.phase, Season.Phase.OVER)
	var rank := s.standings[0].rank_of(sc.team)
	assert_eq(SeasonPack.goal_met(sc, s), rank <= 4)
	assert_eq(s.movements()[0][0].size(), 0, "nobody goes up")
	assert_eq(s.movements()[0][1].size(), 0, "or down")
	# Saved and loaded, it is still that season with its scenario.
	var back := SaveIO.season_from(SaveIO.season_to(s))
	assert_not_null(back.history)
	assert_eq(back.history.id, pack.id)
	assert_eq(back.scenario_id, "climb")
	assert_eq(back.rules.extra_inning_limit, 12)


func test_the_screen_starts_one_and_shows_then_and_now_at_the_end() -> void:
	var screen := (load("res://league/league_screen.tscn") as PackedScene).instantiate() as LeagueScreen
	add_child_autofree(screen)
	screen._setup_mode = "history"
	screen._pack_id = "fiction-2025"
	screen._scenario_id = "upset"
	screen.refresh()
	screen.begin_history(_pack(), "upset", "")
	var s := LeagueSession.season
	assert_eq(s.my_team, _pack().scenario("upset").team)
	s.play_to_end()
	screen.refresh()
	assert_true(s.finished())


## The real seasons in the local content pack (./dev kbo), newest first; none on a machine
## without it.
func _real_packs() -> Array[SeasonPack]:
	var out: Array[SeasonPack] = []
	for pack: SeasonPack in SeasonPack.available():
		if pack.id.begins_with("kbo-"):
			out.append(pack)
	out.reverse()
	return out


func test_every_real_season_in_the_local_pack_is_whole() -> void:
	# docs/13 S17: the seasons chosen in content-local/kbo/history.json, built from the Kaggle
	# records: the clubs as they were called, the real table, that year's rules and postseason.
	var packs := _real_packs()
	if packs.is_empty():
		pending("no real seasons in content-local/ (./dev kbo)")
		return
	for pack: SeasonPack in packs:
		var clubs := pack.clubs()
		assert_eq(clubs.size(), pack.team_ids.size(), "%s: its roster pack has every club" % pack.id)
		assert_eq(clubs.size() % 2, 0, "%s: an even number of clubs (the schedule pairs them)" % pack.id)
		var names: Dictionary[String, bool] = {}
		for t: Team in clubs:
			assert_ne(t.name, "")
			names[t.name] = true
		assert_eq(names.size(), clubs.size(), "%s: club names are distinct" % pack.id)
		assert_eq(pack.standings.size(), clubs.size())
		for row: Array in pack.standings:
			assert_true(pack.team_ids.has(str(row[0])))
			assert_eq(int(row[1]) + int(row[2]) + int(row[3]), pack.games, "%s %s: the real record adds up to the season" % [pack.id, row[0]])
		assert_true(pack.team_ids.has(pack.champion), "%s: the champion is one of its clubs" % pack.id)
		var rounds := pack.postseason_format()
		assert_eq(rounds[-1].name, "한국시리즈")
		assert_eq(rounds[-1].wins, 4)
		assert_lte(rounds.size() + 1, clubs.size())
		assert_eq(pack.scenarios.size(), 1, "%s: the club that made history that season" % pack.id)
		var legend := pack.scenarios[0]
		assert_eq(pack.title, legend.title)
		assert_true(legend.title.begins_with("%d " % pack.year))
		assert_ne(legend.tagline, "")
		assert_ne(legend.path, "")
		assert_true(legend.kind in ["double", "champion"], "%s: a title to win again" % pack.id)
		assert_eq(int(pack.actual_of(legend.team)[0]) == 1, legend.kind == "double", "%s: the double for a club that was first" % pack.id)
		assert_eq(pack.champion, legend.team, "%s: the club won it that year" % pack.id)
		assert_gte(legend.stars.size(), 4, "%s: its leading men" % pack.id)
		var ids: Dictionary[String, bool] = {}
		for sc: SeasonPack.Scenario in pack.scenarios:
			ids[sc.id] = true
			assert_true(pack.team_ids.has(sc.team), "%s / %s: its club plays that season" % [pack.id, sc.id])
			assert_true(sc.kind in ["double", "champion", "rank", "wins"])
			assert_ne(sc.text, "")
		assert_eq(ids.size(), pack.scenarios.size(), "%s: scenario ids are distinct" % pack.id)
		var s := LeagueSession.start_history(pack, pack.scenarios[0].id, "", 12)
		assert_eq(s.my_team, pack.scenarios[0].team)
		assert_eq(s.postseason_format(0).size(), rounds.size())
		for t: Team in s.teams.values():
			assert_eq(t.registered.size(), s.rules.registered_roster, "%s %s: that year's first team" % [pack.id, t.name])
			assert_gte(t.rotation().size(), 5, "%s %s has its starters" % [pack.id, t.name])
			var foreign := 0
			var asia := 0
			for p: Player in t.first_team():
				assert_eq(p.potential, 0.0, "that year's ratings as they were")
				if p.origin == &"foreign":
					foreign += 1
				elif p.origin == &"asia":
					asia += 1
			assert_lte(foreign, s.rules.foreign_players, "%s %s" % [pack.id, t.name])
			assert_lte(asia, s.rules.asia_quota, "%s %s" % [pack.id, t.name])
			# A line-up can be made (every position covered).
			var game := AiManager.new(s.env, s.catalog, s.ovr).make_lineup(s.squad_for(t, 0, t.rotation()[0].id), s.rules, t.rotation()[0].id)
			assert_eq(game.lineup.size(), 9)
			assert_true(game.validate().is_empty(), "%s %s: %s" % [pack.id, t.name, ", ".join(game.validate())])


func test_the_newest_real_season_plays_to_its_korean_series() -> void:
	var packs := _real_packs()
	if packs.is_empty():
		pending("no real seasons in content-local/ (./dev kbo)")
		return
	var pack := packs[0]
	var s := LeagueSession.start_history(pack, pack.scenarios[0].id, "", 12)
	s.play_to_end()
	assert_eq(s.phase, Season.Phase.OVER)
	var post := s.postseasons[0]
	assert_eq(post.seeds.size(), 5, "five clubs from the wild card")
	assert_eq(post.round_name(post.format.size() - 1), "한국시리즈")
	assert_eq(post.rounds.size(), 4)
	assert_ne(s.champion_of(0), "")
	assert_true(post.seeds.has(s.champion_of(0)))
