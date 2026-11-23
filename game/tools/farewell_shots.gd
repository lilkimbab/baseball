extends SceneTree
## Photographs a retirement at the ballpark (FarewellScene) for checking it: a veteran's career
## made up (fifteen seasons, his number retired), the tribute skipped, the ceremony on the field
## photographed at --at times (s, the default through all of it).
##
##   ./dev tool-win farewell_shots build/farewell/f [--at 1,5,9,13,17,21]

var _prefix := "user://farewell"
var _times: Array[float] = [1.0, 4.5, 7.5, 9.0, 11.0, 13.5, 15.0, 17.0, 19.0, 21.5]
var _scene: FarewellScene
var _taken := 0
var _due: Array[String] = []
var _frames := 0


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_prefix = args.get("out", _prefix)
	if args.has("at"):
		_times.clear()
		for t: String in str(args["at"]).split(","):
			_times.append(float(t))
	Profile.tool_run()
	var rules := CareerIO.load_default()
	var spec := PlayerCreator.Spec.new()
	spec.name = "한도윤"
	spec.number = 27
	spec.type_id = rules.batter_types[0].id
	var made := PlayerCreator.create(spec, rules, PitchCatalogIO.load_default())
	CareerSession.start(made, LeagueSession.league_clubs()[2].id, 36, 5)
	var cs := CareerSession.career_season
	cs.pro_games = 36
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
	var c := CareerSession.career
	var team: Team = cs.season.teams[c.team_id]
	var now := cs.season.season_year
	for i: int in 14:
		var b := BattingLine.new()
		b.games = 130
		b.pa = 560
		b.ab = 500
		b.hits = 155
		b.home_runs = 24
		b.rbi = 88
		c.seasons.append([now - 14 + i, team.name, 150, "1군 타율 .310 24홈런", SaveIO.fields(b), SaveIO.fields(PitchingLine.new())])
	c.pro_years = 14
	c.titles_won = [[now - 9, "홈런왕"], [now - 6, "홈런왕"]]
	c.all_stars = 8
	cs.cues.clear()
	CareerSession.slot = "farewell_shots"
	_scene = (load(CareerSession.FAREWELL) as PackedScene).instantiate() as FarewellScene
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	for name: String in _due:
		root.get_texture().get_image().save_png("%s_%s.png" % [_prefix, name])
		print("farewell_shots: %s" % name)
	_due.clear()
	if _frames > 20000:
		return true
	if _scene._tribute != null and is_instance_valid(_scene._tribute):
		_scene._tribute._finish()
	var b := _scene.broadcast
	if _scene._stage == 1 and b.current != null and b.current.kind == Broadcast.Kind.FAREWELL:
		if _taken < _times.size() and b.time >= _times[_taken]:
			_due.append("%02d_%04.1f" % [_taken, b.time])
			_taken += 1
		return false
	if _scene._stage >= 1 and _taken > 0 and (b.current == null or _taken >= _times.size()):
		SaveIO.delete_slot("farewell_shots")
		return _due.is_empty()
	return false
