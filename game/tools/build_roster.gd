extends SceneTree
## Builds a roster pack from a season's records in CSV files (docs/13 S17): RosterBuilder runs
## the match engine's formula backwards so that the pack plays that season again. The files
## (UTF-8, a header row, columns in any order; columns in brackets may be left out):
##
##   teams.csv     id, name, short, [stadium], [primary], [secondary], [accent]
##   players.csv   id, team, name, number, born, [height_cm], [weight_kg], bats (R/L/S),
##                 throws (R/L), positions ("SS/2B"; pitchers "SP" or "RP"), [origin
##                 (foreign/asia)], [registered (1 on the first team, 0 not)]
##   batting.csv   id, pa, [ab], h, 2b, 3b, hr, bb, [hbp], so, [sb], [cs]
##   pitching.csv  id, g, gs, outs (innings × 3), bf, so, bb, hr
##
## The records are the user's to gather (the KBO's site does not allow automatic collection);
## they and the pack stay in the local content pack, out of git.
##
##   godot --headless --path game --script res://tools/build_roster.gd -- --in ../content-local/raw/2025 --out ../content-local/rosters/kbo-2025.json --id kbo-2025 --name "KBO 2025" --season 2025 [--league-prior] [--contact-from-k 0.8]


func _init() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var dir := _path(str(args.get("in", "")))
	var out := _path(str(args.get("out", "")))
	if dir == "" or out == "":
		print("build_roster: --in <folder of CSV files> --out <pack.json> [--id] [--name] [--season]")
		quit(1)
		return
	var tables: Array = []
	for name: String in ["teams", "players", "batting", "pitching"]:
		var rows := read_csv(dir.path_join(name + ".csv"))
		if rows.is_empty():
			print("build_roster: %s.csv missing or empty in %s" % [name, dir])
			quit(1)
			return
		tables.append(rows)
	# Variants to try against a real season (tools/season_check.gd --roster).
	RosterBuilder.by_playing_time = not args.has("league-prior")
	RosterBuilder.contact_from_k = float(str(args.get("contact-from-k", RosterBuilder.CONTACT_FROM_K)))
	var teams := RosterBuilder.build(tables[0], tables[1], tables[2], tables[3], LeagueEnvIO.load_default(), PitchCatalogIO.load_default(), RosterIO.load_names())
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := RosterIO.save_pack(out, str(args.get("id", out.get_file().get_basename())), str(args.get("name", "")), int(str(args.get("season", "2025"))), teams)
	var count := 0
	for t: Team in teams:
		count += t.players.size()
	print("build_roster: %s (%d clubs, %d players) %s" % [out, teams.size(), count, "ok" if err == OK else error_string(err)])
	quit(0 if err == OK else 1)


func _path(p: String) -> String:
	if p == "" or p.is_absolute_path():
		return p
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


## Rows of a CSV file as Dictionaries keyed by the header (numbers stay strings; the builder
## reads them with float()/int()).
static func read_csv(path: String) -> Array:
	var rows: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return rows
	var header := f.get_csv_line()
	for i: int in header.size():
		header[i] = header[i].strip_edges().to_lower().trim_prefix("﻿")
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < header.size() or (line.size() == 1 and line[0].strip_edges() == ""):
			continue
		var row := {}
		for i: int in header.size():
			row[header[i]] = line[i].strip_edges()
		rows.append(row)
	return rows
