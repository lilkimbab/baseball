class_name Standings
extends RefCounted
## A division's table. Ranked by winning percentage with ties left out (wins
## over wins and losses, the KBO way); clubs level on percentage are split by their games
## against each other, then run difference, then by name so the order is always the same.

var rows: Dictionary[String, StandingsRow] = {}


static func of(team_ids: PackedStringArray) -> Standings:
	var s := Standings.new()
	for id: String in team_ids:
		var row := StandingsRow.new()
		row.team_id = id
		s.rows[id] = row
	return s


## Ties as losses in every row's percentage (RuleSet.ties_as_losses).
func count_ties_as_losses(on: bool) -> void:
	for r: StandingsRow in rows.values():
		r.ties_as_losses = on


func row(team_id: String) -> StandingsRow:
	return rows.get(team_id)


func record(game: ScheduledGame) -> void:
	if not game.played:
		return
	var a: StandingsRow = rows.get(game.away)
	var h: StandingsRow = rows.get(game.home)
	var away_result := signi(game.away_score - game.home_score)
	if a != null:
		a.add(away_result, game.home, false, game.away_score, game.home_score)
	if h != null:
		h.add(-away_result, game.away, true, game.home_score, game.away_score)


## Rows from first to last.
func ranked() -> Array[StandingsRow]:
	var out: Array[StandingsRow] = []
	out.assign(rows.values())
	out.sort_custom(func(x: StandingsRow, y: StandingsRow) -> bool: return x.pct() > y.pct() or (is_equal_approx(x.pct(), y.pct()) and x.team_id < y.team_id))
	# Break ties group by group.
	var i := 0
	while i < out.size():
		var j := i + 1
		while j < out.size() and is_equal_approx(out[j].pct(), out[i].pct()):
			j += 1
		if j - i > 1:
			var group: Array[StandingsRow] = out.slice(i, j)
			_break_tie(group)
			for k: int in group.size():
				out[i + k] = group[k]
		i = j
	return out


## Clubs level on percentage: their record against each other (all the others in the group),
## then run difference.
func _break_tie(group: Array[StandingsRow]) -> void:
	var ids: Dictionary[String, bool] = {}
	for r: StandingsRow in group:
		ids[r.team_id] = true
	var mutual: Dictionary[String, float] = {}
	for r: StandingsRow in group:
		var w := 0
		var l := 0
		for other: String in ids:
			if other == r.team_id:
				continue
			var v := r.against(other)
			w += v.x
			l += v.y
		mutual[r.team_id] = float(w) / (w + l) if w + l > 0 else 0.5
	group.sort_custom(func(x: StandingsRow, y: StandingsRow) -> bool:
		var mx: float = mutual[x.team_id]
		var my: float = mutual[y.team_id]
		if not is_equal_approx(mx, my):
			return mx > my
		if x.run_difference() != y.run_difference():
			return x.run_difference() > y.run_difference()
		return x.team_id < y.team_id)


## Place of a club, 1 for first.
func rank_of(team_id: String) -> int:
	var order := ranked()
	for i: int in order.size():
		if order[i].team_id == team_id:
			return i + 1
	return 0


## Games behind the leader: half the difference in wins minus losses.
func games_behind(team_id: String) -> float:
	var order := ranked()
	if order.is_empty():
		return 0.0
	var lead := order[0]
	var r := row(team_id)
	return ((lead.wins - lead.losses) - (r.wins - r.losses)) * 0.5
