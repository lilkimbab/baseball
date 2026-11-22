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
## Tries that did not get the ball (a dive that came up short): whose, and (time, x, y, z) of
## the ball as it went by him.
var miss_keys := PackedStringArray()
var misses := PackedVector4Array()
## Fielders who never had the ball off the bat, however near it went by them (the player's
## own fielder who did not get to it).
var bystanders := PackedStringArray()
## Who first had the ball off the bat and when (the play worked it out; "" when nobody did:
## a home run, or a timeline made by hand).
var fielded_key := ""
var fielded_time := -1.0


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


func add_miss(key: String, time: float, at: Vector3) -> void:
	miss_keys.append(key)
	misses.append(Vector4(time, at.x, at.y, at.z))


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


## `next` taken up at `at` (s) by people who until then were somewhere else (`shown`: key to
## the field position each is at now): each runs from where he is to where `next` has him, at
## `pace` m/s, and follows it from there; one `next` leaves standing stays where he is. The
## ball and the throws are `next`'s own. For a play worked out again part way through (the
## player's own fielding and throws): nobody jumps.
static func stitched(next: PlayTimeline, at: float, shown: Dictionary[String, Vector3], pace: float = 9.5) -> PlayTimeline:
	var out := PlayTimeline.new()
	out.throws = next.throws
	out.miss_keys = next.miss_keys
	out.misses = next.misses
	out.bystanders = next.bystanders
	out.fielded_key = next.fielded_key
	out.fielded_time = next.fielded_time
	for key: String in next.tracks:
		var track := next.tracks[key]
		if key == "ball" or not shown.has(key):
			out.tracks[key] = track
			continue
		var here := shown[key]
		var joined := PackedVector4Array([Vector4(at, here.x, here.y, here.z)])
		var last := track[track.size() - 1]
		if last.x <= at:
			# Nothing more for him to do: he stays (a step or two is not worth a run back).
			if Vector2(last.y - here.x, last.z - here.y).length() > 3.0:
				joined.append(Vector4(at + Vector2(last.y - here.x, last.z - here.y).length() / pace, last.y, last.z, last.w))
			out.tracks[key] = joined
			continue
		# The first moment he can be where `next` has him.
		var meet := at
		var there := next.position(key, meet)
		while meet < at + 4.0 and Vector2(there.x - here.x, there.y - here.y).length() > pace * (meet - at) + 0.05:
			meet += 0.04
			there = next.position(key, meet)
		if meet > at:
			joined.append(Vector4(meet, there.x, there.y, there.z))
		for frame: Vector4 in track:
			if frame.x > meet:
				joined.append(frame)
		out.tracks[key] = joined
	out.duration = next.duration
	return out
