extends GutTest
## Line-ups and substitutions: who may play, no re-entry, and the designated hitter rules
## (docs/13 S4-3).

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _team(dh: bool = true) -> TeamInGame:
	var rules := RuleSet.kbo_2026()
	rules.designated_hitter = dh
	return F.game(rules).teams[0]


func test_the_computer_manager_builds_a_legal_lineup() -> void:
	for seed_value: int in [1, 2, 3, 4, 5] as Array[int]:
		var state := F.game(null, seed_value)
		for t: TeamInGame in state.teams:
			assert_eq(t.validate(true), PackedStringArray(), "seed %d %s" % [seed_value, t.name])


func test_problems_are_reported_in_words() -> void:
	var t := _team()
	t.lineup[1].player_id = t.lineup[0].player_id
	var problems := t.validate(true)
	assert_gt(problems.size(), 0)
	assert_string_contains(" ".join(problems), "두 번")


func test_a_left_hander_cannot_play_shortstop() -> void:
	var t := _team()
	var ss := t.slot_of(t.fielder_at(Position.Kind.SS))
	t.player(t.lineup[ss].player_id).throws = &"L"
	assert_string_contains(" ".join(t.validate(true)), "유격수")


func test_a_player_taken_out_cannot_come_back() -> void:
	var t := _team()
	var original := t.lineup[3].player_id
	t.pinch(3, t.bench[0])
	assert_true(t.removed.has(original))
	assert_false(t.is_available(original))
	t.lineup[5].player_id = original
	assert_string_contains(" ".join(t.validate()), "교체된")


func test_pinch_hitters_must_be_given_a_position_before_the_team_takes_the_field() -> void:
	var t := _team()
	t.pinch(2, t.bench[0])
	assert_eq(t.validate(), PackedStringArray(), "fine while batting")
	assert_gt(t.validate(true).size(), 0, "not fine on defence")
	var ai := F.manager()
	var state := F.game()
	state.teams[0] = t
	state.top = false
	var fix := ai.next_change(state)
	assert_not_null(fix)
	GameFlow.apply(state, fix)
	assert_eq(t.validate(true), PackedStringArray())


func test_moving_the_designated_hitter_into_the_field_ends_the_dh() -> void:
	var t := _team()
	var dh_slot := -1
	for i: int in t.lineup.size():
		if t.lineup[i].position == Position.Kind.DH:
			dh_slot = i
	var dh := t.lineup[dh_slot].player_id
	var left_fielder := t.fielder_at(Position.Kind.LF)
	t.move(dh, Position.Kind.LF)
	assert_false(t.dh_active)
	assert_true(t.removed.has(left_fielder), "the left fielder he replaced is out")
	assert_gt(t.slot_of(t.pitcher_id), -1, "the pitcher now bats, in the left fielder's place")
	assert_eq(t.validate(true), PackedStringArray())


func test_moving_the_pitcher_into_the_field_ends_the_dh() -> void:
	var t := _team()
	var old := t.pitcher_id
	var reliever := t.bullpen[0]
	t.pitcher_to_field(Position.Kind.RF, reliever)
	assert_false(t.dh_active)
	assert_eq(t.lineup[t.slot_of(old)].position, Position.Kind.RF, "the old pitcher plays right field")
	assert_gt(t.slot_of(reliever), -1, "the new pitcher bats")
	assert_eq(t.pitcher_id, reliever)
	assert_eq(t.lineup.size(), 9)


func test_a_pinch_hitter_who_stays_in_to_pitch_ends_the_dh() -> void:
	var t := _team()
	var pinch := t.bench[0]
	t.player(pinch).pitching = PitchingRatings.new()
	t.pinch(4, pinch)
	t.change_pitcher(pinch)
	assert_false(t.dh_active)
	assert_eq(t.lineup[4].position, Position.Kind.P)
	var dh_left := true
	for slot: LineupSlot in t.lineup:
		if slot.position == Position.Kind.DH:
			dh_left = false
	assert_true(dh_left, "no designated hitter any more")


func test_without_the_dh_a_new_pitcher_bats_in_the_old_pitcher_s_place() -> void:
	var t := _team(false)
	var slot := t.slot_of(t.pitcher_id)
	assert_gt(slot, -1, "the pitcher bats")
	var reliever := t.bullpen[0]
	t.change_pitcher(reliever)
	assert_eq(t.lineup[slot].player_id, reliever)
	assert_eq(t.validate(true), PackedStringArray())


func test_without_the_dh_a_pitcher_batted_for_is_replaced_in_that_place() -> void:
	var t := _team(false)
	var slot := t.slot_of(t.pitcher_id)
	t.pinch(slot, t.bench[0])
	var reliever := t.bullpen[0]
	t.change_pitcher(reliever)
	assert_eq(t.lineup[slot].player_id, reliever)
	assert_eq(t.lineup[slot].position, Position.Kind.P)
	assert_eq(t.validate(true), PackedStringArray())
