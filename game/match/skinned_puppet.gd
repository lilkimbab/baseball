class_name SkinnedPuppet
extends Puppet
## The same poses as Puppet, shown on the skinned player model instead of capsules.
##
## Key poses (apply) give hand and foot targets: Puppet.solve() works out joint positions and
## this turns them into bone rotations. Recorded motion (apply_joints) gives the joints of a
## real player; the trunk takes the recorded orientations and the limbs are fitted to this
## model's proportions with two-bone IK.

const MODEL := "res://assets/characters/player_base.glb"
const LIMBS: Array[Array] = [
	[&"LeftUpperArm", &"LeftLowerArm"], [&"LeftLowerArm", &"LeftHand"],
	[&"RightUpperArm", &"RightLowerArm"], [&"RightLowerArm", &"RightHand"],
	[&"LeftUpperLeg", &"LeftLowerLeg"], [&"LeftLowerLeg", &"LeftFoot"],
	[&"RightUpperLeg", &"RightLowerLeg"], [&"RightLowerLeg", &"RightFoot"],
]

const OPTIONAL_GEAR: Array[StringName] = [&"Mask", &"ChestProtector", &"ShinGuards"]
const FINGERS: Array[String] = ["Index", "Middle", "Ring", "Little"]
## Curl in degrees for [finger base, middle, tip, thumb] per grip.
const CURL := {
	Grip.RELAXED: [18.0, 22.0, 14.0, 10.0],
	Grip.BAT: [72.0, 84.0, 58.0, 34.0],
	Grip.BALL: [32.0, 44.0, 30.0, 38.0],
	Grip.GLOVE: [14.0, 8.0, 5.0, 12.0],
}
## Recorded trunk axes lean forward of the true ones (the markers sit on the front of the
## body), so the pelvis and ribcage are tipped back by this much, in radians.
const PELVIS_UPRIGHT := 0.0
const CHEST_UPRIGHT := 0.0

## Curl of the ring and little fingers [base, middle, tip] around a ball: they tuck in beside
## it while the index and middle fingers lie over the top.
const BALL_TUCK: Array[float] = [78.0, 88.0, 60.0]
## Equipment built to real sizes by tools/blender/make_props.py. Gloves are modelled in the
## hand's own frame (see _hand_frame), for the left hand.
const PROPS := {&"glove": "res://assets/props/glove.glb", &"mitt": "res://assets/props/mitt.glb", &"bat": "res://assets/props/bat.glb"}

## Team look and lettering. Change it and call repaint().
var uniform := UniformStyle.new()
## Batting gloves instead of bare hands.
var gloves := false
## Standing height in metres; the model is scaled to it. Set before adding to the scene, or
## change it with set_body().
var height := 1.83
## The body build (docs/13 S11-1): &"lean", &"standard", &"solid" or &"heavy", each a model
## built by ./dev model.
var build: StringName = &"standard"
## The batting helmet's ear flaps: &"left" (on the model's left ear: the ear toward the
## pitcher for a right-handed batter, and for a left-hander too once the figure is mirrored),
## or &"both" for a switch hitter (docs/13 S11-5).
var helmet_flaps: StringName = &"left"
## The team's letter on the front of the cap and helmet ("" none).
var logo := ""
var _flaps: Dictionary[StringName, MeshInstance3D] = {}
var _logos: Array[Label3D] = []
## Which of the model's four short hair styles shows (1 to 4; 0 none), and its colour.
var hair := 1
var hair_color := Color(0.07, 0.06, 0.055)
## &"glove" for a fielder's glove, &"mitt" for the catcher's.
var glove_kind: StringName = &"glove"
var _glove_shown: StringName = &""

var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _cap: MeshInstance3D
var _helmet: MeshInstance3D
var _model: Node3D
var _gear_parts: Dictionary[StringName, MeshInstance3D] = {}
## Finger curls for the grips they were last worked out for, and bones that the first posing
## pass can skip (arms, legs and fingers hang off the joints that pass is run to find).
var _curls: Dictionary[int, Basis] = {}
var _curls_for := -1
var _is_limb: PackedByteArray = PackedByteArray()
## Axis (skeleton space, at rest) each finger bone curls about, by bone index.
var _curl_axis: Dictionary[int, Vector3] = {}
## Skeleton space -> puppet space, and back.
var _to_puppet := Transform3D.IDENTITY
var _to_skeleton := Transform3D.IDENTITY
var _bone: Dictionary[StringName, int] = {}
var _rest: Array[Transform3D] = []
var _local_rest: Array[Transform3D] = []
var _parent: PackedInt32Array = PackedInt32Array()
## Rest direction (skeleton space) from each limb bone to the next joint.
var _aim_rest: Dictionary[StringName, Vector3] = {}
## Pelvis bone origin relative to the midpoint of the hip joints, at rest.
var _hips_offset := Vector3.ZERO
## Height of the ankle joint above the ground when standing, in the puppet's space.
var _ankle_height := 0.07
## Rest axis (skeleton space) each limb bone's elbow or knee bends about.
var _hinge_rest: Dictionary[StringName, Vector3] = {}
## Rest direction of each hand from the wrist to the knuckles, across the palm from the little
## finger to the index finger, and of each foot toward the toes along the ground.
var _hand_rest: Dictionary[String, Vector3] = {}
var _grip_rest: Dictionary[String, Vector3] = {}
var _toe_rest: Dictionary[String, Vector3] = {}
## Hinge axis and direction of each upper limb bone in the last recorded frame shown. A
## straight limb does not say how it is twisted, so the twist carries over from when it bent.
var _hinge_last: Dictionary[StringName, Vector3] = {}
var _dir_last: Dictionary[StringName, Vector3] = {}
## The way each palm faces at rest (skeleton space), and each wrist's place in the last
## recorded frame shown (puppet space), from which the hand's speed is worked out.
var _palm_rest: Dictionary[String, Vector3] = {}
var _wrist_last: Dictionary[String, Vector3] = {}
## Each hand as posed, in the puppet's space: origin in the palm, X across it toward the
## index finger, Y along the fingers, Z out of the palm.
var _hand_frame: Dictionary[String, Transform3D] = {}


static func available() -> bool:
	return ResourceLoader.exists(MODEL)


## The model file for a build (the standard one if that build has not been made).
static func model_for(b: StringName) -> String:
	var path := "res://assets/characters/player_%s.glb" % b
	return path if b != &"standard" and ResourceLoader.exists(path) else MODEL


## The build for a player of this height, weight and position (A): by body mass index, with
## catchers and first basemen a little thicker and centre fielders and middle infielders a
## little leaner, as clubs tend to play them.
static func build_for(height_cm: float, weight_kg: float, position: Position.Kind = Position.Kind.DH) -> StringName:
	var m := height_cm / 100.0
	var bmi := weight_kg / maxf(m * m, 1.0)
	match position:
		Position.Kind.C, Position.Kind.B1:
			bmi += 0.8
		Position.Kind.CF, Position.Kind.SS, Position.Kind.B2:
			bmi -= 0.6
	if bmi < 24.5:
		return &"lean"
	if bmi < 26.8:
		return &"standard"
	if bmi < 28.8:
		return &"solid"
	return &"heavy"


## Gives the figure another player's body: his build's model and his height.
func set_body(height_m: float, b: StringName) -> void:
	if _model == null:
		height = height_m
		build = b
		return
	if b != build or model_for(b) != model_for(build):
		build = b
		height = height_m
		var old := _model
		remove_child(old)
		old.queue_free()
		_load_model()
		_measure()
		_measure_fingers()
		_curls_for = -1
		_hinge_last.clear()
		_dir_last.clear()
		_wrist_last.clear()
		_paint()
	elif not is_equal_approx(height_m, height):
		height = height_m
		_model.scale = Vector3.ONE * (height / _mesh.get_aabb().end.y)
		_recompute_frames()
		_measure()


func _ready() -> void:
	_load_model()
	_measure()
	_measure_fingers()
	_paint()
	_build_props()
	apply(PuppetClips.fielder_ready())


func _recompute_frames() -> void:
	_to_puppet = Transform3D.IDENTITY
	var node: Node3D = _skeleton
	while node != self:
		_to_puppet = node.transform * _to_puppet
		node = node.get_parent() as Node3D
	_to_skeleton = _to_puppet.affine_inverse()


func _load_model() -> void:
	var model := (load(model_for(build)) as PackedScene).instantiate() as Node3D
	# glTF characters face +Z; the puppet's space faces -Z.
	model.rotation.y = PI
	add_child(model)
	_model = model
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_mesh = model.find_child("Body", true, false) as MeshInstance3D
	model.scale = Vector3.ONE * (height / _mesh.get_aabb().end.y)
	_cap = model.find_child("Cap", true, false) as MeshInstance3D
	_helmet = model.find_child("Helmet", true, false) as MeshInstance3D
	_flaps.clear()
	for side: StringName in [&"Left", &"Right"]:
		var flap := model.find_child("HelmetFlap" + side, true, false) as MeshInstance3D
		if flap != null:
			_flaps[side] = flap
	_logos.clear()
	_gear_parts.clear()
	for piece: StringName in OPTIONAL_GEAR:
		var part := model.find_child(piece, true, false) as MeshInstance3D
		if part != null:
			_gear_parts[piece] = part
	_recompute_frames()


func set_colors(jersey_color: Color, pants_color: Color, cap_color: Color) -> void:
	super.set_colors(jersey_color, pants_color, cap_color)
	uniform.jersey = jersey_color
	uniform.pants = pants_color
	uniform.cap = cap_color
	uniform.socks = cap_color
	uniform.trim = cap_color
	repaint()


## Applies the current uniform style, lettering and gloves to the model.
func repaint() -> void:
	if _mesh != null:
		_paint()


func set_back_lettering(number: int, player_name: String, ink: Color = Color.BLACK) -> void:
	uniform.number = number
	uniform.player_name = player_name
	uniform.ink = ink
	repaint()


func apply(pose: PuppetPose) -> void:
	solve(pose)
	_show_gear()
	_hinge_last.clear()
	var basis_for: Dictionary[int, Basis] = {}
	var curl := _finger_curls()

	# Spine: from the pelvis frame (heading plus a little lean) to the chest frame.
	var hip_right := hip_basis * Vector3.RIGHT
	var pelvis := Basis(hip_right, -pose.lean * 0.3) * hip_basis
	var chest := Basis(hip_right, -pose.lean) * chest_basis
	_turn_spine(basis_for, pelvis, chest)
	_turn(basis_for, &"Neck", Basis(pelvis.get_rotation_quaternion().slerp(chest.get_rotation_quaternion(), 0.6)))
	_turn(basis_for, &"Head", chest_basis)
	_turn(basis_for, &"LeftFoot", hip_basis)
	_turn(basis_for, &"RightFoot", hip_basis)

	# First pass: bend the spine, then read where the model's own shoulders and hips ended
	# up and solve the arms and legs again from there, so hands and feet land on target.
	var globals := _walk(basis_for, curl, pose.hips, true)
	if has_look_target:
		_aim_head(basis_for, _to_puppet * globals[_bone[&"Head"]].origin)
	var elbow_out := chest_basis * Vector3.RIGHT
	var back := chest_basis * Vector3.BACK
	for side: int in [-1, 1] as Array[int]:
		var name := "Right" if side > 0 else "Left"
		var shoulder := _to_puppet * globals[_bone[StringName(name + "UpperArm")]].origin
		var hand := _reach(shoulder, pose.r_hand if side > 0 else pose.l_hand, upper_arm + lower_arm)
		joints[StringName(name + "UpperArm")] = shoulder
		joints[StringName(name + "LowerArm")] = _two_bone(shoulder, hand, upper_arm, lower_arm, elbow_out * (0.5 * side) - Vector3.UP + back * 0.5)
		joints[StringName(name + "Hand")] = hand
		var hip := _to_puppet * globals[_bone[StringName(name + "UpperLeg")]].origin
		var ankle := _reach(hip, pose.r_foot if side > 0 else pose.l_foot, upper_leg + lower_leg)
		joints[StringName(name + "UpperLeg")] = hip
		joints[StringName(name + "LowerLeg")] = _two_bone(hip, ankle, upper_leg, lower_leg, hip_basis * Vector3.FORWARD + hip_right * (0.3 * side))
		joints[StringName(name + "Foot")] = ankle

	# Limbs: aim each bone from its joint toward the next one.
	for pair: Array in LIMBS:
		var from: StringName = pair[0]
		var to: StringName = pair[1]
		var want := _to_skeleton.basis * (joints[to] - joints[from])
		if want.length() < 1e-5:
			continue
		var index := _bone[from]
		basis_for[index] = Basis(Quaternion(_aim_rest[from], want.normalized())) * _rest[index].basis

	_pose_bones(_walk(basis_for, curl, pose.hips))
	_place_props(pose.bat_dir)


## Poses the model from recorded joint positions. The recording is of someone with other
## proportions, so it is fitted: the pelvis path is scaled by leg length, the trunk takes the
## recorded orientations, and feet and hands are placed with two-bone IK from the model's own
## hips and shoulders, bending toward the recorded knees and elbows. Feet therefore stay where
## the recorded feet stood, and two hands on a bat stay together.
func apply_joints(frame: Dictionary[StringName, Vector3], source: JointClip, hands_offset: Vector3 = Vector3.ZERO) -> void:
	_show_gear()
	var basis_for: Dictionary[int, Basis] = {}
	var curl := _finger_curls()

	var hip_mid := frame[&"LeftUpperLeg"].lerp(frame[&"RightUpperLeg"], 0.5)
	var top := frame[&"ThoraxTop"]
	var bottom := frame[&"ThoraxBottom"]
	var across_chest := frame[&"RightUpperArm"] - frame[&"LeftUpperArm"]
	if frame.has(&"ThoraxRight"):
		across_chest = frame[&"ThoraxRight"] - top
	var pelvis := _body_frame(frame[&"RightUpperLeg"] - frame[&"LeftUpperLeg"], bottom - hip_mid, PELVIS_UPRIGHT)
	var chest := _body_frame(across_chest, top - bottom, CHEST_UPRIGHT)
	hip_basis = pelvis
	chest_basis = chest
	spine_dir = chest.y
	_turn_spine(basis_for, pelvis, chest)
	_turn(basis_for, &"Neck", chest)
	_turn(basis_for, &"Head", chest)

	var leg_scale := (upper_leg + lower_leg) / source.leg_length
	var arm_scale := (upper_arm + lower_arm) / source.arm_length
	var hips := _fit(hip_mid, source, leg_scale)
	joints[&"Hips"] = hips

	# First pass places the trunk; arms and legs are then solved from where the model's own
	# shoulders and hips are. Hands are placed relative to the middle of the shoulders, so the
	# distance between them is the recorded one.
	var globals := _walk(basis_for, curl, hips, true)
	_face_target(basis_for, _to_puppet * globals[_bone[&"Head"]].origin, chest)
	var recorded_mid := frame[&"LeftUpperArm"].lerp(frame[&"RightUpperArm"], 0.5)
	var model_mid := _to_puppet * globals[_bone[&"LeftUpperArm"]].origin.lerp(globals[_bone[&"RightUpperArm"]].origin, 0.5)
	for side: String in JointClip.SIDES:
		var shoulder := _to_puppet * globals[_bone[StringName(side + "UpperArm")]].origin
		var wrist := model_mid + (frame[StringName(side + "Hand")] - recorded_mid) * arm_scale + hands_offset
		_fit_limb(frame, side, ["UpperArm", "LowerArm", "Hand"], shoulder, wrist, upper_arm, lower_arm)
		var hip := _to_puppet * globals[_bone[StringName(side + "UpperLeg")]].origin
		var ankle := _fit(frame[StringName(side + "Foot")], source, leg_scale)
		_fit_limb(frame, side, ["UpperLeg", "LowerLeg", "Foot"], hip, ankle, upper_leg, lower_leg)

	var bat := bat_direction(frame)
	var pelvis_turn := basis_for[_bone[&"Hips"]] * _rest[_bone[&"Hips"]].basis.inverse()
	var chest_turn := basis_for[_bone[&"UpperChest"]] * _rest[_bone[&"UpperChest"]].basis.inverse()
	for side: String in JointClip.SIDES:
		_orient_limb(basis_for, StringName(side + "UpperArm"), StringName(side + "LowerArm"), StringName(side + "Hand"), chest_turn, false)
		_orient_limb(basis_for, StringName(side + "UpperLeg"), StringName(side + "LowerLeg"), StringName(side + "Foot"), pelvis_turn, true)
		_orient_hand(basis_for, side, frame, bat)
		_orient_foot(basis_for, side, joints[StringName(side + "Foot")].y - _ankle_height)

	_pose_bones(_walk(basis_for, curl, hips))
	_place_props(bat)


## Forgets the limb twists carried over from earlier recorded frames. Call when the figure
## is about to show an unrelated motion.
func reset_motion() -> void:
	_hinge_last.clear()
	_dir_last.clear()
	_wrist_last.clear()


## A held ball sits against the base of the index and middle fingers, on the palm side.
func ball_spot(hand: StringName) -> Vector3:
	var side := "Left" if hand == &"LeftHand" else "Right"
	if not _hand_frame.has(side):
		return joints[hand]
	var frame := _hand_frame[side]
	return frame.origin + frame.basis.y * 0.03 + frame.basis.z * 0.044


func _build_props() -> void:
	super._build_props()
	_use_prop(&"Bat", &"bat", Color(0.74, 0.57, 0.36), 0.42, 26.0)


## Replaces a stand-in shape with the real piece of equipment, if it has been built.
func _use_prop(part: StringName, prop: StringName, colour: Color, roughness: float, grain_scale: float) -> void:
	var path: String = PROPS[prop]
	if not ResourceLoader.exists(path):
		return
	var scene := (load(path) as PackedScene).instantiate()
	var source := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var surface := StandardMaterial3D.new()
	surface.albedo_color = colour
	surface.roughness = roughness
	surface.normal_enabled = true
	surface.normal_texture = _grain()
	surface.normal_scale = 0.6
	surface.uv1_triplanar = true
	surface.uv1_scale = Vector3.ONE * grain_scale
	_parts[part].mesh = source.mesh
	_parts[part].material_override = surface
	scene.free()


func _place_props(direction: Vector3) -> void:
	super._place_props(direction)
	var glove := _parts[&"Glove"]
	if not glove.visible or not _hand_frame.has("Left"):
		return
	if _glove_shown != glove_kind:
		_glove_shown = glove_kind
		_use_prop(&"Glove", glove_kind, Color(0.35, 0.19, 0.085), 0.58, 12.0)
	# The glove is worn: it sits in the hand's frame, knuckles at its origin.
	glove.transform = _hand_frame["Left"]


func _show_gear() -> void:
	_cap.visible = headgear != &"helmet"
	_helmet.visible = headgear == &"helmet"
	for side: StringName in _flaps:
		_flaps[side].visible = headgear == &"helmet" and (side == &"Left" or helmet_flaps == &"both")
	var button := _model.find_child("CapButton", true, false) as MeshInstance3D
	if button != null:
		button.visible = _cap.visible
	for i: int in _logos.size():
		_logos[i].visible = logo != "" and (_cap.visible if i == 0 else _helmet.visible)
	for piece: StringName in _gear_parts:
		_gear_parts[piece].visible = gear.has(piece)


## Sets the bones from pelvis to upper chest, spreading the turn and lean between the two
## frames along the spine.
func _turn_spine(basis_for: Dictionary[int, Basis], pelvis: Basis, chest: Basis) -> void:
	var pelvis_q := pelvis.get_rotation_quaternion()
	var chest_q := chest.get_rotation_quaternion()
	_turn(basis_for, &"Hips", pelvis)
	_turn(basis_for, &"Spine", Basis(pelvis_q.slerp(chest_q, 0.34)))
	_turn(basis_for, &"Chest", Basis(pelvis_q.slerp(chest_q, 0.67)))
	_turn(basis_for, &"UpperChest", chest)


## Writes bone poses to the skeleton from global transforms, and records where the model's
## hands really are so the ball and bat sit in them.
func _pose_bones(globals: Array[Transform3D]) -> void:
	for i: int in _rest.size():
		var parent_global := Transform3D.IDENTITY if _parent[i] < 0 else globals[_parent[i]]
		var local := parent_global.affine_inverse() * globals[i]
		_skeleton.set_bone_pose_position(i, local.origin)
		_skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
	for side: String in JointClip.SIDES:
		var hand := StringName(side + "Hand")
		var index := _bone[hand]
		var middle: int = _bone.get(StringName(side + "MiddleProximal"), index)
		joints[hand] = _to_puppet * globals[index].origin.lerp(globals[middle].origin, 0.7)
		var turn := _to_puppet.basis.orthonormalized() * (globals[index].basis * _rest[index].basis.inverse())
		var fingers := (turn * _hand_rest[side]).normalized()
		var palm := _square_to(turn * _palm_rest[side], fingers)
		_hand_frame[side] = Transform3D(Basis(fingers.cross(palm), fingers, palm), _to_puppet * globals[middle].origin)


## A recorded point moved to where it belongs for this model: scaled about the origin on the
## ground, with the standing ankle height of the recording mapped to the model's.
func _fit(point: Vector3, source: JointClip, scale_by: float) -> Vector3:
	return Vector3(point.x * scale_by, (point.y - source.ankle_height) * scale_by + _ankle_height, point.z * scale_by)


## Works out the joints of one arm or leg: from the model's own shoulder or hip to a target
## for the wrist or ankle, bending toward the recorded elbow or knee.
##
## A nearly straight limb is a bad case for IK: a few millimetres in the target swing the bend
## by many degrees, and recordings are not that exact. So when the target is near full stretch
## and the recorded limb is nearly straight too, the bend is taken from the recording, and the
## end lands where that bend puts it, which is within a centimetre or so of the target.
func _fit_limb(frame: Dictionary[StringName, Vector3], side: String, parts: Array[String], root: Vector3, target: Vector3, l1: float, l2: float) -> void:
	var names: Array[StringName] = [StringName(side + parts[0]), StringName(side + parts[1]), StringName(side + parts[2])]
	var upper := frame[names[1]] - frame[names[0]]
	var lower := frame[names[2]] - frame[names[1]]
	var reach := l1 + l2
	var to := target - root
	var distance := maxf(to.length(), 1e-4)
	# Cosine of the recorded bend: 1 is a straight limb.
	var straightness := upper.normalized().dot(lower.normalized())
	var same_bend := sqrt(maxf(l1 * l1 + l2 * l2 + 2.0 * l1 * l2 * straightness, 0.0))
	var weight := smoothstep(0.9, 0.985, distance / reach) * smoothstep(0.82, 0.95, straightness)
	var tip := root + to / distance * lerpf(minf(distance, reach * 0.9995), same_bend, weight)
	joints[names[0]] = root
	joints[names[1]] = _two_bone(root, tip, l1, l2, upper)
	joints[names[2]] = tip


## Orientation of the pelvis or ribcage from its side-to-side and upward directions, tipped
## back by `upright` radians.
static func _body_frame(right: Vector3, up: Vector3, upright: float) -> Basis:
	var x := right.normalized()
	var z := x.cross(up)
	if z.length() < 1e-5:
		return Basis.IDENTITY
	z = z.normalized()
	return Basis(x, upright) * Basis(x, z.cross(x), z)


## Rotation taking a rest direction and a rest axis square to it onto a direction and axis.
static func _align(dir: Vector3, axis: Vector3, rest_dir: Vector3, rest_axis: Vector3) -> Basis:
	return Basis(dir, axis, dir.cross(axis)) * Basis(rest_dir, rest_axis, rest_dir.cross(rest_axis)).inverse()


static func _square_to(v: Vector3, dir: Vector3) -> Vector3:
	return (v - dir * v.dot(dir)).normalized()


## Orients the two bones of an arm or leg whose joints are in `joints`. Both bones point along
## the limb and share the hinge axis of the elbow or knee, so the joint bends like a hinge and
## the twist of the upper bone comes from the plane the limb lies in. When the limb is nearly
## straight that plane is not defined and the twist carries over from the last frame.
func _orient_limb(basis_for: Dictionary[int, Basis], upper: StringName, lower: StringName, tip: StringName, parent_turn: Basis, is_leg: bool) -> void:
	var to_skeleton := _to_skeleton.basis
	var d1 := (to_skeleton * (joints[lower] - joints[upper])).normalized()
	var d2 := (to_skeleton * (joints[tip] - joints[lower])).normalized()
	var bend := d1.cross(d2)
	var hinge := parent_turn * _hinge_rest[upper]
	if _hinge_last.has(upper):
		hinge = Quaternion(_dir_last[upper], d1) * _hinge_last[upper]
	hinge = _square_to(hinge, d1)
	var weight := smoothstep(0.1, 0.35, bend.length())
	if weight > 0.0:
		# Turn the carried-over axis about the bone toward the one the bend shows.
		var shown := bend.normalized()
		var angle := hinge.signed_angle_to(shown, d1)
		# A knee does not bend backward: a leg that seems to is straight, and tells nothing.
		if is_leg and absf(angle) > PI * 0.5:
			angle = 0.0
		hinge = _square_to(hinge.rotated(d1, angle * weight), d1)
	_hinge_last[upper] = hinge
	_dir_last[upper] = d1
	basis_for[_bone[upper]] = _align(d1, hinge, _aim_rest[upper], _hinge_rest[upper]) * _rest[_bone[upper]].basis
	basis_for[_bone[lower]] = _align(d2, _square_to(hinge, d2), _aim_rest[lower], _hinge_rest[lower]) * _rest[_bone[lower]].basis


## Points a hand the way the recorded hand points. A hand on the bat is turned so that the
## handle lies across the palm, from the little finger toward the index finger.
func _orient_hand(basis_for: Dictionary[int, Basis], side: String, frame: Dictionary[StringName, Vector3], bat: Vector3) -> void:
	var lower := _bone[StringName(side + "LowerArm")]
	var hand := _bone[StringName(side + "Hand")]
	var forearm_turn := basis_for[lower] * _rest[lower].basis.inverse()
	var straight := forearm_turn * _hand_rest[side]
	var want := straight
	var tip := StringName(side + "HandTip")
	if frame.has(tip):
		var recorded := _to_skeleton.basis * (frame[tip] - frame[StringName(side + "Hand")])
		if recorded.length() > 1e-4:
			# A wrist bends about 70 degrees at most; recordings are noisy at speed.
			var turn := Quaternion(straight, recorded.normalized())
			var limit := deg_to_rad(65.0)
			if turn.get_angle() > limit:
				turn = Quaternion.IDENTITY.slerp(turn, limit / turn.get_angle())
			want = turn * straight
	var grip: Grip = left_grip if side == "Left" else right_grip
	if grip == Grip.BAT and bat.length() > 0.5:
		var along := (_to_skeleton.basis * bat).normalized()
		var across := want - along * want.dot(along)
		if across.length() > 0.05:
			var rest_across := _square_to(_hand_rest[side], _grip_rest[side])
			basis_for[hand] = _align(along, across.normalized(), _grip_rest[side], rest_across) * _rest[hand].basis
			return
	var turned := Basis(Quaternion(straight, want)) * forearm_turn
	# The recording does not say how the forearm is rolled. A free hand moving fast leads with
	# its palm: the throwing hand is behind the ball as it comes forward, not beside it.
	var wrist := joints[StringName(side + "Hand")]
	if _wrist_last.has(side) and frame_time > 0.0:
		var moved := wrist - _wrist_last[side]
		var weight := smoothstep(1.5, 6.0, moved.length() / frame_time)
		var push := _to_skeleton.basis * moved
		push -= want * push.dot(want)
		if weight > 0.0 and push.length() > 1e-6:
			var palm := _square_to(turned * _palm_rest[side], want)
			var roll := clampf(palm.signed_angle_to(push.normalized(), want), -1.9, 1.9)
			turned = Basis(want, roll * weight) * turned
	_wrist_last[side] = wrist
	basis_for[hand] = turned * _rest[hand].basis


## A foot near the ground lies flat, pointing where the knee points; a lifted foot follows
## the shin.
func _orient_foot(basis_for: Dictionary[int, Basis], side: String, lift: float) -> void:
	var lower := _bone[StringName(side + "LowerLeg")]
	var foot := _bone[StringName(side + "Foot")]
	var shin_turn := basis_for[lower] * _rest[lower].basis.inverse()
	var follow := shin_turn * _rest[foot].basis
	var toes := _to_puppet.basis * (shin_turn * _toe_rest[side])
	var level := Vector2(toes.x, toes.z)
	var steep := 1.0 - smoothstep(0.15, 0.7, level.length() / toes.length())
	if steep >= 1.0:
		basis_for[foot] = follow
		return
	var flat := _to_skeleton.basis * Basis(Vector3.UP, atan2(-level.x, -level.y)) * _to_puppet.basis * _rest[foot].basis
	# The more the heel is lifted, or the more the shin is laid over, the less the foot is flat.
	var weight := maxf(smoothstep(0.03, 0.12, lift), steep)
	basis_for[foot] = Basis(flat.get_rotation_quaternion().slerp(follow.get_rotation_quaternion(), weight))


## Turns the head toward look_target, keeping it fairly level however the trunk is tilted,
## within what a neck can do. The neck takes half of the turn.
func _face_target(basis_for: Dictionary[int, Basis], head_at: Vector3, chest: Basis) -> void:
	if not has_look_target or look_target.distance_to(head_at) < 0.05:
		return
	var z := (head_at - look_target).normalized()
	var x := Vector3.UP.lerp(chest.y, 0.35).cross(z)
	if x.length() < 1e-3:
		return
	x = x.normalized()
	var turn := (chest.inverse() * Basis(x, z.cross(x), z)).get_rotation_quaternion()
	var limit := deg_to_rad(75.0)
	if turn.get_angle() > limit:
		turn = Quaternion.IDENTITY.slerp(turn, limit / turn.get_angle())
	_turn(basis_for, &"Head", chest * Basis(turn))
	_turn(basis_for, &"Neck", chest * Basis(Quaternion.IDENTITY.slerp(turn, 0.5)))


## Global transform of every bone (skeleton space) for the given target orientations,
## walking parent-first. Bones without a target keep their rest pose relative to the parent.
## With trunk_only the bones below the shoulders and hips are left out: the first pass only
## needs to know where those joints and the head are.
func _walk(basis_for: Dictionary[int, Basis], curl: Dictionary[int, Basis], hips_at: Vector3, trunk_only: bool = false) -> Array[Transform3D]:
	var globals: Array[Transform3D] = []
	globals.resize(_rest.size())
	var hips := _bone[&"Hips"]
	for i: int in _rest.size():
		if trunk_only and _is_limb[i] == 1:
			continue
		var parent_global := Transform3D.IDENTITY if _parent[i] < 0 else globals[_parent[i]]
		var g := parent_global * _local_rest[i]
		if basis_for.has(i):
			g.basis = basis_for[i]
		elif curl.has(i):
			# A curl is the bone's orientation relative to its parent; carry it along with
			# however the parent has moved.
			g.basis = parent_global.basis * curl[i]
		if i == hips:
			g.origin = _to_skeleton * hips_at + g.basis * (_rest[i].basis.inverse() * _hips_offset)
		globals[i] = g
	return globals


## Turns the head (and half as much the neck) toward look_target, within what a neck can do.
func _aim_head(basis_for: Dictionary[int, Basis], head_at: Vector3) -> void:
	var to_target := chest_basis.inverse() * (look_target - head_at)
	if to_target.length() < 0.05:
		return
	var yaw := clampf(atan2(to_target.x, -to_target.z), deg_to_rad(-85.0), deg_to_rad(85.0))
	var pitch := clampf(atan2(to_target.y, Vector2(to_target.x, to_target.z).length()), deg_to_rad(-35.0), deg_to_rad(30.0))
	_turn(basis_for, &"Head", chest_basis * Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, pitch))
	_turn(basis_for, &"Neck", chest_basis * Basis(Vector3.UP, -yaw * 0.5) * Basis(Vector3.RIGHT, pitch * 0.5))


## Orientations of the finger bones relative to their parents that close the fingers for the
## current grips. Worked out again only when a grip changes.
func _finger_curls() -> Dictionary[int, Basis]:
	var grips := int(left_grip) * 16 + int(right_grip)
	if grips == _curls_for:
		return _curls
	_curls_for = grips
	var out: Dictionary[int, Basis] = {}
	for side: String in ["Left", "Right"]:
		var grip: Grip = left_grip if side == "Left" else right_grip
		var degrees: Array = CURL[grip]
		for finger: String in FINGERS:
			var tucked := grip == Grip.BALL and (finger == "Ring" or finger == "Little")
			var parts: Array[String] = ["Proximal", "Intermediate", "Distal"]
			for part: int in parts.size():
				_add_curl(out, StringName(side + finger + parts[part]), BALL_TUCK[part] if tucked else float(degrees[part]))
		for part: String in ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal"]:
			_add_curl(out, StringName(side + part), degrees[3])
	_curls = out
	return out


func _add_curl(out: Dictionary[int, Basis], bone: StringName, degrees: float) -> void:
	if not _bone.has(bone):
		return
	var index := _bone[bone]
	if _curl_axis.has(index):
		# Stored relative to the parent bone, ready to be carried along by it.
		out[index] = _rest[_parent[index]].basis.inverse() * Basis(_curl_axis[index], deg_to_rad(degrees)) * _rest[index].basis


## Finds, for each finger bone, the axis it bends about. The resting hand is slightly curled,
## which shows which way the palm faces.
func _measure_fingers() -> void:
	for side: String in ["Left", "Right"]:
		var hand := _origin(StringName(side + "Hand"))
		var palm := Vector3.ZERO
		for finger: String in FINGERS:
			var a := _origin(StringName(side + finger + "Proximal"))
			var b := _origin(StringName(side + finger + "Intermediate"))
			var c := _origin(StringName(side + finger + "Distal"))
			var first := (b - a).normalized()
			var bend := (c - b).normalized() - first
			palm += bend - first * bend.dot(first)
		if palm.length() < 0.02:
			var across := _origin(StringName(side + "IndexProximal")) - _origin(StringName(side + "LittleProximal"))
			palm = across.cross(_origin(StringName(side + "MiddleProximal")) - hand) * (1.0 if side == "Left" else -1.0)
		palm = palm.normalized()
		_palm_rest[side] = palm
		for finger: String in FINGERS:
			var chain: Array[StringName] = [StringName(side + finger + "Proximal"), StringName(side + finger + "Intermediate"), StringName(side + finger + "Distal")]
			for i: int in chain.size():
				var from := _origin(chain[mini(i, 1)])
				var to := _origin(chain[mini(i, 1) + 1])
				_curl_axis[_bone[chain[i]]] = (to - from).normalized().cross(palm).normalized()
		# The thumb closes across the palm, toward the base of the index finger.
		var thumb: Array[StringName] = [StringName(side + "ThumbMetacarpal"), StringName(side + "ThumbProximal"), StringName(side + "ThumbDistal")]
		var toward := _origin(StringName(side + "IndexProximal")) - _origin(thumb[1])
		for i: int in thumb.size():
			var from := _origin(thumb[mini(i, 1)])
			var to := _origin(thumb[mini(i, 1) + 1])
			var along := (to - from).normalized()
			_curl_axis[_bone[thumb[i]]] = along.cross((toward - along * toward.dot(along)).normalized() + palm * 0.6).normalized()


## Sets a bone's target orientation: its rest orientation carried along by a rotation of the
## body given in puppet space.
func _turn(basis_for: Dictionary[int, Basis], bone: StringName, body_rotation: Basis) -> void:
	var index := _bone[bone]
	basis_for[index] = _to_skeleton.basis * body_rotation * _to_puppet.basis * _rest[index].basis


func _measure() -> void:
	var count := _skeleton.get_bone_count()
	_rest.resize(count)
	_local_rest.resize(count)
	_parent.resize(count)
	for i: int in count:
		_bone[StringName(_skeleton.get_bone_name(i))] = i
		_rest[i] = _skeleton.get_bone_global_rest(i)
		_local_rest[i] = _skeleton.get_bone_rest(i)
		_parent[i] = _skeleton.get_bone_parent(i)
	for pair: Array in LIMBS:
		var from: StringName = pair[0]
		var to: StringName = pair[1]
		_aim_rest[from] = (_origin(to) - _origin(from)).normalized()
	# Everything below an upper arm or an upper leg.
	_is_limb.resize(count)
	for i: int in count:
		var above := _parent[i]
		_is_limb[i] = 0
		while above >= 0:
			var name := _skeleton.get_bone_name(above)
			if name.ends_with("UpperArm") or name.ends_with("UpperLeg"):
				_is_limb[i] = 1
				break
			above = _parent[above]

	# Lengths are measured on the skeleton and used in the puppet's space, where the model
	# has been scaled to the player's height.
	var size := _to_puppet.basis.get_scale().x
	upper_arm = _origin(&"LeftUpperArm").distance_to(_origin(&"LeftLowerArm")) * size
	lower_arm = _origin(&"LeftLowerArm").distance_to(_origin(&"LeftHand")) * size
	upper_leg = _origin(&"LeftUpperLeg").distance_to(_origin(&"LeftLowerLeg")) * size
	lower_leg = _origin(&"LeftLowerLeg").distance_to(_origin(&"LeftFoot")) * size
	shoulder_half = absf(_origin(&"LeftUpperArm").x - _origin(&"RightUpperArm").x) * 0.5 * size
	hip_half = absf(_origin(&"LeftUpperLeg").x - _origin(&"RightUpperLeg").x) * 0.5 * size
	var hip_mid := _origin(&"LeftUpperLeg").lerp(_origin(&"RightUpperLeg"), 0.5)
	var shoulder_mid := _origin(&"LeftUpperArm").lerp(_origin(&"RightUpperArm"), 0.5)
	spine = shoulder_mid.distance_to(hip_mid) * size + shoulder_drop
	_hips_offset = _origin(&"Hips") - hip_mid
	_ankle_height = (_to_puppet * _origin(&"LeftFoot")).y

	# The model rests with elbows and knees slightly bent, which shows the axis each bends about.
	for side: String in JointClip.SIDES:
		for limb: Array in [["UpperArm", "LowerArm", "Hand"], ["UpperLeg", "LowerLeg", "Foot"]]:
			var upper := StringName(side + str(limb[0]))
			var lower := StringName(side + str(limb[1]))
			var d1 := _aim_rest[upper]
			var d2 := _aim_rest[lower]
			var axis := d1.cross(d2)
			if axis.length() < 0.05:
				axis = Vector3.RIGHT if limb[0] == "UpperLeg" else d1.cross(Vector3.BACK)
			_hinge_rest[upper] = _square_to(axis, d1)
			_hinge_rest[lower] = _square_to(axis, d2)
		var wrist := _origin(StringName(side + "Hand"))
		_hand_rest[side] = (_origin(StringName(side + "MiddleProximal")) - wrist).normalized()
		_grip_rest[side] = (_origin(StringName(side + "IndexProximal")) - _origin(StringName(side + "LittleProximal"))).normalized()
		var toes := _origin(StringName(side + "Toes")) - _origin(StringName(side + "Foot"))
		_toe_rest[side] = Vector3(toes.x, 0.0, toes.z).normalized()


func _origin(bone: StringName) -> Vector3:
	return _rest[_bone[bone]].origin


static var _shared_grain: NoiseTexture2D


static func _grain() -> NoiseTexture2D:
	if _shared_grain == null:
		_shared_grain = GreyboxField.grain_texture(true)
	return _shared_grain


func _paint() -> void:
	var plain := {
		"Socks": uniform.socks, "Cap": uniform.cap, "Helmet": uniform.cap, "Collar": uniform.trim,
		"Gear": uniform.cap.darkened(0.25), "Bars": Color(0.09, 0.09, 0.1),
		"Shoes": Color(0.06, 0.06, 0.07), "Belt": Color(0.05, 0.05, 0.06),
	}
	for part: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for surface: int in part.mesh.get_surface_count():
			var original := part.mesh.surface_get_material(surface)
			var source := original.resource_name
			if source == "Jersey" or source == "Pants":
				part.set_surface_override_material(surface, _garment_material(part, source == "Jersey"))
			elif source == "Hands":
				part.set_surface_override_material(surface, _glove_material() if gloves else _skin(original))
			elif source == "Skin":
				part.set_surface_override_material(surface, _skin(original))
			elif part.name == &"Eyes":
				part.set_surface_override_material(surface, _eyes(original))
			elif String(part.name).begins_with("Hair"):
				part.visible = String(part.name) == "Hair%d" % hair
				part.set_surface_override_material(surface, _hair_material(original))
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif part.name == &"Eyebrows" or part.name == &"Eyelashes":
				part.set_surface_override_material(surface, _solid(original, true))
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif plain.has(source):
				part.set_surface_override_material(surface, _plain_material(source, plain[source]))


static var _solid_copies: Dictionary[int, StandardMaterial3D] = {}
static var _skin_copies: Dictionary[int, StandardMaterial3D] = {}
static var _pores: NoiseTexture2D
static var _sheen: NoiseTexture2D


## Skin (docs/13 S11-3): light scattering under the surface (warm, soft shading where light
## turns to shadow), a roughness that varies over the face (some places shine, others are
## matte), and fine pore detail.
static func _skin(original: Material) -> Material:
	var base := _solid(original, false) as StandardMaterial3D
	if base == null:
		return original
	var key := base.get_instance_id()
	if _skin_copies.has(key):
		return _skin_copies[key]
	var m := base.duplicate() as StandardMaterial3D
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.35
	m.subsurf_scatter_skin_mode = true
	m.roughness = 0.62
	m.roughness_texture = _skin_sheen()
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	# Pores: far too fine to see as a pattern at playing distance, they only break up the
	# highlights a little.
	m.normal_enabled = true
	m.normal_texture = _skin_pores()
	m.normal_scale = 0.06
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 240.0
	m.metallic_specular = 0.45
	_skin_copies[key] = m
	return m


static func _skin_pores() -> NoiseTexture2D:
	if _pores == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.35
		noise.fractal_octaves = 2
		_pores = NoiseTexture2D.new()
		_pores.width = 256
		_pores.height = 256
		_pores.seamless = true
		_pores.as_normal_map = true
		_pores.bump_strength = 2.0
		_pores.noise = noise
	return _pores


## Broad patches from shiny (dark in the texture: low roughness) to matte.
static func _skin_sheen() -> NoiseTexture2D:
	if _sheen == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.02
		_sheen = NoiseTexture2D.new()
		_sheen.width = 128
		_sheen.height = 128
		_sheen.seamless = true
		_sheen.noise = noise
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.45, 0.45, 0.45))
		ramp.set_color(1, Color(0.8, 0.8, 0.8))
		_sheen.color_ramp = ramp
	return _sheen


## The team letter on the front of the cap and the helmet: a small label riding on the head
## bone, placed at the front of each in the model's rest pose.
func set_logo(letter: String, colour: Color) -> void:
	logo = letter
	if _logos.is_empty() and letter != "":
		for gear: MeshInstance3D in [_cap, _helmet]:
			var box := gear.get_aabb()
			var front := Vector3(box.get_center().x, box.position.y + box.size.y * (0.62 if gear == _cap else 0.58), box.end.z + 0.002)
			var attach := BoneAttachment3D.new()
			attach.bone_name = "Head"
			_skeleton.add_child(attach)
			var label := Label3D.new()
			label.pixel_size = 0.0009
			label.font = UiTheme.font(700)
			label.font_size = 64
			label.outline_size = 0
			label.double_sided = false
			var rest := _skeleton.get_bone_global_rest(_bone[&"Head"])
			label.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY, front)
			attach.add_child(label)
			_logos.append(label)
	for label: Label3D in _logos:
		label.text = letter
		label.modulate = colour
	_show_gear()


## Hair (docs/13 S11-4): the style's strand texture as a cut-out, tinted to the player's colour.
func _hair_material(original: Material) -> Material:
	var base := _solid(original, true) as StandardMaterial3D
	if base == null:
		return original
	var m := base.duplicate() as StandardMaterial3D
	m.albedo_color = hair_color * 2.2
	m.roughness = 0.55
	m.alpha_scissor_threshold = 0.4
	return m


## A player's hair: style 1 to 4 and colour.
func set_hair(style: int, colour: Color) -> void:
	if style == hair and colour == hair_color:
		return
	hair = style
	hair_color = colour
	repaint()


## Eyes: a wet, glossy surface, so the sky shows as a highlight on the cornea.
static func _eyes(original: Material) -> Material:
	var base := _solid(original, false) as StandardMaterial3D
	if base == null:
		return original
	var m := base.duplicate() as StandardMaterial3D
	m.roughness = 0.05
	m.metallic_specular = 0.9
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.02
	return m


## The model's own materials arrive marked see-through, which draws skin with speckled edges
## and dark patches where brows and lashes lie over it. Skin and eyes are made solid; brows
## and lashes become cut-outs.
static func _solid(original: Material, cutout: bool) -> Material:
	var base := original as StandardMaterial3D
	if base == null:
		return original
	var key := base.get_instance_id() * 2 + int(cutout)
	if not _solid_copies.has(key):
		var copy := base.duplicate() as StandardMaterial3D
		copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if cutout else BaseMaterial3D.TRANSPARENCY_DISABLED
		copy.alpha_scissor_threshold = 0.35
		copy.cull_mode = BaseMaterial3D.CULL_DISABLED if cutout else BaseMaterial3D.CULL_BACK
		_solid_copies[key] = copy
	return _solid_copies[key]


func _plain_material(source: String, colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = {"Helmet": 0.2, "Shoes": 0.45, "Belt": 0.4, "Gear": 0.6, "Bars": 0.35}.get(source, 0.85)
	if source != "Shoes" and source != "Socks":
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if source == "Bars":
		material.metallic = 0.7
	if source == "Helmet":
		material.clearcoat_enabled = true
		material.clearcoat = 0.7
	else:
		material.normal_enabled = true
		material.normal_texture = _grain()
		material.normal_scale = 0.5
		material.uv1_triplanar = true
		material.uv1_scale = Vector3.ONE * 13.0
	return material


func _glove_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.07, 0.07, 0.08)
	material.roughness = 0.55
	material.normal_enabled = true
	material.normal_texture = _grain()
	material.normal_scale = 0.6
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * 30.0
	return material


## Cloth material whose colour comes from a texture painted for this player: the texture is
## drawn once in an off-screen viewport sized to the garment so lettering is not stretched.
func _garment_material(part: MeshInstance3D, is_jersey: bool) -> StandardMaterial3D:
	var bounds := part.mesh.get_aabb().size
	var half_size := Vector2(bounds.x, bounds.y)
	var pixels_per_metre := 1000.0 if is_jersey else 520.0
	var old := part.get_node_or_null("Art")
	if old != null:
		old.free()
	var viewport := SubViewport.new()
	viewport.name = "Art"
	viewport.size = Vector2i(roundi(half_size.x * pixels_per_metre) * 2, roundi(half_size.y * pixels_per_metre))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.disable_3d = true
	var art := UniformArt.new()
	art.garment = UniformArt.Garment.JERSEY if is_jersey else UniformArt.Garment.PANTS
	art.style = uniform
	art.half_size = half_size
	art.font = _lettering_font()
	art.size = Vector2(viewport.size)
	viewport.add_child(art)
	part.add_child(viewport)

	var material := StandardMaterial3D.new()
	material.albedo_texture = viewport.get_texture()
	material.roughness = 0.88
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static var _font: SystemFont


static func _lettering_font() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Pretendard", "Noto Sans KR", "Noto Sans CJK KR", "Malgun Gothic", "NanumGothic"])
		_font.font_weight = 900
	return _font
