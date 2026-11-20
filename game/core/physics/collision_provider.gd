class_name CollisionProvider
extends RefCounted
## What the ball can run into. AnalyticField implements this from a stadium definition for
## headless runs; the match scene implements it with engine queries against real colliders.


## First contact of a sphere of the given radius moved from `from` to `to`, or null.
func sweep(_from: Vector3, _to: Vector3, _radius: float) -> SweepHit:
	return null


## Ground surface under a position.
func surface_at(_pos: Vector3) -> StringName:
	return &"grass"


## True once the ball is beyond the playing field (over the fence or into the stands).
func is_out_of_play(_pos: Vector3) -> bool:
	return false
