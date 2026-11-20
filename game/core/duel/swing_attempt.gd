class_name SwingAttempt
extends RefCounted
## One swing: when the barrel arrives and where the batter aimed, plus how it turned out.

enum Kind { CONTACT, POWER }

var kind: Kind = Kind.CONTACT
## Time (seconds after release) at which the barrel reaches the contact zone.
var contact_time := 0.0
## Aim point on the plane of the plate: x across, y up. Only used if has_aim.
var aim := Vector2.ZERO
var has_aim := false

## Filled in when the swing is resolved.
var resolved := false
## Timing error as a fraction of the window: negative = early, positive = late, |1| = limit.
var tau := 0.0
var judgment: StringName = &""
var made_contact := false
