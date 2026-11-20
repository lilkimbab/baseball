class_name LineupSlot
extends RefCounted
## One place in the batting order.

var player_id := ""
var position: Position.Kind = Position.Kind.DH
## The position this slot had before a pinch hitter or runner took it, for when the team
## goes back on defence.
var replaced_position: Position.Kind = Position.Kind.DH


static func make(player: String, at: Position.Kind) -> LineupSlot:
	var s := LineupSlot.new()
	s.player_id = player
	s.position = at
	s.replaced_position = at
	return s


func copy() -> LineupSlot:
	var s := LineupSlot.make(player_id, position)
	s.replaced_position = replaced_position
	return s
