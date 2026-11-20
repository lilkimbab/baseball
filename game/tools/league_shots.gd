extends SceneTree
## Screenshots of the league screen: the setup, a day in the season with the club tabs, the
## postseason and the season's end.
##
##   ./dev tool-win league_shots build/league/shot

var _prefix := "user://league"
var _screen: LeagueScreen
var _frames := 0
var _step := 0
const STEPS: Array[String] = ["setup", "season", "farm", "scout", "traits", "postseason", "end"]


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_prefix = args.get("out", _prefix)
	LeagueSession.season = null
	_screen = (load(LeagueSession.SCREEN) as PackedScene).instantiate() as LeagueScreen
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % 8 != 0:
		return false
	if _step > 0:
		root.get_texture().get_image().save_png("%s_%s.png" % [_prefix, STEPS[_step - 1]])
		print("league_shots: %s" % STEPS[_step - 1])
	if _step >= STEPS.size():
		return true
	match STEPS[_step]:
		"season":
			var clubs := RosterIO.load_pack(LeagueSession.PACK)
			_screen.begin(clubs[25].id, 36)
			for d: int in 9:
				_screen.quick_result()
				_screen.next_day()
		"farm", "scout", "traits":
			if STEPS[_step] == "traits":
				LeagueSession.season.club.points = 400
				LeagueSession.season.club.buy_trait(LeagueSession.season.club_rules, Rng.new(3))
				LeagueSession.season.club.buy_trait(LeagueSession.season.club_rules, Rng.new(4))
			_screen._tab = STEPS[_step]
			_screen.refresh()
		"postseason":
			_screen._tab = "roster"
			_screen.to_phase_end()
		"end":
			_screen.to_phase_end()
	_step += 1
	return false
