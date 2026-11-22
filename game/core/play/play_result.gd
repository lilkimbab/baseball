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
## The hard chance of the play, if there was one: a fielder who got to the ball with little or
## no time to spare (a running or diving catch in the air, a diving stop on the ground), held
## or not. `hard_odds` is how likely he was to hold it. The scene may show it slowly, close up.
var hard_fielder: Position.Kind = Position.Kind.DH
var hard_time := 0.0
var hard_at := Vector3.ZERO
var hard_odds := 1.0
var hard_made := false
var hard_air := false
## How far short of the fence (m, along its own line) a ball in the air came down or was
## caught; INF for one on the ground. Negative or zero: it went over.
var short_of_fence := INF


func has_hard_chance() -> bool:
	return hard_fielder != Position.Kind.DH
