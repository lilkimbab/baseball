extends GutTest
## Ballparks (docs/13 S13): four made-up parks from their definitions, built to match their
## physics, with the sun where parks are built to have it and the light of the time of day.


func test_four_parks_load_and_their_physics_matches_their_fence() -> void:
	var ids := StadiumIO.ids()
	assert_eq(ids.size(), 4)
	for id: String in ids:
		var park := StadiumIO.load_park(id)
		assert_eq(park.id, id)
		assert_gte(park.fence_points.size(), 5, id)
		var fence := park.fence()
		var field := park.analytic()
		for az: float in [-45.0, -20.0, 0.0, 20.0, 45.0]:
			var d := fence.distance_at(az)
			assert_between(d, 90.0, 130.0, "%s fence at %d" % [id, int(az)])
			assert_almost_eq(field.boundary_distance(az), d, 1.0, "%s: the ball hits the fence that is drawn" % id)
		assert_almost_eq(field.boundary_distance(180.0), park.backstop, 0.5, "%s backstop" % id)
	assert_eq(StadiumIO.load_park("galaxy_dome").analytic().ground_surface, &"turf", "the dome plays on turf")
	assert_eq(StadiumIO.load_park("no_such_park").id, StadiumIO.DEFAULT)
	assert_eq(StadiumIO.load_park("standard").id, "standard")


func test_the_parks_have_their_character() -> void:
	var big := StadiumIO.load_park("grand_park").fence()
	var small := StadiumIO.load_park("harbor_field").fence()
	assert_gt(big.distance_at(0.0), small.distance_at(0.0) + 5.0, "the big park is deeper")
	var odd := StadiumIO.load_park("lighthouse_park").fence()
	assert_gt(odd.height_at(35.0), 6.5, "a high wall in right")
	assert_lt(odd.distance_at(45.0), odd.distance_at(-45.0) - 4.0, "and a short right-field line")
	assert_almost_eq(StadiumIO.load_park("galaxy_dome").fence().height_at(0.0), 4.0, 0.01)


func test_the_sun_is_never_in_the_batter_s_eyes() -> void:
	# Parks are built so the batter does not face the sun: at 14:00 and at 17:00 it is behind
	# home rather than out beyond centre field.
	for id: String in StadiumIO.ids():
		for time: StringName in [&"day", &"dusk"]:
			var light := ParkLighting.new(StadiumIO.load_park(id), time)
			var dir := light.sun_direction()
			assert_gt(dir.z, 0.0, "%s %s: the sun is up" % [id, time])
			assert_lt(dir.y, 0.0, "%s %s: behind the plate" % [id, time])
			light.free()
	var noon := ParkLighting.sun_position(12.6)
	assert_almost_eq(noon.y, 180.0, 1.0, "due south at solar noon")
	assert_between(noon.x, 60.0, 70.0, "high in the season")
	assert_lt(ParkLighting.sun_position(20.5).x, 0.0, "down by a night game")


func test_the_lights_follow_the_time_and_the_roof() -> void:
	var open := StadiumIO.load_park("grand_park")
	var day := ParkLighting.new(open, &"day")
	var night := ParkLighting.new(open, &"night")
	var dome := ParkLighting.new(StadiumIO.load_park("galaxy_dome"), &"day")
	assert_false(day.lights_on())
	assert_true(night.lights_on())
	assert_true(dome.lights_on() and dome.indoor())
	add_child_autofree(day)
	add_child_autofree(night)
	add_child_autofree(dome)
	assert_not_null(day.sun, "a sun by day")
	assert_null(night.sun, "none at night")
	assert_eq(night.lamps.size(), 4, "the towers light it")
	assert_null(dome.sun, "no sun under a roof")


## Children named `stem` (Godot numbers the repeats: Dugout, Dugout2, ...).
func _named(park: Node, stem: String) -> int:
	var count := 0
	for child: Node in park.get_children():
		var n := String(child.name).replace("@", "")
		if n.begins_with(stem) and n.trim_prefix(stem).is_valid_int() or n == stem:
			count += 1
	return count


func test_a_park_is_built_with_all_its_parts() -> void:
	for id: String in ["grand_park", "galaxy_dome"]:
		var park := StadiumBuilder.new(StadiumIO.load_park(id))
		add_child_autofree(park)
		for part: String in ["Ground", "Fence", "HomeRunLine", "BackstopNet", "BattersEye", "Seats", "StandWalls"]:
			assert_not_null(park.find_child(part, false, false), "%s has %s" % [id, part])
		assert_eq(_named(park, "Dugout"), 2, "%s: a dugout on each side" % id)
		assert_eq(_named(park, "Mound"), 5, "%s: the field's mound and four in the bullpens" % id)
		if id == "galaxy_dome":
			assert_not_null(park.find_child("Dome", false, false))
		else:
			assert_eq(_named(park, "Lamps"), 6, "six light towers")
		# The distance signs say what the fence is.
		var signs := park.find_children("*", "Label3D", false, false)
		assert_eq(signs.size(), 5)
		assert_eq((signs[2] as Label3D).text, str(roundi(park.fence.distance_at(0.0))))
