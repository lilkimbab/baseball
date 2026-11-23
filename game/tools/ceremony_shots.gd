extends SceneTree
## Photographs the cutscenes away from the field (Ceremony), each kind at a few moments, with a
## club's real man in its uniform:
##
##   ./dev tool-win ceremony_shots build/ceremony/c [--only award,champion] [--at 1.0,3.0,5.0]

const KINDS := ["draft", "contract", "award", "champion", "trade", "call_up"]

var _prefix := "user://ceremony"
var _kinds: Array = []
var _times: Array[float] = [1.2, 3.2, 4.4, 6.0]
var _index := -1
var _shown: Ceremony
var _clock := 0.0
var _taken := 0
var _due: Array[String] = []
var _wait := 0


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_prefix = args.get("out", _prefix)
	_kinds = str(args.get("only", ",".join(KINDS))).split(",")
	if args.has("at"):
		_times.clear()
		for t: String in str(args["at"]).split(","):
			_times.append(float(t))
	Profile.tool_run()
	var blank := Control.new()
	blank.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(blank)


func _process(delta: float) -> bool:
	for name: String in _due:
		root.get_texture().get_image().save_png("%s_%s.png" % [_prefix, name])
		print("ceremony_shots: %s" % name)
	_due.clear()
	if _wait > 0:
		_wait -= 1
		return false
	if _shown == null or not is_instance_valid(_shown):
		_index += 1
		if _index >= _kinds.size():
			return true
		_start(str(_kinds[_index]))
		_clock = 0.0
		_taken = 0
		return false
	_clock = _shown.time
	if _taken < _times.size() and _clock >= _times[_taken]:
		_due.append("%s_%d" % [_kinds[_index], _taken])
		_taken += 1
	elif _taken >= _times.size() or _shown._finished:
		# (Only after the last picture has been saved.)
		_shown.queue_free()
		_shown = null
		_wait = 3
	return false


func _start(kind: String) -> void:
	var clubs := LeagueSession.league_clubs()
	var club: Team = clubs[2]
	var other: Team = clubs[5]
	var man: Player = club.players[3]
	for p: Player in club.players:
		if not p.is_pitcher():
			man = p
			break
	var heading := {"draft": "2027 KBO 신인 드래프트", "contract": "2028 FA 계약", "award": "2027 KBO 시상식", "champion": "2027 한국시리즈", "trade": "2027년 트레이드", "call_up": "2027년 %s" % club.name}
	var big := {"draft": "%s 1라운드 3순위" % club.name, "contract": "%s 입단" % club.name, "award": "홈런왕", "champion": "%s 우승!" % club.name, "trade": "%s 이적" % club.name, "call_up": "첫 1군 등록"}
	var more := {"draft": ["계약금 2억 5,000만원", "서울고 출신"], "contract": ["4년 · 연봉 12억"], "award": ["타점왕", "상금 3,000만원"], "champion": ["2027년 통합 챔피언"], "trade": ["%s → %s" % [other.name, club.name]], "call_up": ["37일 · 퓨처스에서 올라왔습니다"]}
	_shown = Ceremony.play(root.get_child(0), Ceremony.KINDS[StringName(kind)], man, club, heading[kind], big[kind], PackedStringArray(more[kind]), Callable(), other if kind == "trade" else null)
