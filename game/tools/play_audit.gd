extends SceneTree
## Looks for faults in how balls in play are shown (docs/13 S12): plays the match scene frame
## by frame, as it is drawn, and counts the things that should never be seen. Each is listed
## with how often it happened and a few of the places (play number, who, when), so it can be
## found again with the same seed.
##
##   godot --headless --path game --script res://tools/play_audit.gd -- --plays 150
##
## Options: --plays <n, default 120>  --seed <n>
##          --bat: the player at bat (swings scripted), the slow-motion moments as they come;
##                 with --force every fly and every first catch is made one
##          --field: the player in the field with his own fielder run at the ball
##
## What is counted (a frame is a sixtieth of a second of the play):
##   jump       someone moved faster than anyone runs (more than JUMP_SPEED m/s)
##   spin       someone turned more than SPIN_DEG degrees in one frame
##   lurch      someone's hips rose or fell more than LURCH m in one frame
##   ball jump  the ball moved further in a frame than a ball can
##   catch gap  at a catch the ball in flight was more than CATCH_GAP m from the glove
##   throw gap  at a throw's release the ball was more than THROW_GAP m from the hand
##   (the ball shown is in the glove from a catch and in the hand from a throw's start: a jump
##   between the two shows up as a ball jump)
##   overlap    two people stood inside each other for more than OVERLAP_TIME s
##   lost ball  the ball was off the screen for more than LOST_TIME s of a play
##   camera     the camera moved more than CAMERA_JUMP m in a frame without a cut being due
##   close-up   in a slow-motion moment its subject was not on the screen

const DT := 1.0 / 60.0
const JUMP_SPEED := 12.5
const SPIN_DEG := 50.0
const LURCH := 0.3
const BALL_SPEED := 75.0
const CATCH_GAP := 0.45
const THROW_GAP := 0.8
const OVERLAP := 0.3
const OVERLAP_TIME := 0.3
const LOST_TIME := 0.6
const CAMERA_JUMP := 4.0

var _scene: MatchScene
var _want := 120
var _bat := false
var _field := false
var _force := false
var _plays := 0
var _frames := 0
var _rng := Rng.new(5)
var _swung := false
var _counts := {}
var _examples := {}
## Per puppet: where it was, which way it faced and how high its hips were, last frame.
var _last := {}
var _ball_last := Vector3.INF
var _camera_last := Vector3.INF
var _time_last := -1.0
var _overlaps := {}
var _lost := 0.0
var _lost_noted := false
var _was_close := false
var _play_seen: PlayResult
var _still := 0
var _done_moments := {}


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_want = int(str(args.get("plays", "120")))
	_bat = args.has("bat")
	_field = args.has("field")
	_force = args.has("force")
	Settings.manual_fielding = _field
	Settings.highlights = true
	_scene = (load("res://match/match.tscn") as PackedScene).instantiate() as MatchScene
	_scene.human_team = 0 if _bat else (1 if _field else -1)
	_scene.innings = 9
	_scene.use_motion = false
	_scene.seed_value = int(str(args.get("seed", "31")))
	root.add_child(_scene)
	_drive_alone(_scene)


## Only this tool moves the scene on, a sixtieth of a second at a time, as the game's own
## frames would. (Left to itself the scene also stepped and redrew once per engine frame,
## with the real time since the last one: a third of a second, which finished every pose
## easing at once and showed as jumps that the game does not have.)
func _drive_alone(scene: Node) -> void:
	scene.set_process(false)
	scene.set_physics_process(false)


func _process(_delta: float) -> bool:
	for i: int in 30:
		_tick()
		if _plays >= _want:
			_report()
			return true
		if _scene.game.over:
			# Another game, on from where the seed left off.
			var seed_value := _scene.seed_value + 1
			var team := _scene.human_team
			_scene.queue_free()
			_scene = (load("res://match/match.tscn") as PackedScene).instantiate() as MatchScene
			_scene.human_team = team
			_scene.innings = 9
			_scene.use_motion = false
			_scene.seed_value = seed_value
			root.add_child(_scene)
			_drive_alone(_scene)
			_last.clear()
			return false
	_frames += 1
	if _frames > 400000:
		_report()
		return true
	return false


func _tick() -> void:
	_play_for_the_player()
	var was := _scene._play_time
	_scene.step(DT)
	var playing := _scene._play_time >= 0.0 and _scene._play != null
	if playing and _scene._play != _play_seen and _scene._play_time < 0.1:
		if _force and _scene._highlights.is_empty() and _scene._controls_running() and not _scene._play.foul:
			_force_highlights()
	if playing:
		_play_seen = _scene._play
	_scene.refresh(DT)
	if playing and not _scene._play.foul and not _scene._running:
		_look()
	else:
		_forget()
	if was >= 0.0 and _scene._play_time < 0.0:
		_plays += 1
		_forget()
		_done_moments.clear()


func _forget() -> void:
	_last.clear()
	_overlaps.clear()
	_ball_last = Vector3.INF
	_camera_last = Vector3.INF
	_time_last = -1.0
	_lost = 0.0
	_lost_noted = false
	_was_close = false


func _note(what: String, where: String) -> void:
	_counts[what] = int(_counts.get(what, 0)) + 1
	var list: Array = _examples.get(what, [])
	if list.size() < 8:
		list.append("play %d %s" % [_plays, where])
	_examples[what] = list


func _people() -> Dictionary[String, Puppet]:
	var all: Dictionary[String, Puppet] = {}
	for kind: Position.Kind in _scene.fielders:
		all["F:%s" % Position.code(kind)] = _scene.fielders[kind]
	for i: int in _scene.runner_puppets.size():
		if _scene.runner_puppets[i].visible and _scene._runners_at_start[i] != "":
			all["R%d" % (i + 1)] = _scene.runner_puppets[i]
	if _scene.batter.visible:
		all["B"] = _scene.batter
	return all


func _look() -> void:
	var t := _scene._play_time
	var step := t - _time_last if _time_last >= 0.0 else 0.0
	var h := _scene.highlight()
	var close := h != null
	# What moved, and how.
	var people := _people()
	if step > 1e-5:
		for key: String in people:
			var p := people[key]
			var at := Field.to_field(p.global_position)
			var now := [at, p.rotation.y, p.shown_hips_height(), str(_scene._doing.get(p, &""))]
			if _last.has(key):
				var before: Array = _last[key]
				var moved := Vector2(at.x - before[0].x, at.y - before[0].y).length()
				if moved / step > JUMP_SPEED and moved > 0.35:
					var track: Variant = _scene._play.timeline.tracks.get(key, PackedVector4Array())
					_note("jump", "%s t=%.2f moved %.1f m (doing %s, result %s by %s, fielded %s at %.2f, hard %s at %.2f, track %s)" % [key, t, moved, str(_scene._doing.get(p, &"")), PaResult.Kind.keys()[_scene._play.result], _scene._play.fielders, _scene._play.timeline.fielded_key, _scene._play.timeline.fielded_time, Position.code(_scene._play.hard_fielder), _scene._play.hard_time, str(track).substr(0, 160)])
				var turned := absf(rad_to_deg(wrapf(p.rotation.y - float(before[1]), -PI, PI))) * (DT / step)
				if turned > SPIN_DEG and step > DT * 0.5:
					_note("spin", "%s t=%.2f turned %.0f deg" % [key, t, turned])
				var hips := float(now[2])
				if absf(hips - float(before[2])) > LURCH and step > DT * 0.5:
					_note("lurch", "%s t=%.2f hips %.2f to %.2f (%s -> %s)" % [key, t, float(before[2]), hips, before[3], now[3]])
			_last[key] = now
	# The ball.
	var ball := _scene.shown_ball(t)
	if _ball_last.is_finite() and step > 1e-5:
		var went := ball.distance_to(_ball_last)
		if went > maxf(BALL_SPEED * step, 1.2):
			_note("ball jump", "t=%.2f moved %.1f m from %s to %s (throws %s)" % [t, went, _ball_last, ball, _scene._play.timeline.throws])
	_ball_last = ball
	# Catches and throws as they happen.
	if _scene._moves != null and _time_last >= 0.0:
		for key: String in _scene._moves.by_key:
			if not people.has(key):
				continue
			for m: PlayMoves.Moment in _scene._moves.by_key[key]:
				var tag := "%d|%s|%d|%.2f" % [_plays, key, m.kind, m.time]
				if _done_moments.has(tag) or not (_time_last < m.time and t >= m.time):
					continue
				_done_moments[tag] = true
				var p := people[key]
				if m.kind == PlayMoves.Kind.CATCH:
					# The glove against the ball in flight (the ball shown is in the glove from
					# the catch on).
					var glove := Field.to_field(p.global_transform * p.glove_pocket())
					var gap := glove.distance_to(_scene._ball_at(_scene._play.timeline, t))
					if gap > CATCH_GAP:
						var tl := _scene._play.timeline
						_note("catch gap", "%s t=%.2f ball %.2f m from the glove (ball z %.1f) fielded %s at %.2f, ball then %s, his track %s, misses %s %s" % [key, t, gap, ball.z, tl.fielded_key, tl.fielded_time, tl.position("ball", tl.fielded_time), tl.tracks[key], tl.miss_keys, tl.misses])
				elif m.kind == PlayMoves.Kind.THROW:
					var hand := Field.to_field(p.global_transform * p.ball_spot(&"RightHand"))
					var gap := hand.distance_to(ball)
					if gap > THROW_GAP:
						_note("throw gap", "%s t=%.2f ball %.2f m from the hand: he is at %s, the ball at %s, track %s" % [key, t, gap, Field.to_field(p.global_position), ball, _scene._play.timeline.tracks[key]])
	# People inside each other.
	var keys := people.keys()
	for i: int in keys.size():
		for j: int in range(i + 1, keys.size()):
			var a := Field.to_field(people[keys[i]].global_position)
			var b := Field.to_field(people[keys[j]].global_position)
			var pair := "%s+%s" % [keys[i], keys[j]]
			if Vector2(a.x - b.x, a.y - b.y).length() < OVERLAP:
				_overlaps[pair] = float(_overlaps.get(pair, 0.0)) + step
				if float(_overlaps[pair]) > OVERLAP_TIME and float(_overlaps[pair]) - step <= OVERLAP_TIME:
					_note("overlap", "%s t=%.2f" % [pair, t])
			else:
				_overlaps.erase(pair)
	# The camera.
	var cam := _scene.camera
	if _camera_last.is_finite() and close == _was_close:
		var swung := cam.global_position.distance_to(_camera_last)
		if swung > CAMERA_JUMP:
			_note("camera", "t=%.2f moved %.1f m" % [t, swung])
	_camera_last = cam.global_position
	# (A close-up is on the fielder: the ball may go by out of it.)
	if not close and not cam.is_position_in_frustum(Field.to_world(ball)) and t < _scene._play.timeline.duration:
		_lost += step
		if _lost > LOST_TIME and not _lost_noted:
			_lost_noted = true
			_note("lost ball", "t=%.2f ball at %s" % [t, ball])
	else:
		_lost = 0.0
	if close:
		var subject := Field.to_world(Vector3(0.0, 0.3, 1.0))
		var who := "the batter"
		if h.kind == PlayHighlight.Kind.CONTACT:
			subject = _scene.batter.global_position + Vector3.UP * 1.2
		else:
			var man := _scene._play.timeline.position(h.key, t)
			subject = Field.to_world(Vector3(man.x, man.y, 1.0))
			who = h.key
		_counts["close-up frames"] = int(_counts.get("close-up frames", 0)) + 1
		if not cam.is_position_in_frustum(subject):
			_note("close-up", "t=%.2f %s is off the screen (%s) eye %s look %s him %s spot %s from %.2f until %.2f" % [t, who, PlayHighlight.Kind.keys()[h.kind], Field.to_field(cam.global_position), _scene._follow_target, Field.to_field(subject), h.at, h.from, h.until])
		elif cam.global_position.distance_to(subject) > 16.0:
			_note("close-up", "t=%.2f %s is %.0f m away" % [t, who, cam.global_position.distance_to(subject)])
	_was_close = close
	_time_last = t


func _play_for_the_player() -> void:
	var duel := _scene.duel
	if _scene.human_pitches():
		match _scene.state:
			DuelScene.State.PRE_PITCH:
				if _scene.state_time > 0.3:
					_scene.target = duel.zone.point(_rng.next_range(0.1, 0.9), _rng.next_range(0.1, 0.9))
					_scene.press_pitch_button()
			DuelScene.State.CHARGE:
				if _scene.ring >= _scene.sweet - 0.02:
					_scene.release_pitch_button()
	if _scene.human_bats() and _scene.state == DuelScene.State.LIVE and duel.phase == PitchDuel.Phase.FLIGHT and not _swung:
		var at := duel.pitch.plate_pos
		if duel.zone.contains(at.x, at.z) and duel.time >= duel.ideal_contact_time - SwingModel.swing_time(SwingAttempt.Kind.POWER):
			_scene.swing(SwingAttempt.Kind.POWER)
			_swung = true
	if _scene.state != DuelScene.State.LIVE:
		_swung = false
	# The catch key when the prompt shows, as a player would.
	var own_fielder := _scene.manual_fielder()
	if own_fielder != null and _scene.manual_chasing() and own_fielder.catch_soon(_scene._play_time, duel.path) and not own_fielder.glove_up(_scene._play_time):
		own_fielder.press_catch(_scene._play_time)
	_scene.manual_push = Vector2.ZERO
	if _scene.manual_chasing():
		var own := _scene.manual_fielder()
		var t := _scene._play_time
		var going := duel.path.position_at(t + 0.35)
		if _scene.landing_known and t < _scene.landing_time:
			going = _scene.landing_point
		var to := Vector2(going.x, going.y) - own.pos
		if to.length() > 0.3:
			_scene.manual_push = to.normalized()


func _force_highlights() -> void:
	var play := _scene._play
	var found: Array[PlayHighlight] = []
	if duel_launch() > 15.0:
		var c := PlayHighlight.new()
		c.kind = PlayHighlight.Kind.CONTACT
		c.until = PlayHighlight.CONTACT_SPAN
		c.pace = PlayHighlight.CONTACT_PACE
		c.freeze = PlayHighlight.CONTACT_FREEZE
		found.append(c)
		_scene._freeze = c.freeze
	var key := "F:%s" % Position.code(_scene.chasing_fielder())
	var when := play.hard_time if play.has_hard_chance() else -1.0
	var where := play.hard_at
	if play.has_hard_chance():
		key = "F:%s" % Position.code(play.hard_fielder)
	else:
		for m: PlayMoves.Moment in _scene._moves.by_key.get(key, []):
			if m.kind == PlayMoves.Kind.CATCH and when < 0.0:
				when = m.time
				where = m.at
	if when > 1.0:
		var h := PlayHighlight.new()
		h.kind = PlayHighlight.Kind.CHANCE
		h.from = when - PlayHighlight.CHANCE_BEFORE
		h.until = when + PlayHighlight.CHANCE_AFTER
		h.pace = PlayHighlight.CHANCE_PACE
		h.at = where
		h.key = key
		found.append(h)
	_scene._highlights = found


func duel_launch() -> float:
	return _scene.duel.contact.launch_deg() if _scene.duel.contact != null else 0.0


func _report() -> void:
	var mode := "the player at bat" if _bat else ("the player in the field" if _field else "computer against computer")
	print("audit: %d plays, %s" % [_plays, mode])
	var order := ["jump", "spin", "lurch", "ball jump", "catch gap", "throw gap", "overlap", "lost ball", "camera", "close-up"]
	for what: String in order:
		var n := int(_counts.get(what, 0))
		print("audit: %-10s %5d  (%.2f a play)" % [what, n, float(n) / maxi(_plays, 1)])
		for where: String in _examples.get(what, []):
			print("audit:      %s" % where)
	if _counts.has("close-up frames"):
		print("audit: close-up frames looked at: %d" % int(_counts["close-up frames"]))
	quit(0)
