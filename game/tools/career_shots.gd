extends SceneTree
## Screenshots of the career screens: player creation, the hub, and a scene card in a game.
##
##   ./dev tool-win career_shots build/career/shot

var _prefix := "user://career"
var _frames := 0
var _step := 0
var _node: Node
var _match: CareerMatch
var _card_frames := 0


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_prefix = args.get("out", _prefix)
	CareerSession.career_season = null
	_node = (load(CareerSession.CREATE) as PackedScene).instantiate()
	root.add_child(_node)


func _shot(tag: String) -> void:
	root.get_texture().get_image().save_png("%s_%s.png" % [_prefix, tag])
	print("career_shots: %s" % tag)


func _process(delta: float) -> bool:
	_frames += 1
	if _match != null:
		_match.step(1.0 / 30.0)
		if _match.paused and _match.my_scene_now() and _frames > 10:
			_card_frames += 1
			# The screen texture is the frame drawn before this one.
			if _card_frames == 4:
				_shot("card")
				return true
		return _frames > 20000
	if _frames % 10 != 0:
		return false
	match _step:
		0:
			var c := _node as CreationScreen
			c.spec.name = "한결"
			c.spec.number = 27
			c.spec.position = "CF"
			c.spec.type_id = "speed"
			c.team_id = RosterIO.load_pack(LeagueSession.PACK)[24].id
			c.refresh()
		1:
			_shot("create")
			var r := CareerIO.load_default()
			var c := _node as CreationScreen
			CareerSession.start(PlayerCreator.create(c.spec, r, PitchCatalogIO.load_default()), c.team_id, 36, 11)
			for i: int in 6:
				if CareerSession.career_season.has_game():
					CareerSession.last_report = CareerSession.career_season.quick()
				CareerSession.career_season.next_day()
			CareerSession.career.gp["batting"] = 120.0
			_node.queue_free()
			_node = (load(CareerSession.HUB) as PackedScene).instantiate()
			root.add_child(_node)
		2:
			_shot("hub")
			while not CareerSession.career_season.has_game():
				CareerSession.career_season.next_day()
			_node.queue_free()
			_match = (load(CareerSession.MATCH) as PackedScene).instantiate() as CareerMatch
			root.add_child(_match)
	_step += 1
	return false
