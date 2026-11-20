class_name PlayRunner
extends RefCounted
## One runner, or the batter, during a play.

var id := ""
## Base he starts from: 0 = the batter, 1..3.
var from := 0
var speed := 50.0
## Reading the play: how soon he starts and how well he judges a close one.
var baserunning := 50.0
var bats_left := false

# Worked out during the play.
## Metres off his base toward the next one when he starts running.
var gap := 0.0
## Seconds after contact he starts running.
var start := 0.0
## Forced to run because the batter became a runner.
var forced := false
## Base he ends on (from..4), or -1 when put out.
var to := 0
## Base he was put out at or running to.
var out_at := 0
var out_kind: RunnerMove.OutKind = RunnerMove.OutKind.NONE
## The bases he gained beyond the play's own were on an error.
var on_error := false
## When he reached the base he ends on, or was put out.
var time := 0.0


static func make(runner_id: String, base: int, run: float = 50.0, reads: float = 50.0) -> PlayRunner:
	var r := PlayRunner.new()
	r.id = runner_id
	r.from = base
	r.to = base
	r.speed = run
	r.baserunning = reads
	return r


func is_out() -> bool:
	return to < 0


func put_out(base: int, kind: RunnerMove.OutKind, at_time: float) -> void:
	to = -1
	out_at = base
	out_kind = kind
	time = at_time


func move() -> RunnerMove:
	var m := RunnerMove.make(from, to, out_kind, on_error)
	m.out_at = out_at
	return m
