class_name DuelScene
extends Node3D
## Stage S3: pitcher against batter, one pitch at a time. The player bats against an AI
## pitcher, pitches to an AI batter, or watches the two AIs. No fielding or base running yet:
## a ball in play is followed until it stops or leaves the park.

enum State { PRE_PITCH, CHARGE, ACCURACY, WINDUP, LIVE, RESULT }

const TICK := 1.0 / 240.0
const AI_PITCH_DELAY := 1.3
const CHARGE_TIME := 0.9
const ACCURACY_TIME := 0.85
## Fraction of the accuracy sweep at which the ring is exactly on target.
const ACCURACY_SWEET := 0.75
const MAX_FOLLOW_TIME := 6.5
## How far outside the strike zone the pointer can be put: to the side, and above or below.
const AIM_BEYOND_ZONE := Vector2(0.25, 0.3)

const BAT_CAMERA := [Vector3(0.55, -2.7, 0.9), Vector3(-0.2, 18.4, -0.45), 45.0]
## Far behind the mound with a long lens, like the reference footage: the whole pitcher stands
## left of centre with his back to the camera, and the batter and catcher sit above him, large
## enough to aim at. Solved from a reference frame (reference/target-pitchview.png) by fitting
## where the pitcher, batter and umpire appear: about 61 m behind the pitcher, which makes the
## batter look nearly as tall as the pitcher (1.3 to 1), as in the reference.
const PITCH_CAMERA := [Vector3(-7.2, 79.2, 4.6), Vector3(0.17, 3.37, 0.9), 3.6]

## &"bat" = player bats, &"pitch" = player pitches, &"watch" = AI against AI.
@export var mode: StringName = &"bat"
@export var seed_value := 20261120
## Show the pitcher and batter as the skinned player model when it has been built.
@export var use_models := true
## Play recorded deliveries and swings when the local content pack has them (see MotionLibrary).
@export var use_motion := true

var cfg: PhysicsConfig
var catalog: Dictionary[StringName, PitchType]
var field_model: AnalyticField
## The ballpark (docs/13 S13): the practice park unless a full game picks the home club's.
var stadium: StadiumDef
var park: StadiumBuilder
## Day, dusk or night (docs/13 S13-7); a dome has its own light.
var time_of_day: StringName = &"day"
var lighting: ParkLighting
var settings := DuelSettings.new()
var duel: PitchDuel

var state: State = State.PRE_PITCH
var state_time := 0.0
var balls := 0
var strikes := 0
var banner := ""
var banner_time := 0.0

## Pitching input.
var pitch_ids: Array[StringName] = [&"four_seam", &"two_seam", &"slider", &"curve", &"changeup"]
var selected_pitch := 0
var target := Vector3.ZERO
var power := 0.0
var ring := 0.0
var accuracy := 0.0
var decision: PitchDecision

## Batting input.
## The batter aims his swing with the pointer (the bat-shaped cursor over the zone); off,
## the swing goes where he reads the pitch.
var aim_enabled := true
var aim_point := Vector3.ZERO
## Where the pointer is on screen. Tools and tests set this to aim without a mouse; while it
## is Vector2.INF the real mouse is used.
var pointer_override := Vector2.INF

var camera: Camera3D
var pitcher: Puppet
var batter: Puppet
var catcher: Puppet
var umpire: Puppet
var ball_actor: BallActor
var hud: DuelHud

## Recorded motion for the delivery and the swing; null = key poses.
var pitch_motion: PitchMotion
var swing_motion: SwingMotion

var _rng: Rng
var _ai_rng: Rng
var _pitch_count := 0
var _pitch_clock := -1.0
## Officials in the middle of a signal.
var _signalling: Dictionary[Puppet, bool] = {}
var _swing_clock := -1.0
var _swing_lead := 0.11
var _swing_height := 0.8
var _follow_target := Vector3.ZERO
var _load_started := false
var _throwing_hand: StringName = &"RightHand"
var _swing_shown := false
## The barrel's sweet spot at contact in the recorded swing, in the batter's space, and how
## far the hands have to move from the recording for this swing to go where it is aimed.
var _recorded_contact := Vector3.ZERO
var _reach := Vector3.ZERO
var _frame_time := 1.0 / 60.0
## Batting practice against some pitches only (their ids; empty: every pitch).
var practice_pool: Array = []
var from_practice_menu := false


func _ready() -> void:
	cfg = PhysicsConfigIO.load_default()
	catalog = PitchCatalogIO.load_default()
	_rng = Rng.new(seed_value)
	_ai_rng = _rng.fork(1)

	_read_practice()
	park = StadiumBuilder.new(stadium if stadium != null else StadiumDef.standard())
	add_child(park)
	field_model = park.collision
	_build_environment()
	_build_players()
	if use_motion:
		set_motion(MotionLibrary.find(&"pitch"), MotionLibrary.find(&"swing"))
	ball_actor = BallActor.new()
	add_child(ball_actor)
	ball_actor.visible = false

	camera = Camera3D.new()
	camera.far = 700.0
	add_child(camera)
	camera.make_current()
	_snap_camera()

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = DuelHud.new()
	hud.scene = self
	layer.add_child(hud)

	_new_duel()
	target = duel.zone.center()
	aim_point = duel.zone.center()


## The practice field opened from its menu (PracticeScreen): what to practise, against whom,
## where and at what hour.
func _read_practice() -> void:
	if not PracticeScreen.pending or get_script() != DuelScene:
		return
	PracticeScreen.pending = false
	from_practice_menu = true
	mode = StringName(PracticeScreen.mode)
	practice_pool = PracticeScreen.pitch_pool()
	settings.throws_left = PracticeScreen.pitcher_left
	settings.bats_left = PracticeScreen.batter_left
	if PracticeScreen.park != "":
		stadium = StadiumIO.load_park(PracticeScreen.park)
	time_of_day = StringName(PracticeScreen.time)


func set_mode(new_mode: StringName) -> void:
	mode = new_mode
	balls = 0
	strikes = 0
	_enter(State.PRE_PITCH)
	_snap_camera()


## Uses recorded clips for the delivery and the swing. Null keeps the key poses for that one.
func set_motion(pitch_clip: JointClip, swing_clip: JointClip, swing_high: JointClip = null, swing_low: JointClip = null) -> void:
	pitch_motion = PitchMotion.new(pitch_clip) if pitch_clip != null else null
	swing_motion = SwingMotion.new(swing_clip) if swing_clip != null else null
	if swing_motion != null:
		swing_motion.high = swing_high
		swing_motion.low = swing_low
	settings.release_point = DuelSettings.new().release_point
	var on_rubber := Vector3(0.0, Field.RUBBER_Y, Field.MOUND_HEIGHT)
	if pitch_motion != null:
		# The recording's origin is under the pivot foot, which stands against the front of the
		# rubber. The ball leaves from where this pitcher's hand is at the moment of release.
		on_rubber.y -= 0.06
		pitcher.position = Field.to_world(on_rubber)
		pitcher.reset_motion()
		_throwing_hand = &"LeftHand" if pitch_clip.side == &"L" else &"RightHand"
		pitcher.right_grip = Puppet.Grip.BALL
	else:
		pitcher.position = Field.to_world(on_rubber)
	var in_box := Vector3(-1.05, 0.25, 0.0)
	if swing_motion != null:
		# Stand the batter where the recorded swing meets the ball over the middle of the
		# plate and on the plane contact is judged at, as far as the box allows.
		batter.reset_motion()
		batter.apply_joints(swing_clip.sample(swing_motion.contact), swing_clip)
		_recorded_contact = batter.sweet_spot()
		batter.reset_motion()
		in_box.x = clampf(_recorded_contact.z, -1.25, -0.75)
		in_box.y = clampf(SwingModel.CONTACT_PLANE_Y + _recorded_contact.x, -0.3, 0.6)
	batter.position = Field.to_world(in_box)


## Where the ball leaves the pitcher's hand (field coordinates): the pitcher as he stands on
## the rubber now, posed at the moment of release. Measured at the release itself, so the
## ball always leaves from his hand. (Measured once when his delivery was chosen, through the
## figure as it happened to stand, it came out behind him when he had just fielded a ball and
## was still turned away, or on the wrong side when the last man drawn threw with the other
## hand.)
func pitcher_release_point() -> Vector3:
	if pitch_motion == null:
		return settings.release_point
	pitcher.apply_joints(pitch_motion.frame(release_time()), pitch_motion.clip)
	var at := Field.to_field(pitcher.global_transform * pitcher.ball_spot(_throwing_hand))
	# DuelSettings takes a right-hander's release point and mirrors it for a left-hander.
	return Vector3(-at.x, at.y, at.z) if settings.throws_left else at


func release_time() -> float:
	return pitch_motion.release_time if pitch_motion != null else PuppetClips.PITCH_RELEASE


## Number of pitches started since the scene loaded.
func pitches_thrown() -> int:
	return _pitch_count - 1


## Whether the timing call of the last swing is still shown.
func swing_feedback_visible() -> bool:
	return true


## The keys for this scene, for the help line.
func help_keys() -> String:
	return "F1 타격   F2 투구   F3 관전   Esc 나가기"


func human_pitches() -> bool:
	return mode == &"pitch"


func human_bats() -> bool:
	return mode == &"bat"


func selected_type() -> PitchType:
	return catalog[pitch_ids[selected_pitch]]


# --- The pitch wheel (docs/05 2.2; the user: "a circle with six directions, as in 2K14: the
# pitch is chosen by the way the mouse goes") ---

## A pitcher throws six pitches at most: one to each of six directions round a circle, the
## first straight up and the rest clockwise.
const WHEEL_SLOTS := 6
## The pointer has to leave the middle of the wheel by this much (px at 1080 lines) to choose.
const WHEEL_DEAD := 34.0

## Open while the right mouse button is held before a pitch: its middle on the screen, and
## the pitch the pointer is toward (-1 in the middle: keep the one already chosen).
var wheel_open := false
var wheel_centre := Vector2.ZERO
var wheel_pick := -1


## The direction of a slot of the wheel on the screen (y down): 0 straight up, then clockwise.
static func wheel_direction(slot: int) -> Vector2:
	return Vector2.UP.rotated(TAU * slot / WHEEL_SLOTS)


## The slot the pointer is toward from the wheel's middle, or -1 in the middle or toward a
## direction this pitcher has no pitch in.
func wheel_slot_toward(pointer: Vector2) -> int:
	var away := pointer - wheel_centre
	if away.length() < WHEEL_DEAD * maxf(get_viewport().get_visible_rect().size.y / 1080.0, 0.5):
		return -1
	var slot := posmod(roundi(Vector2.UP.angle_to(away) / (TAU / WHEEL_SLOTS)), WHEEL_SLOTS)
	return slot if slot < mini(pitch_ids.size(), WHEEL_SLOTS) else -1


## Opens the wheel at a place on the screen (the right mouse button; tools and tests call it).
func open_wheel(at: Vector2) -> void:
	if not human_pitches() or state != State.PRE_PITCH:
		return
	wheel_open = true
	wheel_centre = at
	wheel_pick = -1


## Closes the wheel and takes the pitch the pointer was toward, if any.
func close_wheel() -> void:
	if wheel_open and wheel_pick >= 0:
		selected_pitch = wheel_pick
	wheel_open = false
	wheel_pick = -1


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_F1:
				set_mode(&"bat")
			KEY_F2:
				set_mode(&"pitch")
			KEY_F3:
				set_mode(&"watch")
			KEY_V:
				aim_enabled = not aim_enabled
			KEY_ESCAPE:
				# The practice field goes back to the hub; run on its own, it ends the program.
				if OS.get_cmdline_user_args().is_empty() and ResourceLoader.exists("res://ui/hub_screen.tscn"):
					Loading.go(get_tree(), Screen.PRACTICE if from_practice_menu else Screen.HUB, {"title": "연습 종료"})
				else:
					get_tree().quit()
		if human_pitches() and state == State.PRE_PITCH:
			var index := key.keycode - KEY_1
			if index >= 0 and index < mini(pitch_ids.size(), WHEEL_SLOTS):
				selected_pitch = index

	var click := event as InputEventMouseButton
	if click == null:
		return
	if human_bats() and click.pressed:
		if click.button_index == MOUSE_BUTTON_LEFT:
			swing(SwingAttempt.Kind.CONTACT)
		elif click.button_index == MOUSE_BUTTON_RIGHT:
			swing(SwingAttempt.Kind.POWER)
	elif human_pitches() and click.button_index == MOUSE_BUTTON_RIGHT:
		if click.pressed:
			open_wheel(click.position)
		else:
			close_wheel()
	elif human_pitches() and click.button_index == MOUSE_BUTTON_LEFT and not wheel_open:
		if click.pressed:
			press_pitch_button()
		else:
			release_pitch_button()


## Player swing. Also used by tools to script input.
func swing(kind: SwingAttempt.Kind) -> void:
	if state != State.LIVE or duel.phase != PitchDuel.Phase.FLIGHT:
		return
	if duel.start_swing(kind, Vector2(aim_point.x, aim_point.z), aim_enabled):
		_begin_swing_pose()


func press_pitch_button() -> void:
	if state == State.PRE_PITCH:
		power = 0.0
		_enter(State.CHARGE)
	elif state == State.ACCURACY:
		accuracy = clampf(1.0 - absf(ring - ACCURACY_SWEET) / (1.0 - ACCURACY_SWEET), 0.0, 1.0)
		_begin_windup()


func release_pitch_button() -> void:
	if state == State.CHARGE:
		ring = 0.0
		_enter(State.ACCURACY)


func _physics_process(delta: float) -> void:
	step(delta)


## Advances the duel by one physics tick. Public so tests and tools can drive the scene
## without waiting for real frames.
func step(delta: float) -> void:
	state_time += delta
	banner_time = maxf(banner_time - delta, 0.0)
	if _pitch_clock >= 0.0:
		_pitch_clock += delta
	if _swing_clock >= 0.0:
		_swing_clock += delta
	if swing_motion != null:
		swing_motion.advance(delta)

	match state:
		State.PRE_PITCH:
			if not human_pitches() and state_time >= AI_PITCH_DELAY:
				decision = _ai_pitch_decision()
				_begin_windup()
		State.CHARGE:
			power = minf(power + delta / CHARGE_TIME, 1.0)
		State.ACCURACY:
			ring += delta / ACCURACY_TIME
			if ring >= 1.0:
				accuracy = 0.0
				_begin_windup()
		State.WINDUP:
			# The batter starts his stride while the pitcher is still in his delivery.
			if swing_motion != null and not _load_started and _pitch_clock >= release_time() - swing_motion.load_lead():
				_load_started = true
				swing_motion.begin_load()
			if _pitch_clock >= release_time():
				_release()
		State.LIVE:
			for i: int in roundi(delta / TICK):
				duel.tick(TICK)
			# A swing the AI scheduled at release starts when its time comes.
			if duel.swing != null and not _swing_shown and duel.time >= duel.swing.contact_time - SwingModel.swing_time(duel.swing.kind):
				_begin_swing_pose()
			var following := duel.phase == PitchDuel.Phase.IN_PLAY and state_time > MAX_FOLLOW_TIME
			var hit := duel.phase == PitchDuel.Phase.IN_PLAY and _finish_on_contact()
			if duel.is_over() or following or hit:
				_finish_pitch()
		State.RESULT:
			var hold := 2.6 if duel.result == PitchDuel.Result.HOME_RUN else 1.5
			if state_time >= hold:
				_after_result()


func _process(delta: float) -> void:
	refresh(delta)


## Updates everything that is only for show: poses, ball, camera, HUD.
func refresh(delta: float) -> void:
	_frame_time = delta
	_update_pointer()
	_update_preview()
	_record_trail(delta)
	_pose_players()
	_show_ball()
	_move_camera(delta)
	hud.queue_redraw()


func _enter(next: State) -> void:
	state = next
	state_time = 0.0


func _new_duel() -> void:
	_pitch_count += 1
	duel = PitchDuel.new(cfg, field_model, settings, _rng.fork(100 + _pitch_count))
	_pitch_clock = -1.0
	_swing_clock = -1.0
	_load_started = false
	_swing_shown = false


func _begin_windup() -> void:
	if human_pitches():
		decision = PitchDecision.new()
		decision.type = selected_type()
		decision.target = target
		decision.quality = accuracy
		decision.effort = lerpf(0.93, 1.0, power)
	_pitch_clock = 0.0
	_enter(State.WINDUP)


func _release() -> void:
	settings.release_point = pitcher_release_point()
	duel.throw_pitch(decision)
	if not human_bats():
		_ai_react()
	_enter(State.LIVE)


# --- Hooks a full game (MatchScene) replaces ---


## The computer's pitch when the player is not pitching.
func _ai_pitch_decision() -> PitchDecision:
	if not practice_pool.is_empty():
		var some: Dictionary[StringName, PitchType] = {}
		for id: StringName in practice_pool:
			if catalog.has(id):
				some[id] = catalog[id]
		if not some.is_empty():
			return AiPitcher.choose(some, duel.zone, _ai_rng)
	return AiPitcher.choose(catalog, duel.zone, _ai_rng)


## The computer batter's reaction right after release.
func _ai_react() -> void:
	AiBatter.react(duel, _ai_rng)


## The plate umpire is making some other signal than the pitch's (a full game's "time").
func _umpire_busy() -> bool:
	return false


## Hand the pitch over as soon as the ball is hit, instead of following it to rest.
func _finish_on_contact() -> bool:
	return false


## After the result has been shown: the next pitch.
func _after_result() -> void:
	_new_duel()
	_enter(State.PRE_PITCH)


func _begin_swing_pose() -> void:
	_swing_shown = true
	_swing_lead = SwingModel.swing_time(duel.swing.kind)
	_swing_height = duel.ideal_contact_pos.z
	if swing_motion != null:
		swing_motion.aim_height(_swing_height)
	_swing_clock = 0.0
	if swing_motion == null:
		return
	swing_motion.begin_swing(maxf(duel.swing.contact_time - duel.time, 0.02))
	# The recorded swing goes through one spot. Move the hands so that this one goes where
	# the batter aims, or where the pitch crosses if he is not aiming. Along the pitch's path
	# the swing meets the ball where the recording does.
	var at := duel.ideal_contact_pos
	if duel.swing.has_aim:
		at.x = duel.swing.aim.x
		at.z = duel.swing.aim.y
	_reach = batter.to_local(Field.to_world(at)) - _recorded_contact
	_reach.x = 0.0
	_reach = _reach.limit_length(0.45)


func _finish_pitch() -> void:
	match duel.result:
		PitchDuel.Result.BALL:
			balls += 1
			banner = "볼넷" if balls >= 4 else "볼"
		PitchDuel.Result.CALLED_STRIKE:
			strikes += 1
			banner = "삼진" if strikes >= 3 else "스트라이크"
		PitchDuel.Result.SWINGING_STRIKE:
			strikes += 1
			banner = "삼진" if strikes >= 3 else "헛스윙"
		PitchDuel.Result.FOUL:
			strikes = mini(strikes + 1, 2)
			banner = "파울"
		PitchDuel.Result.HOME_RUN:
			banner = "홈런!  %d m" % roundi(duel.carry_distance)
		_:
			banner = "인플레이  %d m" % roundi(Trajectory.ground_distance(duel.ball.pos))
	var in_play := duel.result == PitchDuel.Result.IN_PLAY or duel.result == PitchDuel.Result.HOME_RUN
	if in_play or balls >= 4 or strikes >= 3:
		balls = 0
		strikes = 0
	banner_time = 2.4
	if swing_motion != null:
		swing_motion.relax()
	_enter(State.RESULT)


# --- The pitch's path: before it is thrown (the player's), and after (everyone's) ---


## Where the pitch the player has chosen would arrive, and for a pitch that moves the last
## stretch of its path into the zone (the user: "a four-seam fastball needs only its mark in
## the zone; show a breaking ball bending a little inside the zone; the path need not start
## from the pitcher" — drawn from the hand it came out of his neck on the screen and covered
## him). Empty for no preview; one point for a straight pitch; the tail, ending at the plate,
## for one that moves.
var preview := PackedVector3Array()
var _preview_key := ""
## The same for the last pitch thrown, recorded as it flew (drawn after it for a moment).
var trail := PackedVector3Array()
var _trail_clock := 0.0
## Seconds between the points of a tail, and how many of them: the last 0.17 s of flight,
## about six metres, which is where a breaking ball does what the batter sees.
const PATH_STEP := 0.014
const TAIL_POINTS := 12
## Pitches thrown to go straight: only where they arrive is shown.
const STRAIGHT_PITCHES: Array[StringName] = [&"four_seam", &"rising_fastball"]


static func goes_straight(type: PitchType) -> bool:
	return type != null and STRAIGHT_PITCHES.has(type.id)


## Works out where the pitch the player would throw to the target now arrives, and how it
## comes in (docs/05 2.2): from his release point, his pitch type, its spin, without the miss
## of execution.
func _update_preview() -> void:
	if not human_pitches() or not (state == State.PRE_PITCH or state == State.CHARGE or state == State.ACCURACY):
		preview.clear()
		_preview_key = ""
		return
	var type := selected_type()
	if type == null:
		return
	var key := "%s|%.2f|%.2f|%s" % [type.id, target.x, target.z, settings.throws_left]
	if key == _preview_key:
		return
	_preview_key = key
	var flight := PitchModel.throw_type(cfg, type, settings.release(), target, settings.throws_left)
	if goes_straight(type):
		preview = PackedVector3Array([flight.plate_pos])
		return
	var whole := PitchModel.path(cfg, flight, PATH_STEP)
	preview = whole.slice(maxi(whole.size() - TAIL_POINTS, 0))


## Keeps the end of the pitch's path as it flies, for the tail drawn after it.
func _record_trail(delta: float) -> void:
	if duel == null or duel.pitch == null:
		return
	if state == State.LIVE and duel.phase == PitchDuel.Phase.FLIGHT:
		if trail.is_empty() or duel.time < 0.02:
			trail.clear()
			_trail_clock = 0.0
		if duel.decision != null and goes_straight(duel.decision.type):
			return
		_trail_clock += delta
		if _trail_clock >= PATH_STEP and duel.ball.pos.y > Field.PLATE_FRONT_Y - 0.5:
			_trail_clock = 0.0
			trail.append(duel.ball.pos)
			if trail.size() > TAIL_POINTS:
				trail.remove_at(0)
	elif state == State.PRE_PITCH or state == State.WINDUP:
		trail.clear()


func _update_pointer() -> void:
	var mouse := pointer_override if pointer_override.is_finite() else get_viewport().get_mouse_position()
	if wheel_open:
		# The pointer is choosing a pitch: the target stays where it was.
		if not human_pitches() or state != State.PRE_PITCH:
			wheel_open = false
		else:
			wheel_pick = wheel_slot_toward(mouse)
			return
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.BACK, -Field.PLATE_FRONT_Y)
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit == null:
		hit = Plane(Vector3.FORWARD, Field.PLATE_FRONT_Y).intersects_ray(origin, dir)
	if hit == null:
		return
	var at := Field.to_field(hit)
	var zone := duel.zone
	at.x = clampf(at.x, -zone.half_width - AIM_BEYOND_ZONE.x, zone.half_width + AIM_BEYOND_ZONE.x)
	at.z = clampf(at.z, zone.bottom - AIM_BEYOND_ZONE.y, zone.top + AIM_BEYOND_ZONE.y)
	at.y = Field.PLATE_FRONT_Y
	if human_pitches() and state == State.PRE_PITCH:
		target = at
	if human_bats():
		aim_point = at


## Poses an umpire making a call, or puts him back as he stands when `pose` is null. Only
## a change is applied, so the officials cost nothing while they stand still.
func signal_call(u: Puppet, pose: PuppetPose) -> void:
	if pose != null:
		u.frame_time = _frame_time
		u.apply(pose)
		_signalling[u] = true
	elif _signalling.has(u):
		_signalling.erase(u)
		u.apply(PuppetClips.umpire())


func _pose_players() -> void:
	# The plate umpire's right fist goes up for a called strike; a ball gets no signal.
	var strike := state == State.RESULT and duel.result == PitchDuel.Result.CALLED_STRIKE
	if not _umpire_busy():
		signal_call(umpire, PuppetClips.umpire_signal(&"strike", state_time) if strike else null)
	# The pitcher holds the ball until release and watches the plate; the batter watches the
	# ball once it is on its way, and the pitcher's hand before that.
	var ball_out := state == State.LIVE or state == State.RESULT
	pitcher.right_grip = Puppet.Grip.RELAXED if ball_out else Puppet.Grip.BALL
	pitcher.look_at_world(Field.to_world(Vector3(0.0, 0.3, 0.9)))
	var watching := duel.ball.pos if state == State.LIVE and duel.phase == PitchDuel.Phase.FLIGHT else settings.release()
	batter.look_at_world(Field.to_world(watching))
	pitcher.frame_time = _frame_time
	batter.frame_time = _frame_time
	if pitch_motion != null:
		pitcher.apply_joints(pitch_motion.frame(_pitch_clock), pitch_motion.clip)
	else:
		pitcher.apply(PuppetClips.pitch(maxf(_pitch_clock, 0.0)))
	if swing_motion != null:
		batter.apply_joints(swing_motion.frame(), swing_motion.clip, _reach * swing_motion.reach_weight())
	elif _swing_clock >= 0.0:
		batter.apply(PuppetClips.swing(_swing_clock - _swing_lead, _swing_lead, _swing_height))
	else:
		batter.apply(PuppetClips.stance())


func _show_ball() -> void:
	match state:
		State.LIVE, State.RESULT:
			ball_actor.show_at(duel.ball.pos)
		State.WINDUP:
			var hand: Vector3 = pitcher.global_transform * pitcher.ball_spot(_throwing_hand)
			ball_actor.show_at(Field.to_field(hand))
		_:
			ball_actor.visible = false


func _camera_preset() -> Array:
	return PITCH_CAMERA if human_pitches() else BAT_CAMERA


func _snap_camera() -> void:
	var preset := _camera_preset()
	var from: Vector3 = preset[0]
	var to: Vector3 = preset[1]
	camera.fov = preset[2]
	camera.look_at_from_position(Field.to_world(from), Field.to_world(to))


func _move_camera(delta: float) -> void:
	var in_play := duel.phase == PitchDuel.Phase.IN_PLAY or (state == State.RESULT and duel.contact != null and duel.contact.made_contact)
	if in_play and (state == State.RESULT or state_time > 0.0):
		var ball := duel.ball.pos
		var from := Vector3(clampf(ball.x * 0.25, -12.0, 12.0), -15.0, 15.0)
		_follow_target = _follow_target.lerp(Vector3(ball.x, ball.y, maxf(ball.z * 0.5, 0.0)), clampf(delta * 6.0, 0.0, 1.0))
		var want := Field.to_world(from)
		camera.position = camera.position.lerp(want, clampf(delta * 3.0, 0.0, 1.0))
		camera.fov = lerpf(camera.fov, 40.0, clampf(delta * 3.0, 0.0, 1.0))
		camera.look_at(Field.to_world(_follow_target))
		# The batting camera sits where the catcher and umpire are, so they stay hidden
		# until the camera has pulled away from there.
		var away: bool = human_pitches() or camera.position.distance_to(Field.to_world(BAT_CAMERA[0])) > 6.0
		catcher.visible = away
		umpire.visible = away
		return
	_follow_target = Vector3(0.0, 10.0, 1.0)
	_snap_camera()
	# The batting camera sits where the catcher crouches, so he and the umpire are only
	# drawn from elsewhere.
	catcher.visible = human_pitches()
	umpire.visible = human_pitches()


func _build_environment() -> void:
	lighting = ParkLighting.new(park.def, time_of_day)
	add_child(lighting)
	park.set_lights(lighting.lights_on(), lighting.darkness())


func _build_players() -> void:
	var home := Color(0.93, 0.93, 0.95)
	var away := Color(0.16, 0.24, 0.5)
	# Stage S3b: the pitcher and the batter use the player model; everyone else is still a mannequin.
	pitcher = _add_puppet(Vector3(0.0, Field.RUBBER_Y, Field.MOUND_HEIGHT), PI, home, Color(0.1, 0.15, 0.35), use_models)
	batter = _add_puppet(Vector3(-1.05, 0.25, 0.0), -PI / 2.0, away, Color(0.75, 0.12, 0.12), use_models)
	batter.show_bat = true
	batter.show_glove = false
	batter.headgear = &"helmet"
	batter.left_grip = Puppet.Grip.BAT
	batter.right_grip = Puppet.Grip.BAT
	pitcher.left_grip = Puppet.Grip.GLOVE
	# Fictional clubs: a home side in white with navy trim, visitors in black and orange.
	_dress(pitcher, UniformStyle.make(Color(0.94, 0.94, 0.96), Color(0.92, 0.92, 0.94), Color(0.1, 0.15, 0.35), Color(0.1, 0.15, 0.35), "Harbor"), 18, "서강민", false)
	var visitors := UniformStyle.make(Color(0.08, 0.08, 0.09), Color(0.9, 0.9, 0.91), Color(0.95, 0.45, 0.08), Color(0.95, 0.45, 0.08), "Comets")
	visitors.cap = Color(0.07, 0.07, 0.08)
	visitors.pants_pinstripes = true
	_dress(batter, visitors, 27, "한도윤", true)
	catcher = _add_puppet(Vector3(0.0, -1.15, 0.0), 0.0, home, Color(0.1, 0.15, 0.35), use_models)
	catcher.left_grip = Puppet.Grip.GLOVE
	if catcher is SkinnedPuppet:
		(catcher as SkinnedPuppet).glove_kind = &"mitt"
	catcher.headgear = &"none"
	catcher.gear = SkinnedPuppet.CATCHER_GEAR.duplicate()
	_dress(catcher, UniformStyle.make(Color(0.94, 0.94, 0.96), Color(0.92, 0.92, 0.94), Color(0.1, 0.15, 0.35), Color(0.1, 0.15, 0.35), "Harbor"), 22, "오세현", false)
	catcher.apply(PuppetClips.catcher())
	# The plate umpire stands behind the catcher in black and grey.
	umpire = _add_puppet(Vector3(0.25, -2.3, 0.0), 0.0, Color(0.08, 0.08, 0.09), Color(0.05, 0.05, 0.06), use_models)
	dress_umpire(umpire, 27, true)
	umpire.apply(PuppetClips.umpire())
	_build_fielders()


## The seven fielders behind the battery (for show in the duel).
func _build_fielders() -> void:
	var home := Color(0.93, 0.93, 0.95)
	var spots: Array[Vector3] = [
		Vector3(21.0, 24.0, 0.0), Vector3(9.0, 36.0, 0.0), Vector3(-21.0, 24.0, 0.0), Vector3(-9.0, 36.0, 0.0),
		Vector3(-45.0, 75.0, 0.0), Vector3(0.0, 95.0, 0.0), Vector3(45.0, 75.0, 0.0),
	]
	var home_style := UniformStyle.make(Color(0.94, 0.94, 0.96), Color(0.92, 0.92, 0.94), Color(0.1, 0.15, 0.35), Color(0.1, 0.15, 0.35), "Harbor")
	var names: Array[String] = ["문지호", "강태윤", "이서준", "박하람", "정우성", "최민재", "윤도현"]
	var numbers: Array[int] = [3, 7, 5, 6, 9, 51, 24]
	for i: int in spots.size():
		var spot := spots[i]
		var facing := atan2(spot.x, spot.y) + PI
		var fielder := _add_puppet(spot, -facing + PI + PI, home, Color(0.1, 0.15, 0.35), use_models)
		fielder.left_grip = Puppet.Grip.GLOVE
		var style := UniformStyle.make(home_style.jersey, home_style.pants, home_style.trim, home_style.ink, home_style.wordmark)
		_dress(fielder, style, numbers[i], names[i], false)
		fielder.look_at_world(Field.to_world(Vector3(0.0, 0.0, 1.0)))
		fielder.apply(PuppetClips.fielder_ready())


## Dresses an umpire (docs/13 S11-8): the polo shirt and charcoal trousers, his number on
## the sleeve; behind the plate his mask and ball bags too, and a thicker trunk for the chest
## protector he wears under the shirt.
func dress_umpire(puppet: Puppet, number: int, at_the_plate: bool) -> void:
	var style := UniformStyle.for_official(number)
	puppet.show_glove = false
	puppet.gear = (SkinnedPuppet.PLATE_UMPIRE_GEAR if at_the_plate else SkinnedPuppet.UMPIRE_GEAR).duplicate()
	if at_the_plate:
		# His short-billed cap is part of his gear.
		puppet.headgear = &"none"
	var model := puppet as SkinnedPuppet
	if model != null:
		# Umpires are grown men of every build but lean.
		var builds: Array[StringName] = [&"solid", &"standard", &"heavy", &"solid"]
		model.set_body(1.76 + 0.02 * (number % 5), &"heavy" if at_the_plate and number % 2 == 0 else (&"solid" if at_the_plate else builds[number % builds.size()]))
		model.set_hair(1 + number % 4, Color(0.09, 0.08, 0.075).lerp(Color(0.45, 0.45, 0.46), 0.5 if number % 3 == 0 else 0.0))
		model.set_face("umpire%d" % number)
	_dress(puppet, style, number, "", false)
	if model != null:
		model.set_logo(style.cap_letter, style.cap_ink())


func _dress(puppet: Puppet, style: UniformStyle, number: int, player_name: String, with_gloves: bool) -> void:
	var model := puppet as SkinnedPuppet
	if model == null:
		return
	style.number = number
	style.player_name = player_name
	model.uniform = style
	model.gloves = with_gloves
	model.repaint()


func _add_puppet(field_pos: Vector3, yaw: float, jersey: Color, cap: Color, skinned: bool = false) -> Puppet:
	var puppet: Puppet = SkinnedPuppet.new() if skinned and SkinnedPuppet.available() else Puppet.new()
	puppet.set_colors(jersey, Color(0.84, 0.84, 0.86), cap)
	puppet.position = Field.to_world(field_pos)
	puppet.rotation.y = yaw
	add_child(puppet)
	return puppet
