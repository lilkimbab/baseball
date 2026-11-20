class_name WinExpectancy
extends RefCounted
## The home team's chance of winning from any moment of a game, and how much the coming plate
## appearance matters (leverage index), for the "승부처" mark and the win-probability line
## (docs/03 section 9, docs/05 section 3.1).
##
## Worked out, not looked up: plate-appearance outcomes at the league's rates (LeagueEnv)
## drive a base-out Markov chain, which gives the runs still to come in a half-inning from
## each of the 24 base-out states; half-innings chain into the game's win probability, with
## the KBO's walk-off, nine-inning and extra-inning rules (a tie after the last inning counts
## as half a win). Leverage is the expected swing in win probability of the coming plate
## appearance, divided by its average over the plate appearances of typical games, so 1 is
## an ordinary one; HIGH and above is "승부처" (Tango's definition).
##
## Runner advances on hits and outs use fixed shares (A: typical MLB/KBO base-running):
## a single scores a runner from second 60% of the time (85% with two outs) and takes a runner
## from first to third 27%; a double scores a runner from first 40% (60% with two outs); an out
## in play is a double play 13% of the time with a runner on first and fewer than two out,
## otherwise it scores a runner from third 35% and moves a runner from second 30%.

const HIGH := 2.0
const MAX_RUNS := 12
const MAX_DIFF := 20
const ITERATIONS := 40

var rates := PackedFloat64Array()
var innings := 9
var extra_limit := 11
## Runs still to come in the half-inning: index outs * 8 + bases (bit 1 first, 2 second,
## 4 third) → probability of 0..MAX_RUNS runs.
var _runs: Array[PackedFloat64Array] = []
var _half: Dictionary[int, float] = {}
var _raw: Dictionary[int, float] = {}
var _norm := 0.0


static func for_league(env: LeagueEnv, rules: RuleSet) -> WinExpectancy:
	var w := WinExpectancy.new()
	w.rates = env.rates
	w.innings = rules.innings
	w.extra_limit = rules.extra_inning_limit if rules.extra_inning_limit > 0 else rules.innings + 6
	w._build_runs()
	return w


# --- Half-innings ---


## Outcomes of one plate appearance from (outs, bases): [probability, outs after, bases after, runs].
func transitions(outs: int, bases: int) -> Array[PackedFloat64Array]:
	var out: Array[PackedFloat64Array] = []
	var on1 := bases & 1 != 0
	var on2 := bases & 2 != 0
	var on3 := bases & 4 != 0
	var runners := int(on1) + int(on2) + int(on3)
	var p := rates
	var add := func(prob: float, o: int, b: int, r: int) -> void:
		if prob > 0.0:
			out.append(PackedFloat64Array([prob, o, b, r]))
	add.call(p[LeagueEnv.Outcome.K], outs + 1, bases, 0)
	# Walk or hit by pitch: forced runners move up.
	var walk_bases := bases
	var walk_runs := 0
	if on1:
		if on2:
			if on3:
				walk_runs = 1
			walk_bases = 7
		else:
			walk_bases = bases | 2 | 1
	else:
		walk_bases = bases | 1
	add.call(p[LeagueEnv.Outcome.BB] + p[LeagueEnv.Outcome.HBP], outs, walk_bases, walk_runs)
	# Single.
	var score2 := 0.85 if outs == 2 else 0.6
	for second_scores: bool in [true, false]:
		var p2 := (score2 if second_scores else 1.0 - score2) if on2 else (1.0 if second_scores else 0.0)
		if p2 <= 0.0:
			continue
		for first_to_third: bool in [true, false]:
			var third_open := not on2 or second_scores
			var p1 := (0.27 if first_to_third else 0.73) if on1 and third_open else (0.0 if first_to_third else 1.0)
			if p1 <= 0.0:
				continue
			var runs := int(on3) + int(on2 and second_scores)
			var b := 1
			if on2 and not second_scores:
				b |= 4
			if on1:
				b |= 4 if first_to_third else 2
			add.call(p[LeagueEnv.Outcome.SINGLE] * p2 * p1, outs, b, runs)
	# Double.
	var score1 := 0.6 if outs == 2 else 0.4
	if on1:
		add.call(p[LeagueEnv.Outcome.DOUBLE] * score1, outs, 2, int(on2) + int(on3) + 1)
		add.call(p[LeagueEnv.Outcome.DOUBLE] * (1.0 - score1), outs, 2 | 4, int(on2) + int(on3))
	else:
		add.call(p[LeagueEnv.Outcome.DOUBLE], outs, 2, int(on2) + int(on3))
	add.call(p[LeagueEnv.Outcome.TRIPLE], outs, 4, runners)
	add.call(p[LeagueEnv.Outcome.HR], outs, 0, runners + 1)
	# Out in play.
	var in_play := p[LeagueEnv.Outcome.OUT]
	var dp := 0.13 if on1 and outs < 2 else 0.0
	if dp > 0.0:
		if outs + 2 >= 3:
			add.call(in_play * dp, 3, 0, 0)
		else:
			# With nobody out a runner on third scores on the double play.
			var runs := 1 if on3 else 0
			add.call(in_play * dp, outs + 2, 4 if on2 else 0, runs)
	var rest := in_play * (1.0 - dp)
	if outs == 2:
		add.call(rest, 3, 0, 0)
		return out
	var s3 := 0.35 if on3 else 0.0
	var a2 := 0.3 if on2 and not on3 else 0.0
	for scores: bool in [true, false]:
		var ps := s3 if scores else 1.0 - s3
		if ps <= 0.0:
			continue
		for moves: bool in [true, false]:
			var pm := a2 if moves else 1.0 - a2
			if pm <= 0.0:
				continue
			var b := bases
			if on3 and scores:
				b &= ~4
			if on2 and moves:
				b = (b & ~2) | 4
			add.call(rest * ps * pm, outs + 1, b, 1 if scores else 0)
	return out


func _build_runs() -> void:
	_runs.clear()
	for i: int in 24:
		var d := PackedFloat64Array()
		d.resize(MAX_RUNS + 1)
		_runs.append(d)
	# Two outs first: an out ends the half; then one out, then none.
	for outs: int in [2, 1, 0]:
		for iteration: int in ITERATIONS:
			for bases: int in 8:
				var d := PackedFloat64Array()
				d.resize(MAX_RUNS + 1)
				for t: PackedFloat64Array in transitions(outs, bases):
					var o := int(t[1])
					var r := int(t[3])
					if o >= 3:
						d[mini(r, MAX_RUNS)] += t[0]
						continue
					var next := _runs[o * 8 + int(t[2])]
					for k: int in MAX_RUNS + 1:
						if next[k] > 0.0:
							d[mini(k + r, MAX_RUNS)] += t[0] * next[k]
				_runs[outs * 8 + bases] = d


## Probability of 0..MAX_RUNS more runs in the half-inning from here.
func runs_to_come(outs: int, bases: int) -> PackedFloat64Array:
	return _runs[clampi(outs, 0, 2) * 8 + (bases & 7)]


## Average runs to come (the run expectancy table).
func run_expectancy(outs: int, bases: int) -> float:
	var d := runs_to_come(outs, bases)
	var total := 0.0
	for k: int in d.size():
		total += k * d[k]
	return total


# --- Games ---


## The home team's chance of winning at the start of a half-inning with the home side
## `diff` runs ahead.
func at_half(inning: int, top: bool, diff: int) -> float:
	if diff > MAX_DIFF:
		return 1.0
	if diff < -MAX_DIFF:
		return 0.0
	var key := (inning * 2 + (0 if top else 1)) * 100 + diff + 50
	if _half.has(key):
		return _half[key]
	var d := runs_to_come(0, 0)
	var total := 0.0
	for k: int in d.size():
		total += d[k] * (_after_top(inning, diff - k) if top else _after_bottom(inning, diff + k))
	_half[key] = total
	return total


func _after_top(inning: int, diff: int) -> float:
	if inning >= innings and diff > 0:
		return 1.0
	return at_half(inning, false, diff)


func _after_bottom(inning: int, diff: int) -> float:
	if inning < innings:
		return at_half(inning + 1, true, diff)
	if diff > 0:
		return 1.0
	if diff < 0:
		return 0.0
	if inning >= extra_limit:
		return 0.5
	return at_half(inning + 1, true, 0)


## The home team's chance of winning now: inning, half, home lead, outs and bases (bit 1
## first, 2 second, 4 third).
func home_win(inning: int, top: bool, diff: int, outs: int, bases: int) -> float:
	if outs >= 3:
		return _after_top(inning, diff) if top else _after_bottom(inning, diff)
	var d := runs_to_come(outs, bases)
	var total := 0.0
	for k: int in d.size():
		if d[k] <= 0.0:
			continue
		total += d[k] * (_after_top(inning, diff - k) if top else _after_bottom(inning, diff + k))
	return total


func for_state(state: GameState) -> float:
	return home_win(state.inning, state.top, state.score[1] - state.score[0], state.outs, bases_of(state))


static func bases_of(state: GameState) -> int:
	var b := 0
	for i: int in 3:
		if not state.base_empty(i + 1):
			b |= 1 << i
	return b


# --- Leverage ---


## Expected change in the home team's win chance over the coming plate appearance.
func swing(inning: int, top: bool, diff: int, outs: int, bases: int) -> float:
	var key := (((inning * 2 + (0 if top else 1)) * 100 + clampi(diff, -49, 49) + 50) * 3 + outs) * 8 + bases
	if _raw.has(key):
		return _raw[key]
	var now := home_win(inning, top, diff, outs, bases)
	var total := 0.0
	for t: PackedFloat64Array in transitions(outs, bases):
		var runs := int(t[3])
		var after_diff := diff - runs if top else diff + runs
		var o := int(t[1])
		var next := home_win(inning, top, after_diff, o, int(t[2]) if o < 3 else 0)
		total += t[0] * absf(next - now)
	_raw[key] = total
	return total


## Leverage index of the coming plate appearance: 1 is ordinary, HIGH and up a key moment.
func leverage(inning: int, top: bool, diff: int, outs: int, bases: int) -> float:
	if _norm <= 0.0:
		_norm = _average_swing()
	return swing(inning, top, diff, outs, bases) / _norm


func leverage_of(state: GameState) -> float:
	return leverage(state.inning, state.top, state.score[1] - state.score[0], state.outs, bases_of(state))


## The average swing over the plate appearances of games played out through the chain (a
## fixed seed, so it is always the same number).
func _average_swing(games: int = 400) -> float:
	var rng := Rng.new(1234)
	var total := 0.0
	var count := 0
	for g: int in games:
		var inning := 1
		var top := true
		var diff := 0
		var outs := 0
		var bases := 0
		var guard := 0
		while guard < 400:
			guard += 1
			total += swing(inning, top, diff, outs, bases)
			count += 1
			var options := transitions(outs, bases)
			var weights := PackedFloat64Array()
			for t: PackedFloat64Array in options:
				weights.append(t[0])
			var t := options[rng.pick_weighted(weights)]
			var runs := int(t[3])
			diff += -runs if top else runs
			outs = int(t[1])
			bases = int(t[2])
			if not top and inning >= innings and diff > 0:
				break
			if outs >= 3:
				outs = 0
				bases = 0
				if top:
					if inning >= innings and diff > 0:
						break
					top = false
				else:
					if inning >= innings and (diff != 0 or inning >= extra_limit):
						break
					top = true
					inning += 1
	return total / maxi(count, 1)
