extends SceneTree
## Loads every save slot there is and plays each a few days on, in memory only (nothing is
## written back): do the person's own saves of older games still load and play? (queue stage 1)
##
##   ./dev tool-win save_check build/saves/check [--days 5]

func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var days := int(str(args.get("days", "5")))
	var slots := SaveIO.slots()
	print("save_check: %d slots" % slots.size())
	var bad := 0
	for meta: Dictionary in slots:
		var slot := str(meta["slot"])
		var mode := str(meta.get("mode", ""))
		var raw := SaveIO.read(SaveIO.slot_path(slot) + ("/career.json" if mode == "career" else "/league.json"))
		var line := "%s (%s, format %s, %s %s년 %s일)" % [slot, mode, str(meta.get("format", "?")), str(meta.get("team", "")), str(meta.get("year", "")), str(meta.get("day", ""))]
		if mode == "career":
			var cs := SaveIO.load_career(slot)
			if cs == null or cs.career.player == null:
				print("save_check: FAIL %s: did not load" % line)
				bad += 1
				continue
			for i: int in days:
				if cs.season.finished():
					break
				if cs.has_game():
					cs.quick()
				cs.next_day()
			print("save_check: ok %s → day %d, %s, salary %d" % [line, cs.season.day + 1, "1군" if cs.career.first_team else "2군", cs.career.salary])
		else:
			var s := SaveIO.load_league(slot)
			if s == null:
				print("save_check: FAIL %s: did not load" % line)
				bad += 1
				continue
			for i: int in days:
				if s.finished():
					break
				s.play_day(true)
				s.advance()
			print("save_check: ok %s → day %d, difficulty %d" % [line, s.day + 1, s.difficulty])
	print("save_check: %d failed" % bad)
	quit(0)
