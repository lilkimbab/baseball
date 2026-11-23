extends SceneTree
## Photographs the menu screens (docs/04 section 5), for checking their look.
##
##   ./dev tool-win menu_shots build/menus/menu [--only hub,settings] [--league] [--career]
##       [--school | --school-done | --season-done] [--draft-at mine|end]
##
## --league starts a manager league first (so the hub and the league screen have one to show).

const SCREENS := {
	"title": "res://ui/title_screen.tscn", "hub": "res://ui/hub_screen.tscn", "quick": "res://ui/quick_match_screen.tscn",
	"settings": "res://ui/settings_screen.tscn", "practice": "res://ui/practice_screen.tscn", "load": "res://ui/load_screen.tscn",
	"shop": "res://ui/shop_screen.tscn", "league": "res://league/league_screen.tscn", "career": "res://career/career_screen.tscn",
	"create": "res://career/creation_screen.tscn", "achievements": "res://ui/achievements_screen.tscn",
	"draft": "res://career/draft_screen.tscn", "splash": "res://ui/splash_screen.tscn", "retire": "res://career/retire_screen.tscn",
}

var _prefix := "user://menu"
var _names := PackedStringArray()
var _index := -1
var _frames := 0
var _scene: Node
var _card := false
var _compare := false
var _args: Dictionary = {}
## --tab <id> --pick: the league screen on that tab, its first player picked. --records
## <batting|pitching|clubs>: the records room on that board. --compare: two hitters compared.
## --group <id>: the settings screen on that group (game, screen, sound, show).


func _initialize() -> void:
	_args = CmdArgs.parse(OS.get_cmdline_user_args())
	_prefix = str(_args.get("out", _prefix))
	_names = PackedStringArray(str(_args["only"]).split(","))
	# --roster <path>: the quick game with a roster pack of the local content pack.
	if _args.has("roster"):
		QuickMatchScreen.roster = str(_args["roster"])
	# --menu-font <id>: the menus in another family (UiTheme.MENU_FAMILIES).
	if _args.has("menu-font"):
		Settings.ensure_loaded()
		Settings.menu_font = str(_args["menu-font"])
		UiTheme.set_menu_family(Settings.menu_font)
	# --pick <base id> [--grade n]: the shop with that product picked, in that grade.
	if _args.has("pick") and not _args.has("tab"):
		ShopScreen.picked = str(_args["pick"])
		ShopScreen.picked_grade = int(str(_args.get("grade", "0")))
	# --group <game|screen|sound|show>: the settings screen opens on that group.
	if _args.has("group"):
		SettingsScreen.group = str(_args["group"])
	# --setup: the league screen's club choice (no league started).
	if _args.has("swing-turn"):
		PlayerStage.swing_turn = float(str(_args["swing-turn"]))
	if (_args.has("league") or _names.has("league")) and not _args.has("history") and not _args.has("setup"):
		var clubs := LeagueSession.league_clubs()
		LeagueSession.start(clubs[2].id, 36, 4)
		LeagueSession.slot = "menu_shots"
		for i: int in 6:
			LeagueSession.season.play_day(true)
			LeagueSession.season.advance()
	# --history <pack id> [--scenario <id>] [--ended]: the history mode's choice, or (with
	# --ended) a season of it played to the end.
	# --traits: a club with a few traits held and worn, to see the badge case filled.
	if _args.has("traits") and LeagueSession.season != null:
		var s := LeagueSession.season
		var team: Team = s.teams[s.my_team]
		for item: Vector2i in [Vector2i(0, 0), Vector2i(0, 0), Vector2i(1, 1), Vector2i(8, 0), Vector2i(11, 2), Vector2i(13, 0), Vector2i(3, 0)]:
			s.club.bag.append(item)
		var men := team.first_team()
		var hitter: Player = null
		for man: Player in men:
			if not man.is_pitcher() and hitter == null:
				hitter = man
		s.club.equip(hitter, s.club.bag.find(Vector2i(1, 1)), s.club_rules)
		s.club.points = 260
	if _args.has("history") and _args.has("ended"):
		var pack := SeasonPack.by_id(str(_args["history"]))
		LeagueSession.start_history(pack, str(_args.get("scenario", "")), str(pack.team_ids[0]), 3)
		LeagueSession.slot = "menu_shots"
		LeagueSession.season.play_to_end()
	# --history <pack id> --post <days> [--team <id>]: that season played into its postseason.
	if _args.has("history") and _args.has("post"):
		var pack := SeasonPack.by_id(str(_args["history"]))
		LeagueSession.start_history(pack, "", str(_args.get("team", pack.team_ids[0])), 3)
		LeagueSession.slot = "menu_shots"
		LeagueSession.season.play_regular_season()
		for i: int in int(str(_args["post"])):
			LeagueSession.season.play_day(true)
			LeagueSession.season.advance()
	if _args.has("career") or _names.has("career"):
		var rules := CareerIO.load_default()
		var spec := PlayerCreator.Spec.new()
		spec.name = "한도윤"
		spec.number = 27
		spec.type_id = rules.batter_types[0].id
		spec.body_id = rules.bodies[1].id
		spec.skin = rules.skins[1]
		spec.hair = rules.hairs[0]
		spec.beard = rules.beards[0]
		var made := PlayerCreator.create(spec, rules, PitchCatalogIO.load_default())
		# --school: a high-school career (--school-done: its season played out, the draft next).
		if _args.has("school") or _args.has("school-done") or _names.has("draft"):
			var school := str((SchoolLeague.schools()[0] as Dictionary)["id"])
			CareerSession.start_school(made, school, 72, 5)
			if _args.has("school-done") or _names.has("draft"):
				var cs := CareerSession.career_season
				var guard := 0
				while not cs.season.finished() and guard < 200:
					if cs.has_game():
						cs.quick()
					cs.next_day()
					guard += 1
		else:
			CareerSession.start(made, LeagueSession.league_clubs()[2].id, 36, 5)
			CareerSession.career_season.pro_games = 36
			# --season-done: the pro season played out (the winter, the next season after it).
			if _args.has("season-done"):
				var cs := CareerSession.career_season
				var guard := 0
				while not cs.season.finished() and guard < 400:
					if cs.all_star_today:
						cs.quick_all_star()
					if cs.derby_waiting:
						cs.quick_derby()
					if cs.has_game():
						cs.quick()
					cs.next_day()
					guard += 1
				# --fa: a star with his eight seasons in, at his free agency (--fa-declared: filed,
				# with an agent, the offers in).
				if _args.has("fa"):
					var c := CareerSession.career
					for i: int in 8:
						c.first_days.append(cs.season.total_days())
					for key: String in ["contact_r", "contact_l", "power_r", "power_l", "eye"]:
						c.player.batting.set(key, 88.0)
					CareerSession.start_winter()
					if _args.has("fa-declared"):
						CareerFA.hire_agent(cs)
						CareerFA.declare(cs, Rng.new(3))
			# --rich: money in hand and a trainer hired (the 계약·투자 tab).
			if _args.has("rich"):
				CareerSession.career.money = 24000
				CareerSession.career.earned = 61000
				CareerSession.career_season.trainer = 1
				CareerSession.career_season.invest_paid = {"training": 2000}
		# (No cutscenes waiting: the screen itself is the picture.)
		if CareerSession.career_season != null:
			CareerSession.career_season.cues.clear()
		CareerSession.slot = "menu_shots_career"
	_next()


func _next() -> void:
	if _scene != null:
		_scene.queue_free()
		_scene = null
	_index += 1
	_frames = 0
	if _index >= _names.size():
		SaveIO.delete_slot("menu_shots")
		SaveIO.delete_slot("menu_shots_career")
		quit()
		return
	var name := _names[_index]
	# The opening's notice, the title with its menu open, the loading screens (a game's
	# match-up and the league's).
	if name == "splash_notice":
		_scene = (load(SCREENS["splash"]) as PackedScene).instantiate()
		_scene.set("_part", 2)
		root.add_child(_scene)
		current_scene = _scene
		return
	if name == "buttons":
		# Every look of button, as it stands and lit, an ordinary one in each part's colour.
		_scene = Control.new()
		_scene.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(_scene)
		var back := ColorRect.new()
		back.color = Color(0.06, 0.065, 0.08)
		back.set_anchors_preset(Control.PRESET_FULL_RECT)
		_scene.add_child(back)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.position = Vector2(80, 60)
		grid.add_theme_constant_override("h_separation", 60)
		grid.add_theme_constant_override("v_separation", 22)
		_scene.add_child(grid)
		var rows: Array = [["게임 시작", "play", "menu", UiTheme.BRAND], ["경기 시작", "play", "primary", UiTheme.BRAND], ["구매 · 400 P", "shopping-cart", "gold", UiTheme.BRAND],
			["삭제", "trash", "danger", UiTheme.BRAND], ["리그 · 다음 날", "caret-right", "button", UiTheme.MODE_COLOURS["league"]], ["전설의 시작 · 훈련", "barbell", "button", UiTheme.MODE_COLOURS["career"]],
			["연습 · 다시", "arrows-clockwise", "button", UiTheme.MODE_COLOURS["practice"]], ["상점 · 장비", "storefront", "button", UiTheme.MODE_COLOURS["shop"]]]
		for row: Array in rows:
			for lit: bool in [false, true]:
				var b := UiKit.button(str(row[0]), Callable(), str(row[1]), str(row[2]), 400.0)
				b.tint = row[3]
				b.preview_lit = lit
				grid.add_child(b)
		current_scene = _scene
		return
	if name == "title_open":
		_scene = (load(SCREENS["title"]) as PackedScene).instantiate()
		root.add_child(_scene)
		current_scene = _scene
		return
	if name == "loading_match" or name == "loading_place":
		_scene = Node.new()
		root.add_child(_scene)
		var veil := Loading.new()
		if name == "loading_match":
			var clubs := RosterIO.load_pack("res://data/rosters/fiction-2026.json")
			veil.set("_info", {"away": clubs[0], "home": clubs[1], "title": "친선 경기", "line": "등대 파크 · 야간 · 9이닝", "record0": "12승 8패 1무", "record1": "10승 11패 0무"})
			veil.set("_target", "res://match/match.tscn")
		else:
			veil.set("_info", {"title": "리그로 이동 중"})
			veil.set("_target", LeagueSession.SCREEN)
		veil.set("_stage", 2)
		veil.set("_progress", 1.0)
		_scene.add_child(veil)
		return
	if name == "card":
		_scene = (load(SCREENS["hub"]) as PackedScene).instantiate()
		root.add_child(_scene)
		current_scene = _scene
		_card = true
		return
	_scene = (load(SCREENS[name]) as PackedScene).instantiate()
	root.add_child(_scene)
	current_scene = _scene
	# --draft-at <mine|end>: the draft board run on to his pick, or to its end.
	var draft := _scene as DraftScreen
	if draft != null and _args.has("draft-at"):
		if str(_args["draft-at"]) == "end":
			draft.skip_to_end()
		else:
			draft.skip_to_mine()
	# --career-tab <home|growth|table>: the career hub's tab.
	var career := _scene as CareerScreen
	if career != null and _args.has("career-tab"):
		career.set("_tab", str(_args["career-tab"]))
		if career.is_node_ready():
			career.refresh()
	var league := _scene as LeagueScreen
	if league != null and _args.has("history") and not _args.has("ended") and not _args.has("post"):
		league.set("_setup_mode", "history")
		league.set("_pack_id", str(_args["history"]))
		league.set("_scenario_id", str(_args.get("scenario", "")))
		if league.is_node_ready():
			league.refresh()
	if league != null and _args.has("tab"):
		league.set("_tab", str(_args["tab"]))
		if _args.has("pick"):
			var s := LeagueSession.season
			league.set("_picked", (s.teams[s.my_team] as Team).first_team()[2].id)
		# --records <batting|pitching|clubs>: the records room's board.
		if _args.has("records"):
			league.set("_records_view", str(_args["records"]))
		# --farm <players|table>: the second-team tab's view; with --pick, its first man.
		if _args.has("farm"):
			league.set("_farm_view", str(_args["farm"]))
			if _args.has("pick"):
				var s := LeagueSession.season
				league.set("_picked", (s.teams[s.my_team] as Team).second_team()[0].id)
		if league.is_node_ready():
			league.refresh()
		# --compare: two of the club's hitters side by side (opened once the screen is built).
		_compare = _args.has("compare")


func _process(_delta: float) -> bool:
	if _scene == null:
		return false
	_frames += 1
	if _card and _frames == 5:
		_card = false
		var s := LeagueSession.season
		var team: Team = s.teams[s.my_team]
		var pick: Player = null
		for p: Player in team.first_team():
			if p.is_pitcher() == _args.has("pitcher"):
				pick = p
				break
		PlayerCard.open_for(_scene, pick, s)
	if _compare and _frames == 5:
		_compare = false
		var s := LeagueSession.season
		var hitters: Array[Player] = []
		for p: Player in (s.teams[s.my_team] as Team).first_team():
			if not p.is_pitcher():
				hitters.append(p)
		PlayerCompare.open_for(_scene, hitters[0], hitters[3], s)
	# --frames 40,80,120: several pictures of the screen as it moves (the title's swing).
	if _args.has("frames"):
		var marks := PackedInt32Array(Array(str(_args["frames"]).split(",")).map(func(x: String) -> int: return int(x)))
		if marks.has(_frames):
			var shot := "%s_%s_f%03d.png" % [_prefix, _names[_index], _frames]
			root.get_texture().get_image().save_png(shot)
			print("menu_shots: ", shot)
		if _frames >= marks[marks.size() - 1]:
			_next()
		return false
	if _names[_index] == "title_open" and _frames == 20:
		_scene.call("_open")
	var shoot_at := 50 if _names[_index].begins_with("loading_") else (90 if _names[_index] == "splash_notice" else 150)
	# (The opening's ident by its own clock: at the moment the name has been drawn.)
	if _names[_index] == "splash" or _names[_index] == "splash_notice":
		if float(_scene.get("_t" if _names[_index] == "splash" else "_part_t")) < (1.9 if _names[_index] == "splash" else 1.2):
			return false
	elif _frames < shoot_at:
		return false
	var path := "%s_%s.png" % [_prefix, _names[_index]]
	root.get_texture().get_image().save_png(path)
	print("menu_shots: ", path)
	_next()
	return false
