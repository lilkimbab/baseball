class_name PitchTally
extends RefCounted
## Pitch-by-pitch and batted-ball counts from the physical resolver, checked against the
## targets for the pitcher and batter AI and batted-ball quality (docs/09 8.3).

var pitches := 0
var in_zone := 0
var swings := 0
var swings_in_zone := 0
var swings_out_zone := 0
var far_out := 0
var far_out_swings := 0
var contacts := 0
var first_pitches := 0
var first_strikes := 0
var three_ball := 0
var three_ball_zone := 0
var oh_two := 0
var oh_two_zone := 0
var three_oh := 0
var three_oh_swings := 0
var plate_appearances := 0
var hit_by_pitch := 0
var foul_tips := 0
var fouls := 0
var batted := 0
var exit_speed := 0.0
var launch := 0.0
var grounders := 0
var liners := 0
var flies := 0
var popups := 0
var pulled := 0
var centre := 0
var opposite := 0
var home_runs := 0
var misses: Dictionary[StringName, int] = {}
## Balls in play (not home runs) and hits on them, by launch: ground, line, fly, pop-up.
var in_play_by_kind := PackedInt32Array([0, 0, 0, 0])
var hits_by_kind := PackedInt32Array([0, 0, 0, 0])
var errors_by_kind := PackedInt32Array([0, 0, 0, 0])
var doubles_by_kind := PackedInt32Array([0, 0, 0, 0])
## Launch angles of batted balls in 10-degree bins from -40 to 80.
var launch_bins := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var offset_bins := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
## Exit speeds in 10 km/h bins from 60 to 190.
var speed_bins := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var failures := 0
var _rows := PackedStringArray()


func add(state: GameState, duel: PitchDuel) -> void:
	pitches += 1
	var zone := duel.zone.is_strike(duel.pitch)
	var plate := duel.pitch.plate_pos
	var swung := duel.swing != null and duel.swing.kind != SwingAttempt.Kind.BUNT
	if zone:
		in_zone += 1
	if swung:
		swings += 1
		if zone:
			swings_in_zone += 1
		else:
			swings_out_zone += 1
		if duel.swing.made_contact:
			contacts += 1
		else:
			var why := duel.swing.miss_reason if duel.swing.miss_reason != &"" else &"?"
			misses[why] = misses.get(why, 0) + 1
	if duel.zone.distance_outside(plate.x, plate.z) > 0.30:
		far_out += 1
		if swung:
			far_out_swings += 1
	var strike := zone or duel.swing != null or duel.result != PitchDuel.Result.BALL
	if duel.result == PitchDuel.Result.HIT_BY_PITCH:
		strike = false
		hit_by_pitch += 1
	if state.balls == 0 and state.strikes == 0:
		first_pitches += 1
		plate_appearances += 1
		if strike:
			first_strikes += 1
	if state.balls == 3:
		three_ball += 1
		if zone:
			three_ball_zone += 1
	if state.balls == 0 and state.strikes == 2:
		oh_two += 1
		if zone:
			oh_two_zone += 1
	if state.balls == 3 and state.strikes == 0:
		three_oh += 1
		if swung:
			three_oh_swings += 1
	if duel.result == PitchDuel.Result.FOUL_TIP:
		foul_tips += 1
	if duel.result == PitchDuel.Result.FOUL:
		fouls += 1
	if duel.contact != null and duel.contact.made_contact and duel.path != null and duel.result != PitchDuel.Result.FOUL:
		_batted(duel)


## The result of a ball in play, by how it was hit.
func add_play(duel: PitchDuel, play: PlayResult) -> void:
	if play.foul or duel.contact == null or play.result == PaResult.Kind.HOME_RUN:
		return
	var la := duel.contact.launch_deg()
	var k := 0 if la < 10.0 else (1 if la < 25.0 else (2 if la < 50.0 else 3))
	in_play_by_kind[k] += 1
	if PaResult.is_hit(play.result):
		hits_by_kind[k] += 1
	if play.result == PaResult.Kind.REACHED_ON_ERROR:
		errors_by_kind[k] += 1
	if play.result == PaResult.Kind.DOUBLE or play.result == PaResult.Kind.TRIPLE:
		doubles_by_kind[k] += 1


func _batted(duel: PitchDuel) -> void:
	batted += 1
	exit_speed += duel.contact.exit_speed_kmh()
	var la := duel.contact.launch_deg()
	launch += la
	launch_bins[clampi(int(floor((la + 40.0) / 10.0)), 0, 11)] += 1
	offset_bins[clampi(int(floor((duel.swing.offset + 0.08) / 0.01)), 0, 15)] += 1
	speed_bins[clampi(int(floor((duel.contact.exit_speed_kmh() - 60.0) / 10.0)), 0, 12)] += 1
	if la < 10.0:
		grounders += 1
	elif la < 25.0:
		liners += 1
	elif la < 50.0:
		flies += 1
	else:
		popups += 1
	# Spray as the batter sees it: positive toward his pull side.
	var spray := duel.contact.spray_deg() * (1.0 if duel.settings.bats_left else -1.0)
	if spray > 15.0:
		pulled += 1
	elif spray < -15.0:
		opposite += 1
	else:
		centre += 1
	if duel.result == PitchDuel.Result.HOME_RUN:
		home_runs += 1


func merge(other: PitchTally) -> void:
	for key: String in ["pitches", "in_zone", "swings", "swings_in_zone", "swings_out_zone", "far_out", "far_out_swings",
			"contacts", "first_pitches", "first_strikes", "three_ball", "three_ball_zone", "oh_two", "oh_two_zone",
			"three_oh", "three_oh_swings", "plate_appearances", "hit_by_pitch", "foul_tips", "fouls", "batted",
			"grounders", "liners", "flies", "popups", "pulled", "centre", "opposite", "home_runs"]:
		set(key, int(get(key)) + int(other.get(key)))
	exit_speed += other.exit_speed
	launch += other.launch
	for i: int in launch_bins.size():
		launch_bins[i] += other.launch_bins[i]
	for i: int in offset_bins.size():
		offset_bins[i] += other.offset_bins[i]
	for i: int in speed_bins.size():
		speed_bins[i] += other.speed_bins[i]
	for k: int in 4:
		in_play_by_kind[k] += other.in_play_by_kind[k]
		hits_by_kind[k] += other.hits_by_kind[k]
		errors_by_kind[k] += other.errors_by_kind[k]
		doubles_by_kind[k] += other.doubles_by_kind[k]
	for why: StringName in other.misses:
		misses[why] = misses.get(why, 0) + other.misses[why]


func text() -> String:
	_rows.clear()
	failures = 0
	var out_zone := maxi(pitches - in_zone, 1)
	_rows.append("투구 %d, 타석 %d (타석당 투구 %.2f)" % [pitches, plate_appearances, float(pitches) / maxi(plate_appearances, 1)])
	_check("존 안 스윙", float(swings_in_zone) / maxi(in_zone, 1), 0.65, 0.69)
	_check("존 밖 스윙", float(swings_out_zone) / out_zone, 0.26, 0.31)
	_check("30cm 넘게 벗어난 공에 스윙", float(far_out_swings) / maxi(far_out, 1), 0.0, 0.01)
	_check("스윙 중 접촉", float(contacts) / maxi(swings, 1), 0.77, 0.82)
	var why := PackedStringArray()
	for reason: StringName in misses:
		why.append("%s %.3f" % [reason, float(misses[reason]) / maxi(swings, 1)])
	_rows.append("  헛스윙 원인/스윙: " + ", ".join(why))
	_check("초구 스트라이크", float(first_strikes) / maxi(first_pitches, 1), 0.59, 0.63)
	_check("존 안 투구", float(in_zone) / maxi(pitches, 1), 0.47, 0.52)
	_check("3볼에서 존 안", float(three_ball_zone) / maxi(three_ball, 1), 0.65, 1.0)
	_check("0-2에서 존 안", float(oh_two_zone) / maxi(oh_two, 1), 0.0, 0.30)
	_check("3-0에서 스윙", float(three_oh_swings) / maxi(three_oh, 1), 0.0, 0.10)
	_check("타석당 투구", float(pitches) / maxi(plate_appearances, 1), 3.8, 4.0)
	_check("파울/투구", float(fouls + foul_tips) / maxi(pitches, 1), 0.16, 0.20)
	_rows.append("%-26s %8.4f" % ["사구/투구", float(hit_by_pitch) / maxi(pitches, 1)])
	var n := maxi(batted, 1)
	# Set by the home-run and in-play rates (docs/09 8.3); KBO exit speeds are not published.
	_check("평균 타구 속도(km/h)", exit_speed / n, 140.0, 146.0)
	_check("평균 발사각(°)", launch / n, 10.0, 14.0)
	_check("땅볼 비율", float(grounders) / n, 0.43, 0.47)
	_rows.append("%-26s %8.3f %8.3f %8.3f" % ["라인드라이브/뜬공/팝업", float(liners) / n, float(flies) / n, float(popups) / n])
	var parts := PackedStringArray()
	for k: int in 4:
		parts.append("%s %.3f (%d, 장타 %d, 실책 %d)" % [["땅볼", "라인", "뜬공", "팝업"][k], float(hits_by_kind[k]) / maxi(in_play_by_kind[k], 1), in_play_by_kind[k], doubles_by_kind[k], errors_by_kind[k]])
	_rows.append("  안타율: " + ", ".join(parts))
	var bins := PackedStringArray()
	for i: int in launch_bins.size():
		bins.append("%d:%.0f%%" % [-40 + 10 * i, 100.0 * launch_bins[i] / n])
	_rows.append("  발사각 분포: " + " ".join(bins))
	var offs := PackedStringArray()
	for i: int in offset_bins.size():
		offs.append("%d:%.0f%%" % [-8 + i, 100.0 * offset_bins[i] / n])
	_rows.append("  오프셋(cm) 분포: " + " ".join(offs))
	var speeds := PackedStringArray()
	for i: int in speed_bins.size():
		speeds.append("%d:%.0f%%" % [60 + 10 * i, 100.0 * speed_bins[i] / n])
	_rows.append("  타구 속도(km/h) 분포: " + " ".join(speeds))
	_check("뜬공 대비 홈런", float(home_runs) / maxi(flies + popups, 1), 0.08, 0.12)
	_check("당겨치기", float(pulled) / n, 0.38, 0.42)
	_check("가운데", float(centre) / n, 0.33, 0.37)
	_check("밀어치기", float(opposite) / n, 0.23, 0.27)
	return "\n".join(_rows)


func _check(label: String, value: float, low: float, high: float) -> void:
	var bad := value < low or value > high
	if bad:
		failures += 1
	_rows.append("%-26s %8.3f %8s %s" % [label, value, "%.2f~%.2f" % [low, high], "!!" if bad else ""])
