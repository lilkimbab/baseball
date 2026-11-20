extends SceneTree
## Plays one game and prints the play-by-play and the box score.
##
##   godot --headless --path game --script res://tools/sim_game.gd -- --seed 7
##
## Options: --seed <n>  --innings <3|6|9>  --pack <res://data/rosters/x.json> (default: two
## made-up average clubs)  --away <team id> --home <team id>  --quiet (box score only)
## --physical (every pitch and ball in play simulated, S5; default: the stat resolver)


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var seed_value := int(str(args.get("seed", "7")))
	var catalog := PitchCatalogIO.load_default()
	var env := LeagueEnvIO.load_default()
	var ovr := LeagueEnvIO.load_overall()
	var teams: Array[Team] = []
	if args.has("pack"):
		teams = RosterIO.load_pack(str(args["pack"]))
	else:
		var gen := LeagueGenerator.new(RosterIO.load_names(), catalog, seed_value)
		teams = [gen.team(0, 50.0), gen.team(1, 50.0)]
	var away := _find(teams, str(args.get("away", teams[0].id)))
	var home := _find(teams, str(args.get("home", teams[1].id)))
	var rules := RuleSet.kbo_2026() if not args.has("innings") else RuleSet.short_game(int(str(args["innings"])))
	var sim := GameSim.create(away, home, rules, env, catalog, ovr, Rng.new(seed_value).fork(1), null, null, args.has("physical"))
	sim.keep_log = not args.has("quiet")
	sim.play()
	print("%s  %d : %d  %s" % [away.name, sim.state.score[0], sim.state.score[1], home.name])
	print("")
	for line: String in sim.log:
		print(line)
	print("")
	print(sim.scorer.book.box_score(sim.state))
	quit()


func _find(teams: Array[Team], id: String) -> Team:
	for t: Team in teams:
		if t.id == id:
			return t
	return teams[0]
