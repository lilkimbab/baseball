extends SceneTree
## Plays many games between clubs of league-average talent and compares the league totals
## with the targets in data/league_env.json (docs/13 S4-12).
##
##   godot --headless --path game --script res://tools/sim_batch.gd -- --games 2000
##
## Options: --games <n, default 1000>  --seed <n>  --teams <n, default 30>  --env <preset>
## Prints one line per measure: the simulated value, the target, and "!!" when it is outside
## the allowed range.

var _lines := PackedStringArray()


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var games := int(str(args.get("games", "1000")))
	var seed_value := int(str(args.get("seed", "2026")))
	var team_count := int(str(args.get("teams", "30")))
	var catalog := PitchCatalogIO.load_default()
	var env := LeagueEnvIO.load_default(str(args.get("env", "")))
	var ovr := LeagueEnvIO.load_overall()
	var gen := LeagueGenerator.new(RosterIO.load_names(), catalog, seed_value)
	var teams: Array[Team] = []
	for i: int in team_count:
		teams.append(gen.team(i, 50.0))
	var report := BatchReport.run(teams, games, RuleSet.kbo_2026(), env, catalog, ovr, Rng.new(seed_value).fork(9))
	print(report.text(env))
	quit(0 if report.failures == 0 else 1)
