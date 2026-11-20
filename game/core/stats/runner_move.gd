class_name RunnerMove
extends RefCounted
## Where one runner (or the batter) went on a play.

enum OutKind { NONE, FORCE, TAG, FLY, STRIKEOUT }

## Base the runner started from: 0 = the batter, 1..3 = first to third.
var from := 0
## Base he ended on: 1..3, 4 = scored, -1 = put out.
var to := 1
var out_kind: OutKind = OutKind.NONE
## He got there because of a fielding error (no RBI, and a run that is not earned).
var on_error := false


static func make(from_base: int, to_base: int, out: OutKind = OutKind.NONE, error: bool = false) -> RunnerMove:
	var m := RunnerMove.new()
	m.from = from_base
	m.to = to_base
	m.out_kind = out
	m.on_error = error
	return m


func is_out() -> bool:
	return to < 0


func scores() -> bool:
	return to == 4
