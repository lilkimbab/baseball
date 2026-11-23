class_name CareerRules
extends RefCounted
## The numbers of the career mode (data/career.ko.json). Read by CareerIO.


class PlayerType:
	var id := ""
	var name := ""
	var strengths := PackedStringArray()
	var weak := PackedStringArray()
	## Added to every rating (the all-round type).
	var all := 0.0
	## Pitchers: the pitches he starts with (the first is his fastball) and its speed.
	var pitches: Array[StringName] = []
	var velocity := 144.0


class Evolution:
	var from: StringName = &""
	var to: StringName = &""
	var uses := 0
	## "velocity" (km/h of his fastball) or a rating of the pitch: "movement", "command".
	var rating := ""
	var at_least := 0.0


class Body:
	var id := ""
	var name := ""
	var height := 183.0
	var weight := 88.0


var base := 40.0
var strength := 14.0
var weakness := -4.0
var positions := PackedStringArray()
var position_names: Dictionary[String, String] = {}
var batter_types: Array[PlayerType] = []
var pitcher_types: Array[PlayerType] = []
var bodies: Array[Body] = []
var skins := PackedStringArray()
var hairs := PackedStringArray()
var beards := PackedStringArray()
## Growth points: field → event → points; the scene and game goals, the clutch factor, the
## cost of a rating point and the type's discount.
var gp: Dictionary[String, Dictionary] = {}
var scene_goal_gp := 10.0
var game_goal_gp := 25.0
var clutch := 1.5
var cost_base := 10.0
var type_discount := 0.2
## Field → the ratings its points buy.
var ratings: Dictionary[String, PackedStringArray] = {}
## Type id or pitching position → [what, how many].
var game_goals: Dictionary[String, Array] = {}
var evolutions: Array[Evolution] = []
## Game rating: base, per-event weights by field, goal and clutch bonuses, medal lines (bronze,
## silver, gold).
var rating: Dictionary = {}
var medals := PackedFloat64Array([6.0, 7.5, 9.0])
## Reward boxes by medal: points, growth points, gear (name, rating, amount).
var reward_points := PackedInt32Array([30, 60, 100])
var reward_gp := PackedInt32Array([8, 16, 30])
var gear: Array[Dictionary] = []
var all_star: Dictionary = {}
var new_pitch_gp := 150.0
var max_pitches := 6
var learnable: Array[StringName] = []


func field_of(rating: String) -> String:
	for field: String in ratings:
		if ratings[field].has(rating):
			return field
	return ""


static func is_pitching_position(position: String) -> bool:
	return position == "SP" or position == "RP" or position == "CL"


func types_for(position: String) -> Array[PlayerType]:
	return pitcher_types if is_pitching_position(position) else batter_types


func type_by_id(id: String) -> PlayerType:
	for t: PlayerType in batter_types + pitcher_types:
		if t.id == id:
			return t
	return null


func body_by_id(id: String) -> Body:
	for b: Body in bodies:
		if b.id == id:
			return b
	return bodies[0] if not bodies.is_empty() else Body.new()
