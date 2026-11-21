class_name SwingMotion
extends RefCounted
## Plays a batting clip around a pitch: waiting in the stance, the load and stride as the
## pitch comes, the swing timed so that the barrel arrives when the game says it does, the
## finish, and back to the stance.
##
## The clip is one recorded swing with these moments marked: stride (the front foot starts to
## move), launch (the hands start forward), contact, and finish (the bat has come around).

enum Phase { IDLE, LOAD, SWING, FINISH }

## Typical time from release to the plate, used to time the stride before the pitch is thrown.
const NOMINAL_FLIGHT := 0.44
const LOAD_BLEND := 0.25
const RETURN_BLEND := 0.7
const FINISH_HOLD := 0.35
## The waiting motion is the start of the clip played forward and back; it slows to a stop
## over this many seconds at each end so the turn-round is not a jerk.
const IDLE_RAMP := 0.3

var clip: JointClip
## The same batter's swings at a high and a low pitch, if there are any (docs/13 S10-3): the
## swing is blended toward one of them by the height the bat meets the ball.
var high: JointClip
var low: JointClip
var phase: Phase = Phase.IDLE
var stride := 0.0
var launch := 0.0
var contact := 0.0
var finish := 0.0

var _idle_length := 0.0
var _idle_clock := 0.0
## Position in the clip while loading, swinging and finishing.
var _time := 0.0
var _rate := 1.0
var _held := 0.0
var _from: Dictionary[StringName, Vector3] = {}
var _blend := 1.0
var _blend_length := 0.1
## The clip blended toward and how far (0 none, 1 all of it).
var _other: JointClip
var _other_weight := 0.0


func _init(source: JointClip) -> void:
	clip = source
	contact = clip.event(&"contact", clip.duration * 0.8)
	launch = clip.event(&"launch", contact - 0.13)
	stride = clip.event(&"stride", maxf(launch - 0.8, 0.0))
	finish = clip.event(&"finish", clip.duration)
	_idle_length = maxf(stride - 0.05, 0.05)


## Picks the high or low swing for a ball met at `height` metres: none at the main swing's own
## contact height, all of the other at its contact height, in proportion between.
func aim_height(height: float) -> void:
	_other = null
	_other_weight = 0.0
	var own := _contact_height(clip)
	var other := high if height > own else low
	if other == null:
		return
	var there := _contact_height(other)
	if absf(there - own) < 0.03:
		return
	_other = other
	_other_weight = clampf((height - own) / (there - own), 0.0, 1.0)


static func _contact_height(c: JointClip) -> float:
	var t := c.event(&"contact", c.duration * 0.8)
	var pose := c.sample(t)
	return pose[&"BatSweetSpot"].y if pose.has(&"BatSweetSpot") else 0.8


## The other clip's time for a time in the main clip, matching the swing's marked moments.
func _other_time(t: float) -> float:
	var a: Array[float] = [0.0, stride, launch, contact, finish, clip.duration]
	var o := _other
	var oc := o.event(&"contact", o.duration * 0.8)
	var ol := o.event(&"launch", oc - 0.13)
	var b: Array[float] = [0.0, o.event(&"stride", maxf(ol - 0.8, 0.0)), ol, oc, o.event(&"finish", o.duration), o.duration]
	for i: int in range(1, a.size()):
		if t <= a[i] or i == a.size() - 1:
			var span := maxf(a[i] - a[i - 1], 1e-4)
			return lerpf(b[i - 1], b[i], clampf((t - a[i - 1]) / span, 0.0, 1.0))
	return t


## How long before the release the load should start, so that the batter reaches the launch
## position as an ordinary fastball gets close.
func load_lead() -> float:
	return (launch - stride) - (NOMINAL_FLIGHT - (contact - launch))


## Starts the load and stride. The batter then waits in the launch position.
func begin_load() -> void:
	if phase != Phase.IDLE:
		return
	_start_blend(LOAD_BLEND)
	phase = Phase.LOAD
	_time = stride


## Starts the swing so that the barrel reaches contact `seconds` from now.
func begin_swing(seconds: float) -> void:
	if phase == Phase.SWING or phase == Phase.FINISH:
		return
	if phase == Phase.IDLE:
		# No load happened (a quick pitch): go straight to just before the launch.
		_start_blend(0.06)
		_time = maxf(launch - 0.05, stride)
	phase = Phase.SWING
	_rate = (contact - _time) / maxf(seconds, 0.02)


## The pitch is over. A batter who did not swing steps back into the stance; one who did
## finishes the swing first.
func relax() -> void:
	if phase == Phase.LOAD:
		_start_blend(RETURN_BLEND)
		phase = Phase.IDLE


func advance(delta: float) -> void:
	_idle_clock += delta
	if _blend < 1.0:
		_blend = minf(_blend + delta / _blend_length, 1.0)
	match phase:
		Phase.LOAD:
			# Ease into the launch position and wait there.
			_time = minf(_time + delta * clampf((launch - _time) / 0.1, 0.05, 1.0), launch)
		Phase.SWING:
			_time += delta * _rate
			if _time >= contact:
				phase = Phase.FINISH
				_held = 0.0
		Phase.FINISH:
			_rate = move_toward(_rate, 1.0, delta * 6.0)
			_time = minf(_time + delta * _rate, finish)
			if _time >= finish:
				_held += delta
				if _held >= FINISH_HOLD:
					_start_blend(RETURN_BLEND)
					phase = Phase.IDLE


func frame() -> Dictionary[StringName, Vector3]:
	var pose := clip.sample(_idle_time() if phase == Phase.IDLE else _time)
	if _other != null and _other_weight > 0.0 and (phase == Phase.SWING or phase == Phase.FINISH):
		pose = JointClip.blend(pose, _other.sample(_other_time(_time)), _other_weight)
	if _blend < 1.0:
		pose = JointClip.blend(_from, pose, smoothstep(0.0, 1.0, _blend))
	return pose


## How strongly the hands should be drawn toward the point the batter swings at: nothing
## before the launch, full at contact, fading out through the finish.
func reach_weight() -> float:
	match phase:
		Phase.SWING:
			return smoothstep(launch - 0.03, contact, _time)
		Phase.FINISH:
			return 1.0 - smoothstep(contact, contact + 0.22, _time)
	return 0.0


## Position in the clip (seconds) of the pose being shown, for tools and tests.
func clip_time() -> float:
	return _idle_time() if phase == Phase.IDLE else _time


func _start_blend(seconds: float) -> void:
	_from = frame()
	_blend = 0.0
	_blend_length = seconds


func _idle_time() -> float:
	var ramp := minf(IDLE_RAMP, _idle_length)
	var half := _idle_length + ramp
	var u := pingpong(_idle_clock, half)
	if u < ramp:
		return u * u / (2.0 * ramp)
	if u > half - ramp:
		return _idle_length - (half - u) * (half - u) / (2.0 * ramp)
	return u - ramp * 0.5
