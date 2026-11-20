class_name BallEvent
extends RefCounted
## Something that happened to the ball during a simulated trajectory.

enum Kind { BOUNCE, WALL, ROLL_START, STOP, OUT_OF_PLAY }

var kind: Kind = Kind.BOUNCE
var time := 0.0
var pos := Vector3.ZERO
var surface: StringName = &""
## Ball speed (m/s) just after the event.
var speed := 0.0


static func make(event_kind: Kind, at_time: float, at: Vector3, surface_name: StringName, ball_speed: float) -> BallEvent:
	var e := BallEvent.new()
	e.kind = event_kind
	e.time = at_time
	e.pos = at
	e.surface = surface_name
	e.speed = ball_speed
	return e
