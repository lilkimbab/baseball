class_name SwingAttempt
extends RefCounted
## One swing: when the barrel arrives and where the batter aimed, plus how it turned out.

enum Kind { CONTACT, POWER, BUNT }

var kind: Kind = Kind.CONTACT
## Time (seconds after release) at which the barrel reaches the contact zone.
var contact_time := 0.0
## Aim point on the plane of the plate: x across, y up. Only used if has_aim.
var aim := Vector2.ZERO
var has_aim := false
## For a bunt: which way the bat is angled, degrees (+ toward first base).
var bunt_angle := 0.0
## Added to the bat-ball offset (metres; negative: the bat passes over the ball), for a
## batter fooled by how much a pitch dropped.
var offset_bias := 0.0
## How far the ball's centre was above the bat's axis at contact (m).
var offset := 0.0

## Filled in when the swing is resolved.
var resolved := false
## Timing error as a fraction of the window: negative = early, positive = late, |1| = limit.
var tau := 0.0
var judgment: StringName = &""
var made_contact := false
## Why a swing missed: &"timing", &"reach" (too far off the plate), &"end" (off the end of
## the bat), &"under" or &"over" (the bat passed below or above the ball).
var miss_reason: StringName = &""

