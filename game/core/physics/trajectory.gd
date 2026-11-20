class_name Trajectory
extends RefCounted
## Sampled path of the ball plus the events along it. Produced by BallFlight.run().

var times: PackedFloat64Array = PackedFloat64Array()
var points: PackedVector3Array = PackedVector3Array()
var events: Array[BallEvent] = []


func duration() -> float:
	return 0.0 if times.is_empty() else times[times.size() - 1]


func end_point() -> Vector3:
	return Vector3.ZERO if points.is_empty() else points[points.size() - 1]


func first_event(kind: BallEvent.Kind) -> BallEvent:
	for e: BallEvent in events:
		if e.kind == kind:
			return e
	return null


func count_events(kind: BallEvent.Kind) -> int:
	var n := 0
	for e: BallEvent in events:
		if e.kind == kind:
			n += 1
	return n


## True if the ball left the field of play in fair territory without touching anything: a home run.
func is_home_run() -> bool:
	if events.is_empty():
		return false
	var first := events[0]
	return first.kind == BallEvent.Kind.OUT_OF_PLAY and Field.is_fair(first.pos)


## Time at which the ball is first at least `distance` metres from home (measured along the
## ground), or -1 if it never gets that far.
func time_at_distance(distance: float) -> float:
	var d2 := distance * distance
	for i: int in points.size():
		var p := points[i]
		if p.x * p.x + p.y * p.y >= d2:
			return times[i]
	return -1.0


## Ball position at a time, linearly interpolated between samples.
func position_at(time: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	if time <= times[0]:
		return points[0]
	var last := times.size() - 1
	if time >= times[last]:
		return points[last]
	var lo := 0
	var hi := last
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if times[mid] <= time:
			lo = mid
		else:
			hi = mid
	var span := times[hi] - times[lo]
	var t := 0.0 if span <= 0.0 else (time - times[lo]) / span
	return points[lo].lerp(points[hi], t)


static func ground_distance(p: Vector3) -> float:
	return sqrt(p.x * p.x + p.y * p.y)
