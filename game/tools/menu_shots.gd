extends SceneTree
## Photographs the menu screens (docs/05 section 5), for checking their look.
##
##   ./dev tool-win menu_shots build/menus/menu [--only hub,settings] [--league] [--career]
##
## --league starts a manager league first (so the hub and the league screen have one to show).

const SCREENS := {
	"title": "res://ui/title_screen.tscn", "hub": "res://ui/hub_screen.tscn", "quick": "res://ui/quick_match_screen.tscn",
	"settings": "res://ui/settings_screen.tscn", "practice": "res://ui/practice_screen.tscn", "load": "res://ui/load_screen.tscn",
	"shop": "res://ui/shop_screen.tscn", "league": "res://league/league_screen.tscn", "career": "res://career/career_screen.tscn",
	"create": "res://career/creation_screen.tscn",
}

var _prefix := "user://menu"
var _names := PackedStringArray()
var _index := -1
var _frames := 0
var _scene: Node
var _card := false
var _args: Dictionary = {}
## --tab <id> --pick: the league screen on that tab, its first player picked.


func _initialize() -> void:
	_args = CmdArgs.parse(OS.get_cmdline_user_args())
	_prefix = str(_args.get("out", _prefix))
	_names = PackedStringArray(str(_args["only"]).split(","))
	if _args.has("league") or _names.has("league"):
		var clubs := RosterIO.load_pack(LeagueSession.PACK)
		LeagueSession.start(clubs[22].id, 36, 4)
		LeagueSession.slot = "menu_shots"
		for i: int in 6:
			LeagueSession.season.play_day()
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
		var clubs := RosterIO.load_pack(LeagueSession.PACK)
		CareerSession.start(PlayerCreator.create(spec, rules, PitchCatalogIO.load_default()), clubs[22].id, 36, 5)
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
	var league := _scene as LeagueScreen
	if league != null and _args.has("tab"):
		league.set("_tab", str(_args["tab"]))
		if _args.has("pick"):
			var s := LeagueSession.season
			league.set("_picked", (s.teams[s.my_team] as Team).first_team()[2].id)
		if league.is_node_ready():
			league.refresh()


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
	if _frames < 150:
		return false
	var path := "%s_%s.png" % [_prefix, _names[_index]]
	root.get_texture().get_image().save_png(path)
	print("menu_shots: ", path)
	_next()
	return false
