class_name SweepHit
extends RefCounted
## First contact found when sweeping the ball along a segment.

## Fraction of the segment travelled before contact, 0..1.
var fraction := 1.0
## Ball centre at the moment of contact.
var point := Vector3.ZERO
## Unit surface normal, pointing back toward the ball.
var normal := Vector3.ZERO
var surface: StringName = &"grass"


static func make(hit_fraction: float, at: Vector3, surface_normal: Vector3, surface_name: StringName) -> SweepHit:
	var hit := SweepHit.new()
	hit.fraction = hit_fraction
	hit.point = at
	hit.normal = surface_normal
	hit.surface = surface_name
	return hit
