class_name PlayCall
extends RefCounted
## One play at a base: the umpire's call.

var time := 0.0
## 1..3, 4 = home.
var base := 0
var out := false
## How close it was: |runner arrival - ball arrival| in seconds.
var margin := 0.0


static func make(at_time: float, at_base: int, is_out: bool, how_close: float) -> PlayCall:
	var c := PlayCall.new()
	c.time = at_time
	c.base = at_base
	c.out = is_out
	c.margin = how_close
	return c
