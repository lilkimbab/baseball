extends SceneTree
## Makes the fictional league's roster pack: 3 divisions of 10 clubs, 28 players each.
##
##   godot --headless --path game --script res://tools/gen_league.gd -- --seed 2026
##
## Options: --seed <n, default 2026>  --out <path, default res://data/rosters/fiction-2026.json>


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var seed_value := int(str(args.get("seed", "2026")))
	var out := str(args.get("out", "res://data/rosters/fiction-2026.json"))
	var gen := LeagueGenerator.new(RosterIO.load_names(), PitchCatalogIO.load_default(), seed_value)
	var teams := gen.league()
	var err := RosterIO.save_pack(out, "fiction-2026", "가상 리그 2026", 2026, teams)
	if err != OK:
		push_error("gen_league: could not write %s (%s)" % [out, error_string(err)])
		quit(1)
		return
	var players := 0
	for t: Team in teams:
		players += t.players.size()
	print("gen_league: %d clubs, %d players -> %s" % [teams.size(), players, out])
	quit()
