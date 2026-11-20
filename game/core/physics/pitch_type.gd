class_name PitchType
extends RefCounted
## Reference definition of a pitch type (data/pitch_types.json). Values describe a
## right-handed, over-the-top delivery; a pitcher's own pitches scale them.

var id: StringName = &""
var label := ""
var family: StringName = &""
var speed_kmh := 0.0
var spin_rpm := 0.0
## Share of the spin that is perpendicular to the flight path and so bends the ball, 0..1.
var efficiency := 1.0
## Direction of the Magnus force seen by the catcher: 0 = up, +90 = toward first base.
var tilt_deg := 0.0
