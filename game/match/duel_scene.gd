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

const BAT_CAMERA := [Vector3(0.55, -2.7, 0.9), Vector3(-0.2, 18.4, -0.45), 45.0]
## Far behind the mound with a long lens, like the reference footage: the pitcher's back fills
## the left of the frame and the batter and catcher are large enough to aim at.
const PITCH_CAMERA := [Vector3(-0.8, 33.0, 2.7), Vector3(0.15, 0.0, 1.1), 7.5]

## &"bat" = player bats, &"pitch" = player pitches, &"watch" = AI against AI.
@export var mode: StringName = &"bat"
@export var seed_value := 20261120
## Show the pitcher and batter as the skinned player model when it has been built.
@export var use_models := true

var cfg: PhysicsConfig
var catalog: Dictionary[StringName, PitchType]
var field_model: AnalyticField
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
var aim_enabled := false
var aim_point := Vector3.ZERO

var camera: Camera3D
var pitcher: Puppet
var batter: Puppet
var catcher: Puppet
var ball_actor: BallActor
var hud: DuelHud

var _rng: Rng
var _ai_rng: Rng
var _pitch_count := 0
var _pitch_clock := -1.0
var _swing_clock := -1.0
var _swing_lead := 0.11
var _swing_height := 0.8
var _follow_target := Vector3.ZERO


func _ready() -> void:
	cfg = PhysicsConfigIO.load_default()
	catalog = PitchCatalogIO.load_default()
	_rng = Rng.new(seed_value)
	_ai_rng = _rng.fork(1)

	var park := GreyboxField.new()
	field_model = AnalyticField.create(park.fence)
	add_child(park)
	_build_environment()
	_build_players()
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


func set_mode(new_mode: StringName) -> void:
	mode = new_mode
	balls = 0
	strikes = 0
	_enter(State.PRE_PITCH)
	_snap_camera()


## Number of pitches started since the scene loaded.
func pitches_thrown() -> int:
	return _pitch_count - 1


func human_pitches() -> bool:
	return mode == &"pitch"


func human_bats() -> bool:
	return mode == &"bat"


func selected_type() -> PitchType:
	return catalog[pitch_ids[selected_pitch]]


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
				get_tree().quit()
		if human_pitches() and state == State.PRE_PITCH:
			var index := key.keycode - KEY_1
			if index >= 0 and index < pitch_ids.size():
				selected_pitch = index

	var click := event as InputEventMouseButton
	if click == null:
		return
	if human_bats() and click.pressed:
		if click.button_index == MOUSE_BUTTON_LEFT:
			swing(SwingAttempt.Kind.CONTACT)
		elif click.button_index == MOUSE_BUTTON_RIGHT:
			swing(SwingAttempt.Kind.POWER)
	elif human_pitches() and click.button_index == MOUSE_BUTTON_LEFT:
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

	match state:
		State.PRE_PITCH:
			if not human_pitches() and state_time >= AI_PITCH_DELAY:
				decision = AiPitcher.choose(catalog, duel.zone, _ai_rng)
				_begin_windup()
		State.CHARGE:
			power = minf(power + delta / CHARGE_TIME, 1.0)
		State.ACCURACY:
			ring += delta / ACCURACY_TIME
			if ring >= 1.0:
				accuracy = 0.0
				_begin_windup()
		State.WINDUP:
			if _pitch_clock >= PuppetClips.PITCH_RELEASE:
				_release()
		State.LIVE:
			for i: int in roundi(delta / TICK):
				duel.tick(TICK)
			var following := duel.phase == PitchDuel.Phase.IN_PLAY and state_time > MAX_FOLLOW_TIME
			if duel.is_over() or following:
				_finish_pitch()
		State.RESULT:
			var hold := 2.6 if duel.result == PitchDuel.Result.HOME_RUN else 1.5
			if state_time >= hold:
				_new_duel()
				_enter(State.PRE_PITCH)


func _process(delta: float) -> void:
	refresh(delta)


## Updates everything that is only for show: poses, ball, camera, HUD.
func refresh(delta: float) -> void:
	_update_pointer()
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
	duel.throw_pitch(decision)
	if not human_bats():
		AiBatter.react(duel, _ai_rng)
	_enter(State.LIVE)


func _begin_swing_pose() -> void:
	_swing_lead = SwingModel.swing_time(duel.swing.kind)
	_swing_height = duel.ideal_contact_pos.z
	_swing_clock = 0.0


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
	_enter(State.RESULT)


func _update_pointer() -> void:
	var mouse := get_viewport().get_mouse_position()
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
	at.x = clampf(at.x, -zone.half_width - 0.35, zone.half_width + 0.35)
	at.z = clampf(at.z, zone.bottom - 0.4, zone.top + 0.4)
	at.y = Field.PLATE_FRONT_Y
	if human_pitches() and state == State.PRE_PITCH:
		target = at
	if human_bats():
		aim_point = at


func _pose_players() -> void:
	pitcher.apply(PuppetClips.pitch(maxf(_pitch_clock, 0.0)))
	if _swing_clock >= 0.0:
		batter.apply(PuppetClips.swing(_swing_clock - _swing_lead, _swing_lead, _swing_height))
	else:
		batter.apply(PuppetClips.stance())


func _show_ball() -> void:
	match state:
		State.LIVE, State.RESULT:
			ball_actor.show_at(duel.ball.pos)
		State.WINDUP:
			var hand: Vector3 = pitcher.global_transform * pitcher.joints[&"RightHand"]
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
		catcher.visible = true
		return
	_follow_target = Vector3(0.0, 10.0, 1.0)
	_snap_camera()
	# The batting camera sits where the catcher crouches, so he is only drawn from elsewhere.
	catcher.visible = human_pitches()


func _build_environment() -> void:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)


func _build_players() -> void:
	var home := Color(0.93, 0.93, 0.95)
	var away := Color(0.16, 0.24, 0.5)
	# Stage S3b: the pitcher and the batter use the player model; everyone else is still a mannequin.
	pitcher = _add_puppet(Vector3(0.0, Field.RUBBER_Y, Field.MOUND_HEIGHT), PI, home, Color(0.1, 0.15, 0.35), use_models)
	batter = _add_puppet(Vector3(-1.05, 0.25, 0.0), -PI / 2.0, away, Color(0.75, 0.12, 0.12), use_models)
	batter.show_bat = true
	catcher = _add_puppet(Vector3(0.0, -1.15, 0.0), 0.0, home, Color(0.1, 0.15, 0.35))
	catcher.apply(PuppetClips.catcher())
	var spots: Array[Vector3] = [
		Vector3(21.0, 24.0, 0.0), Vector3(9.0, 36.0, 0.0), Vector3(-21.0, 24.0, 0.0), Vector3(-9.0, 36.0, 0.0),
		Vector3(-45.0, 75.0, 0.0), Vector3(0.0, 95.0, 0.0), Vector3(45.0, 75.0, 0.0),
	]
	for spot: Vector3 in spots:
		var facing := atan2(spot.x, spot.y) + PI
		_add_puppet(spot, -facing + PI + PI, home, Color(0.1, 0.15, 0.35)).apply(PuppetClips.fielder_ready())


func _add_puppet(field_pos: Vector3, yaw: float, jersey: Color, cap: Color, skinned: bool = false) -> Puppet:
	var puppet: Puppet = SkinnedPuppet.new() if skinned and SkinnedPuppet.available() else Puppet.new()
	puppet.set_colors(jersey, Color(0.84, 0.84, 0.86), cap)
	puppet.position = Field.to_world(field_pos)
	puppet.rotation.y = yaw
	add_child(puppet)
	return puppet
