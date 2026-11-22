extends GutTest
## Uniform lettering and trim (docs/13 S11-9; the user: "bring in the number and letter faces
## real ballplayers wear ... it looks made by an AI").


func _clubs() -> Array[Team]:
	return RosterIO.load_pack(LeagueSession.PACK)


func _is_latin(text: String) -> bool:
	for i: int in text.length():
		if text.unicode_at(i) > 0x24F:
			return false
	return text != ""


func test_the_four_kinds_of_lettering_are_there() -> void:
	for kind: StringName in [&"block", &"tuscan", &"script", &"name", &"name_square"]:
		assert_not_null(UniformFonts.face(kind), "%s face" % kind)
	assert_true(UniformFonts.face(&"name").has_char("배".unicode_at(0)), "the name face has Korean letters")
	assert_true(UniformFonts.face(&"block").has_char("7".unicode_at(0)), "the block face has numbers")


func test_letters_are_sized_by_their_capitals() -> void:
	for kind: StringName in [&"block", &"tuscan", &"script", &"name"]:
		assert_between(UniformArt.cap_ratio(UniformFonts.face(kind)), 0.45, 1.05, "%s: a capital's share of the font size" % kind)
	assert_almost_eq(UniformArt.BACK_NUMBER, 0.2032, 0.001, "8 in on the back")
	assert_almost_eq(UniformArt.FRONT_NUMBER, 0.1016, 0.001, "4 in on the front")


func test_every_club_wears_its_nickname_at_home_and_its_town_away() -> void:
	var seen := {}
	var kinds := {}
	for t: Team in _clubs():
		var home := UniformStyle.for_team(t, true)
		var away := UniformStyle.for_team(t, false)
		assert_true(_is_latin(home.wordmark), "%s at home: %s" % [t.name, home.wordmark])
		assert_true(_is_latin(away.wordmark), "%s away: %s" % [t.name, away.wordmark])
		assert_ne(home.wordmark.to_lower(), away.wordmark.to_lower(), "%s: nickname at home, town away" % t.name)
		assert_true(_is_latin(home.cap_letter) and home.cap_letter.length() == 1, "%s: a letter on the cap" % t.name)
		assert_true(home.lettering in [&"block", &"tuscan", &"script"], "a known kind of lettering")
		assert_ne(away.lettering, &"script", "road jerseys carry block letters")
		seen[home.wordmark] = true
		kinds[home.lettering] = true
		# Lettering stands out from the cloth it is on.
		assert_gt(absf(home.ink.get_luminance() - home.jersey.get_luminance()), 0.25, "%s home lettering shows" % t.name)
		assert_gt(absf(away.ink.get_luminance() - away.jersey.get_luminance()), 0.2, "%s away lettering shows" % t.name)
	assert_eq(seen.size(), _clubs().size(), "no two clubs share a nickname")
	assert_eq(kinds.size(), 3, "all three kinds of lettering are worn in the league")


func test_a_clubs_uniform_is_the_same_every_time_and_copies_whole() -> void:
	var t := _clubs()[4]
	var a := UniformStyle.for_team(t, true)
	var b := UniformStyle.for_team(t, true)
	assert_eq(a.wordmark, b.wordmark)
	assert_eq(a.lettering, b.lettering)
	assert_eq(a.sleeve_bands, b.sleeve_bands)
	a.number = 27
	a.player_name = "한도윤"
	var c := a.copy()
	assert_eq(c.wordmark, a.wordmark)
	assert_eq(c.lettering, a.lettering)
	assert_eq(c.outline, a.outline)
	assert_eq(c.piping, a.piping)
	assert_eq(c.sleeve_sponsor, a.sleeve_sponsor)
	assert_eq(c.number, 27)
	c.number = 3
	assert_eq(a.number, 27, "a copy is its own")


func test_the_painter_is_told_where_the_sleeves_and_the_chest_are() -> void:
	var puppet := SkinnedPuppet.new()
	puppet.uniform = UniformStyle.for_team(_clubs()[0], true)
	add_child_autofree(puppet)
	puppet.repaint()
	var jersey := puppet.find_child("Jersey", true, false) as MeshInstance3D
	var art := jersey.get_node("Art").get_child(0) as UniformArt
	assert_eq(art.sleeves.size(), 2, "two sleeves")
	for sleeve: Dictionary in art.sleeves:
		assert_between(float(sleeve["hem"]), 0.1, 0.22, "the sleeve ends at mid-biceps")
		assert_gt((sleeve["along"] as Vector2).y, 0.3, "the arm runs down the jersey")
	assert_gt((art.sleeves[0]["shoulder"] as Vector2).x, (art.sleeves[1]["shoulder"] as Vector2).x, "wearer's left first")
	assert_between(art.neck_point, 0.08, 0.2, "the point of the V below the top of the jersey")
	assert_between(art.chest, art.neck_point + 0.06, 0.34, "the chest line below it")


func test_piping_down_the_trousers_is_a_strip_on_the_side_seam() -> void:
	var with_piping: Team = null
	var without: Team = null
	for t: Team in _clubs():
		if UniformStyle.for_team(t, true).pants_stripe:
			with_piping = t
		else:
			without = t
	assert_not_null(with_piping, "some clubs wear piping")
	assert_not_null(without, "and some do not")
	for t: Team in [with_piping, without]:
		var puppet := SkinnedPuppet.new()
		puppet.uniform = UniformStyle.for_team(t, true)
		add_child_autofree(puppet)
		puppet.repaint()
		var stripe := puppet.find_child("PantsStripe", true, false) as MeshInstance3D
		assert_not_null(stripe, "the model has the strip (run ./dev model)")
		if stripe == null:
			continue
		assert_eq(stripe.visible, puppet.uniform.pants_stripe)
		# Down the outside of both legs, from under the belt to the hem.
		var pants := puppet.find_child("Pants", true, false) as MeshInstance3D
		var box := stripe.get_aabb()
		assert_gt(box.size.y, pants.get_aabb().size.y * 0.85, "the length of the leg")
		assert_gt(box.size.x, pants.get_aabb().size.x * 0.8, "on the outer sides")


func test_umpires_dress_as_umpires() -> void:
	var style := UniformStyle.for_official(27)
	assert_true(style.official)
	assert_lt(style.jersey.get_luminance(), 0.15, "a black polo shirt")
	assert_between(style.pants.get_luminance(), 0.15, 0.4, "charcoal trousers")
	assert_eq(style.undershirt, style.jersey, "the shirt's own cloth in the opening of its collar")
	assert_eq(style.cap_letter, UniformStyle.LEAGUE, "the league's initials on his cap")
	assert_eq(style.wordmark, "", "no club's name")
	assert_eq(style.number, 27, "his number, worn on the sleeve")
	for at_the_plate: bool in [true, false]:
		var puppet := SkinnedPuppet.new()
		add_child_autofree(puppet)
		puppet.uniform = style.copy()
		puppet.gear = (SkinnedPuppet.PLATE_UMPIRE_GEAR if at_the_plate else SkinnedPuppet.UMPIRE_GEAR).duplicate()
		puppet.headgear = &"none" if at_the_plate else &"cap"
		puppet.repaint()
		puppet.apply(PuppetClips.umpire())
		var shown := func(part: String) -> bool:
			var node := puppet.find_child(part, true, false) as MeshInstance3D
			return node != null and node.visible
		assert_true(shown.call("PoloCollar"), "a polo shirt's collar")
		assert_eq(shown.call("Mask"), at_the_plate, "the mask behind the plate only")
		assert_eq(shown.call("BallBags"), at_the_plate, "the ball bags behind the plate only")
		assert_eq(shown.call("UmpireCap"), at_the_plate, "the short-billed cap under the mask")
		assert_eq(shown.call("Cap"), not at_the_plate, "the ordinary cap on the bases")
		assert_false(shown.call("ChestProtector"), "none of the catcher's gear")
		# Black shoes, soles and all.
		var shoes := puppet.find_child("Shoes", true, false) as MeshInstance3D
		for surface: int in shoes.mesh.get_surface_count():
			var m := shoes.get_surface_override_material(surface) as StandardMaterial3D
			assert_lt(m.albedo_color.get_luminance(), 0.12, "black shoes")
	# The plate umpire's cap has a bill half as long as a player's.
	var model := SkinnedPuppet.new()
	add_child_autofree(model)
	var cap := model.find_child("Cap", true, false) as MeshInstance3D
	var short := model.find_child("UmpireCap", true, false) as MeshInstance3D
	assert_not_null(short, "run ./dev model")
	if short != null:
		assert_lt(short.get_aabb().end.z, cap.get_aabb().end.z - 0.025, "a shorter bill")


func test_each_player_wears_his_uniform_his_own_way() -> void:
	var seen := {"sleeves": 0, "socks": 0, "elbow": 0, "leg": 0}
	var puppet := SkinnedPuppet.new()
	puppet.uniform = UniformStyle.for_team(_clubs()[0], true)
	add_child_autofree(puppet)
	for i: int in 40:
		puppet.set_face("p%05d" % (i + 1))
		seen["sleeves"] += int(puppet.long_sleeves)
		seen["socks"] += int(puppet.high_socks)
		seen["elbow"] += int(puppet.guards.has(&"ElbowGuard"))
		seen["leg"] += int(puppet.guards.has(&"LegGuard"))
	for what: String in seen:
		assert_between(int(seen[what]), 4, 34, "some players and not all: %s" % what)
	# The same player, the same way every time.
	puppet.set_face("p00007")
	var first := [puppet.long_sleeves, puppet.high_socks, puppet.guards.duplicate()]
	puppet.set_face("p00012")
	puppet.set_face("p00007")
	assert_eq([puppet.long_sleeves, puppet.high_socks, puppet.guards.duplicate()], first)


func test_guards_go_with_the_helmet_and_trousers_to_the_knee_show_the_socks() -> void:
	var puppet := SkinnedPuppet.new()
	puppet.uniform = UniformStyle.for_team(_clubs()[0], true)
	add_child_autofree(puppet)
	puppet.guards.assign(SkinnedPuppet.BATTER_GUARDS)
	puppet.high_socks = true
	puppet.repaint()
	var elbow := puppet.find_child("ElbowGuard", true, false) as MeshInstance3D
	var leg := puppet.find_child("LegGuard", true, false) as MeshInstance3D
	assert_not_null(elbow, "run ./dev model")
	if elbow == null:
		return
	puppet.headgear = &"cap"
	puppet.apply(PuppetClips.fielder_ready())
	assert_false(elbow.visible or leg.visible, "no guards in the field")
	puppet.headgear = &"helmet"
	puppet.apply(PuppetClips.stance())
	assert_true(elbow.visible and leg.visible, "worn at bat")
	# The guards are on the front arm and leg (the model's left; a left-hander's is mirrored).
	assert_gt(elbow.get_aabb().get_center().x, 0.1, "the left arm")
	assert_gt(leg.get_aabb().get_center().x, 0.02, "the left leg")
	# Trousers to the knee: cut away below it, the calves under them dressed as socks.
	var pants := puppet.find_child("Pants", true, false) as MeshInstance3D
	var cloth := pants.get_surface_override_material(0) as StandardMaterial3D
	assert_eq(cloth.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
	var art := pants.get_node("Art").get_child(0) as UniformArt
	assert_true(art.clip_contents)
	assert_between(art.size.y / float((pants.get_node("Art") as SubViewport).size.y), 0.4, 0.7, "cut a little below the knee")
	var body := puppet.find_child("Body", true, false) as MeshInstance3D
	var socks := -1
	for surface: int in body.mesh.get_surface_count():
		if body.mesh.surface_get_material(surface).resource_name == "Socks":
			socks = surface
	var top := -INF
	for v: Vector3 in body.mesh.surface_get_arrays(socks)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		top = maxf(top, v.y)
	assert_gt(top, 0.4, "the socks go up to the knee under the trousers")
	# An umpire wears his as they are made.
	puppet.uniform = UniformStyle.for_official(12)
	puppet.repaint()
	assert_false(puppet.high_socks or puppet.long_sleeves)
