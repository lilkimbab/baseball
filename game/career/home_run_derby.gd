class_name HomeRunDerby
extends DuelScene
## The career player's turn in the home run derby: batting
## practice pitches over the middle at about 112 km/h; every swing that is not a home run is an
## out, a take is nothing; ten outs and the turn is over. The count goes back to the career.

## The league's derby: his hitter, set by the league screen before it opens;
## null for the career's.
static var league_batter: Player

var home_runs := 0
var outs := 0
var limit := 10
var speed := 112.0
var done := false
var _bp_rng := Rng.new(7)


func _ready() -> void:
	mode = &"bat"
	var cs := CareerSession.career_season
	if league_batter != null:
		var p := league_batter
		settings.contact = p.batting.contact()
		settings.power = p.batting.power()
		settings.eye = p.batting.eye
		settings.batter_height = p.height_cm / 100.0
		settings.bats_left = p.bats == &"L"
		limit = LeagueAllStar.DERBY_OUTS
		cs = null
	if cs != null:
		var p := cs.career.player
		settings.contact = p.batting.contact()
		settings.power = p.batting.power()
		settings.eye = p.batting.eye
		settings.batter_height = p.height_cm / 100.0
		settings.bats_left = p.bats == &"L"
		limit = int(cs.rules.all_star.get("derby_outs", 10))
		speed = float(cs.rules.all_star.get("derby_speed", 112.0))
	super._ready()
	# Balls and strikes mean nothing here; the outs and home runs are on the help line.
	(hud as DuelHud).show_count = false


func set_mode(_new_mode: StringName) -> void:
	pass


func help_keys() -> String:
	if done:
		return "홈런 %d개 · Enter %s로 돌아가기" % [home_runs, "리그" if league_batter != null else "전설의 시작"]
	return "홈런 더비 · 홈런 %d개 · 아웃 %d/%d · 클릭 스윙" % [home_runs, outs, limit]


## A batting-practice pitch: a four-seam at derby speed, over the middle, a little scattered.
func _ai_pitch_decision() -> PitchDecision:
	var d := PitchDecision.new()
	d.type = catalog[&"four_seam"]
	var c := duel.zone.center()
	d.target = c + Vector3(_bp_rng.next_normal() * 0.08, 0.0, _bp_rng.next_normal() * 0.07)
	d.quality = 1.0
	d.effort = speed / d.type.speed_kmh
	return d


func _finish_pitch() -> void:
	if duel.result == PitchDuel.Result.HOME_RUN:
		home_runs += 1
	elif duel.swing != null:
		outs += 1
	super._finish_pitch()
	if outs >= limit and not done:
		done = true
		banner = "홈런 더비 끝: %d개" % home_runs
		banner_time = 1e9
		if league_batter != null and LeagueSession.season != null:
			var lines := LeagueAllStar.swung_derby(LeagueSession.season, home_runs, Difficulty.by_id(Settings.difficulty)) if not Profile.tool_run() else PackedStringArray()
			if LeagueAllStar.winner(LeagueSession.season) == league_batter.id:
				banner = "홈런 더비 우승! %d개" % home_runs
			if not lines.is_empty():
				banner += "  ·  " + lines[lines.size() - 1]
			LeagueSession.autosave()
		elif CareerSession.career_season != null:
			var winner := CareerSession.career_season.finish_derby(home_runs)
			if winner == CareerSession.career_season.career.player.id:
				banner = "홈런 더비 우승! %d개" % home_runs


func _after_result() -> void:
	if done:
		return
	super._after_result()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if done and key != null and key.pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_ESCAPE):
		if league_batter != null:
			league_batter = null
			Loading.go(get_tree(), LeagueSession.SCREEN, {"title": "리그로 이동 중"})
			return
		Loading.go(get_tree(), CareerSession.HUB, {"title": "커리어로 이동 중"})
		return
	super._unhandled_input(event)
