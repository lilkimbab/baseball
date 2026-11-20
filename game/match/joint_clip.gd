class_name JointClip
extends RefCounted
## A recorded motion stored as joint positions per frame, plus named moments such as the
## release of the ball or contact. Positions are in the figure's own space, in metres:
## +X to its right, +Y up, -Z the way it faces at address.
##
## tools/mocap/convert_obp.py writes these as JSON from motion-capture data. A frame is a
## dictionary from joint name to position; Puppet.apply_joints() poses a figure from one.

const SIDES: Array[String] = ["Left", "Right"]

var kind: StringName = &""
## &"R" or &"L": the throwing hand, or the side of the plate the batter stands on.
var side: StringName = &"R"
var source := ""
var fps := 120.0
var duration := 0.0
## Height of the ankle joint of a foot standing flat, as recorded.
var ankle_height := 0.08
var events: Dictionary[StringName, float] = {}
var joint_names: Array[StringName] = []
## Limb lengths of the recorded player: hip to ankle and shoulder to wrist.
var leg_length := 0.9
var arm_length := 0.58

var _frames: Array[PackedFloat32Array] = []


## Reads a clip file. Returns null if there is none or it is not a usable clip.
static func load_file(path: String) -> JointClip:
	if not FileAccess.file_exists(path):
		return null
	return from_dictionary(JsonIO.read_object(path))


static func from_dictionary(data: Dictionary) -> JointClip:
	var clip := JointClip.new()
	clip.kind = StringName(str(data.get("kind", "")))
	clip.side = StringName(str(data.get("side", "R")))
	clip.source = str(data.get("source", ""))
	clip.fps = float(data.get("fps", 120.0))
	clip.ankle_height = float(data.get("ankle_height", 0.08))
	var names: Array = data.get("joints", [])
	for joint: Variant in names:
		clip.joint_names.append(StringName(str(joint)))
	var marks: Dictionary = data.get("events", {})
	for mark: Variant in marks:
		clip.events[StringName(str(mark))] = float(marks[mark])
	var frames: Array = data.get("frames", [])
	for row: Variant in frames:
		var values := PackedFloat32Array(row as Array)
		if values.size() != names.size() * 3:
			push_error("JointClip: a frame of %s has %d values for %d joints" % [clip.source, values.size(), names.size()])
			return null
		clip._frames.append(values)
	if clip._frames.is_empty() or clip.fps <= 0.0:
		return null
	clip.duration = float(clip._frames.size() - 1) / clip.fps
	clip._measure()
	return clip


## Builds a clip from frames given directly (tests, hand-made motions).
static func from_frames(frames: Array[Dictionary], frames_per_second: float, marks: Dictionary[StringName, float] = {}) -> JointClip:
	var clip := JointClip.new()
	clip.fps = frames_per_second
	clip.events = marks
	for joint: StringName in frames[0]:
		clip.joint_names.append(joint)
	for frame: Dictionary in frames:
		var values := PackedFloat32Array()
		for joint: StringName in clip.joint_names:
			var at: Vector3 = frame[joint]
			values.append_array(PackedFloat32Array([at.x, at.y, at.z]))
		clip._frames.append(values)
	clip.duration = float(clip._frames.size() - 1) / clip.fps
	clip._measure()
	return clip


func frame_count() -> int:
	return _frames.size()


## Time of a named moment in seconds from the start of the clip.
func event(mark: StringName, fallback: float = 0.0) -> float:
	return events.get(mark, fallback)


## Joint positions at a time, interpolated between recorded frames. Times outside the clip
## give its first or last frame.
func sample(time: float) -> Dictionary[StringName, Vector3]:
	var at := clampf(time, 0.0, duration) * fps
	var i := mini(int(at), _frames.size() - 1)
	var j := mini(i + 1, _frames.size() - 1)
	var f := at - float(i)
	var a := _frames[i]
	var b := _frames[j]
	var out: Dictionary[StringName, Vector3] = {}
	for k: int in joint_names.size():
		var o := k * 3
		out[joint_names[k]] = Vector3(lerpf(a[o], b[o], f), lerpf(a[o + 1], b[o + 1], f), lerpf(a[o + 2], b[o + 2], f))
	return out


## Mix of two frames. Joint positions are simply interpolated; the figure keeps its own limb
## lengths when it is posed, so a blend between very different poses still holds together.
static func blend(from: Dictionary[StringName, Vector3], to: Dictionary[StringName, Vector3], weight: float) -> Dictionary[StringName, Vector3]:
	var out: Dictionary[StringName, Vector3] = {}
	for joint: StringName in to:
		var a: Vector3 = from.get(joint, to[joint])
		out[joint] = a.lerp(to[joint], weight)
	return out


func _measure() -> void:
	var legs: Array[float] = []
	var arms: Array[float] = []
	@warning_ignore("integer_division")
	var step := maxi(_frames.size() / 40, 1)
	for i: int in range(0, _frames.size(), step):
		var frame := sample(float(i) / fps)
		for prefix: String in SIDES:
			var leg := _chain(frame, prefix, ["UpperLeg", "LowerLeg", "Foot"])
			var arm := _chain(frame, prefix, ["UpperArm", "LowerArm", "Hand"])
			if leg > 0.0:
				legs.append(leg)
			if arm > 0.0:
				arms.append(arm)
	if not legs.is_empty():
		legs.sort()
		leg_length = legs[legs.size() >> 1]
	if not arms.is_empty():
		arms.sort()
		arm_length = arms[arms.size() >> 1]


## Length along a chain of joints, or zero if the frame does not have them all.
static func _chain(frame: Dictionary[StringName, Vector3], prefix: String, parts: Array[String]) -> float:
	var total := 0.0
	for i: int in parts.size() - 1:
		var from := StringName(prefix + parts[i])
		var to := StringName(prefix + parts[i + 1])
		if not frame.has(from) or not frame.has(to):
			return 0.0
		total += frame[from].distance_to(frame[to])
	return total
