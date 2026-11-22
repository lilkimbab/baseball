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
