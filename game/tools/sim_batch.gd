extends SceneTree
## Plays many games between clubs of league-average talent and compares the league totals
## with the targets in data/league_env.json (docs/13 S4-12).
##
##   godot --headless --path game --script res://tools/sim_batch.gd -- --games 2000
##
## Options: --games <n, default 1000>  --seed <n>  --teams <n, default 30>  --env <preset>
##          --leagues <n, default 4>: the games are split over this many separately made-up
##          leagues, so that one league's luck in its draw of players does not tilt the result;
##          the leagues are played at the same time on worker threads
##          --physical: every pitch and ball in play simulated (S5), with the pitch-level checks
##          --dump <file>: save the totals as JSON instead of printing them
##          --merge <file,file,...>: add up saved totals and print them
## Prints one line per measure: the simulated value, the target, and "!!" when it is outside
## the allowed range.

var _lines := PackedStringArray()


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	if args.has("merge"):
		_merge(str(args["merge"]).split(","), LeagueEnvIO.load_default(str(args.get("env", ""))))
		return
	var games := int(str(args.get("games", "1000")))
	var seed_value := int(str(args.get("seed", "2026")))
	var team_count := int(str(args.get("teams", "30")))
	var catalog := PitchCatalogIO.load_default()
	var env := LeagueEnvIO.load_default(str(args.get("env", "")))
	var ovr := LeagueEnvIO.load_overall()
	var leagues := maxi(int(str(args.get("leagues", "4"))), 1)
	var physical := args.has("physical")
	var names := RosterIO.load_names()
	# Shared data is loaded once here, before the leagues run side by side on worker threads.
	PhysicsConfigIO.load_default()
	MotionIO.load_default()
	MotionIO.alignment()
	var parts: Array[BatchReport] = []
	parts.resize(leagues)
	var play_league := func(l: int) -> void:
		var gen := LeagueGenerator.new(names, catalog, seed_value + l * 1009)
		var teams: Array[Team] = []
		for i: int in team_count:
			teams.append(gen.team(i, 50.0))
		parts[l] = BatchReport.run(teams, games / leagues, RuleSet.kbo_2026(), env, catalog, ovr, Rng.new(seed_value + l).fork(9), physical)
	var group := WorkerThreadPool.add_group_task(play_league, leagues)
	WorkerThreadPool.wait_for_group_task_completion(group)
	var report: BatchReport = parts[0]
	for l: int in range(1, leagues):
		report.merge(parts[l])
	if args.has("dump"):
		ReportIO.save(report, str(args["dump"]))
		quit(0)
		return
	print(report.text(env))
	quit(0 if report.failures == 0 else 1)


## Adds up reports saved by separate processes (--dump) and prints the total.
func _merge(paths: PackedStringArray, env: LeagueEnv) -> void:
	var report: BatchReport = null
	for path: String in paths:
		var part := ReportIO.load_report(path)
		if report == null:
			report = part
		else:
			report.merge(part)
	print(report.text(env))
	quit(0 if report.failures == 0 else 1)
