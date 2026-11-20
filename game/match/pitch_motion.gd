class_name PitchMotion
extends RefCounted
## Timing of a pitching clip: waiting in the set position, the delivery, the follow-through,
## and the return to the set position for the next pitch.

## The recording stops while the pitcher is still moving; the last part is slowed to a stop.
const TAIL := 0.15
## Seconds the follow-through is held, then seconds taken to get back to the set position.
const HOLD := 0.3
const RECOVER := 0.8

var clip: JointClip
## Seconds from the start of the delivery to the release of the ball.
var release_time := 0.0


func _init(source: JointClip) -> void:
	clip = source
	release_time = clip.event(&"release", clip.duration * 0.85)


## Seconds after the start of the delivery at which the pitcher is back in the set position.
func length() -> float:
	return clip.duration + TAIL + HOLD + RECOVER


## Joint positions `clock` seconds after the delivery started. Zero or less is the set
## position the pitcher waits in.
func frame(clock: float) -> Dictionary[StringName, Vector3]:
	if clock <= 0.0:
		return clip.sample(0.0)
	var slow_from := clip.duration - TAIL
	if clock <= slow_from:
		return clip.sample(clock)
	# Decelerate through the last TAIL seconds of the recording over twice that time.
	var u := clampf((clock - slow_from) / (TAIL * 2.0), 0.0, 1.0)
	var finish := clip.sample(slow_from + TAIL * (1.0 - (1.0 - u) * (1.0 - u)))
	var back := (clock - clip.duration - TAIL - HOLD) / RECOVER
	if back <= 0.0:
		return finish
	return JointClip.blend(finish, clip.sample(0.0), smoothstep(0.0, 1.0, back))
