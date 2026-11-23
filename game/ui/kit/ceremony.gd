class_name Ceremony
extends CanvasLayer
## A cutscene away from the field (queue stage 6; the user, 2026-11-23: "a contract with the
## club, the championship ceremony after the season, the awards ... as close to the real KBO as
## can be; outside the games, put together to suit"). One stage for all of them, dressed by the
## kind: the club's colours and emblem behind, the man in his uniform under the lights, what the
## moment is about in his hands — the club's jersey with his name and number held up (a draft
## pick's or a signing's photo call), the trophy at an award, the cup over his head at a
## championship — the photographers' flashes, confetti at a win, and its words in a broadcast's
## lower third. KBO style he bows to the room first. A trade shows the two clubs' emblems with
## the way he went. Five to eight seconds; Space, Enter, Esc or a click skips it.
##
##   Ceremony.play(self, Ceremony.Kind.AWARD, player, club, "2027 KBO 시상식", "홈런왕", ["42홈런"], func() -> void: ...)

enum Kind { DRAFT, CONTRACT, AWARD, CHAMPION, TRADE, CALL_UP }

## How long each kind lasts (s).
const LENGTH := {Kind.DRAFT: 7.5, Kind.CONTRACT: 6.5, Kind.AWARD: 7.5, Kind.CHAMPION: 8.0, Kind.TRADE: 6.5, Kind.CALL_UP: 4.5}
const FADE := 0.5
const GOLD := Color(1.0, 0.8, 0.32)

var kind: Kind = Kind.AWARD
var player: Player
var club: Team
## A trade's club he left.
var from_club: Team
var title := ""
var subtitle := ""
var lines := PackedStringArray()
var done: Callable
var time := 0.0

var _back: Control
var _front: Control
var _viewport: SubViewport
var _camera: Camera3D
var _puppet: SkinnedPuppet
var _jersey: Node3D
var _trophy: Node3D
var _flashes: Array = []
var _confetti: Array = []
var _rng := Rng.new(7)
var _finished := false
var _sound: AudioStreamPlayer


## The kinds by the names the career's cues use (CareerSeason.cue).
const KINDS := {&"draft": Kind.DRAFT, &"contract": Kind.CONTRACT, &"award": Kind.AWARD, &"champion": Kind.CHAMPION, &"trade": Kind.TRADE, &"call_up": Kind.CALL_UP}

## Somewhere one is showing (a screen waits for it before the next).
static var showing := false


## Plays a list of cues one after another ([kind name, heading, big line, more lines, club,
## the club he left, the player]); `on_done` after the last. Nothing without a screen.
static func play_all(holder: Node, cues: Array, on_done: Callable = Callable()) -> void:
	if cues.is_empty() or DisplayServer.get_name() == "headless" or holder == null or not holder.is_inside_tree():
		if on_done.is_valid():
			on_done.call()
		return
	var c: Array = cues[0]
	var rest := cues.slice(1)
	play(holder, KINDS.get(c[0], Kind.CONTRACT), c[6], c[4], str(c[1]), str(c[2]), c[3], func() -> void:
		play_all(holder, rest, on_done), c[5])


## Shows a ceremony over everything; `on_done` is called when it is over or skipped.
static func play(holder: Node, what: Kind, p: Player, team: Team, heading: String, big: String, more: PackedStringArray, on_done: Callable = Callable(), left: Team = null) -> Ceremony:
	var c := Ceremony.new()
	c.kind = what
	c.player = p
	c.club = team
	c.title = heading
	c.subtitle = big
	c.lines = more
	c.done = on_done
	c.from_club = left
	showing = true
	holder.get_tree().root.add_child(c)
	return c


func _ready() -> void:
	layer = 90
	_rng = Rng.new(hash("%s:%d:%s" % [player.id if player != null else "", kind, subtitle]))
	_back = Control.new()
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back.mouse_filter = Control.MOUSE_FILTER_STOP
	_back.draw.connect(_draw_back)
	# A click anywhere skips it (and nothing under it takes the click).
	_back.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed:
			_finish())
	add_child(_back)
	var view := SubViewportContainer.new()
	view.stretch = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	view.add_child(_viewport)
	_front = Control.new()
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.draw.connect(_draw_front)
	add_child(_front)
	_build_stage()
	_sound = AudioStreamPlayer.new()
	_sound.bus = &"Crowd"
	add_child(_sound)
	var cheer := "crowd/roar" if kind == Kind.CHAMPION else ("crowd/clap_big" if kind in [Kind.AWARD, Kind.DRAFT, Kind.CONTRACT] else "crowd/clap")
	if DisplayServer.get_name() != "headless":
		_sound.stream = GameAudio.stream(cheer)
		_sound.volume_db = -8.0
		_sound.play()


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.72)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	var world := WorldEnvironment.new()
	world.environment = env
	_viewport.add_child(world)
	# A key from the front left above, a warm spot from overhead, a cool rim from behind.
	for spec: Array in [[Vector3(-35.0, -30.0, 0.0), Color(1.0, 0.95, 0.88), 1.3, true], [Vector3(-25.0, 155.0, 0.0), Color(0.7, 0.82, 1.0), 1.5, false], [Vector3(-80.0, 0.0, 0.0), Color(1.0, 0.92, 0.8), 0.6, false]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = spec[0]
		light.light_color = spec[1]
		light.light_energy = spec[2]
		light.shadow_enabled = spec[3]
		_viewport.add_child(light)
	# The stage he stands on: a dark disc with a ring of the club's colour.
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.6
	cyl.height = 0.06
	disc.mesh = cyl
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.06, 0.065, 0.08)
	floor_mat.roughness = 0.25
	floor_mat.metallic = 0.3
	disc.material_override = floor_mat
	disc.position.y = -0.03
	_viewport.add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.55
	torus.outer_radius = 1.62
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = club.accent if club != null else GOLD
	ring_mat.emission_enabled = true
	ring_mat.emission = ring_mat.albedo_color
	ring_mat.emission_energy_multiplier = 1.4
	ring.material_override = ring_mat
	ring.position.y = 0.01
	ring.scale = Vector3(1.0, 0.3, 1.0)
	_viewport.add_child(ring)
	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	if player != null and SkinnedPuppet.available():
		_puppet = SkinnedPuppet.new()
		var style := UniformStyle.for_team(club, true) if club != null else UniformStyle.make(Color(0.94, 0.94, 0.96), Color(0.92, 0.92, 0.94), Color(0.1, 0.15, 0.35), Color(0.1, 0.15, 0.35), "")
		style.number = player.number
		style.player_name = player.name
		_puppet.uniform = style
		_puppet.set_colors(style.jersey, style.pants, style.cap)
		_puppet.show_glove = false
		_viewport.add_child(_puppet)
		_puppet.set_body(player.height_cm / 100.0, SkinnedPuppet.build_for(player.height_cm, player.weight_kg, player.primary_position()))
		_puppet.set_hair(1 + absi(hash(player.id)) % 4, MatchScene.hair_color_of(player))
		_puppet.set_face(player.id, 2026 - player.born)
		if club != null:
			_puppet.set_logo(style.cap_letter, style.cap_ink())
		_puppet.repaint()
		_puppet.rotation.y = PI
		_puppet.apply(PuppetClips.standing())
		if kind in [Kind.DRAFT, Kind.CONTRACT, Kind.TRADE]:
			_jersey = _make_jersey(style)
			_viewport.add_child(_jersey)
		elif kind in [Kind.AWARD, Kind.CHAMPION]:
			_trophy = _make_trophy(kind == Kind.CHAMPION)
			_viewport.add_child(_trophy)


## The club's jersey with his name and number, as it is held up for the cameras.
func _make_jersey(style: UniformStyle) -> Node3D:
	var root := Node3D.new()
	var cloth := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.62, 0.74)
	cloth.mesh = quad
	var m := StandardMaterial3D.new()
	m.albedo_color = style.jersey
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.material_override = m
	root.add_child(cloth)
	# Shoulders: a strip of the club's colour along the top.
	var band := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(0.62, 0.05)
	band.mesh = bq
	var bm := StandardMaterial3D.new()
	bm.albedo_color = club.primary if club != null else Color(0.1, 0.15, 0.35)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	band.material_override = bm
	band.position = Vector3(0.0, 0.345, 0.002)
	root.add_child(band)
	var ink := club.primary if club != null else Color(0.1, 0.15, 0.35)
	if style.jersey.get_luminance() < 0.4:
		ink = Color(0.96, 0.96, 0.96)
	var name_label := Label3D.new()
	name_label.text = player.name
	name_label.font = UiTheme.display(900)
	name_label.font_size = 64
	name_label.pixel_size = 0.0016
	name_label.modulate = ink
	name_label.outline_size = 0
	name_label.position = Vector3(0.0, 0.2, 0.004)
	root.add_child(name_label)
	var number := Label3D.new()
	number.text = str(player.number)
	number.font = UiTheme.display(900)
	number.font_size = 200
	number.pixel_size = 0.0018
	number.modulate = ink
	number.outline_size = 0
	number.position = Vector3(0.0, -0.06, 0.004)
	root.add_child(number)
	return root


## A trophy in gold: a dark base, a stem, a cup with two handles (the championship's taller,
## the award's a smaller cup).
func _make_trophy(big: bool) -> Node3D:
	var root := Node3D.new()
	var gold := StandardMaterial3D.new()
	gold.albedo_color = GOLD
	gold.metallic = 1.0
	gold.roughness = 0.22
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.06, 0.05)
	dark.roughness = 0.35
	var k := 1.35 if big else 1.0
	var parts: Array = [
		[0.09 * k, 0.1 * k, 0.1 * k, -0.2 * k, dark],
		[0.025 * k, 0.04 * k, 0.12 * k, -0.09 * k, gold],
		[0.12 * k, 0.05 * k, 0.2 * k, 0.07 * k, gold],
	]
	for part: Array in parts:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = float(part[0])
		c.bottom_radius = float(part[1])
		c.height = float(part[2])
		mi.mesh = c
		mi.material_override = part[4]
		mi.position.y = float(part[3])
		root.add_child(mi)
	for side: float in [-1.0, 1.0]:
		var handle := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.035 * k
		t.outer_radius = 0.05 * k
		handle.mesh = t
		handle.material_override = gold
		handle.position = Vector3(side * 0.125 * k, 0.09 * k, 0.0)
		handle.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		root.add_child(handle)
	return root


func _process(delta: float) -> void:
	time += delta
	var length: float = LENGTH[kind]
	if not _finished and time >= length:
		_finish()
		return
	_pose_and_props()
	_move_camera()
	# The photographers: flashes now and then, more at the photo call.
	var rate := 6.0 if _photo_call() else 1.6
	if not _finished and _rng.next_float() < rate * delta:
		_flashes.append([_rng.next_float(), 0.35 + 0.4 * _rng.next_float(), time])
	_flashes = _flashes.filter(func(f: Array) -> bool: return time - float(f[2]) < 0.25)
	if kind in [Kind.AWARD, Kind.CHAMPION] and time > _raise_at():
		_rain(delta, 90.0 if kind == Kind.CHAMPION else 40.0)
	_back.queue_redraw()
	_front.queue_redraw()


## When the moment's thing goes up (the jersey held up, the trophy raised).
func _raise_at() -> float:
	match kind:
		Kind.CHAMPION:
			return 0.9
		Kind.AWARD:
			return 3.6
		Kind.CALL_UP:
			return 1.4
	return 3.0


func _photo_call() -> bool:
	return time > _raise_at() and time < _raise_at() + 2.5


func _pose_and_props() -> void:
	if _puppet == null:
		return
	var up := _raise_at()
	var pose := PuppetClips.standing()
	var bows := kind in [Kind.DRAFT, Kind.CONTRACT, Kind.AWARD, Kind.TRADE]
	if bows and time > 0.9 and time < up:
		# Down for half a second, held, and up again.
		var k := smoothstep(0.9, 1.4, time) * (1.0 - smoothstep(up - 0.9, up - 0.4, time))
		pose = PuppetClips.bow(k)
	elif time >= up:
		var k := smoothstep(up, up + 0.45, time)
		var to: PuppetPose
		match kind:
			Kind.DRAFT, Kind.CONTRACT, Kind.TRADE:
				to = PuppetClips.hold(1.42, 0.56, 0.32)
			Kind.AWARD:
				# At the waist for the photo, then up over his head.
				to = PuppetClips.hold(1.08, 0.26, 0.3) if time < up + 1.6 else PuppetClips.hold(1.08, 0.26, 0.3).blend(PuppetClips.hold(2.0, 0.26, 0.12), smoothstep(up + 1.6, up + 2.1, time))
			Kind.CHAMPION:
				to = PuppetClips.hold(2.02, 0.3, 0.1) if fmod(time - up, 1.6) < 1.2 else PuppetClips.fist_pump()
			_:
				to = PuppetClips.fist_pump() if time < up + 1.6 else PuppetClips.wave(time)
		pose = pose.blend(to, k)
	_puppet.apply(pose)
	var r := _puppet.global_transform * _puppet.ball_spot(&"RightHand")
	var l := _puppet.global_transform * _puppet.ball_spot(&"LeftHand")
	var mid := (r + l) * 0.5
	var shown := time >= up
	if _jersey != null:
		_jersey.visible = shown
		_jersey.position = mid + Vector3(0.0, -0.36, 0.06)
		_jersey.rotation = Vector3.ZERO
	if _trophy != null:
		_trophy.visible = shown
		_trophy.position = mid + Vector3(0.0, 0.17 if kind == Kind.CHAMPION else 0.12, 0.04)


func _move_camera() -> void:
	var h := player.height_cm / 100.0 if player != null else 1.85
	var k := smoothstep(0.0, float(LENGTH[kind]), time)
	# In slowly from a full figure to the waist up, drifting across.
	var from := Vector3(0.9, h * 0.58, 6.2)
	var to := Vector3(-0.25, h * 0.7, 3.6)
	# He stands right of the middle: the words are on the left.
	var look_from := Vector3(-0.35, h * 0.52, 0.0)
	var look_to := Vector3(-0.42, h * 0.68, 0.0)
	if kind == Kind.CHAMPION or kind == Kind.AWARD:
		look_to.y = h * 0.78
	_camera.fov = lerpf(30.0, 27.0, k)
	_camera.look_at_from_position(from.lerp(to, k), look_from.lerp(look_to, k))


## Confetti from above: the club's colours and gold.
func _rain(delta: float, per_second: float) -> void:
	var view := _front.size
	var colours: Array[Color] = [GOLD, Color(1, 1, 1)]
	if club != null:
		colours.append(club.primary)
		colours.append(club.accent)
	var n := int(per_second * delta + _rng.next_float())
	for i: int in n:
		_confetti.append([Vector2(_rng.next_float() * view.x, -20.0), Vector2(_rng.next_range(-40.0, 40.0), _rng.next_range(120.0, 260.0)), colours[_rng.next_int(colours.size())], _rng.next_float() * TAU, _rng.next_range(5.0, 11.0)])
	for c: Array in _confetti:
		var v: Vector2 = c[1]
		c[0] = (c[0] as Vector2) + Vector2(v.x + 30.0 * sin(time * 3.0 + float(c[3])), v.y) * delta
		c[3] = float(c[3]) + delta * 4.0
	_confetti = _confetti.filter(func(c: Array) -> bool: return (c[0] as Vector2).y < view.y + 20.0)


func _draw_back() -> void:
	var view := _back.size
	var primary := club.primary if club != null else Color(0.15, 0.2, 0.35)
	# Night-dark at the top into the club's colour at the floor.
	var top := Color(0.02, 0.025, 0.04)
	var bottom := primary.darkened(0.45)
	_back.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(view.x, 0.0), view, Vector2(0.0, view.y)]), PackedColorArray([top, top, bottom, bottom]))
	# The club's emblem large behind him, pushed back into the dark.
	var k := view.y / 1080.0
	var side := 760.0 * k
	if club != null:
		Emblem.draw_emblem(_back, club, Rect2(Vector2(view.x * 0.5 - side * 0.5, view.y * 0.42 - side * 0.5), Vector2(side, side)))
		_back.draw_rect(Rect2(Vector2.ZERO, view), Color(0.02, 0.025, 0.04, 0.62))
	# Beams of light sweeping from above.
	for i: int in 5:
		var x := view.x * (0.12 + 0.19 * i) + 80.0 * k * sin(time * 0.6 + i * 1.7)
		var foot := view.x * 0.5 + (x - view.x * 0.5) * 0.25
		_back.draw_colored_polygon(PackedVector2Array([Vector2(x - 26.0 * k, -10.0), Vector2(x + 26.0 * k, -10.0), Vector2(foot + 150.0 * k, view.y * 0.86), Vector2(foot - 150.0 * k, view.y * 0.86)]), Color(1.0, 0.96, 0.85, 0.035))
	# A trade: where he came from, where he goes.
	if kind == Kind.TRADE and from_club != null and club != null:
		var s := 220.0 * k
		var a := clampf((time - 0.4) / 0.6, 0.0, 1.0)
		Emblem.draw_emblem(_back, from_club, Rect2(Vector2(view.x * 0.16 - s * 0.5, view.y * 0.3 - s * 0.5), Vector2(s, s)))
		Emblem.draw_emblem(_back, club, Rect2(Vector2(view.x * 0.84 - s * 0.5, view.y * 0.3 - s * 0.5), Vector2(s, s)))
		var y := view.y * 0.3
		var x0 := view.x * 0.16 + s * 0.65
		var x1 := lerpf(x0, view.x * 0.84 - s * 0.65, a)
		_back.draw_line(Vector2(x0, y), Vector2(x1, y), GOLD, 8.0 * k, true)
		if a > 0.95:
			_back.draw_colored_polygon(PackedVector2Array([Vector2(x1 + 30.0 * k, y), Vector2(x1 - 6.0 * k, y - 26.0 * k), Vector2(x1 - 6.0 * k, y + 26.0 * k)]), GOLD)


func _draw_front() -> void:
	var view := _front.size
	var k := view.y / 1080.0
	for c: Array in _confetti:
		var at: Vector2 = c[0]
		var size := float(c[4]) * k
		_front.draw_set_transform(at, float(c[3]), Vector2(1.0, 0.45 + 0.55 * absf(sin(float(c[3])))))
		_front.draw_rect(Rect2(Vector2(-size * 0.5, -size * 0.5), Vector2(size, size)), c[2])
	_front.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for f: Array in _flashes:
		var age := time - float(f[2])
		var a := 1.0 - age / 0.25
		var at := Vector2(float(f[0]) * view.x, float(f[1]) * view.y)
		_front.draw_circle(at, (40.0 + 140.0 * age) * k, Color(1, 1, 1, 0.22 * a))
		_front.draw_circle(at, 10.0 * k, Color(1, 1, 1, 0.9 * a))
		_front.draw_rect(Rect2(Vector2.ZERO, view), Color(1, 1, 1, 0.05 * a))
	_lower_third(view, k)
	var hint := "Space 건너뛰기"
	var font := UiTheme.font(600)
	_front.draw_string(font, Vector2(view.x - 230.0 * k, view.y - 34.0 * k), hint, HORIZONTAL_ALIGNMENT_RIGHT, 200.0 * k, roundi(17 * k), Color(1, 1, 1, 0.55))
	# In and out of black.
	var length: float = LENGTH[kind]
	var dark := maxf(1.0 - time / FADE, clampf((time - (length - FADE)) / FADE, 0.0, 1.0))
	if dark > 0.0:
		_front.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, dark))


## Its words, as a broadcast's lower third: the club's colour, the occasion, the big line, the
## details, sliding in one after another.
func _lower_third(view: Vector2, k: float) -> void:
	var a := clampf((time - 0.5) / 0.4, 0.0, 1.0)
	if a <= 0.0:
		return
	var slide := (1.0 - a) * -60.0 * k
	var box := Rect2(Vector2(90.0 * k + slide, view.y * 0.66), Vector2(760.0 * k, 64.0 * k + 120.0 * k + 34.0 * k * lines.size()))
	_front.draw_rect(box, Color(0.03, 0.035, 0.05, 0.82 * a))
	var accent := club.primary if club != null else UiTheme.BRAND
	_front.draw_rect(Rect2(box.position, Vector2(10.0 * k, box.size.y)), Color(accent.lightened(0.1), a))
	var display := UiTheme.display(900)
	var font := UiTheme.font(600)
	var x := box.position.x + 40.0 * k
	_front.draw_string(font, Vector2(x, box.position.y + 50.0 * k), title, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(26 * k), Color(GOLD, a))
	var b := clampf((time - 0.9) / 0.4, 0.0, 1.0)
	_front.draw_string(display, Vector2(x, box.position.y + 140.0 * k), subtitle, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 60.0 * k, roundi(64 * k), Color(1, 1, 1, b))
	for i: int in lines.size():
		var c := clampf((time - 1.3 - 0.25 * i) / 0.4, 0.0, 1.0)
		_front.draw_string(font, Vector2(x, box.position.y + 190.0 * k + 34.0 * k * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 60.0 * k, roundi(24 * k), Color(1, 1, 1, 0.85 * c))


func _input(event: InputEvent) -> void:
	# The screen under it must not take the keys meant for skipping.
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	showing = false
	var callback := done
	queue_free()
	if callback.is_valid():
		callback.call()
