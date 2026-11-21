class_name PitchMotion
extends RefCounted
## Timing of a pitching clip: waiting in the set position, the delivery, the follow-through,
## and the return to the set position for the next pitch.

## The recording stops while the pitcher is still moving; the last part is slowed to a stop.
const TAIL := 0.15
## Seconds the follow-through is held, then seconds taken to get back to the set position.
const HOLD := 0.3
const RECOVER := 0.8
const STRETCH_LEAD := 0.35

var clip: JointClip
## Seconds from the start of the delivery to the release of the ball.
var release_time := 0.0
## Seconds of the recording skipped at the start: none from the windup, the start of the leg
## lift from the set position (docs/13 S10-4).
var offset := 0.0
var _full_release := 0.0


func _init(source: JointClip) -> void:
	clip = source
	_full_release = clip.event(&"release", clip.duration * 0.85)
	release_time = _full_release


## With runners on the pitcher works from the set position: the delivery starts at the leg
## lift (STRETCH_LEAD before the knee is highest), about 1.0 to 1.4 seconds to release (a KBO
## quick motion is 1.2 to 1.5). Without runners he takes the whole delivery.
func use_stretch(stretch: bool) -> void:
	var peak := clip.event(&"knee_peak", -1.0)
	offset = clampf(peak - STRETCH_LEAD, 0.0, maxf(_full_release - 0.6, 0.0)) if stretch and peak > 0.0 else 0.0
	release_time = _full_release - offset


## Seconds after the start of the delivery at which the pitcher is back in the set position.
func length() -> float:
	return clip.duration - offset + TAIL + HOLD + RECOVER


## Joint positions `clock` seconds after the delivery started. Zero or less is the set
## position the pitcher waits in.
func frame(clock: float) -> Dictionary[StringName, Vector3]:
	clock += offset
	if clock <= offset:
		return clip.sample(offset)
	var slow_from := clip.duration - TAIL
	if clock <= slow_from:
		return clip.sample(clock)
	# Decelerate through the last TAIL seconds of the recording over twice that time.
	var u := clampf((clock - slow_from) / (TAIL * 2.0), 0.0, 1.0)
	var finish := clip.sample(slow_from + TAIL * (1.0 - (1.0 - u) * (1.0 - u)))
	var back := (clock - clip.duration - TAIL - HOLD) / RECOVER
	if back <= 0.0:
		return finish
	return JointClip.blend(finish, clip.sample(offset), smoothstep(0.0, 1.0, back))
