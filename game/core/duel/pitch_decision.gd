class_name PitchDecision
extends RefCounted
## What the pitcher chose to throw.

var type: PitchType
## Intended location on the plane of the plate's front edge.
var target := Vector3.ZERO
## How well the pitch was executed, 0 (worst) to 1 (perfect).
var quality := 0.7
## The player's own pitch: the miss follows his timing on the gauge far more closely than a
## computer pitcher's follows its draw (PitchDuel.player_scatter). A pitch let go at the right
## moment goes where it was aimed; the pitcher's command still sets how far a poor one strays.
var by_hand := false
## How far from ready the pitcher was (GameState.cold): his miss is wider.
var cold := 0.0
## Fraction of full velocity, 0.9-1.0.
var effort := 1.0
