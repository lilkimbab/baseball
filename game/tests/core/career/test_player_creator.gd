extends GutTest
## Making the career player.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _spec(position: String, type_id: String) -> PlayerCreator.Spec:
	var s := PlayerCreator.Spec.new()
	s.name = "한신인"
	s.number = 7
	s.position = position
	s.type_id = type_id
	return s


func test_every_type_starts_strong_where_it_should() -> void:
	var r := CareerIO.load_default()
	assert_eq(r.batter_types.size(), 5)
	assert_eq(r.pitcher_types.size(), 5)
	assert_eq(r.positions.size(), 11)
	var contact := PlayerCreator.create(_spec("2B", "contact"), r, F.catalog()).player
	var power := PlayerCreator.create(_spec("1B", "power"), r, F.catalog()).player
	var speed := PlayerCreator.create(_spec("CF", "speed"), r, F.catalog()).player
	var glove := PlayerCreator.create(_spec("SS", "defence"), r, F.catalog()).player
	assert_gt(contact.batting.contact(), power.batting.contact())
	assert_gt(power.batting.power(), contact.batting.power())
	assert_gt(speed.batting.speed, power.batting.speed)
	assert_gt(glove.fielding.range, contact.fielding.range)
	assert_eq(glove.primary_position(), Position.Kind.SS)
	# A rookie: second-team level.
	assert_between(ClubRules.player_ovr(contact, F.overall(), F.catalog()), 30.0, 55.0)


func test_pitcher_types_bring_their_pitches() -> void:
	var r := CareerIO.load_default()
	var power_arm := PlayerCreator.create(_spec("SP", "power_arm"), r, F.catalog())
	var finesse := PlayerCreator.create(_spec("RP", "finesse"), r, F.catalog())
	var closer := PlayerCreator.create(_spec("CL", "control"), r, F.catalog())
	assert_true(power_arm.is_pitcher())
	assert_eq(power_arm.player.role(), &"SP")
	assert_eq(closer.player.role(), &"RP")
	assert_eq(closer.position, "CL")
	assert_gt(power_arm.player.pitching.fastball_speed(), finesse.player.pitching.fastball_speed())
	# A young pitcher starts with two pitches and learns more (the user, 2026-11-23).
	assert_eq(finesse.player.pitching.arsenal.size(), 2)
	assert_gt(power_arm.player.pitching.stamina, finesse.player.pitching.stamina, "a starter has more stamina")
	var usage := 0.0
	for a: ArsenalPitch in finesse.player.pitching.arsenal:
		usage += a.usage
	assert_almost_eq(usage, 1.0, 1e-6)


func test_a_rookie_joins_the_second_team() -> void:
	var r := CareerIO.load_default()
	var c := PlayerCreator.create(_spec("SS", "all_round"), r, F.catalog())
	var team := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), 3).team(0, 50.0)
	c.join(team)
	assert_eq(c.team_id, team.id)
	assert_not_null(team.player(c.player.id))
	assert_false(team.is_registered(c.player.id))
	assert_false(c.first_team)
