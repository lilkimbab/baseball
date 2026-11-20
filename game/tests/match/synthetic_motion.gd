class_name SyntheticMotion
extends RefCounted
## Hand-made joint frames and clips for tests, so they do not depend on the local content
## pack. The figure is a 1.85 m player in the puppet's space: +X right, +Y up, -Z forward.


static func standing() -> Dictionary[StringName, Vector3]:
	var frame: Dictionary[StringName, Vector3] = {}
	for side: int in [-1, 1] as Array[int]:
		var name := "Right" if side > 0 else "Left"
		frame[StringName(name + "UpperLeg")] = Vector3(0.09 * side, 0.95, 0.0)
		frame[StringName(name + "LowerLeg")] = Vector3(0.10 * side, 0.52, -0.03)
		frame[StringName(name + "Foot")] = Vector3(0.12 * side, 0.08, 0.0)
		frame[StringName(name + "UpperArm")] = Vector3(0.19 * side, 1.45, 0.0)
		frame[StringName(name + "LowerArm")] = Vector3(0.25 * side, 1.17, 0.02)
		frame[StringName(name + "Hand")] = Vector3(0.26 * side, 0.92, -0.08)
		frame[StringName(name + "HandTip")] = Vector3(0.26 * side, 0.85, -0.10)
	frame[&"ThoraxTop"] = Vector3(0.0, 1.5, 0.0)
	frame[&"ThoraxBottom"] = Vector3(0.0, 1.22, 0.0)
	frame[&"ThoraxRight"] = Vector3(0.1, 1.5, 0.0)
	return frame


## Both knees bent and the hips lowered.
static func squat() -> Dictionary[StringName, Vector3]:
	var frame := standing()
	for joint: StringName in frame:
		if not String(joint).ends_with("Foot") and not String(joint).ends_with("LowerLeg"):
			frame[joint] += Vector3(0.0, -0.3, 0.05)
	frame[&"LeftLowerLeg"] = Vector3(-0.12, 0.42, -0.3)
	frame[&"RightLowerLeg"] = Vector3(0.12, 0.42, -0.3)
	return frame


## The same frame turned about the vertical axis through the origin.
static func turned(frame: Dictionary[StringName, Vector3], radians: float) -> Dictionary[StringName, Vector3]:
	var out: Dictionary[StringName, Vector3] = {}
	for joint: StringName in frame:
		out[joint] = frame[joint].rotated(Vector3.UP, radians)
	return out


## Stride out, trunk forward, right hand high and in front: the moment of release.
static func release() -> Dictionary[StringName, Vector3]:
	var frame := standing()
	frame[&"LeftUpperLeg"] = Vector3(-0.09, 0.8, -0.55)
	frame[&"RightUpperLeg"] = Vector3(0.09, 0.8, -0.55)
	frame[&"LeftLowerLeg"] = Vector3(-0.1, 0.45, -0.95)
	frame[&"LeftFoot"] = Vector3(-0.12, 0.08, -1.05)
	frame[&"RightLowerLeg"] = Vector3(0.12, 0.42, -0.25)
	frame[&"RightFoot"] = Vector3(0.14, 0.12, 0.05)
	frame[&"ThoraxBottom"] = Vector3(0.0, 1.05, -0.68)
	frame[&"ThoraxTop"] = Vector3(0.0, 1.28, -0.85)
	frame[&"ThoraxRight"] = Vector3(0.1, 1.28, -0.85)
	frame[&"LeftUpperArm"] = Vector3(-0.19, 1.24, -0.82)
	frame[&"RightUpperArm"] = Vector3(0.19, 1.24, -0.82)
	frame[&"RightLowerArm"] = Vector3(0.42, 1.36, -1.0)
	frame[&"RightHand"] = Vector3(0.55, 1.52, -1.2)
	frame[&"RightHandTip"] = Vector3(0.58, 1.56, -1.27)
	frame[&"LeftLowerArm"] = Vector3(-0.25, 1.0, -0.9)
	frame[&"LeftHand"] = Vector3(-0.15, 0.85, -0.85)
	frame[&"LeftHandTip"] = Vector3(-0.12, 0.8, -0.85)
	return frame


## A 1.4 s delivery at 60 frames a second: standing, then to the release pose at 1.0 s.
static func pitch_clip() -> JointClip:
	var frames: Array[Dictionary] = []
	for i: int in 85:
		frames.append(JointClip.blend(standing(), release(), smoothstep(0.2, 1.0, i / 60.0)))
	var clip := JointClip.from_frames(frames, 60.0, {&"release": 1.0})
	clip.kind = &"pitch"
	clip.source = "synthetic delivery"
	return clip


## Hands together on a bat held up behind the right shoulder.
static func stance() -> Dictionary[StringName, Vector3]:
	var frame := standing()
	frame[&"RightLowerArm"] = Vector3(0.36, 1.2, -0.05)
	frame[&"LeftLowerArm"] = Vector3(-0.05, 1.18, -0.28)
	return _with_bat(frame, Vector3(0.2, 1.35, -0.18), Vector3(0.2, 0.9, 0.38).normalized())


## Arms out over the plate, bat level and pointing forward.
static func contact() -> Dictionary[StringName, Vector3]:
	var frame := standing()
	frame[&"RightLowerArm"] = Vector3(0.05, 1.12, -0.25)
	frame[&"LeftLowerArm"] = Vector3(-0.38, 1.2, -0.2)
	return _with_bat(frame, Vector3(-0.05, 1.12, -0.36), Vector3(-0.25, -0.2, -0.95).normalized())


static func _with_bat(frame: Dictionary[StringName, Vector3], grip: Vector3, along: Vector3) -> Dictionary[StringName, Vector3]:
	# Bottom (left) hand nearer the knob, top (right) hand above it; wrists a little behind.
	var back := Vector3(0.0, 0.0, 0.07)
	frame[&"LeftHandTip"] = grip - along * 0.045
	frame[&"RightHandTip"] = grip + along * 0.045
	frame[&"LeftHand"] = frame[&"LeftHandTip"] + back
	frame[&"RightHand"] = frame[&"RightHandTip"] + back
	frame[&"BatGrip"] = grip
	frame[&"BatSweetSpot"] = grip + along * 0.55
	return frame


## A 1.6 s swing at 60 frames a second: stance, front foot lifted from 0.4 s (stride), hands
## start forward at 0.8 s (launch), contact at 0.95 s, and round to a finish at 1.3 s.
static func swing_clip() -> JointClip:
	var frames: Array[Dictionary] = []
	for i: int in 97:
		var t := i / 60.0
		var frame := JointClip.blend(stance(), contact(), smoothstep(0.8, 0.95, t))
		frame = JointClip.blend(frame, stance(), smoothstep(0.95, 1.3, t))
		var lift := smoothstep(0.4, 0.6, t) * (1.0 - smoothstep(0.65, 0.8, t))
		frame[&"LeftFoot"] += Vector3(-0.1, 0.12, 0.0) * lift
		frames.append(frame)
	var clip := JointClip.from_frames(frames, 60.0, {&"stride": 0.4, &"launch": 0.8, &"contact": 0.95, &"finish": 1.3})
	clip.kind = &"swing"
	clip.source = "synthetic swing"
	return clip
