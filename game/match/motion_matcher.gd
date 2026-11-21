class_name MotionMatcher
extends RefCounted
## Motion matching for fielders and runners on the move (docs/13 S12, approved proposal 4):
## a database of recorded locomotion (the CMU runs, jogs, turns and stops, converted by
## tools/mocap/convert_bvh.py into content-local/animations/cmu) in which, every
## SEARCH_EVERY seconds, the frame is found whose motion best matches where the player is
## going — his speed now and where he will be in 0.2 s and 0.4 s, by his own heading — and
## whose feet are where his feet are now. That frame plays on until the next search, and a
## change of frame is blended in over BLEND seconds. The play's timeline knows where each
## player will be, so the future part of the match is exact.
##
## Each recorded frame is turned so the body faces -Z: the figure's heading is the puppet's
## own rotation, which follows his path; the recording supplies the steps, lean and arms.

const DIR := "animations/cmu"
## Recordings that are not locomotion (throws, long mixed takes) are left out.
const SKIP: Array[String] = ["124_12", "33_01", "09_12"]
const SAMPLE_FPS := 30.0
const SEARCH_EVERY := 0.12
const BLEND := 0.15
## Feature weights: speed now, where he will be, where his feet are.
const W_VEL := 1.0
const W_FUTURE := 1.4
const W_FEET := 0.6
## Playback runs faster than recorded for a man going faster than the recording, within
## these bounds.
const RATE := Vector2(0.6, 2.2)
const FEATURES := 10

static var _shared: MotionMatcher
static var _tried := false

var clips: Array[JointClip] = []
## Per database entry: the clip, its time, and the speed (m/s) it was recorded at.
var entry_clip := PackedInt32Array()
var entry_time := PackedFloat32Array()
var entry_speed := PackedFloat32Array()
var features := PackedFloat32Array()


## The shared database, or null when the local content pack has no recordings.
static func shared() -> MotionMatcher:
	if not _tried:
		_tried = true
		var m := MotionMatcher.new()
		if m._load():
			_shared = m
	return _shared


func size() -> int:
	return entry_clip.size()


func _load() -> bool:
	var dir := MotionLibrary.pack_root().path_join(DIR)
	if not DirAccess.dir_exists_absolute(dir):
		return false
	var files := DirAccess.get_files_at(dir)
	for file: String in files:
		if not file.ends_with(".json") or SKIP.has(file.get_basename()):
			continue
		var clip := JointClip.load_file(dir.path_join(file))
		if clip == null or not clip.joint_names.has(&"Root"):
			continue
		var upright := _upright(clip)
		if sound(upright):
			clips.append(upright)
	for c: int in clips.size():
		var clip := clips[c]
		var t := 0.0
		while t <= clip.duration - 0.45:
			var f := _clip_features(clip, t)
			entry_clip.append(c)
			entry_time.append(t)
			entry_speed.append(Vector2(f[0], f[1]).length())
			features.append_array(f)
			t += 1.0 / SAMPLE_FPS
	return size() > 0


## A recording fit to use: the hips at a standing man's height through it (mostly) and the
## feet never above the knees. (One CMU take comes out floating two metres up.)
static func sound(clip: JointClip) -> bool:
	var heights := PackedFloat32Array()
	var t := 0.0
	while t <= clip.duration:
		var f := clip.sample(t)
		heights.append(f[&"LeftUpperLeg"].lerp(f[&"RightUpperLeg"], 0.5).y)
		if maxf(f[&"LeftFoot"].y, f[&"RightFoot"].y) > 0.9:
			return false
		t += 0.1
	heights.sort()
	var middle := heights[heights.size() / 2]
	return middle > 0.75 and middle < 1.15


## The clip with every frame turned to face -Z about its hips, and its Root track turned the
## same way frame by frame (so Root differences are travel in the body's own heading).
static func _upright(clip: JointClip) -> JointClip:
	var frames: Array[Dictionary] = []
	var n := clip.frame_count()
	var heading_root := Vector3.ZERO
	var last_root := Vector3.ZERO
	for i: int in n:
		var f := clip.sample(float(i) / clip.fps)
		var across := f[&"RightUpperLeg"] - f[&"LeftUpperLeg"]
		var yaw := atan2(-across.z, across.x)
		var hips := f[&"LeftUpperLeg"].lerp(f[&"RightUpperLeg"], 0.5)
		var turn := Basis(Vector3.UP, -yaw)
		var out: Dictionary[StringName, Vector3] = {}
		for joint: StringName in f:
			if joint == &"Root":
				continue
			var rel := f[joint] - Vector3(hips.x, 0.0, hips.z)
			out[joint] = turn * rel
		# Travel since the last frame, in this frame's heading, added up.
		var root := f[&"Root"]
		if i > 0:
			heading_root += turn * (root - last_root)
		last_root = root
		out[&"Root"] = heading_root
		frames.append(out)
	var upright := JointClip.from_frames(frames, clip.fps)
	upright.source = clip.source
	upright.ankle_height = clip.ankle_height
	return upright


## Features of a recorded moment: velocity now (x, z), where it will be in 0.2 s and 0.4 s
## (x, z each), and the feet relative to the hips (x, z each); all in the body's heading.
static func _clip_features(clip: JointClip, t: float) -> PackedFloat32Array:
	var now := clip.sample(t)
	var soon := clip.sample(t + 0.2)
	var later := clip.sample(t + 0.4)
	var before := clip.sample(maxf(t - 0.05, 0.0))
	var after := clip.sample(t + 0.05)
	var dt := (minf(t + 0.05, clip.duration) - maxf(t - 0.05, 0.0))
	var v := (after[&"Root"] - before[&"Root"]) / maxf(dt, 1e-3)
	var p1 := soon[&"Root"] - now[&"Root"]
	var p2 := later[&"Root"] - now[&"Root"]
	var lf := now[&"LeftFoot"]
	var rf := now[&"RightFoot"]
	return PackedFloat32Array([v.x, v.z, p1.x, p1.z, p2.x, p2.z, lf.x, lf.z, rf.x, rf.z])


## The best entry for a man moving with velocity `vel` (m/s, in his heading: +X right, -Z
## ahead), to be at `p1` and `p2` (his heading) in 0.2 s and 0.4 s, with his feet at `feet`
## (left x, z, right x, z). Returns the entry index.
func search(vel: Vector2, p1: Vector2, p2: Vector2, feet: PackedFloat32Array) -> int:
	var best := -1
	var best_cost := INF
	var speed := vel.length()
	for e: int in size():
		var o := e * FEATURES
		# Recordings are time-scaled to his speed: compare their shape, not their pace.
		var rate := clampf(speed / maxf(entry_speed[e], 0.3), RATE.x, RATE.y)
		var c := 0.0
		var dv := Vector2(features[o] * rate - vel.x, features[o + 1] * rate - vel.y)
		c += W_VEL * dv.length_squared()
		var d1 := Vector2(features[o + 2] * rate - p1.x, features[o + 3] * rate - p1.y)
		var d2 := Vector2(features[o + 4] * rate - p2.x, features[o + 5] * rate - p2.y)
		c += W_FUTURE * (d1.length_squared() + d2.length_squared() * 0.5)
		if feet.size() == 4:
			var dl := Vector2(features[o + 6] - feet[0], features[o + 7] - feet[1])
			var dr := Vector2(features[o + 8] - feet[2], features[o + 9] - feet[3])
			c += W_FEET * (dl.length_squared() + dr.length_squared())
		if c < best_cost:
			best_cost = c
			best = e
	return best


## One player's playback: which recording, where in it, and the blend from the last one.
class Playback:
	var matcher: MotionMatcher
	var clip := -1
	var time := 0.0
	var rate := 1.0
	var since_search := INF
	var from: Dictionary[StringName, Vector3] = {}
	var blend := 1.0

	func _init(m: MotionMatcher) -> void:
		matcher = m

	## Advances by `delta` and returns the pose for a man moving as given (see search()).
	func step(delta: float, vel: Vector2, p1: Vector2, p2: Vector2) -> Dictionary[StringName, Vector3]:
		var current: Dictionary[StringName, Vector3] = {}
		if clip >= 0:
			time = minf(time + delta * rate, matcher.clips[clip].duration)
			current = matcher.clips[clip].sample(time)
		since_search += delta
		var at_end := clip >= 0 and time >= matcher.clips[clip].duration - 0.05
		if since_search >= SEARCH_EVERY or clip < 0 or at_end:
			since_search = 0.0
			var feet := PackedFloat32Array()
			if not current.is_empty():
				feet = PackedFloat32Array([current[&"LeftFoot"].x, current[&"LeftFoot"].z, current[&"RightFoot"].x, current[&"RightFoot"].z])
			var e := matcher.search(vel, p1, p2, feet)
			if e >= 0:
				var same := matcher.entry_clip[e] == clip and absf(matcher.entry_time[e] - time) < 0.2
				if not same:
					if not current.is_empty():
						from = _show(current)
						blend = 0.0
					clip = matcher.entry_clip[e]
					time = matcher.entry_time[e]
				rate = clampf(vel.length() / maxf(matcher.entry_speed[e], 0.3), RATE.x, RATE.y)
		var pose := _show(matcher.clips[clip].sample(time))
		if blend < 1.0 and not from.is_empty():
			blend = minf(blend + delta / BLEND, 1.0)
			return JointClip.blend(from, pose, smoothstep(0.0, 1.0, blend))
		return pose

	## The frame without its travel track, for the figure.
	static func _show(f: Dictionary[StringName, Vector3]) -> Dictionary[StringName, Vector3]:
		var out := f.duplicate()
		out.erase(&"Root")
		return out
