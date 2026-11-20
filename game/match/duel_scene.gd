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
## enough to aim at. Worked back from a reference frame taken during the pitch gauge.
const PITCH_CAMERA := [Vector3(-3.9, 54.6, 4.0), Vector3(0.3, 0.0, 0.8), 6.5]

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


func _ready() -> void:
	cfg = PhysicsConfigIO.load_default()
	catalog = PitchCatalogIO.load_default()
	_rng = Rng.new(seed_value)
	_ai_rng = _rng.fork(1)

	var park := GreyboxField.new()
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


func set_mode(new_mode: StringName) -> void:
	mode = new_mode
	balls = 0
	strikes = 0
	_enter(State.PRE_PITCH)
	_snap_camera()


## Uses recorded clips for the delivery and the swing. Null keeps the key poses for that one.
func set_motion(pitch_clip: JointClip, swing_clip: JointClip) -> void:
	pitch_motion = PitchMotion.new(pitch_clip) if pitch_clip != null else null
	swing_motion = SwingMotion.new(swing_clip) if swing_clip != null else null
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
		pitcher.apply_joints(pitch_motion.frame(pitch_motion.release_time), pitch_clip)
		settings.release_point = Field.to_field(pitcher.global_transform * pitcher.ball_spot(_throwing_hand))
		pitcher.reset_motion()
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


func release_time() -> float:
	return pitch_motion.release_time if pitch_motion != null else PuppetClips.PITCH_RELEASE


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
	if swing_motion != null:
		swing_motion.advance(delta)

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
	_frame_time = delta
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
	duel.throw_pitch(decision)
	if not human_bats():
		AiBatter.react(duel, _ai_rng)
	_enter(State.LIVE)


func _begin_swing_pose() -> void:
	_swing_shown = true
	_swing_lead = SwingModel.swing_time(duel.swing.kind)
	_swing_height = duel.ideal_contact_pos.z
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


func _update_pointer() -> void:
	var mouse := pointer_override if pointer_override.is_finite() else get_viewport().get_mouse_position()
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


func _pose_players() -> void:
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
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.16, 0.34, 0.68)
	sky_material.sky_horizon_color = Color(0.62, 0.74, 0.88)
	sky_material.ground_horizon_color = Color(0.5, 0.56, 0.6)
	sky_material.ground_bottom_color = Color(0.2, 0.22, 0.24)
	sky_material.sun_angle_max = 25.0
	sky_material.energy_multiplier = 0.8
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	# Contact shadows where things meet the ground, a little bloom on bright surfaces, and
	# haze that lightens the far outfield. The forward renderer draws all of these; the
	# lighter renderers used for captures inside WSL skip what they cannot do.
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.76, 0.86)
	env.fog_density = 0.0009
	env.fog_sun_scatter = 0.15
	env.fog_sky_affect = 0.2
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.89)
	sun.light_energy = 1.35
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


func _build_players() -> void:
	var home := Color(0.93, 0.93, 0.95)
	var away := Color(0.16, 0.24, 0.5)
	# Stage S3b: the pitcher and the batter use the player model; everyone else is still a mannequin.
	pitcher = _add_puppet(Vector3(0.0, Field.RUBBER_Y, Field.MOUND_HEIGHT), PI, home, Color(0.1, 0.15, 0.35), use_models)
	batter = _add_puppet(Vector3(-1.05, 0.25, 0.0), -PI / 2.0, away, Color(0.75, 0.12, 0.12), use_models)
	batter.show_bat = true
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
	catcher.headgear = &"helmet"
	catcher.gear = [&"Mask", &"ChestProtector", &"ShinGuards"]
	_dress(catcher, UniformStyle.make(Color(0.94, 0.94, 0.96), Color(0.92, 0.92, 0.94), Color(0.1, 0.15, 0.35), Color(0.1, 0.15, 0.35), "Harbor"), 22, "오세현", false)
	catcher.apply(PuppetClips.catcher())
	# The plate umpire stands behind the catcher in black and grey.
	umpire = _add_puppet(Vector3(0.25, -2.3, 0.0), 0.0, Color(0.08, 0.08, 0.09), Color(0.05, 0.05, 0.06), use_models)
	var officials := UniformStyle.make(Color(0.07, 0.07, 0.08), Color(0.34, 0.35, 0.37), Color(0.07, 0.07, 0.08), Color(0.07, 0.07, 0.08), "")
	_dress(umpire, officials, 0, "", false)
	umpire.show_glove = false
	umpire.gear = [&"Mask"]
	umpire.apply(PuppetClips.umpire())
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
