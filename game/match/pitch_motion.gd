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
## Longest step (m) the pitcher takes walking back, and how high the stepping foot comes up.
const WALK_STEP := 0.55
const STEP_LIFT := 0.07
## The part of each step's time a foot is in the air; the rest both feet are down.
const STEP_SHARE := 0.85

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
	return walk_back(finish, clip.sample(offset), minf(back, 1.0))


## From the follow-through back to the set position (docs/13 S12-7), `back` from 0 to 1. The
## body goes back at an even pace while the feet take turns, the farther one first: one stays
## planted while the other is picked up and put down nearer the rubber, so neither slides.
static func walk_back(finish: Dictionary[StringName, Vector3], set_frame: Dictionary[StringName, Vector3], back: float) -> Dictionary[StringName, Vector3]:
	var out := JointClip.blend(finish, set_frame, smoothstep(0.0, 1.0, back))
	if not finish.has(&"LeftFoot") or not set_frame.has(&"LeftFoot"):
		return out
	var away: Dictionary[String, float] = {}
	for side: String in JointClip.SIDES:
		var d := set_frame[StringName(side + "Foot")] - finish[StringName(side + "Foot")]
		away[side] = Vector2(d.x, d.z).length()
	var first := "Left" if away["Left"] >= away["Right"] else "Right"
	var steps := clampi(ceili(maxf(away["Left"], away["Right"]) / WALK_STEP) * 2, 2, 6)
	for side: String in JointClip.SIDES:
		var turn := 0 if side == first else 1
		@warning_ignore("integer_division")
		var own := (steps + 1 - turn) / 2
		var done := 0.0
		var lift := 0.0
		for k: int in range(turn, steps, 2):
			# Each step ends a little before the next begins: both feet are down between.
			var u := clampf((back * steps - k) / STEP_SHARE, 0.0, 1.0)
			done += smoothstep(0.0, 1.0, u) / own
			lift = maxf(lift, sin(PI * u))
		var foot := StringName(side + "Foot")
		var at := finish[foot].lerp(set_frame[foot], minf(done, 1.0)) + Vector3.UP * (STEP_LIFT * lift)
		var moved := at - out[foot]
		out[foot] = at
		var knee := StringName(side + "LowerLeg")
		out[knee] += moved * 0.5
	return out
