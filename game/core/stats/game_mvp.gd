class_name GameMvp
extends RefCounted
## The player of the game: the best day on the winning side, scored the way a
## broadcast picks one: bases gained and runs made for a hitter, outs and runs saved for a
## pitcher. In a tie the best day of either side.


## The MVP's id, or "" for a game with no plate appearances.
static func pick(state: GameState, book: StatBook) -> String:
	var best := ""
	var best_score := -INF
	for t: int in 2:
		if state.winner >= 0 and t != state.winner:
			continue
		for id: String in book.batters[t]:
			var s := batter_score(book.batting[id])
			if s > best_score:
				best_score = s
				best = id
		for id: String in book.pitchers[t]:
			var s := pitcher_score(book.pitching[id], id == book.winner_id, id == book.save_id)
			if s > best_score:
				best_score = s
				best = id
	return best


static func batter_score(b: BattingLine) -> float:
	return b.total_bases() + b.runs + 1.2 * b.rbi + 0.8 * (b.walks + b.intentional_walks + b.hit_by_pitch) \
		+ 0.6 * b.stolen_bases - 0.25 * (b.ab - b.hits)


static func pitcher_score(p: PitchingLine, won: bool, saved: bool) -> float:
	return p.outs * 0.55 + p.strikeouts * 0.4 - p.earned_runs * 2.0 - (p.hits + p.walks + p.hit_by_pitch) * 0.45 \
		+ (2.0 if won else 0.0) + (1.5 if saved else 0.0)
