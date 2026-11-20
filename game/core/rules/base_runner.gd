class_name BaseRunner
extends RefCounted
## A runner on base and the facts the scorer needs about him.

var player_id := ""
## Pitcher charged if he scores: the one who let him on, as a rule.
var responsible_pitcher_id := ""
## He reached on an error (or would have been out but for one): his run is not earned.
var unearned := false
var reached_by: PaResult.Kind = PaResult.Kind.NONE


static func make(player: String, pitcher: String, how: PaResult.Kind = PaResult.Kind.NONE, error: bool = false) -> BaseRunner:
	var r := BaseRunner.new()
	r.player_id = player
	r.responsible_pitcher_id = pitcher
	r.reached_by = how
	r.unearned = error
	return r


func copy() -> BaseRunner:
	return BaseRunner.make(player_id, responsible_pitcher_id, reached_by, unearned)
