class_name PlayTimeline
extends RefCounted
## Where everyone and the ball are during a play, as key frames the scene interpolates
## between. Keys: "ball", "F:SS" for fielders by position code, "R:<player id>" for runners.
## Each key frame is (time, x, y, z) in field coordinates.

var tracks: Dictionary[String, PackedVector4Array] = {}
## When the play is over: everyone has stopped and the ball is held.
var duration := 0.0
## Throws, for drawing arcs: (release time, arrival time) per throw, with the two end points.
var throws: Array[PackedVector4Array] = []


func add(key: String, time: float, at: Vector3) -> void:
	if not tracks.has(key):
		tracks[key] = PackedVector4Array()
	var track := tracks[key]
	# Keep frames in time order; a frame at the same time replaces the last one.
	if not track.is_empty() and track[track.size() - 1].x >= time:
		track[track.size() - 1] = Vector4(time, at.x, at.y, at.z)
	else:
		track.append(Vector4(time, at.x, at.y, at.z))
	tracks[key] = track
	duration = maxf(duration, time)


func add_throw(from_time: float, from: Vector3, to_time: float, to: Vector3) -> void:
	throws.append(PackedVector4Array([Vector4(from_time, from.x, from.y, from.z), Vector4(to_time, to.x, to.y, to.z)]))
	duration = maxf(duration, to_time)


func position(key: String, time: float) -> Vector3:
	if not tracks.has(key):
		return Vector3.ZERO
	var track := tracks[key]
	if track.is_empty():
		return Vector3.ZERO
	if time <= track[0].x:
		return Vector3(track[0].y, track[0].z, track[0].w)
	for i: int in range(1, track.size()):
		if time <= track[i].x:
			var a := track[i - 1]
			var b := track[i]
			var f := 0.0 if b.x <= a.x else (time - a.x) / (b.x - a.x)
			return Vector3(lerpf(a.y, b.y, f), lerpf(a.z, b.z, f), lerpf(a.w, b.w, f))
	var last := track[track.size() - 1]
	return Vector3(last.y, last.z, last.w)
