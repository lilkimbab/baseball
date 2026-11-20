class_name TeamInGame
extends RefCounted
## One team during a game: batting order, who plays where, who is left on the bench and in
## the bullpen, and who has been taken out (and may not come back).

var team_id := ""
var name := ""
var short_name := ""
var players: Dictionary[String, Player] = {}
var lineup: Array[LineupSlot] = []
var pitcher_id := ""
var starter_id := ""
var bench: Array[String] = []
var bullpen: Array[String] = []
var removed: Array[String] = []
var dh_active := true
var pitchers_used: Array[String] = []
## Manager's habits: how readily he sends runners and calls for bunts (1 = league average).
var steal_style := 1.0
var bunt_style := 1.0


func player(id: String) -> Player:
	return players.get(id, null)


func batter_at(index: int) -> String:
	return lineup[posmod(index, lineup.size())].player_id


func slot_of(id: String) -> int:
	for i: int in lineup.size():
		if lineup[i].player_id == id:
			return i
	return -1


## The player at a position on defence. The pitcher is always pitcher_id.
func fielder_at(kind: Position.Kind) -> String:
	if kind == Position.Kind.P:
		return pitcher_id
	for slot: LineupSlot in lineup:
		if slot.position == kind:
			return slot.player_id
	return ""


func is_available(id: String) -> bool:
	return not removed.has(id) and (bench.has(id) or bullpen.has(id))


func copy() -> TeamInGame:
	var t := TeamInGame.new()
	t.team_id = team_id
	t.name = name
	t.short_name = short_name
	t.players = players
	for slot: LineupSlot in lineup:
		t.lineup.append(slot.copy())
	t.pitcher_id = pitcher_id
	t.starter_id = starter_id
	t.bench = bench.duplicate()
	t.bullpen = bullpen.duplicate()
	t.removed = removed.duplicate()
	t.dh_active = dh_active
	t.pitchers_used = pitchers_used.duplicate()
	t.steal_style = steal_style
	t.bunt_style = bunt_style
	return t


## Problems with the line-up, as readable sentences. Empty when it is legal. With
## for_defence the team is about to take the field, so pinch hitters and runners must have
## been given positions by then.
func validate(for_defence: bool = false) -> PackedStringArray:
	var problems := PackedStringArray()
	if lineup.size() != 9:
		problems.append("타순은 9명이어야 한다 (%d명)" % lineup.size())
	var seen: Dictionary[String, bool] = {}
	var covered: Dictionary[int, int] = {}
	for slot: LineupSlot in lineup:
		if seen.has(slot.player_id):
			problems.append("%s 선수가 타순에 두 번 있다" % slot.player_id)
		seen[slot.player_id] = true
		if removed.has(slot.player_id):
			problems.append("교체된 %s 선수가 다시 들어왔다" % slot.player_id)
		covered[slot.position] = int(covered.get(slot.position, 0)) + 1
		if for_defence and (slot.position == Position.Kind.PH or slot.position == Position.Kind.PR):
			problems.append("%s 선수의 수비 위치가 정해지지 않았다" % slot.player_id)
		var p := player(slot.player_id)
		if p == null:
			problems.append("%s 선수가 명단에 없다" % slot.player_id)
		elif slot.position != Position.Kind.P and Position.is_field(slot.position) and Position.needs_right_hand(slot.position) and p.throws == &"L":
			problems.append("왼손잡이 %s 선수는 %s를 볼 수 없다" % [p.name, Position.name_of(slot.position)])
	for kind: Position.Kind in Position.FIELD:
		if kind == Position.Kind.P and dh_active:
			continue
		var count: int = covered.get(kind, 0)
		if for_defence and count != 1:
			problems.append("%s 자리에 %d명" % [Position.name_of(kind), count])
	if dh_active:
		if int(covered.get(Position.Kind.P, 0)) > 0:
			problems.append("지명타자가 있으면 투수는 타순에 없다")
		if for_defence and int(covered.get(Position.Kind.DH, 0)) != 1:
			problems.append("지명타자가 한 명이어야 한다")
		if seen.has(pitcher_id):
			problems.append("지명타자가 있는데 투수가 타순에 있다")
	else:
		if int(covered.get(Position.Kind.DH, 0)) > 0:
			problems.append("지명타자가 없는데 지명타자 자리가 있다")
		if for_defence and lineup[maxi(slot_of(pitcher_id), 0)].player_id != pitcher_id:
			problems.append("투수가 타순에 없다")
	var pitcher := player(pitcher_id)
	if pitcher == null or not pitcher.is_pitcher():
		problems.append("투수가 아닌 선수가 마운드에 있다")
	if removed.has(pitcher_id):
		problems.append("교체된 투수가 다시 올라왔다")
	return problems


## A pinch hitter (or runner) takes a place in the order. The player he replaces is out of
## the game for good. His position is settled when the team next takes the field.
func pinch(slot_index: int, in_id: String, as_runner: bool = false) -> void:
	var slot := lineup[slot_index]
	_remove(slot.player_id)
	_take_from_bench(in_id)
	if slot.position != Position.Kind.PH and slot.position != Position.Kind.PR:
		slot.replaced_position = slot.position
	slot.player_id = in_id
	slot.position = Position.Kind.PR if as_runner else Position.Kind.PH


## A bench player replaces someone in the field, in the same batting place.
func replace_fielder(out_id: String, in_id: String, at: Position.Kind) -> void:
	var index := slot_of(out_id)
	_remove(out_id)
	_take_from_bench(in_id)
	lineup[index].player_id = in_id
	lineup[index].position = at
	lineup[index].replaced_position = at


## A player already in the game changes position. Moving the designated hitter into the
## field ends the designated hitter for this team: the pitcher bats in the place of the
## player who leaves the field.
func move(id: String, to: Position.Kind) -> void:
	var index := slot_of(id)
	var from := lineup[index].position
	var holder := slot_of(fielder_at(to)) if to != Position.Kind.P else -1
	if dh_active and from == Position.Kind.DH and holder >= 0:
		_remove(lineup[holder].player_id)
		lineup[holder].player_id = pitcher_id
		lineup[holder].position = Position.Kind.P
		lineup[holder].replaced_position = Position.Kind.P
		dh_active = false
	elif holder >= 0 and holder != index:
		# Two players swap positions.
		lineup[holder].position = from
		lineup[holder].replaced_position = from
	lineup[index].position = to
	lineup[index].replaced_position = to


## A new pitcher comes in.
## - Without the designated hitter he bats in the old pitcher's place (or in a pinch
##   hitter's place, if the pitcher was batted for).
## - If he is a pinch hitter or runner who is already in the order, the designated hitter
##   ends: he pitches from his place in the order, and the designated hitter takes the field
##   at the position of the player he replaced.
func change_pitcher(in_id: String) -> void:
	var old := pitcher_id
	var own_slot := slot_of(in_id)
	if own_slot >= 0:
		var left_open := lineup[own_slot].replaced_position
		lineup[own_slot].position = Position.Kind.P
		lineup[own_slot].replaced_position = Position.Kind.P
		if dh_active:
			for slot: LineupSlot in lineup:
				if slot.position == Position.Kind.DH:
					slot.position = left_open if Position.is_field(left_open) and left_open != Position.Kind.P else Position.Kind.LF
					slot.replaced_position = slot.position
			dh_active = false
		_remove(old)
	else:
		_take_from_bench(in_id)
		if not dh_active:
			var index := slot_of(old)
			if index < 0:
				for i: int in lineup.size():
					if lineup[i].replaced_position == Position.Kind.P and (lineup[i].position == Position.Kind.PH or lineup[i].position == Position.Kind.PR):
						index = i
			if index >= 0:
				if lineup[index].player_id != old:
					_remove(lineup[index].player_id)
				lineup[index].player_id = in_id
				lineup[index].position = Position.Kind.P
				lineup[index].replaced_position = Position.Kind.P
		_remove(old)
	pitcher_id = in_id
	if not pitchers_used.has(in_id):
		pitchers_used.append(in_id)


## The pitcher moves to a position in the field and a new pitcher comes in. Ends the
## designated hitter: the old pitcher bats in the designated hitter's place, and the new
## pitcher in the place of the fielder who leaves.
func pitcher_to_field(to: Position.Kind, new_pitcher: String) -> void:
	var old := pitcher_id
	var holder := slot_of(fielder_at(to))
	_take_from_bench(new_pitcher)
	if dh_active:
		for slot: LineupSlot in lineup:
			if slot.position == Position.Kind.DH:
				_remove(slot.player_id)
				slot.player_id = old
				slot.position = to
				slot.replaced_position = to
		dh_active = false
	else:
		var own := slot_of(old)
		lineup[own].position = to
		lineup[own].replaced_position = to
	if holder >= 0:
		_remove(lineup[holder].player_id)
		lineup[holder].player_id = new_pitcher
		lineup[holder].position = Position.Kind.P
		lineup[holder].replaced_position = Position.Kind.P
	pitcher_id = new_pitcher
	if not pitchers_used.has(new_pitcher):
		pitchers_used.append(new_pitcher)


func _remove(id: String) -> void:
	if id != "" and not removed.has(id):
		removed.append(id)
	bench.erase(id)
	bullpen.erase(id)


func _take_from_bench(id: String) -> void:
	bench.erase(id)
	bullpen.erase(id)
