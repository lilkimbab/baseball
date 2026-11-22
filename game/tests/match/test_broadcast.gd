extends GutTest
## The broadcast's moments (docs/11 section 6, docs/13 S16): the introduction holds the first
## pitch and can be skipped, each half gets its card with the half just over, a new batter and
## a new pitcher get theirs, the cameras move through their shots, a home run is replayed.

const MATCH := preload("res://match/match.tscn")
const DT := 1.0 / 120.0


func test_segments_keep_time_hold_and_skip() -> void:
	var b := Broadcast.new()
	var seg := Broadcast.segment(Broadcast.Kind.HALF)
	seg.shots = [Broadcast.Shot.make(0.0, Vector3(0, -10, 10), Vector3(0, 40, 0), 50.0, Vector3(0, -20, 10), Vector3(0, 40, 0), 40.0)]
	b.push(seg)
	b.push(Broadcast.segment(Broadcast.Kind.BATTER, {}, false))
	assert_true(b.holding())
	var cam := b.camera()
	assert_eq(cam[0], Vector3(0, -10, 10), "starts at its first framing")
	b.step(seg.duration * 0.5)
	cam = b.camera()
	assert_almost_eq(float(cam[2]), 45.0, 1.0, "half way through its move")
	b.step(seg.duration)
	assert_true(b.showing(Broadcast.Kind.BATTER), "the next in line")
	assert_false(b.holding(), "a card over the player's own at-bat does not hold the game")
	b.skip()
	assert_null(b.current)
	b.enabled = false
	b.push(Broadcast.segment(Broadcast.Kind.HALF))
	assert_null(b.current, "nothing when turned off")


func test_a_game_waits_for_its_introduction_then_shows_halves_and_batters() -> void:
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = -1
	scene.innings = 3
	scene.seed_value = 41
	scene.use_motion = false
	add_child_autofree(scene)
	scene.broadcast.enabled = true
	scene._push_pregame()
	assert_true(scene.broadcast.showing(Broadcast.Kind.PREGAME))
	for i: int in roundi(5.0 / DT):
		scene.step(DT)
	assert_eq(scene.state, DuelScene.State.PRE_PITCH, "no pitch while the introduction shows")
	assert_eq(scene.game.pitch_counts.get(scene.game.pitcher_id(), 0), 0)
	scene.refresh(DT)
	assert_false(scene.broadcast.camera().is_empty(), "its own camera")
	scene.broadcast.skip()
	var halves := 0
	var batters := 0
	var summaries := 0
	var seen: Broadcast.Segment = null
	var ticks := 0
	while not scene.game.over and ticks < 400000:
		scene.step(DT)
		if ticks % 4 == 0:
			scene.refresh(DT * 4.0)
		ticks += 1
		var c := scene.broadcast.current
		if c != null and c != seen:
			seen = c
			match c.kind:
				Broadcast.Kind.HALF:
					halves += 1
					if c.data.has("summary"):
						summaries += 1
						assert_string_contains(str(c.data["summary"]), "득점")
				Broadcast.Kind.BATTER:
					batters += 1
					assert_eq(str(c.data["id"]), scene.game.batter_id(), "the man now up")
					assert_gt(scene.broadcast_lines(scene.game.batting_team().player(scene.game.batter_id())).size(), 0)
	assert_true(scene.game.over, "the game still finishes")
	assert_gte(halves, 4, "a card for each half after the first (the last bottom half may not be played)")
	assert_eq(summaries, halves, "each with the half just over")
	assert_gt(batters, 15, "batters introduced")
