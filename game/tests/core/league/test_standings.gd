extends GutTest
## The division table.


func _game(away: String, home: String, a: int, h: int) -> ScheduledGame:
	var g := ScheduledGame.make(0, away, home, 0, 1)
	g.finish(a, h)
	return g


func test_ties_are_left_out_of_the_percentage() -> void:
	var s := Standings.of(PackedStringArray(["a", "b"]))
	s.record(_game("a", "b", 3, 1))
	s.record(_game("a", "b", 2, 2))
	s.record(_game("a", "b", 0, 4))
	s.record(_game("a", "b", 5, 4))
	var a := s.row("a")
	assert_eq([a.wins, a.losses, a.ties], [2, 1, 1])
	# 2 / (2 + 1), not 2 / 4.
	assert_almost_eq(a.pct(), 0.6667, 0.0001)
	assert_eq(a.pct_text(), ".667")
	assert_eq(a.away, Vector3i(2, 1, 1))
	assert_eq(s.row("b").home, Vector3i(1, 2, 1))
	assert_eq(a.runs_for, 10)
	assert_eq(a.streak, 1)
	assert_eq(a.streak_text(), "1연승")


func test_a_club_with_more_ties_can_rank_above_one_with_more_wins() -> void:
	# KBO 2025-style: 10-5 with 3 ties (.667) is ahead of 11-6 (.647).
	var s := Standings.of(PackedStringArray(["x", "y", "z"]))
	for i: int in 10:
		s.record(_game("x", "z", 1, 0))
	for i: int in 5:
		s.record(_game("x", "z", 0, 1))
	for i: int in 3:
		s.record(_game("x", "z", 0, 0))
	for i: int in 11:
		s.record(_game("y", "z", 1, 0))
	for i: int in 6:
		s.record(_game("y", "z", 0, 1))
	var order := s.ranked()
	assert_eq(order[0].team_id, "x")
	assert_eq(order[1].team_id, "y")
	assert_eq(s.rank_of("z"), 3)


func test_level_clubs_are_split_by_their_games_against_each_other() -> void:
	var s := Standings.of(PackedStringArray(["a", "b", "c", "d"]))
	# a and b both 2-2; b won the head-to-head 2-1 though a has the better run difference.
	s.record(_game("a", "b", 1, 2))
	s.record(_game("a", "b", 3, 2))
	s.record(_game("a", "b", 0, 1))
	s.record(_game("a", "c", 20, 0))
	s.record(_game("b", "c", 0, 1))
	s.record(_game("d", "c", 0, 1))
	s.record(_game("d", "c", 0, 1))
	assert_almost_eq(s.row("a").pct(), s.row("b").pct(), 0.0001)
	assert_lt(s.row("b").run_difference(), s.row("a").run_difference())
	var order := s.ranked()
	assert_eq(order[0].team_id, "c")
	assert_eq(order[1].team_id, "b")
	assert_eq(order[2].team_id, "a")
	assert_eq(order[3].team_id, "d")


func test_games_behind_and_last_ten() -> void:
	var s := Standings.of(PackedStringArray(["a", "b"]))
	for i: int in 12:
		s.record(_game("a", "b", 2, 1) if i % 3 != 0 else _game("a", "b", 1, 2))
	# a 8-4, b 4-8: four games behind: (8 − 4 − (4 − 8)) / 2.
	assert_eq(s.games_behind("a"), 0.0)
	assert_eq(s.games_behind("b"), 4.0)
	assert_eq(s.row("a").last_ten.size(), 10)
	assert_eq(s.row("a").last_ten_text(), "7승 3패")
	assert_eq(s.row("b").streak_text(), "2연패")
