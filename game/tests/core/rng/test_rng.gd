extends GutTest
## Expected values come from an independent PCG32 implementation (and, for seed 42 / stream 54,
## match the reference output published with the PCG library).


func test_matches_reference_sequence_seed_42_stream_54() -> void:
	var rng := Rng.new(42, 54)
	var expected: Array[int] = [0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b, 0xcbed606e]
	for value: int in expected:
		assert_eq(rng.next_u32(), value)


func test_matches_reference_sequence_other_seeds() -> void:
	var zero := Rng.new(0, 0)
	for value: int in [3837872008, 932996374, 1548399547, 1612522464] as Array[int]:
		assert_eq(zero.next_u32(), value)
	var dated := Rng.new(20261120, 7)
	for value: int in [4072683277, 688676395, 2415838184, 2436398546] as Array[int]:
		assert_eq(dated.next_u32(), value)


func test_same_seed_gives_same_sequence_and_different_seed_differs() -> void:
	var a := Rng.new(123, 1)
	var b := Rng.new(123, 1)
	var c := Rng.new(124, 1)
	var same := true
	var differs := false
	for i: int in 50:
		var x := a.next_u32()
		same = same and x == b.next_u32()
		differs = differs or x != c.next_u32()
	assert_true(same, "identical seeds must agree")
	assert_true(differs, "different seeds must diverge")


func test_floats_stay_in_unit_interval_with_mean_near_half() -> void:
	var rng := Rng.new(7)
	var total := 0.0
	var in_range := true
	for i: int in 20000:
		var x := rng.next_float()
		in_range = in_range and x >= 0.0 and x < 1.0
		total += x
	assert_true(in_range, "next_float() must be in [0, 1)")
	assert_almost_eq(total / 20000.0, 0.5, 0.01)


func test_next_int_covers_range_evenly() -> void:
	var rng := Rng.new(99)
	var counts: Array[int] = [0, 0, 0, 0, 0, 0]
	for i: int in 60000:
		counts[rng.next_int(6)] += 1
	for c: int in counts:
		assert_between(c, 9600, 10400, "each face of a die about one sixth")


func test_next_int_range_includes_both_ends() -> void:
	var rng := Rng.new(5)
	var low_seen := false
	var high_seen := false
	var ok := true
	for i: int in 2000:
		var v := rng.next_int_range(3, 7)
		ok = ok and v >= 3 and v <= 7
		low_seen = low_seen or v == 3
		high_seen = high_seen or v == 7
	assert_true(ok and low_seen and high_seen)


func test_normal_has_zero_mean_and_unit_deviation() -> void:
	var rng := Rng.new(2026)
	var n := 40000
	var sum := 0.0
	var sum_sq := 0.0
	for i: int in n:
		var x := rng.next_normal()
		sum += x
		sum_sq += x * x
	var mean := sum / n
	assert_almost_eq(mean, 0.0, 0.02)
	assert_almost_eq(sqrt(sum_sq / n - mean * mean), 1.0, 0.02)


func test_pick_weighted_follows_weights() -> void:
	var rng := Rng.new(11)
	var weights := PackedFloat64Array([1.0, 3.0, 0.0, 6.0])
	var counts: Array[int] = [0, 0, 0, 0]
	for i: int in 20000:
		counts[rng.pick_weighted(weights)] += 1
	assert_eq(counts[2], 0, "zero weight is never picked")
	assert_between(counts[0], 1800, 2200)
	assert_between(counts[1], 5700, 6300)
	assert_between(counts[3], 11700, 12300)
	assert_eq(rng.pick_weighted(PackedFloat64Array([0.0, 0.0])), -1)


func test_fork_is_independent_of_how_much_the_parent_was_used() -> void:
	var fresh := Rng.new(555)
	var used := Rng.new(555)
	for i: int in 37:
		used.next_u32()
	var a := fresh.fork(3)
	var b := used.fork(3)
	for i: int in 10:
		assert_eq(a.next_u32(), b.next_u32())


func test_forks_with_different_keys_differ() -> void:
	var parent := Rng.new(555)
	var a := parent.fork(1)
	var b := parent.fork(2)
	var differs := false
	for i: int in 10:
		differs = differs or a.next_u32() != b.next_u32()
	assert_true(differs)


func test_state_round_trip_resumes_the_sequence() -> void:
	var rng := Rng.new(31337, 9)
	for i: int in 12:
		rng.next_u32()
	var saved := rng.get_state()
	var expected: Array[int] = []
	for i: int in 5:
		expected.append(rng.next_u32())
	var restored := Rng.new()
	restored.set_state(saved)
	for value: int in expected:
		assert_eq(restored.next_u32(), value)
