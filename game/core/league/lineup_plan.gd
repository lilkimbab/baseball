class_name LineupPlan
extends RefCounted
## Editing the manager's batting order (Team.batting_plan, docs/08 R5): an order is nine
## [player id, position code] pairs from the lead-off man down. Two men in it trade places in
## the order, or trade positions; a man off the bench takes a place, order and position both.
## Nothing here changes a plan that is not the team's own copy until it is stored.


## The order a game's line-up was made with, as a plan.
static func from_game(game: TeamInGame) -> Array:
	var plan: Array = []
	for slot: LineupSlot in game.lineup:
		plan.append([slot.player_id, Position.code(slot.position)])
	return plan


## The team's plan if it has one, else the line-up the computer would play today.
static func current(team: Team, manager: AiManager, rules: RuleSet) -> Array:
	if team.batting_plan.size() == 9:
		return team.batting_plan.duplicate(true)
	var starter := team.rotation()[0].id if not team.rotation().is_empty() else ""
	return from_game(manager.make_lineup(team, rules, starter))


static func swap_order(plan: Array, i: int, j: int) -> void:
	var a: Array = plan[i]
	plan[i] = plan[j]
	plan[j] = a


static func swap_positions(plan: Array, i: int, j: int) -> void:
	var a := str(plan[i][1])
	plan[i][1] = plan[j][1]
	plan[j][1] = a


## A man off the bench bats in place i, at that place's position.
static func bring_in(plan: Array, i: int, player_id: String) -> void:
	plan[i][0] = player_id


## The first-team hitters not in the order.
static func bench(plan: Array, team: Team) -> Array[Player]:
	var in_order: Dictionary[String, bool] = {}
	for entry: Variant in plan:
		in_order[str((entry as Array)[0])] = true
	var out: Array[Player] = []
	for p: Player in team.first_team():
		if not p.is_pitcher() and not in_order.has(p.id):
			out.append(p)
	return out


## What is wrong with an order, one line each (empty when it can be played as it is): a man
## at a position he cannot play, a catcher or infielder throwing left-handed where that will
## not do, someone no longer on the first team.
static func problems(plan: Array, team: Team) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Variant in plan:
		var pair: Array = entry
		var p := team.player(str(pair[0]))
		var kind := Position.from_code(str(pair[1]))
		if p == null or not team.is_registered(p.id) or p.is_pitcher():
			out.append("%s: 1군 타자가 아닙니다" % (p.name if p != null else str(pair[0])))
			continue
		if kind == Position.Kind.DH:
			continue
		if p.aptitude(kind) <= 0.0:
			out.append("%s: %s를 볼 수 없습니다" % [p.name, Position.name_of(kind)])
		elif Position.needs_right_hand(kind) and p.throws == &"L":
			out.append("%s: 좌투로는 %s를 볼 수 없습니다" % [p.name, Position.name_of(kind)])
	return out


## Starters in a new order: the one at i and the one at j trade turns.
static func swap_rotation(team: Team, i: int, j: int) -> void:
	var order := PackedStringArray()
	for p: Player in team.rotation():
		order.append(p.id)
	var a := order[i]
	order[i] = order[j]
	order[j] = a
	team.rotation_plan = order
