class_name PitchDecision
extends RefCounted
## What the pitcher chose to throw.

var type: PitchType
## Intended location on the plane of the plate's front edge.
var target := Vector3.ZERO
## How well the pitch was executed, 0 (worst) to 1 (perfect).
var quality := 0.7
## Fraction of full velocity, 0.9-1.0.
var effort := 1.0
