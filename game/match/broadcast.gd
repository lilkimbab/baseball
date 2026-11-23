class_name Broadcast
extends RefCounted
## The broadcast's own moments between the pitches (docs/11 section 6, docs/13 S16): the
## introduction before the first pitch, the inning's card with the half just over, the batter
## coming up, the pitching change, the replay of a home run. Each is a segment of a few
## seconds with its camera shots and its card; most hold the game while they show, all can be
## skipped (Space, Enter or a click). The match scene asks what to show; this only keeps time.

## BOARD: the park's scoreboard with the player's own man introduced on it (his first at-bat).
## FANS: the batting side's cheering stage and its fans after a home run.
## WALK_OFF: the home side mobbing its hero at the plate; BENCH_CLEAR: both benches out after a
## pitch at a man's head or a beanball (MatchScene's rush of extra figures); INJURY: a hurt man
## helped off by the trainer and a teammate.
enum Kind { PREGAME, HALF, BATTER, PITCHER_CHANGE, REPLAY, GAME_END, BOARD, FANS, WALK_OFF, BENCH_CLEAR, INJURY }

## How long each kind lasts (s).
const LENGTH := {Kind.PREGAME: 21.5, Kind.HALF: 2.6, Kind.BATTER: 2.2, Kind.PITCHER_CHANGE: 2.8, Kind.REPLAY: 4.5, Kind.GAME_END: 3.5, Kind.BOARD: 3.2, Kind.FANS: 2.8, Kind.WALK_OFF: 5.5, Kind.BENCH_CLEAR: 8.5, Kind.INJURY: 12.0}


## A camera shot: from `at` seconds into its segment, moving from (from, to, fov) to (from2,
## to2, fov2) until the next shot (field coordinates).
class Shot:
	var at := 0.0
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var fov := 40.0
	var from2 := Vector3.ZERO
	var to2 := Vector3.ZERO
	var fov2 := 40.0

	static func make(start: float, a: Vector3, b: Vector3, f: float, a2: Vector3 = Vector3.INF, b2: Vector3 = Vector3.INF, f2: float = -1.0) -> Shot:
		var s := Shot.new()
		s.at = start
		s.from = a
		s.to = b
		s.fov = f
		s.from2 = a if a2 == Vector3.INF else a2
		s.to2 = b if b2 == Vector3.INF else b2
		s.fov2 = f if f2 < 0.0 else f2
		return s


class Segment:
	var kind := Kind.HALF
	var duration := 2.0
	## Holds the game while it shows (a batter's card over the player's own at-bat does not).
	var holds := true
	var shots: Array[Shot] = []
	## What its card shows (the HUD reads it).
	var data := {}


var enabled := true
var queue: Array[Segment] = []
var current: Segment
var time := 0.0


func push(seg: Segment) -> void:
	if not enabled:
		return
	queue.append(seg)
	if current == null:
		_next()


static func segment(kind: Kind, data: Dictionary = {}, holds: bool = true) -> Segment:
	var s := Segment.new()
	s.kind = kind
	s.duration = float(LENGTH[kind])
	s.data = data
	s.holds = holds
	return s


func _next() -> void:
	current = queue.pop_front() if not queue.is_empty() else null
	time = 0.0


func step(delta: float) -> void:
	if current == null:
		return
	time += delta
	if time >= current.duration:
		_next()


func skip() -> void:
	if current != null:
		_next()


func skip_all() -> void:
	queue.clear()
	current = null


## Whether the game waits for the broadcast now.
func holding() -> bool:
	return current != null and current.holds


func showing(kind: Kind) -> bool:
	return current != null and current.kind == kind


## The camera now, as [from, to, fov] in field coordinates, or [] when the segment has no
## shot (the game's own camera).
func camera() -> Array:
	if current == null or current.shots.is_empty():
		return []
	var shot := current.shots[0]
	var ends := current.duration
	for i: int in current.shots.size():
		if current.shots[i].at <= time:
			shot = current.shots[i]
			ends = current.shots[i + 1].at if i + 1 < current.shots.size() else current.duration
	var k := smoothstep(shot.at, ends, time)
	return [shot.from.lerp(shot.from2, k), shot.to.lerp(shot.to2, k), lerpf(shot.fov, shot.fov2, k)]


## How far into its segment (0..1), for cards sliding in and out.
func progress() -> float:
	return clampf(time / maxf(current.duration, 0.01), 0.0, 1.0) if current != null else 0.0
