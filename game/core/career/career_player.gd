class_name CareerPlayer
extends RefCounted
## The player of the career mode (docs/02 section 6): the Player himself and what the career
## keeps about him — his position and type, his club and whether he is on its first team,
## growth points per field, popularity, how he looks, and how often he has thrown each pitch.

## The fields growth points are earned and spent in, each only on its own ratings.
const FIELDS: Array[String] = ["batting", "fielding", "running", "pitching"]

var player: Player
## "SP", "RP", "CL", "C", "1B", ... ("CL" is a reliever who closes).
var position := ""
var type_id := ""
var team_id := ""
var first_team := false
var appearance: Dictionary[String, String] = {}
var gp: Dictionary[String, float] = {"batting": 0.0, "fielding": 0.0, "running": 0.0, "pitching": 0.0}
var popularity := 0.0
## Points from reward boxes, and gear he has (name → rating it adds to).
var points := 0
var gear: Dictionary[String, String] = {}
## Game ratings this season.
var ratings := PackedFloat64Array()
var pitch_uses: Dictionary[StringName, int] = {}


func is_pitcher() -> bool:
	return CareerRules.is_pitching_position(position)


## Joins a club's second team (a rookie starts there).
func join(team: Team) -> void:
	team_id = team.id
	if team.registered.is_empty():
		for p: Player in team.players:
			team.registered.append(p.id)
	team.players.append(player)
	first_team = false
