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
## The manager's own choices (docs/08 R5), empty for the computer's: the batting order as
## [player id, position code] from the lead-off man down (with a designated hitter), and the
## starters in the order they take their turns.
var batting_plan: Array = []
var rotation_plan := PackedStringArray()
## Ids of the players on the first team (1군 엔트리); the rest are in the second team (2군).
## Empty means everyone is registered (a pack without a second team).
var registered := PackedStringArray()
## Day each player was taken off the first team. He cannot be registered again for
## RECALL_DAYS days (KBO: 10).
var removed_on: Dictionary[String, int] = {}

const RECALL_DAYS := 10


func player(player_id: String) -> Player:
	for p: Player in players:
		if p.id == player_id:
			return p
	return null


## Starting pitchers on the first team, in rotation order: the manager's order where he has
## set one (those he left out follow in the usual order).
func rotation() -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in players:
		if p.role() == &"SP" and is_registered(p.id):
			out.append(p)
	if rotation_plan.is_empty():
		return out
	var planned: Array[Player] = []
	for id: String in rotation_plan:
		for p: Player in out:
			if p.id == id:
				planned.append(p)
	for p: Player in out:
		if not planned.has(p):
			planned.append(p)
	return planned


func is_registered(player_id: String) -> bool:
	return registered.is_empty() or registered.has(player_id)


## Players on the first team (1군).
func first_team() -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in players:
		if is_registered(p.id):
			out.append(p)
	return out


## Players on the second team (2군).
func second_team() -> Array[Player]:
	var out: Array[Player] = []
	if registered.is_empty():
		return out
	for p: Player in players:
		if not registered.has(p.id):
			out.append(p)
	return out


## Why a player cannot be registered today, or "" if he can: the first team is full, he was
## sent down less than ten days ago, or the club would have too many foreign players on it.
func registration_problem(player_id: String, day: int, rules: RuleSet) -> String:
	var p := player(player_id)
	if p == null:
		return "없는 선수"
	if is_registered(player_id):
		return "이미 등록"
	if registered.size() >= rules.registered_roster:
		return "엔트리 %d명 초과" % rules.registered_roster
	if removed_on.has(player_id) and day - removed_on[player_id] < RECALL_DAYS:
		return "말소 %d일 뒤 재등록 가능" % RECALL_DAYS
	if p.origin == &"foreign" and _registered_with(&"foreign") >= rules.foreign_players:
		return "외국인 %d명 초과" % rules.foreign_players
	if p.origin == &"asia" and _registered_with(&"asia") >= rules.asia_quota:
		return "아시아쿼터 %d명 초과" % rules.asia_quota
	return ""


func register(player_id: String, day: int, rules: RuleSet) -> bool:
	if registration_problem(player_id, day, rules) != "":
		return false
	registered.append(player_id)
	return true


## Sends a player down to the second team.
func unregister(player_id: String, day: int) -> bool:
	if registered.is_empty():
		for p: Player in players:
			registered.append(p.id)
	var i := registered.find(player_id)
	if i < 0:
		return false
	registered.remove_at(i)
	removed_on[player_id] = day
	return true


func _registered_with(origin: StringName) -> int:
	var n := 0
	for p: Player in first_team():
		if p.origin == origin:
			n += 1
	return n


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
