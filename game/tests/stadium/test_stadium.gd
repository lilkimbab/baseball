extends GutTest
## Ballparks (docs/13 S13): four made-up parks from their definitions, built to match their
## physics, with the sun where parks are built to have it and the light of the time of day.


func test_four_parks_load_and_their_physics_matches_their_fence() -> void:
	var ids := StadiumIO.ids()
	assert_gte(ids.size(), 14, "park models enough to tell thirty clubs' homes apart")
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
		for part: String in ["Ground", "Fence", "HomeRunLine", "BackstopNet", "BattersEye", "Seats", "StandWalls", "Scoreboard", "Ads"]:
			assert_not_null(park.find_child(part, false, false), "%s has %s" % [id, part])
		assert_eq(_named(park, "Dugout"), 2, "%s: a dugout on each side" % id)
		assert_eq(_named(park, "Mound"), 5, "%s: the field's mound and four in the bullpens" % id)
		if id == "galaxy_dome":
			assert_not_null(park.find_child("Dome", false, false))
		else:
			assert_eq(_named(park, "LampFrame"), 6, "six light towers")
		# The distance signs say what the fence is.
		var signs := park.find_children("*", "Label3D", false, false)
		assert_eq(signs.size(), 5)
		assert_eq((signs[2] as Label3D).text, str(roundi(park.fence.distance_at(0.0))))


func test_season_games_are_played_at_their_hour() -> void:
	# Tuesday to Friday at night, Saturday at 17:00, Sunday at 14:00; Monday off.
	var times: Array[StringName] = []
	for game_day: int in 7:
		times.append(MatchScene.time_for(game_day))
	assert_eq(times, [&"night", &"night", &"night", &"night", &"dusk", &"day", &"night"] as Array[StringName])
	assert_true(StadiumIO.ids().has(MatchScene.home_park("SSG")), "every club has one of the parks")
	assert_eq(MatchScene.home_park("SSG"), MatchScene.home_park("SSG"), "and always the same one")


func test_the_ad_boards_are_made_up_sponsors() -> void:
	var sponsors := AdStrip.load_sponsors()
	assert_gte(sponsors.size(), 8)
	for s: Dictionary in sponsors:
		assert_true(str(s["name"]).length() >= 2)
		assert_true(Color.html_is_valid(str(s["bg"])) and Color.html_is_valid(str(s["fg"])))


func test_every_club_has_a_home_of_its_own() -> void:
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	var seen := {}
	var settings := {}
	var models := {}
	for t: Team in clubs:
		var def := MatchScene.home_def(t)
		assert_true(Backdrop.KINDS.has(def.backdrop) or def.backdrop == &"none", "%s: %s" % [t.id, def.backdrop])
		seen["%s|%s" % [MatchScene.home_park(t.id), def.backdrop]] = true
		settings[def.backdrop] = true
		models[MatchScene.home_park(t.id)] = true
		assert_eq(def.place_seed, t.id, "laid out from the club")
	assert_gte(Backdrop.KINDS.size(), 10, "kinds of setting")
	assert_gte(models.size(), 10, "the clubs use many models")
	assert_gte(settings.size(), 9, "and many settings")
	assert_gte(seen.size(), clubs.size() - 4, "hardly any two the same")


func test_every_setting_builds_round_a_park() -> void:
	for kind: StringName in Backdrop.KINDS:
		var def := StadiumIO.load_park("harbor_field")
		def.backdrop = kind
		var park := StadiumBuilder.new(def)
		add_child_autofree(park)
		assert_not_null(park.backdrop, kind)
		assert_gt(park.backdrop.get_child_count(), 2, "%s has things in it" % kind)
		park.set_lights(true, 1.0)
