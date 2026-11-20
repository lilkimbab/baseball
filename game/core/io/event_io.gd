class_name EventIO
extends RefCounted
## Game events to and from plain dictionaries, for saved games and replays.


static func to_dictionary(e: GameEvent) -> Dictionary:
	var moves: Array = []
	for m: RunnerMove in e.moves:
		var row := [m.from, m.to, m.out_kind, 1 if m.on_error else 0]
		if m.out_at != 0:
			row.append(m.out_at)
		moves.append(row)
	var d := {"k": e.kind}
	match e.kind:
		GameEvent.Kind.PITCH:
			d["c"] = e.call
		GameEvent.Kind.SUBSTITUTION:
			d["t"] = e.team
			d["ch"] = e.change
			d["out"] = e.out_id
			d["in"] = e.in_id
			d["pos"] = e.position
		_:
			d["r"] = e.result
			d["m"] = moves
			d["p"] = e.pitches
			if e.fielders != "":
				d["f"] = e.fielders
			if e.direction != 0:
				d["d"] = e.direction
	return d


static func from_dictionary(d: Dictionary) -> GameEvent:
	var e := GameEvent.new()
	e.kind = int(d.get("k", 0)) as GameEvent.Kind
	e.call = int(d.get("c", 0)) as GameEvent.Call
	e.team = int(d.get("t", 0))
	e.change = int(d.get("ch", 0)) as GameEvent.Change
	e.out_id = str(d.get("out", ""))
	e.in_id = str(d.get("in", ""))
	e.position = int(d.get("pos", 0)) as Position.Kind
	e.result = int(d.get("r", 0)) as PaResult.Kind
	e.pitches = int(d.get("p", 0))
	e.fielders = str(d.get("f", ""))
	e.direction = int(d.get("d", 0))
	var moves: Array = d.get("m", [])
	for m: Array in moves:
		var move := RunnerMove.make(int(m[0]), int(m[1]), int(m[2]) as RunnerMove.OutKind, int(m[3]) == 1)
		move.out_at = int(m[4]) if m.size() > 4 else 0
		e.moves.append(move)
	return e
