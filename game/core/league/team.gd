class_name Team
extends RefCounted
## A club and its players. The roster pack format is in docs/07 section 5.

var id := ""
var name := ""
var short_name := ""
var stadium := ""
var primary := Color(0.1, 0.15, 0.35)
var secondary := Color(0.95, 0.95, 0.95)
var accent := Color(0.9, 0.6, 0.1)
var players: Array[Player] = []
## Manager's habits (1 = league average): how often he sends runners and asks for bunts.
var steal_style := 1.0
var bunt_style := 1.0
## Next starter in the rotation.
var rotation_index := 0


func player(player_id: String) -> Player:
	for p: Player in players:
		if p.id == player_id:
			return p
	return null


## Starting pitchers in rotation order.
func rotation() -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in players:
		if p.role() == &"SP":
			out.append(p)
	return out


## The starter for the next game, moving the rotation on.
func next_starter() -> Player:
	var starters := rotation()
	if starters.is_empty():
		for p: Player in players:
			if p.is_pitcher():
				return p
		return null
	var p := starters[rotation_index % starters.size()]
	rotation_index += 1
	return p
