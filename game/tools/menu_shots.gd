extends SceneTree
## Photographs the menu screens (docs/05 section 5), for checking their look.
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
					if cs.has_game():
						cs.quick()
					cs.next_day()
					guard += 1
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
	if _frames < 150:
		return false
	var path := "%s_%s.png" % [_prefix, _names[_index]]
	root.get_texture().get_image().save_png(path)
	print("menu_shots: ", path)
	_next()
	return false
