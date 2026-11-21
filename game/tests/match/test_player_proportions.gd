extends GutTest
## The player's body against the tables (docs/12 section 4). tools/blender/anthropometry.py
## measures every build as it is made and leaves the numbers beside the model; these tests hold
## them to what a ballplayer measures (US Army ANSUR II men, the upper part of its range for
## girths). The user: "the head and the body look out of proportion ... the neck looks short".

const MODEL_HEIGHT := 1.83


func _numbers(build: StringName) -> Dictionary:
	var path := SkinnedPuppet.model_for(build).get_basename() + "_measure.json"
	return JsonIO.read_object(path)


## A measurement of a build as a share of its height.
func _share(d: Dictionary, name: String) -> float:
	return float(d[name]) / float(d["stature"])


## A measurement in metres on the model scaled to 1.83 m.
func _at_height(d: Dictionary, name: String) -> float:
	return float(d[name]) * MODEL_HEIGHT / float(d["stature"])


func test_every_build_was_measured() -> void:
	for build: StringName in [&"lean", &"standard", &"solid", &"heavy"]:
		assert_false(_numbers(build).is_empty(), "%s: run ./dev model" % build)


func test_the_head_is_a_grown_mans_size() -> void:
	for build: StringName in [&"lean", &"standard", &"solid", &"heavy"]:
		var d := _numbers(build)
		assert_between(float(d["heads_tall"]), 7.5, 8.0, "%s: head-heights to the body" % build)
		assert_between(_at_height(d, "head_girth"), 0.565, 0.6, "%s: round the head (m)" % build)
		assert_between(_at_height(d, "head_breadth"), 0.15, 0.165, "%s: head breadth" % build)
		assert_between(_at_height(d, "head_length"), 0.19, 0.213, "%s: head front to back" % build)


func test_the_neck_is_as_long_and_as_thick_as_an_athletes() -> void:
	for build: StringName in [&"lean", &"standard", &"solid"]:
		var d := _numbers(build)
		# The chin of a standing man is about 8 cm above the tops of his shoulders.
		assert_between(_share(d, "chin_above_shoulders"), 0.038, 0.056, "%s: chin above the shoulders" % build)
		assert_between(_share(d, "menton_height"), 0.86, 0.876, "%s: height of the chin" % build)
	assert_gt(_share(_numbers(&"heavy"), "chin_above_shoulders"), 0.032, "a heavy man's neck is shorter, not gone")
	assert_between(_at_height(_numbers(&"standard"), "neck_girth"), 0.395, 0.43, "round the neck")
	assert_gt(_at_height(_numbers(&"heavy"), "neck_girth"), _at_height(_numbers(&"lean"), "neck_girth") + 0.03)


func test_the_standard_build_measures_as_a_ballplayer() -> void:
	var d := _numbers(&"standard")
	assert_between(_share(d, "shoulder_breadth"), 0.29, 0.315, "across the shoulders")
	assert_between(_share(d, "shoulder_joints"), 0.19, 0.23, "between the shoulder joints")
	assert_between(_share(d, "chest_girth"), 0.575, 0.625, "round the chest")
	assert_between(_share(d, "waist_girth"), 0.455, 0.5, "round the waist (not a dancer's)")
	assert_between(_share(d, "seat_girth"), 0.525, 0.59, "round the seat")
	assert_between(_share(d, "upper_arm_girth"), 0.18, 0.205, "round the upper arm")
	assert_between(_share(d, "forearm_girth"), 0.16, 0.18, "round the forearm")
	assert_between(_share(d, "wrist_girth"), 0.094, 0.104, "round the wrist")
	assert_between(_share(d, "thigh_girth"), 0.345, 0.375, "round the thigh")
	assert_between(_share(d, "calf_girth"), 0.215, 0.235, "round the calf")
	assert_between(_share(d, "ankle_girth"), 0.122, 0.134, "round the ankle")
	assert_between(_share(d, "foot_length"), 0.148, 0.158, "foot")


func test_the_builds_weigh_what_their_names_say() -> void:
	# At 1.83 m, from the body's volume: lean 80 kg, standard 89, solid 96, heavy 106.
	var want := {&"lean": [76.0, 84.0], &"standard": [85.0, 92.0], &"solid": [92.5, 100.0], &"heavy": [101.0, 111.0]}
	for build: StringName in want:
		var mass := float(_numbers(build)["mass_at_183"])
		assert_between(mass, float(want[build][0]), float(want[build][1]), "%s weighs %.1f kg" % [build, mass])
	# A heavy man is thick in the trunk, not a bodybuilder in the arms.
	var heavy := _numbers(&"heavy")
	assert_gt(_share(heavy, "waist_girth"), 0.52, "heavy: waist")
	assert_lt(_share(heavy, "upper_arm_girth"), 0.245, "heavy: upper arm")
