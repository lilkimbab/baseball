class_name FieldScenes
extends RefCounted
## Two staged cutscenes on the field (the user, 2026-11-23, after the first pass: "the
## bench-clearing looks odd — make it a cutscene where the batter, catcher and fielders all
## gather and both dugouts run in and tangle, as in KBO photos; the injury: medics carrying him
## off on a stretcher, as in a KBO game"). While one plays the game's own cast is hidden and the
## scene's own figures (MatchScene's rush figures, dressed as the men they are) play it out, the
## broadcast cutting between its shots.
##
## The brawl: the batter and the pitcher face each other between the plate and the mound, the
## catcher holds the batter from behind, the plate umpire steps between; the fielders run in
## from where they stand and both benches out of their dugouts, the outfielders last; then a
## knot of men pushing, grabbing, holding their own back and pointing, the whole of it heaving
## back and forth. Nobody throws a punch (KBO's usual: a stand-off and the umpires and coaches
## pulling them apart).
##
## The injury (KBO: an ambulance comes onto the field through the outfield gate): he lies where
## he was hit, holding it, his trainer kneeling by him; the ambulance comes in with its lights
## going; three medics run the stretcher to him, lift him onto it, carry him to the back of the
## ambulance and it drives off, the crowd applauding.

const BRAWL_LENGTH := 8.5
## The title won: the pile at the mound, then the manager tossed (헹가래).
const CHAMPION_LENGTH := 13.0
const MEDICAL_LENGTH := 12.0
## Where the benches meet (field coordinates): between the plate and the mound.
const BRAWL_AT := Vector2(0.0, 6.5)
## The medics' outfits: a bright vest and dark trousers.
const MEDIC_VEST := Color(0.88, 0.95, 0.18)
const MEDIC_PANTS := Color(0.12, 0.13, 0.16)

var scene: MatchScene
## &"brawl", &"medical" or &"champion" while one is planned.
var kind := &""
## Each figure: {side, from, slot, delay, role, speed, face}.
var plan: Array[Dictionary] = []
var _hidden: Array[Node3D] = []
var _stretcher: Node3D
var _ambulance: Node3D
var _lights: Array[MeshInstance3D] = []
var _gate := Vector3.ZERO
var _stop := Vector3.ZERO
var _down := Vector3.ZERO
var _yaw_down := 0.0
var _applauded := false
## A farewell's words over centre field (his number, or a thank-you).
var _banner: Label3D


func _init(s: MatchScene) -> void:
	scene = s


# --- The brawl ---


func plan_brawl() -> void:
	kind = &"brawl"
	plan.clear()
	var g := scene.game
	var rng := Rng.new(hash("brawl:%d:%d" % [scene.seed_value, scene._pitch_count]))
	var centre := Vector3(BRAWL_AT.x, BRAWL_AT.y, 0.0)
	var bat := g.batting()
	var field := g.fielding()
	var batter_id := g.batter_id()
	var pitcher_id := g.pitcher_id()
	var bx := scene._box.x * (-1.0 if scene.settings.bats_left else 1.0)
	var taken: Dictionary[String, bool] = {batter_id: true, pitcher_id: true}
	# The two at the heart of it, the catcher behind the batter.
	_add(bat, g.teams[bat].player(batter_id), Vector3(bx, scene._box.y, 0.0), centre + Vector3(0.0, -0.45, 0.0), 0.15, &"core", 4.5, centre + Vector3(0.0, 0.45, 0.0))
	_add(field, g.teams[field].player(pitcher_id), Vector3(0.0, Field.RUBBER_Y - 1.0, 0.0), centre + Vector3(0.0, 0.45, 0.0), 0.4, &"core", 5.5, centre + Vector3(0.0, -0.45, 0.0))
	var catcher_id := g.teams[field].fielder_at(Position.Kind.C)
	taken[catcher_id] = true
	_add(field, g.teams[field].player(catcher_id), Vector3(0.0, -1.15, 0.0), centre + Vector3(0.3, -1.05, 0.0), 0.05, &"restrain", 5.0, centre + Vector3(0.0, -0.45, 0.0))
	# The fielders from where they stand.
	for kind_on: Position.Kind in [Position.Kind.B1, Position.Kind.B2, Position.Kind.B3, Position.Kind.SS, Position.Kind.LF, Position.Kind.CF, Position.Kind.RF]:
		var id := g.teams[field].fielder_at(kind_on)
		if id == "" or taken.has(id):
			continue
		taken[id] = true
		var fig_at: Vector3 = Field.to_field(scene.fielders[kind_on].position) if scene.fielders.has(kind_on) else Vector3(0.0, 30.0, 0.0)
		var outfield := kind_on in Position.OUTFIELD
		_add(field, g.teams[field].player(id), Vector3(fig_at.x, fig_at.y, 0.0), _ring(centre, rng, true, 1.0 if not outfield else 2.0, 2.4 if not outfield else 3.2), 0.3 + rng.next_float() * 0.4, &"push" if not outfield else &"point", 8.0, centre)
	# The runners on base.
	for base: int in [1, 2, 3]:
		var id := scene._id_on(base)
		if id == "" or taken.has(id):
			continue
		taken[id] = true
		var bag := PlaySim.base_xy(base)
		_add(bat, g.teams[bat].player(id), Vector3(bag.x, bag.y, 0.0), _ring(centre, rng, false, 1.0, 2.2), 0.4, &"grab", 7.0, centre)
	# Both benches.
	for side: int in [bat, field]:
		var men: Array[Player] = []
		for id: String in g.teams[side].players:
			if not taken.has(id) and not g.teams[side].removed.has(id) and men.size() < (8 if side == bat else 6):
				men.append(g.teams[side].players[id])
				taken[id] = true
		var dugout := scene._dugout(side)
		var roles: Array[StringName] = [&"restrain", &"push", &"grab", &"point", &"push", &"grab", &"restrain", &"point"]
		for i: int in men.size():
			var from := dugout + Vector3(rng.next_range(-2.5, 2.5), rng.next_range(-1.5, 1.5), 0.0)
			var near := roles[i] in [&"restrain", &"push", &"grab"]
			_add(side, men[i], from, _ring(centre, rng, side == field, 0.9 if near else 2.0, 2.0 if near else 3.0), 0.6 + rng.next_float() * 1.2, roles[i], 7.5, centre)
	_prepare_figures()


## A place in the knot: on the side's own half (the fielding side toward the mound), between
## `inner` and `outer` from its middle.
func _ring(centre: Vector3, rng: Rng, mound_side: bool, inner: float, outer: float) -> Vector3:
	var ang := rng.next_range(0.25, PI - 0.25)
	if not mound_side:
		ang = -ang
	var r := rng.next_range(inner, outer)
	return centre + Vector3(cos(ang) * r, sin(ang) * r * 0.8, 0.0)


func _add(side: int, p: Player, from: Vector3, slot: Vector3, delay: float, role: StringName, speed: float, face: Vector3) -> void:
	if p == null:
		return
	plan.append({"side": side, "player": p, "from": from, "slot": slot, "delay": delay, "role": role, "speed": speed, "face": face})


func _prepare_figures() -> void:
	scene._rush_figures(plan.size())
	for i: int in plan.size():
		var e := plan[i]
		var p: Player = e["player"]
		if e.has("style"):
			scene._dress(scene._rush[i], e["style"], 0, "", false)
			var model := scene._rush[i] as SkinnedPuppet
			if model != null:
				var boss: bool = e["role"] == &"manager"
				model.set_body(1.76 if boss else 1.75, &"solid" if boss else &"standard")
				model.set_face("manager" if boss else "medic%d" % i, 57 if boss else 35)
				model.set_hair(1 + i % 4, Color(0.06, 0.05, 0.045))
		else:
			scene._dress_rush(scene._rush[i], int(e["side"]), p)


func brawl_shots() -> Array[Broadcast.Shot]:
	var c := Vector3(BRAWL_AT.x, BRAWL_AT.y, 0.0)
	var bx := scene._box.x * (-1.0 if scene.settings.bats_left else 1.0)
	return [
		# Over the batter's shoulder as he starts for the mound.
		Broadcast.Shot.make(0.0, Vector3(bx - 2.6, -2.2, 1.6), c + Vector3(0.0, 4.0, 1.3), 36.0, Vector3(bx - 1.8, -0.8, 1.6), c + Vector3(0.0, 3.0, 1.3), 34.0),
		# Wide from high behind the plate: the benches empty.
		Broadcast.Shot.make(1.7, Vector3(0.0, -16.0, 10.0), c + Vector3(0.0, 8.0, 0.0), 52.0, Vector3(0.0, -13.0, 8.5), c + Vector3(0.0, 4.0, 0.0), 46.0),
		# Close on the knot from the first-base side.
		Broadcast.Shot.make(3.8, c + Vector3(6.5, -1.5, 2.1), c + Vector3(0.0, 0.0, 1.2), 32.0, c + Vector3(5.8, 0.5, 2.0), c + Vector3(0.0, 0.0, 1.2), 30.0),
		# And from the other side, tighter.
		Broadcast.Shot.make(6.2, c + Vector3(-5.2, 3.5, 2.3), c + Vector3(0.0, -0.2, 1.3), 28.0, c + Vector3(-4.6, 3.0, 2.2), c + Vector3(0.0, -0.2, 1.3), 27.0),
	]


func _show_brawl(t: float) -> void:
	# The knot heaves back and forth.
	var heave := Vector3(0.55 * sin(t * 0.9), 0.4 * sin(t * 0.63 + 1.0), 0.0)
	for i: int in scene._rush.size():
		var fig := scene._rush[i]
		if i >= plan.size():
			fig.visible = false
			continue
		var e := plan[i]
		var from: Vector3 = e["from"]
		var slot: Vector3 = (e["slot"] as Vector3) + heave * (1.0 if e["role"] != &"core" else 0.6)
		var delay: float = e["delay"]
		var run_time := maxf(Vector2(slot.x - from.x, slot.y - from.y).length() / float(e["speed"]), 0.01)
		var u := clampf((t - delay) / run_time, 0.0, 1.0)
		var at := from.lerp(slot, smoothstep(0.0, 1.0, u) if e["role"] == &"core" else u)
		var face: Vector3 = (e["face"] as Vector3) + heave
		var pose := PuppetClips.standing()
		var role: StringName = e["role"]
		var sway := 0.12 * sin(t * 2.4 + i * 1.7)
		if t < delay:
			pose = PuppetClips.standing()
		elif u < 1.0:
			pose = PuppetClips.run_at((t - delay) * 3.3, 1.0)
			face = slot
		else:
			at += Vector3(sway, 0.6 * sway, 0.0)
			var beat := fmod(t * 1.3 + i * 0.37, 2.0)
			match role:
				&"core":
					pose = PuppetClips.square_up() if beat < 1.0 else PuppetClips.point_at()
				&"restrain":
					pose = PuppetClips.hold(1.15, 0.32, 0.38).blend(PuppetClips.hold(1.3, 0.4, 0.3), 0.5 + 0.5 * sin(t * 3.0 + i))
				&"push":
					pose = PuppetClips.shove(0.5 + 0.5 * sin(t * 4.0 + i * 2.1))
				&"grab":
					pose = PuppetClips.hold(1.48, 0.5, 0.42).blend(PuppetClips.shove(0.6), 0.5 + 0.5 * sin(t * 3.4 + i))
				_:
					pose = PuppetClips.point_at() if beat < 1.2 else PuppetClips.square_up()
		fig.visible = true
		fig.position = Field.to_world(Vector3(at.x, at.y, 0.0))
		fig.rotation = Vector3(0.0, MatchScene._yaw_toward(Vector2(at.x, at.y), Vector2(face.x, face.y)), 0.0)
		fig.apply(pose)
	# The plate umpire steps between them.
	var ump_from := Vector3(0.3 if scene.settings.bats_left else -0.3, -2.3, 0.0)
	var ump_to := Vector3(BRAWL_AT.x + 0.9, BRAWL_AT.y, 0.0) + heave * 0.8
	var k := clampf((t - 0.6) / 1.6, 0.0, 1.0)
	var ua := ump_from.lerp(ump_to, k)
	scene.umpire.position = Field.to_world(ua)
	scene.umpire.rotation.y = MatchScene._yaw_toward(Vector2(ua.x, ua.y), Vector2(BRAWL_AT.x, BRAWL_AT.y))
	scene.umpire.apply(PuppetClips.run_at(t * 3.0, 0.7) if k < 1.0 else PuppetClips.hold(1.3, 0.9, 0.3))


# --- The injury: the stretcher and the ambulance ---


## He is down where he was hit (`hurt_id` of `side`).
func plan_medical(hurt_id: String, side: int) -> void:
	kind = &"medical"
	plan.clear()
	_applauded = false
	var g := scene.game
	var man := g.teams[side].player(hurt_id)
	if man == null:
		kind = &""
		return
	var bx := scene._box.x * (-1.0 if scene.settings.bats_left else 1.0)
	_down = Vector3(bx + signf(bx) * 0.6, scene._box.y + 0.4, 0.0)
	# He fell away from the plate, his head toward the dugout side.
	_yaw_down = MatchScene._yaw_toward(Vector2(_down.x, _down.y), Vector2(_down.x + signf(bx) * 3.0, _down.y + 1.0))
	# The ambulance comes in by the outfield corner on his side and stops along the line near him.
	var side_sign := signf(bx) if bx != 0.0 else -1.0
	var az := 44.0 * (1.0 if side_sign > 0.0 else -1.0)
	_gate = StadiumBuilder.at_az(az, scene.park.collision.boundary_distance(az) - 2.0, 0.0)
	_stop = _down + Vector3(side_sign * 5.5, 4.0, 0.0)
	_add(side, man, _down, _down, 0.0, &"down", 0.0, _down)
	var trainer := _men_of_bench(side, hurt_id)
	if trainer != null:
		_add(side, trainer, scene._dugout(side), _down + Vector3(-side_sign * 0.7, 0.3, 0.0), 0.2, &"kneel", 6.5, _down)
	for i: int in 3:
		var medic := Player.new()
		medic.id = "medic%d" % i
		medic.name = ""
		plan.append({"side": side, "player": medic, "from": _stop, "slot": _down, "delay": 0.0, "role": &"medic", "speed": 4.5, "face": _down, "index": i,
			"style": UniformStyle.make(MEDIC_VEST, MEDIC_PANTS, MEDIC_PANTS, MEDIC_PANTS, "")})
	_prepare_figures()
	_make_props()


func _men_of_bench(side: int, skip: String) -> Player:
	var men := scene._men_of(side, 1, skip)
	return men[0] if not men.is_empty() else null


## Seconds into the scene: the ambulance at the gate, in the cut at its stop, the medics out
## with the stretcher, him lifted on, carried to the back, aboard, the ambulance away.
const AMB_IN := 2.0
const AMB_CUT := 4.0
const AMB_STOPPED := 5.0
const MEDICS_THERE := 6.4
const LIFTED := 7.6
const AT_DOORS := 10.0
const AMB_OFF := 10.6


func medical_shots() -> Array[Broadcast.Shot]:
	var d := _down
	var out := signf(d.x) if d.x != 0.0 else -1.0
	var to_gate := (_gate - _stop).normalized()
	return [
		# Close on him down, from his outside.
		Broadcast.Shot.make(0.0, d + Vector3(out * 3.2, 2.6, 1.3), d + Vector3(0.0, 0.0, 0.3), 34.0, d + Vector3(out * 2.8, 2.2, 1.2), d + Vector3(0.0, 0.0, 0.3), 31.0),
		# The ambulance through the outfield gate, lights going.
		Broadcast.Shot.make(AMB_IN, _gate - to_gate * 16.0 + Vector3(-out * 5.0, 0.0, 2.5), _gate - to_gate * 3.0 + Vector3(0.0, 0.0, 1.2), 34.0, _gate - to_gate * 14.0 + Vector3(-out * 5.0, 0.0, 2.3), _gate - to_gate * 8.0 + Vector3(0.0, 0.0, 1.2), 34.0),
		# By the plate: it pulls up, the medics run out.
		Broadcast.Shot.make(AMB_CUT, d + Vector3(-out * 6.0, -5.0, 2.6), (d + _stop) * 0.5 + Vector3(0.0, 0.0, 0.8), 40.0, d + Vector3(-out * 5.0, -4.5, 2.4), (d + _stop) * 0.5 + Vector3(0.0, 0.0, 0.8), 37.0),
		# Close as they lift him and carry him off.
		Broadcast.Shot.make(MEDICS_THERE, d + Vector3(out * 3.5, -3.0, 1.8), d + Vector3(0.0, 0.0, 0.6), 34.0, _stop + Vector3(out * 5.0, -4.5, 2.2), _stop + Vector3(0.0, 0.0, 1.0), 38.0),
		# Away it goes.
		Broadcast.Shot.make(AMB_OFF, _stop + Vector3(-out * 9.0, -9.0, 4.0), _stop + Vector3(0.0, 6.0, 1.0), 44.0, _stop + Vector3(-out * 8.0, -8.0, 4.0), _stop + Vector3(0.0, 14.0, 1.0), 46.0),
	]


func _make_props() -> void:
	if _stretcher == null:
		_stretcher = Node3D.new()
		var bed := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.56, 0.06, 1.95)
		bed.mesh = box
		bed.material_override = _mat(Color(0.95, 0.45, 0.1), 0.6)
		_stretcher.add_child(bed)
		for side: float in [-1.0, 1.0]:
			var pole := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.022
			cyl.bottom_radius = 0.022
			cyl.height = 2.35
			pole.mesh = cyl
			pole.material_override = _mat(Color(0.75, 0.76, 0.78), 0.3, 0.8)
			pole.rotation_degrees = Vector3(90.0, 0.0, 0.0)
			pole.position = Vector3(side * 0.3, 0.0, 0.0)
			_stretcher.add_child(pole)
		scene.add_child(_stretcher)
	if _ambulance == null:
		_ambulance = _build_ambulance()
		scene.add_child(_ambulance)
	_stretcher.visible = false
	_ambulance.visible = false


func _mat(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


## A van ambulance: a white box with a red band and the word on its side, a cab in front, a
## bar of red and blue lights, four wheels. Length along its local -Z (its front).
func _build_ambulance() -> Node3D:
	var root := Node3D.new()
	var parts := [
		[Vector3(2.0, 2.05, 3.6), Vector3(0.0, 1.47, 0.55), Color(0.96, 0.96, 0.97)],
		[Vector3(2.0, 1.55, 1.5), Vector3(0.0, 1.22, -1.95), Color(0.96, 0.96, 0.97)],
		[Vector3(2.02, 0.22, 3.62), Vector3(0.0, 1.25, 0.55), Color(0.85, 0.1, 0.12)],
		[Vector3(2.02, 0.12, 1.52), Vector3(0.0, 1.05, -1.95), Color(0.85, 0.1, 0.12)],
		[Vector3(1.9, 0.6, 0.05), Vector3(0.0, 1.62, -2.71), Color(0.15, 0.2, 0.25)],
		[Vector3(2.0, 0.3, 5.1), Vector3(0.0, 0.42, -0.2), Color(0.2, 0.2, 0.22)],
	]
	for part: Array in parts:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = part[0]
		mi.mesh = b
		mi.position = part[1]
		mi.material_override = _mat(part[2], 0.35)
		root.add_child(mi)
	for x: float in [-0.9, 0.9]:
		for z: float in [-1.7, 1.5]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.38
			cyl.bottom_radius = 0.38
			cyl.height = 0.26
			wheel.mesh = cyl
			wheel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			wheel.position = Vector3(x, 0.38, z)
			wheel.material_override = _mat(Color(0.05, 0.05, 0.05), 0.8)
			root.add_child(wheel)
	_lights.clear()
	for i: int in 2:
		var light := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.7, 0.16, 0.3)
		light.mesh = b
		light.position = Vector3(-0.38 + 0.76 * i, 2.58, -0.9)
		var m := _mat(Color(0.95, 0.1, 0.1) if i == 0 else Color(0.15, 0.35, 1.0), 0.3)
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 3.0
		light.material_override = m
		root.add_child(light)
		_lights.append(light)
	for side: float in [-1.0, 1.0]:
		var word := Label3D.new()
		word.text = "구급차"
		word.font = UiTheme.display(900)
		word.font_size = 160
		word.pixel_size = 0.004
		word.modulate = Color(0.85, 0.1, 0.12)
		word.outline_size = 0
		word.position = Vector3(side * 1.012, 1.8, 0.55)
		word.rotation_degrees = Vector3(0.0, 90.0 * side, 0.0)
		root.add_child(word)
	return root


## Where the ambulance is `t` seconds in (field), and the way it faces.
func _ambulance_at(t: float) -> Array:
	var to_stop := (_stop - _gate).normalized()
	if t < AMB_IN:
		return [_gate - to_stop * 3.0, to_stop, false]
	if t < AMB_CUT:
		# In through the gate (before the cut).
		var k := (t - AMB_IN) / (AMB_CUT - AMB_IN)
		return [_gate - to_stop * 3.0 + to_stop * 14.0 * k, to_stop, true]
	if t < AMB_OFF:
		# After the cut: pulling up the last stretch to its stop.
		var k2 := clampf((t - AMB_CUT) / (AMB_STOPPED - AMB_CUT), 0.0, 1.0)
		var ease := 1.0 - (1.0 - k2) * (1.0 - k2)
		return [_stop - to_stop * 9.0 * (1.0 - ease), to_stop, true]
	# Away: back toward the gate, turning.
	var k3 := t - AMB_OFF
	var back := -to_stop
	return [_stop + back * (2.0 * k3 * k3), to_stop.lerp(back, clampf(k3 / 1.2, 0.0, 1.0)).normalized(), true]


func _show_medical(t: float) -> void:
	# The ambulance, its lights turning.
	var amb: Array = _ambulance_at(t)
	var apos: Vector3 = amb[0]
	var adir: Vector3 = amb[1]
	_ambulance.visible = amb[2]
	_ambulance.position = Field.to_world(apos)
	var ahead := Field.to_world(apos + adir) - Field.to_world(apos)
	_ambulance.rotation = Vector3(0.0, atan2(-ahead.x, -ahead.z), 0.0)
	for i: int in _lights.size():
		_lights[i].visible = fmod(t * 3.0 + i * 0.5, 1.0) < 0.5
	var rear := _stop - adir * 3.2
	# The stretcher and the man on it.
	var carry_from := _down
	var carried := 0.0
	if t >= LIFTED:
		carried = clampf((t - LIFTED) / (AT_DOORS - LIFTED), 0.0, 1.0)
	var bed_at := carry_from.lerp(rear, carried)
	var on_bed := t >= LIFTED - 0.6
	var lift := clampf((t - (LIFTED - 0.6)) / 0.6, 0.0, 1.0)
	var bed_height := lerpf(0.12, 0.85, lift)
	var aboard := t >= AT_DOORS + 0.3
	_stretcher.visible = t >= AMB_STOPPED and not aboard
	var bed_yaw := _yaw_down if carried <= 0.0 else MatchScene._yaw_toward(Vector2(bed_at.x, bed_at.y), Vector2(rear.x, rear.y))
	var stretcher_at := bed_at if t >= MEDICS_THERE else _stop.lerp(_down, clampf((t - AMB_STOPPED) / (MEDICS_THERE - AMB_STOPPED), 0.0, 1.0))
	_stretcher.position = Field.to_world(Vector3(stretcher_at.x, stretcher_at.y, bed_height if t >= MEDICS_THERE else 0.85))
	_stretcher.rotation = Vector3(0.0, bed_yaw, 0.0)
	if t >= AT_DOORS and not _applauded:
		_applauded = true
		if scene.sound != null:
			scene.sound._crowd_one("crowd/clap", -4.0)
	for i: int in scene._rush.size():
		var fig := scene._rush[i]
		if i >= plan.size():
			fig.visible = false
			continue
		var e := plan[i]
		var role: StringName = e["role"]
		fig.visible = true
		match role:
			&"down":
				fig.visible = not aboard
				# On his back, a knee up, a hand on where it hit him; then on the stretcher.
				var at := bed_at if on_bed else _down
				var h := (bed_height + 0.04) if on_bed else 0.1
				# (The figure's feet are its origin: it lies along its own facing, head first.)
				var forward := Vector3(sin(bed_yaw if on_bed else _yaw_down), 0.0, cos(bed_yaw if on_bed else _yaw_down))
				var world := Field.to_world(Vector3(at.x, at.y, h))
				fig.position = world - forward * 0.0 - Basis(Vector3.UP, (bed_yaw if on_bed else _yaw_down)) * Vector3(0.0, 0.0, 0.9)
				fig.rotation = Vector3(PI / 2.0, bed_yaw if on_bed else _yaw_down, 0.0)
				fig.apply(PuppetClips.lying(t))
			&"kneel":
				var from: Vector3 = e["from"]
				var slot: Vector3 = e["slot"]
				var run := maxf(Vector2(slot.x - from.x, slot.y - from.y).length() / float(e["speed"]), 0.01)
				var u := clampf((t - float(e["delay"])) / run, 0.0, 1.0)
				# He steps back for the medics.
				var spot := from.lerp(slot, u) if t < MEDICS_THERE else slot + (slot - _down).normalized() * 1.0
				fig.position = Field.to_world(spot)
				fig.rotation = Vector3(0.0, MatchScene._yaw_toward(Vector2(spot.x, spot.y), Vector2(_down.x, _down.y) if u >= 1.0 else Vector2(slot.x, slot.y)), 0.0)
				fig.apply(PuppetClips.run_at(t * 3.0, 0.8) if u < 1.0 else (PuppetClips.kneel() if t < MEDICS_THERE else PuppetClips.standing()))
				fig.visible = t < AT_DOORS + 0.5
			_:
				# The medics: out of the back with the stretcher, at its corners as they lift and
				# carry it, aboard after him.
				var idx := int(e["index"])
				fig.visible = t >= AMB_STOPPED and t < AT_DOORS + 0.6
				var ends := [Vector3(0.0, 0.0, 1.2), Vector3(0.0, 0.0, -1.2), Vector3(0.55, 0.0, 0.0)]
				var local: Vector3 = ends[idx]
				var basis := Basis(Vector3.UP, bed_yaw)
				var world_off := basis * local
				var spot_world := _stretcher.position + Vector3(world_off.x, 0.0, world_off.z)
				spot_world.y = Field.to_world(Vector3.ZERO).y
				fig.position = spot_world
				var walking := (t >= AMB_STOPPED and t < MEDICS_THERE) or (t >= LIFTED and t < AT_DOORS)
				var face := _stretcher.position
				fig.rotation = Vector3(0.0, atan2(-(face.x - spot_world.x), -(face.z - spot_world.z)) if idx == 2 or not walking else bed_yaw + (PI if idx == 1 else 0.0), 0.0)
				if walking:
					fig.apply(PuppetClips.walk(t * 2.2 + idx))
				elif t < LIFTED and t >= MEDICS_THERE:
					fig.apply(PuppetClips.kneel())
				else:
					fig.apply(PuppetClips.hold(0.9, 0.5, 0.3))


# --- The title won: the pile at the mound and the manager tossed ---
# (the user, 2026-11-23: "the championship clinch — the pile, 헹가래"). As a KBO title is won:
# the last out, the pitcher's arms go up and the catcher runs out to leap on him; the fielders
# and both benches of the winners pour onto the mound and jump in a ring; then they lift their
# manager and toss him three times. The other side has gone.

## Where it all happens (field coordinates): the mound.
const MOUND := Vector3(0.0, Field.RUBBER_Y - 0.4, 0.0)
## When the tossing starts, how long each toss takes, how high he goes (m).
const TOSS_FROM := 6.6
const TOSS_EVERY := 1.55
const TOSS_HEIGHT := 1.35
## How high the manager lies on their hands between tosses.
const TOSS_REST := 1.9


func plan_champion(side: int) -> void:
	kind = &"champion"
	plan.clear()
	var g := scene.game
	var rng := Rng.new(hash("title:%d" % scene.seed_value))
	var team := g.teams[side]
	var taken: Dictionary[String, bool] = {}
	var fielding := g.fielding() == side
	# The battery and the fielders from where they stand (when the winners were in the field
	# for the last out; after a walk-off they come from the dugout like the rest).
	if fielding:
		var pitcher_id := g.pitcher_id()
		_add(side, team.player(pitcher_id), MOUND, MOUND, 0.0, &"pitcher", 2.0, MOUND + Vector3(0.0, -3.0, 0.0))
		taken[pitcher_id] = true
		for kind_on: Position.Kind in [Position.Kind.C, Position.Kind.B1, Position.Kind.B2, Position.Kind.B3, Position.Kind.SS, Position.Kind.LF, Position.Kind.CF, Position.Kind.RF]:
			var id := team.fielder_at(kind_on)
			if id == "" or taken.has(id):
				continue
			taken[id] = true
			var at: Vector3 = Field.to_field(scene.fielders[kind_on].position) if scene.fielders.has(kind_on) else (Vector3(0.0, -1.2, 0.0) if kind_on == Position.Kind.C else Vector3(0.0, 30.0, 0.0))
			var delay := 0.15 if kind_on == Position.Kind.C else 0.3 + rng.next_float() * 0.5
			_add(side, team.player(id), Vector3(at.x, at.y, 0.0), _round_mound(rng, 0.7, 1.6), delay, &"pile", 7.5, MOUND)
	# The bench pours out.
	var dugout := scene._dugout(side)
	var men := 0
	for id: String in team.players:
		if taken.has(id) or team.removed.has(id) or men >= 10:
			continue
		taken[id] = true
		men += 1
		var from := dugout + Vector3(rng.next_range(-2.5, 2.5), rng.next_range(-1.5, 1.5), 0.0)
		_add(side, team.players[id], from, _round_mound(rng, 1.2, 2.6), 0.6 + rng.next_float() * 1.6, &"pile", 7.0, MOUND)
	# The manager: in the club's jacket, out last, tossed in the middle.
	var style := UniformStyle.for_team(scene.club(side), side == 1)
	var boss := Player.new()
	boss.id = "manager_%s" % team.team_id
	boss.name = "감독"
	plan.append({"side": side, "player": boss, "from": dugout, "slot": MOUND + Vector3(0.0, -0.6, 0.0), "delay": 2.4, "role": &"manager", "speed": 4.0, "face": MOUND + Vector3(0.0, -3.0, 0.0),
		"style": UniformStyle.make(style.cap.darkened(0.2), Color(0.12, 0.13, 0.16), style.cap, style.cap, style.cap_letter)})
	_prepare_figures()


## A place round the mound, `inner` to `outer` from its middle, all the way round.
func _round_mound(rng: Rng, inner: float, outer: float) -> Vector3:
	var ang := rng.next_range(0.0, TAU)
	var r := rng.next_range(inner, outer)
	return MOUND + Vector3(cos(ang) * r, sin(ang) * r * 0.85, 0.0)


func champion_shots() -> Array[Broadcast.Shot]:
	var c := MOUND
	return [
		# On the mound from in front as the last out is made: the pitcher, arms up.
		Broadcast.Shot.make(0.0, c + Vector3(1.6, -7.0, 1.6), c + Vector3(0.0, 0.0, 1.6), 30.0, c + Vector3(1.0, -5.6, 1.6), c + Vector3(0.0, 0.0, 1.5), 32.0),
		# Wide and high from in front of the backstop (its net is not in the way): everyone
		# pours onto the field.
		Broadcast.Shot.make(2.6, Vector3(0.0, -11.5, 10.5), c + Vector3(0.0, 4.0, 0.0), 52.0, Vector3(0.0, -9.0, 8.5), c + Vector3(0.0, 1.0, 0.0), 46.0),
		# Close and low on the pile, from the first-base side.
		Broadcast.Shot.make(4.6, c + Vector3(7.0, -2.0, 1.4), c + Vector3(0.0, 0.0, 1.4), 34.0, c + Vector3(5.8, -0.6, 1.5), c + Vector3(0.0, 0.0, 1.6), 32.0),
		# The toss, from low in front, looking up.
		Broadcast.Shot.make(TOSS_FROM - 0.4, c + Vector3(-1.5, -7.5, 1.0), c + Vector3(0.0, -0.6, 2.4), 38.0, c + Vector3(-0.8, -6.2, 0.9), c + Vector3(0.0, -0.6, 2.7), 36.0),
	]


func _show_champion(t: float) -> void:
	var toss := t >= TOSS_FROM
	for i: int in scene._rush.size():
		var fig := scene._rush[i]
		if i >= plan.size():
			fig.visible = false
			continue
		var e := plan[i]
		var role: StringName = e["role"]
		var from: Vector3 = e["from"]
		var slot: Vector3 = e["slot"]
		# For the toss the men close in round the manager.
		if toss and role == &"pile":
			var off := Vector2(slot.x - MOUND.x, slot.y - MOUND.y)
			var ring := (MOUND + Vector3(0.0, -0.6, 0.0)) + Vector3(off.normalized().x, off.normalized().y, 0.0) * (0.75 if i % 2 == 0 else 1.25)
			slot = slot.lerp(ring, smoothstep(TOSS_FROM, TOSS_FROM + 0.6, t))
		var delay: float = e["delay"]
		var run_time := maxf(Vector2(slot.x - from.x, slot.y - from.y).length() / float(e["speed"]), 0.01)
		var u := clampf((t - delay) / run_time, 0.0, 1.0)
		var at := from.lerp(slot, u)
		var face: Vector3 = e["face"]
		var pose := PuppetClips.standing()
		var height := 0.0
		if role == &"pitcher":
			# Arms up on the mound; the catcher reaches him and they jump together.
			pose = PuppetClips.hold(2.05, 0.5, 0.15)
			height = 0.3 * maxf(sin((t - 0.6) * 7.0), 0.0) if t > 0.6 and not toss else 0.0
			if toss:
				pose = PuppetClips.hold(1.95, 0.3, 0.25)
		elif role == &"manager":
			if t < delay:
				pose = PuppetClips.standing()
			elif u < 1.0:
				pose = PuppetClips.run_at((t - delay) * 2.6, 0.6)
				face = slot
			elif toss:
				# On his back on their hands, up and down three times, across the camera's view
				# (FieldScenes.champion_shots' last), arms and legs flung out.
				var k := fmod(t - TOSS_FROM, TOSS_EVERY) / TOSS_EVERY
				var lift := TOSS_HEIGHT * sin(k * PI) if t < TOSS_FROM + TOSS_EVERY * 3.0 else 0.0
				var yaw := MatchScene._yaw_toward(Vector2(at.x, at.y), Vector2(at.x + 1.0, at.y))
				fig.visible = true
				# (The figure's feet are its origin: lying, its middle is 0.9 m along its facing.)
				fig.position = Field.to_world(Vector3(at.x, at.y, Field.ground_height(at.x, at.y) + TOSS_REST + lift)) - Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 0.9)
				fig.rotation = Vector3(PI / 2.0, yaw, 0.0)
				fig.apply(PuppetClips.tossed(t, k))
				continue
			else:
				pose = PuppetClips.wave(t)
		else:
			if t < delay:
				pose = PuppetClips.standing()
			elif u < 1.0:
				pose = PuppetClips.run_at((t - delay) * 3.2, 1.0)
				face = slot
			elif toss:
				# Hands up under him, rising and falling with each toss.
				var k := fmod(t - TOSS_FROM, TOSS_EVERY) / TOSS_EVERY
				pose = PuppetClips.hold(1.75 + 0.35 * sin(k * PI), 0.35, 0.3)
				face = MOUND + Vector3(0.0, -0.6, 0.0)
			else:
				# Jumping in the ring, arms up, a fist now and then.
				height = 0.28 * maxf(sin(t * 6.0 + i * 1.3), 0.0)
				pose = PuppetClips.hold(2.0, 0.45, 0.15) if fmod(t * 0.9 + i * 0.31, 1.6) < 1.1 else PuppetClips.fist_pump()
				face = MOUND
		fig.visible = true
		# (On the mound's slope, not in it: it stands ten inches high at the rubber.)
		fig.position = Field.to_world(Vector3(at.x, at.y, height + Field.ground_height(at.x, at.y)))
		var yaw := MatchScene._yaw_toward(Vector2(at.x, at.y), Vector2(face.x, face.y)) if Vector2(face.x - at.x, face.y - at.y).length() > 0.05 else fig.rotation.y
		fig.rotation = Vector3(0.0, yaw, 0.0)
		fig.apply(pose)
	# The umpires walk off.
	scene.umpire.visible = t < 2.0


# --- Shared ---


## The scene's figures at `t` seconds (the game's own cast hidden), or all put back (t < 0).
func show(t: float) -> void:
	if t < 0.0:
		_restore()
		return
	if _hidden.is_empty():
		_hide_cast()
	if kind == &"brawl":
		_show_brawl(t)
	elif kind == &"medical":
		_show_medical(t)
	elif kind == &"champion":
		_show_champion(t)
	elif kind == &"farewell":
		_show_farewell(t)


func _hide_cast() -> void:
	var cast: Array[Node3D] = [scene.batter, scene.catcher, scene.pitcher]
	if kind == &"medical":
		cast = [scene.batter]
	else:
		for kind_on: Position.Kind in scene.fielders:
			cast.append(scene.fielders[kind_on])
		for r: Puppet in scene.runner_puppets:
			cast.append(r)
	for n: Node3D in cast:
		if n != null and n.visible and not _hidden.has(n):
			n.visible = false
			_hidden.append(n)


func _restore() -> void:
	for n: Node3D in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	for fig: Puppet in scene._rush:
		fig.visible = false
	if scene.umpire != null:
		scene.umpire.visible = true
	if _stretcher != null:
		_stretcher.visible = false
	if _ambulance != null:
		_ambulance.visible = false
	if _banner != null:
		_banner.visible = false
	kind = &""


# --- A retirement at his park (the user, 2026-11-23: "a ceremony at the real ballpark, as the
# KBO does it") ---
# As KBO clubs see a star off: his teammates line up along the baselines, he walks out of the
# dugout to the front of home plate, bows to the stands behind it and waves, his number goes up
# over centre field (retired, or a thank-you), and his teammates come together and toss him.

const FAREWELL_LENGTH := 23.0
## Where he stands: in front of home plate, toward the mound.
const FAREWELL_SPOT := Vector3(0.0, 4.5, 0.0)
const FAREWELL_WALK := 2.0
const FAREWELL_BOW := 8.4
const FAREWELL_WAVE := 10.2
const FAREWELL_REVEAL := 12.6
const FAREWELL_TOSS := 16.0


func plan_farewell(side: int, hero: Player, retired: bool) -> void:
	kind = &"farewell"
	plan.clear()
	var g := scene.game
	var team := g.teams[side]
	var dugout := scene._dugout(side)
	var rng := Rng.new(hash("farewell:%s" % hero.id))
	var men := 0
	for id: String in team.players:
		if id == hero.id or team.removed.has(id) or men >= 16:
			continue
		# Two lines from home plate down the baselines, facing where he will stand.
		var line := 1.0 if men % 2 == 0 else -1.0
		var d := 6.0 + float(men / 2) * 2.3
		var slot := Vector3(line * d * 0.7071, d * 0.7071, 0.0)
		var from := dugout + Vector3(rng.next_range(-2.5, 2.5), rng.next_range(-1.5, 1.5), 0.0)
		_add(side, team.players[id], from, slot, rng.next_float() * 1.2, &"line", 5.0, FAREWELL_SPOT)
		men += 1
	_add(side, hero, dugout, FAREWELL_SPOT, FAREWELL_WALK, &"hero", 3.0, FAREWELL_SPOT + Vector3(0.0, -20.0, 0.0))
	var style := UniformStyle.for_team(scene.club(side), side == 1)
	var boss := Player.new()
	boss.id = "manager_%s" % team.team_id
	boss.name = "감독"
	plan.append({"side": side, "player": boss, "from": dugout, "slot": FAREWELL_SPOT + Vector3(1.8, 0.8, 0.0), "delay": 0.4, "role": &"line", "speed": 4.0, "face": FAREWELL_SPOT,
		"style": UniformStyle.make(style.cap.darkened(0.2), Color(0.12, 0.13, 0.16), style.cap, style.cap, style.cap_letter)})
	_prepare_figures()
	# His number over centre field, beyond the wall.
	if _banner == null:
		_banner = Label3D.new()
		_banner.font = UiTheme.display(900)
		_banner.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_banner.outline_size = 24
		_banner.outline_modulate = Color(0.05, 0.05, 0.08, 0.9)
		scene.add_child(_banner)
	var club := scene.club(side)
	# (The number alone in the sky, as a retired number hangs; the words are the broadcast's.)
	_banner.text = str(hero.number) if retired else "THANK YOU"
	_banner.font_size = 260 if retired else 150
	_banner.pixel_size = 0.06
	_banner.modulate = Color(1.0, 0.92, 0.7) if retired else Color.WHITE
	if club != null:
		_banner.outline_modulate = Color(club.primary.darkened(0.5), 0.95)
	var wall := scene.park.collision.boundary_distance(0.0) if scene.park != null else 120.0
	_banner.position = Field.to_world(Vector3(0.0, wall + 6.0, 24.0))
	_banner.visible = false


func farewell_shots() -> Array[Broadcast.Shot]:
	var spot := FAREWELL_SPOT
	var dugout := scene._dugout(GameState.HOME)
	var wall := scene.park.collision.boundary_distance(0.0) if scene.park != null else 120.0
	var banner := Vector3(0.0, wall + 6.0, 22.0)
	var walk_mid := (dugout + spot) * 0.5
	return [
		# The park from high over the first-base side, coming down: the lines forming.
		Broadcast.Shot.make(0.0, Vector3(55.0, 30.0, 42.0), Vector3(0.0, 8.0, 0.0), 50.0, Vector3(34.0, 14.0, 22.0), Vector3(0.0, 4.0, 0.0), 46.0),
		# Out of the dugout and down the line of his teammates.
		Broadcast.Shot.make(FAREWELL_WALK + 1.2, spot + Vector3(0.0, 9.0, 1.7), walk_mid + Vector3(0.0, 0.0, 1.4), 46.0, spot + Vector3(0.0, 7.0, 1.6), spot + Vector3(0.0, -1.0, 1.4), 40.0),
		# Close in front of him as he bows and waves to the stands.
		Broadcast.Shot.make(FAREWELL_BOW - 0.6, spot + Vector3(0.6, -4.6, 1.55), spot + Vector3(0.0, 0.0, 1.45), 32.0, spot + Vector3(0.3, -3.8, 1.55), spot + Vector3(0.0, 0.0, 1.5), 28.0),
		# Over his shoulder to centre field: his number goes up.
		Broadcast.Shot.make(FAREWELL_REVEAL - 0.3, spot + Vector3(1.2, -3.0, 2.1), banner, 44.0, spot + Vector3(0.6, -2.4, 2.2), banner, 26.0),
		# Tossed by his teammates, from low in front.
		Broadcast.Shot.make(FAREWELL_TOSS - 0.3, spot + Vector3(-1.5, -7.5, 1.0), spot + Vector3(0.0, 0.0, 2.4), 38.0, spot + Vector3(-0.8, -6.2, 0.9), spot + Vector3(0.0, 0.0, 2.7), 36.0),
		# From out by second base back to home plate and the full stands behind it.
		Broadcast.Shot.make(FAREWELL_LENGTH - 3.4, Vector3(0.0, 40.0, 9.0), spot + Vector3(0.0, -6.0, 3.0), 50.0, Vector3(0.0, 46.0, 12.0), spot + Vector3(0.0, -14.0, 6.0), 56.0),
	]


func _show_farewell(t: float) -> void:
	var toss := t >= FAREWELL_TOSS
	var hero_at := FAREWELL_SPOT
	for i: int in scene._rush.size():
		var fig := scene._rush[i]
		if i >= plan.size():
			fig.visible = false
			continue
		var e := plan[i]
		var role: StringName = e["role"]
		var from: Vector3 = e["from"]
		var slot: Vector3 = e["slot"]
		var delay: float = e["delay"]
		var speed: float = e["speed"]
		if toss and role == &"line":
			# The lines break and come round him.
			var off := Vector2(slot.x - FAREWELL_SPOT.x, slot.y - FAREWELL_SPOT.y).normalized()
			from = slot
			slot = FAREWELL_SPOT + Vector3(off.x, off.y, 0.0) * (0.75 if i % 2 == 0 else 1.25)
			delay = FAREWELL_TOSS - 0.8
			speed = 6.0
		var run_time := maxf(Vector2(slot.x - from.x, slot.y - from.y).length() / speed, 0.01)
		var u := clampf((t - delay) / run_time, 0.0, 1.0)
		var at := from.lerp(slot, u)
		var face: Vector3 = e["face"]
		var pose := PuppetClips.standing()
		if role == &"hero":
			if t < delay:
				pose = PuppetClips.standing()
			elif u < 1.0:
				pose = PuppetClips.run_at((t - delay) * 1.8, 0.35)
				face = slot
			elif toss:
				# On his back on their hands, up and down three times.
				var k := fmod(t - FAREWELL_TOSS, TOSS_EVERY) / TOSS_EVERY
				var lift := TOSS_HEIGHT * sin(k * PI) if t < FAREWELL_TOSS + TOSS_EVERY * 3.0 else 0.0
				var yaw := MatchScene._yaw_toward(Vector2(at.x, at.y), Vector2(at.x + 1.0, at.y))
				fig.visible = true
				fig.position = Field.to_world(Vector3(at.x, at.y, Field.ground_height(at.x, at.y) + TOSS_REST + lift)) - Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 0.9)
				fig.rotation = Vector3(PI / 2.0, yaw, 0.0)
				fig.apply(PuppetClips.tossed(t, k))
				continue
			elif t < FAREWELL_BOW:
				pose = PuppetClips.wave(t)
			elif t < FAREWELL_WAVE:
				# A deep bow to the stands, held.
				var k := smoothstep(FAREWELL_BOW, FAREWELL_BOW + 0.5, t) * (1.0 - smoothstep(FAREWELL_WAVE - 0.5, FAREWELL_WAVE, t))
				pose = PuppetClips.bow(k)
			elif t < FAREWELL_REVEAL:
				pose = PuppetClips.wave(t)
			else:
				# He turns to centre field to see his number go up, and raises his arms.
				face = Vector3(0.0, 100.0, 0.0)
				pose = PuppetClips.hold(1.95, 0.5, 0.15) if t > FAREWELL_REVEAL + 1.2 else PuppetClips.standing()
			hero_at = at
		else:
			if t < delay:
				pose = PuppetClips.standing()
			elif u < 1.0:
				pose = PuppetClips.run_at((t - delay) * 3.0, 0.8)
				face = slot
			elif toss:
				var k := fmod(t - FAREWELL_TOSS, TOSS_EVERY) / TOSS_EVERY
				pose = PuppetClips.hold(1.75 + 0.35 * sin(k * PI), 0.35, 0.3)
				face = FAREWELL_SPOT
			else:
				# Applauding him: hands together at the chest, again and again.
				pose = PuppetClips.hold(1.3, 0.06 + 0.1 * absf(sin(t * 8.0 + i)), 0.3)
				face = hero_at
		fig.visible = true
		fig.position = Field.to_world(Vector3(at.x, at.y, Field.ground_height(at.x, at.y)))
		var turn := MatchScene._yaw_toward(Vector2(at.x, at.y), Vector2(face.x, face.y)) if Vector2(face.x - at.x, face.y - at.y).length() > 0.05 else fig.rotation.y
		fig.rotation = Vector3(0.0, turn, 0.0)
		fig.apply(pose)
	scene.umpire.visible = false
	if _banner != null:
		var r := clampf((t - FAREWELL_REVEAL) / 0.8, 0.0, 1.0)
		_banner.visible = r > 0.0
		_banner.modulate.a = r
		_banner.scale = Vector3.ONE * lerpf(0.6, 1.0, 1.0 - pow(1.0 - r, 3.0))
