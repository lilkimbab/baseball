extends PlayTest
## Thousands of random batted balls in random situations, played through PlaySim and then
## GameFlow: nothing may contradict itself.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func test_random_plays_keep_the_game_consistent() -> void:
	var rng := Rng.new(2468)
	var problems := PackedStringArray()
	for i: int in 3000:
		var bases: Array[int] = []
		for b: int in [1, 2, 3]:
			if rng.chance(0.45):
				bases.append(b)
		var outs := rng.next_int(3)
		var path := _hit(rng.next_range(50.0, 180.0), rng.next_range(-40.0, 70.0), rng.next_range(-50.0, 50.0), rng.next_range(-2500.0, 3500.0))
		var r := _run(path, bases, outs, i)
		var tag := "play %d bases %s outs %d %s" % [i, bases, outs, PaResult.text(r.result)]
		if r.foul:
			if not r.moves.is_empty():
				problems.append(tag + ": a foul moved runners")
			continue
		var seen := {}
		var batter_move: RunnerMove = null
		var made := 0
		for m: RunnerMove in r.moves:
			if seen.has(m.from):
				problems.append(tag + ": runner from %d moved twice" % m.from)
			seen[m.from] = true
			if m.from > 0 and not bases.has(m.from):
				problems.append(tag + ": a move from empty base %d" % m.from)
			if not m.is_out() and m.to <= m.from:
				problems.append(tag + ": runner went backward %d->%d" % [m.from, m.to])
			if m.is_out():
				made += 1
				if m.out_at < 1 or m.out_at > 4:
					problems.append(tag + ": out without a base")
			if m.from == 0:
				batter_move = m
		if batter_move == null:
			problems.append(tag + ": the batter has no move")
			continue
		if PaResult.is_hit(r.result) and batter_move.is_out() and batter_move.out_at <= 1:
			problems.append(tag + ": a hit with the batter out at first")
		if (r.result == PaResult.Kind.GROUND_OUT or r.result == PaResult.Kind.FLY_OUT or r.result == PaResult.Kind.POP_OUT) and not batter_move.is_out():
			problems.append(tag + ": an out with the batter safe")
		if r.result == PaResult.Kind.DOUBLE_PLAY and made < 2:
			problems.append(tag + ": a double play with %d outs" % made)
		# Through the rules: the bases afterwards hold distinct runners.
		var s := F.game()
		s.outs = outs
		F.put_runners(s, bases)
		var e := GameEvent.plate_appearance(r.result, r.moves, 1)
		var out := GameFlow.apply(s, e)
		if s.outs > 3:
			problems.append(tag + ": %d outs" % s.outs)
		if not out.half_over:
			var ids := {}
			for b: int in 3:
				if s.bases[b] != null:
					if ids.has(s.bases[b].player_id):
						problems.append(tag + ": the same runner on two bases")
					ids[s.bases[b].player_id] = true
		# The key frames run forward in time.
		for key: String in r.timeline.tracks:
			var track := r.timeline.tracks[key]
			for k: int in range(1, track.size()):
				if track[k].x < track[k - 1].x:
					problems.append(tag + ": key frames of %s go back in time" % key)
					break
		if problems.size() > 12:
			break
	assert_eq(problems, PackedStringArray())
