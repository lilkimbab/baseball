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
## For an out, the base he was put out at or running to (1..4); 0 when not known. A batter
## out at first never reached it, so no run scores if that is the third out; one thrown out
## stretching a hit had reached first, so runs that scored before the out count.
var out_at := 0


static func make(from_base: int, to_base: int, out: OutKind = OutKind.NONE, error: bool = false) -> RunnerMove:
	var m := RunnerMove.new()
	m.from = from_base
	m.to = to_base
	m.out_kind = out
	m.on_error = error
	return m


static func out_at_base(from_base: int, base: int, out: OutKind) -> RunnerMove:
	var m := make(from_base, -1, out)
	m.out_at = base
	return m


## The batter was put out before he reached first base.
func batter_out_before_first() -> bool:
	return from == 0 and is_out() and out_at <= 1


func is_out() -> bool:
	return to < 0


func scores() -> bool:
	return to == 4
