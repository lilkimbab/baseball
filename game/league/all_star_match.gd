class_name AllStarMatch
extends MatchScene
## The league's all-star game played by the manager himself: the two all-star
## teams (LeagueAllStar), he on the side with more of his men; nine innings (or the settings');
## what it pays goes to him at the end, and back to the league screen.


func _read_arguments() -> void:
	Settings.ensure_loaded()
	Settings.apply_rendering(get_tree())
	pitch_clock_on = Settings.pitch_clock
	auto_changes = Settings.auto_changes
	from_menu = true
	innings = Settings.innings
	var s := LeagueSession.season
	human_team = LeagueAllStar.my_side(s) if s != null else 1
	seed_value = hash("all_star:%d" % (s.season_year if s != null else 2026)) % 100000


func _start_game() -> void:
	var s := LeagueSession.season
	var catalog_all := PitchCatalogIO.load_default()
	var env := LeagueEnvIO.load_default()
	var ovr := LeagueEnvIO.load_overall()
	_clubs = LeagueAllStar.teams(s)
	_club_cache = []
	var away := _clubs[0]
	var home := _clubs[1]
	var rules := RuleSet.kbo_2026() if innings >= 9 else RuleSet.short_game(innings)
	manager = AiManager.new(env, catalog_all, ovr)
	game = GameState.new()
	game.rules = rules
	game.teams = [manager.make_lineup(away, rules, away.next_starter().id), manager.make_lineup(home, rules, home.next_starter().id)]
	resolver = PhysicalResolver.new(env, catalog_all, manager, Rng.new(seed_value).fork(5))
	stadium = MatchScene.home_def(s.teams[s.my_team])
	stadium.name = "올스타전 · %s" % stadium.name
	resolver.use_park(stadium)
	scorer = Scorer.new()
	GameFlow.start(game)
	scorer.start(game)
	manager.start_game(game)
	_chosen_team = human_team
	balls = 0
	strikes = 0


## What the game paid: the all-star game's own reward (LeagueAllStar), not a game's.
func _pay_profile() -> void:
	if _profile_paid or game == null or not game.over:
		return
	_profile_paid = true
	var s := LeagueSession.season
	if s == null or DisplayServer.get_name() == "headless" or Profile.tool_run():
		return
	profile_lines = LeagueAllStar.played_game(s, game.score[0], game.score[1], played_level())
	LeagueSession.autosave()


func post_game_hint() -> String:
	return "Esc 리그로 돌아가기"


func leave() -> void:
	Loading.go(get_tree(), LeagueSession.SCREEN, {"title": "리그로 이동 중"})


## Over, any key goes back (there is no playing it again: its reward is once).
func _menu_key(code: Key) -> void:
	if game.over:
		leave()
		return
	super._menu_key(code)
