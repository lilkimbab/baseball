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
## The waiting motion. The recorded swings start well before the stride, and that stretch is
## not a stance: in many of them the hitter is still settling, rocking, waving the bat or
## lifting the front foot (up to 21 cm of chest, 45 cm of bat and 16 cm of front foot in the
## 20 forms). Played forward and back it made the batter rock and wave without end (the user:
## "the batter shakes far too much in the box before the pitch, and the stance looks odd").
## So the stance is the stillest moment of that stretch, held, with only as much of the
## recording around it as keeps the chest within IDLE_CHEST, the bat's end within IDLE_BAT and
## the feet within IDLE_FEET of it — breathing and a small waggle — swayed through slowly.
const IDLE_CHEST := 0.025
const IDLE_BAT := 0.06
const IDLE_FEET := 0.01
const IDLE_MOST := 0.4
const IDLE_PERIOD := 2.6
## Joints watched for stillness.
const STILL_JOINTS: Array[StringName] = [&"ThoraxTop", &"BatGrip", &"BatSweetSpot", &"LeftFoot", &"RightFoot"]

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
## The stance: its moment in the clip and how far either side of it the waiting motion goes.
var set_time := 0.0
var idle_reach := 0.0
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
	_find_stance()


## The stillest moment before the stride (joint movement summed over a fifth of a second,
## the later of two equally still moments preferred: less to do when the load starts), and
## the reach of the recording around it that stays within the limits.
func _find_stance() -> void:
	var step := 1.0 / 30.0
	var times: Array[float] = []
	var t := 0.0
	while t <= _idle_length:
		times.append(t)
		t += step
	if times.size() < 3:
		set_time = _idle_length
		idle_reach = 0.0
		return
	var poses: Array = []
	for at: float in times:
		poses.append(clip.sample(at))
	var speed: Array[float] = []
	for i: int in times.size():
		var j := mini(i + 1, times.size() - 1)
		var k := maxi(i - 1, 0)
		var moved := 0.0
		for joint: StringName in STILL_JOINTS:
			if (poses[j] as Dictionary).has(joint):
				moved += ((poses[j] as Dictionary)[joint] as Vector3).distance_to((poses[k] as Dictionary)[joint])
		speed.append(moved)
	var best := times.size() - 1
	var best_score := INF
	for i: int in times.size():
		var sum := 0.0
		for d: int in range(-3, 4):
			sum += speed[clampi(i + d, 0, times.size() - 1)]
		var score := sum + 0.02 * (_idle_length - times[i])
		if score < best_score:
			best_score = score
			best = i
	set_time = times[best]
	var still: Dictionary = poses[best]
	var reach := 0
	while reach * step < IDLE_MOST:
		var lo := best - reach - 1
		var hi := best + reach + 1
		if lo < 0 or hi >= times.size():
			break
		if not _close(poses[lo], still) or not _close(poses[hi], still):
			break
		reach += 1
	idle_reach = reach * step


static func _close(pose: Dictionary, still: Dictionary) -> bool:
	var limits := {&"ThoraxTop": IDLE_CHEST, &"BatSweetSpot": IDLE_BAT, &"BatGrip": IDLE_BAT, &"LeftFoot": IDLE_FEET, &"RightFoot": IDLE_FEET}
	for joint: StringName in limits:
		if pose.has(joint) and still.has(joint) and (pose[joint] as Vector3).distance_to(still[joint]) > float(limits[joint]):
			return false
	return true


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


## How much higher (m) the barrel is at contact with the other swing mixed in (aim_height)
## than in the main swing alone.
func contact_shift() -> float:
	if _other == null:
		return 0.0
	return (_contact_height(_other) - _contact_height(clip)) * _other_weight


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
	return set_time + idle_reach * sin(TAU * _idle_clock / IDLE_PERIOD)
