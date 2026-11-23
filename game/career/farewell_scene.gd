class_name FarewellScene
extends MatchScene
## His retirement at his club's park (the user, 2026-11-23: "a ceremony at the real ballpark, as
## the KBO does it"; "cutscenes like these skip with Space, as in other games"). The career is
## settled first (CareerSession.retire); the tribute plays as the scoreboard's film
## (CareerFlashback); then the ceremony on the field (FieldScenes.plan_farewell: the lines of his
## teammates, the walk out, the bow, his number over centre field, the toss); then the settling
## up (RetireScreen). Space skips each part.

var _stage := 0
var _tribute: CareerFlashback


func _read_arguments() -> void:
	Settings.ensure_loaded()
	Settings.apply_rendering(get_tree())
	from_menu = true
	innings = 9
	human_team = -1
	var c := CareerSession.career
	seed_value = hash("farewell:%s" % (c.player.id if c != null else "")) % 100000


## His club at home against another; nobody plays (the ceremony holds the game from the start).
func _start_game() -> void:
	var cs := CareerSession.career_season
	var c := CareerSession.career
	var s := cs.season
	var home: Team = s.teams[c.team_id]
	var away: Team = null
	for id: String in s.divisions[0]:
		if id != c.team_id:
			away = s.teams[id]
			break
	var catalog_all := PitchCatalogIO.load_default()
	var env := LeagueEnvIO.load_default()
	var ovr := LeagueEnvIO.load_overall()
	_clubs.assign([away, home])
	_club_cache = []
	var rules := RuleSet.kbo_2026()
	manager = AiManager.new(env, catalog_all, ovr)
	game = GameState.new()
	game.rules = rules
	game.teams = [manager.make_lineup(away, rules, away.next_starter().id), manager.make_lineup(home, rules, home.next_starter().id)]
	resolver = PhysicalResolver.new(env, catalog_all, manager, Rng.new(seed_value).fork(5))
	stadium = MatchScene.home_def(home)
	resolver.use_park(stadium)
	scorer = Scorer.new()
	GameFlow.start(game)
	scorer.start(game)
	manager.start_game(game)
	_chosen_team = -1
	balls = 0
	strikes = 0


func _ready() -> void:
	super._ready()
	if CareerSession.career != null and not CareerSession.career.retired:
		CareerSession.retire()
	_begin.call_deferred()


## The ceremony queued (held at its first shot while the tribute plays).
func _begin() -> void:
	var c := CareerSession.career
	var cs := CareerSession.career_season
	broadcast.skip_all()
	if c == null or cs == null or park == null:
		_leave()
		return
	_field_scenes().plan_farewell(GameState.HOME, c.player, c.number_retired)
	var seg := Broadcast.segment(Broadcast.Kind.FAREWELL)
	seg.shots = _field_scenes().farewell_shots()
	var team: Team = cs.season.teams[c.team_id]
	var sum := CareerContract.totals(c)
	seg.data = {"title": "%d %s 은퇴식" % [cs.season.season_year, team.name], "name": c.player.name, "number": c.player.number, "retired": c.number_retired,
		"slogan": CareerLegacy.slogan(c, team), "line": "프로 %s" % CareerSession._career_line(c, sum[0], sum[1]), "grade": c.legacy_grade}
	broadcast.push(seg)


func _process(delta: float) -> void:
	super._process(delta)
	match _stage:
		0:
			# The tribute on the scoreboard's screen, once the loading screen has lifted.
			broadcast.time = 0.0
			if _tribute == null and not Loading.covering() and broadcast.current != null:
				var c := CareerSession.career
				var cs := CareerSession.career_season
				_tribute = CareerFlashback.play(self, c.player, cs.season, CareerLegacy.flashback(c), "THANK YOU %s" % c.player.name, func() -> void: _stage = 1)
		1:
			if broadcast.current == null:
				_stage = 2
				_leave()


func _leave() -> void:
	Loading.go(get_tree(), CareerSession.RETIRE, {"title": "은퇴식"})


## Nothing to play here: Esc leaves for the settling up.
func _menu_key(code: Key) -> void:
	if code == KEY_ESCAPE:
		broadcast.skip_all()
		return
	super._menu_key(code)
