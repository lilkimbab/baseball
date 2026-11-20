class_name PlayResult
extends RefCounted
## How a batted ball turned out: the umpire's call, the scoring, where everyone went and the
## key frames to show it.

## A foul nobody caught: only a strike (or nothing with two strikes).
var foul := false
var result: PaResult.Kind = PaResult.Kind.NONE
## Moves in the order they happened.
var moves: Array[RunnerMove] = []
## Scorecard: "6-4-3", "8", "E6".
var fielders := ""
## Position number of the fielder who first handled the ball (1..9), 0 if none.
var direction := 0
var errors := 0
## The infield fly rule was called on this ball.
var infield_fly := false
var timeline := PlayTimeline.new()
## Plays at a base, in order: when, which base, out or safe, and how close (seconds between
## ball and runner). The scene shows the umpire's call on the close ones.
var calls: Array[PlayCall] = []
