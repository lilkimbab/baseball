extends GutTest
## Club management (docs/13 S7-9): grades and costs, condition, traits, training, scouting,
## team colours and points.

const F := preload("res://tests/core/rules/rules_fixture.gd")

static var _rules: ClubRules


func _r() -> ClubRules:
	if _rules == null:
		_rules = ClubIO.load_default()
	return _rules


func _team(seed_value: int = 5, mean: float = 50.0) -> Team:
	return LeagueGenerator.new(RosterIO.load_names(), F.catalog(), seed_value).team(0, mean)


func _season(seed_value: int = 4) -> Season:
	var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), seed_value)
	var clubs: Array[Team] = []
	for i: int in 10:
		clubs.append(gen.team(i, 50.0))
	return Season.create(clubs, 10, 36, seed_value, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), _r())


func test_grades_costs_and_caps_follow_the_table() -> void:
	var r := _r()
	assert_eq(r.grade_of(90.0).name, "S")
	assert_eq(r.grade_of(85.0).cost, 7)
	assert_eq(r.grade_of(74.9).name, "B")
	assert_eq(r.grade_of(55.0).cost, 2)
	assert_eq(r.grade_of(20.0).name, "D")
	assert_eq([r.cost_cap(0), r.cost_cap(1), r.cost_cap(2)], [90, 75, 60])
	var cost := r.first_team_cost(_team(), F.overall(), F.catalog())
	# 29 players at 1 to 7 each.
	assert_between(cost, 29, 29 * 7)


func test_condition_drifts_and_mostly_sits_at_normal() -> void:
	var s := _season()
	var counts := PackedInt32Array([0, 0, 0, 0, 0])
	for d: int in 120:
		s.advance()
		for id: String in s.condition:
			counts[s.condition[id]] += 1
	assert_gt(counts[ClubRules.NORMAL], counts[1])
	assert_gt(counts[ClubRules.NORMAL], counts[3])
	assert_gt(counts[0] + counts[4], 0, "the extremes happen")
	var someone: String = s.condition.keys()[0]
	s.condition[someone] = 4
	assert_almost_eq(s.condition_effect(someone), 0.06, 1e-9)
	assert_eq(s.condition_name(someone), "최상")


func test_a_player_plays_at_today_s_condition() -> void:
	var s := _season()
	var team: Team = s.teams.values()[0]
	var starter := team.rotation()[0]
	var hitter: Player = null
	for p: Player in team.first_team():
		if not p.is_pitcher():
			hitter = p
			break
	s.condition[hitter.id] = 0
	var squad := s.squad_for(team, 0, starter.id)
	assert_almost_eq(squad.player(hitter.id).batting.contact_r, hitter.batting.contact_r * 0.94, 0.001)


func test_traits_equip_merge_and_raise_ratings_for_my_club_only() -> void:
	var s := _season()
	var mine: Team = s.teams.values()[1]
	s.manage(mine.id)
	var c := s.club
	var r := _r()
	var precision := r.trait_index("precision")
	c.bag.append(Vector2i(precision, 0))
	c.bag.append(Vector2i(precision, 0))
	assert_true(c.merge(0, 1, r))
	assert_eq(c.bag, [Vector2i(precision, 1)] as Array[Vector2i], "two of a tier make one of the next")
	assert_false(c.merge(0, 0, r))
	var hitter: Player = null
	var pitcher := mine.rotation()[1]
	for p: Player in mine.first_team():
		if not p.is_pitcher():
			hitter = p
			break
	assert_false(c.equip(pitcher, 0, r), "a hitter's trait does not go on a pitcher")
	assert_true(c.equip(hitter, 0, r))
	assert_true(c.bag.is_empty())
	s.condition.clear()
	var squad := s.squad_for(mine, 0, mine.rotation()[0].id)
	# On top of the club's colours (all its own players at the start: the franchise colour).
	var actives := TeamColors.active(mine, c, r, F.overall(), F.catalog())
	var colour := float(TeamColors.deltas(hitter, actives, mine, c, r, F.overall(), F.catalog()).get("contact", 0.0))
	assert_almost_eq(colour, 0.0, 1e-6, "no colour yet: the first team has none of its own prospects")
	var expected := hitter.batting.contact_r + 2.0 * r.trait_tiers[1] + colour
	assert_almost_eq(squad.player(hitter.id).batting.contact_r, minf(expected, 99.0), 0.001)
	c.unequip(hitter.id)
	assert_eq(c.bag.size(), 1)


func test_training_grows_the_young_faster_and_stops_at_the_headroom() -> void:
	var r := _r()
	var team := _team()
	var c := Club.for_team(team)
	var young: Player = null
	var old: Player = null
	for p: Player in team.first_team():
		if p.is_pitcher():
			continue
		if young == null or p.born > young.born:
			young = p
		if old == null or p.born < old.born:
			old = p
	var age := func(p: Player) -> int: return 2026 - p.born
	var start_young := young.batting.contact_r
	var start_old := old.batting.contact_r
	assert_true(c.assign_training(young.id, "batting", r))
	assert_true(c.assign_training(old.id, "batting", r))
	assert_false(c.assign_training(young.id, "nothing", r))
	c.train(team, age, r, F.overall(), F.catalog())
	assert_gt(young.batting.contact_r - start_young, old.batting.contact_r - start_old)
	assert_true(c.training.is_empty(), "assignments are for one day")
	for d: int in 400:
		c.assign_training(young.id, "batting", r)
		c.train(team, age, r, F.overall(), F.catalog())
	assert_almost_eq(float(c.gained[young.id]), ClubRules.by_age(r.headroom, age.call(young)), 0.001, "no further than his headroom")
	# Only three a day.
	var others := team.first_team()
	var n := 0
	for p: Player in others:
		if c.assign_training(p.id, "running", r):
			n += 1
	assert_eq(n, r.train_per_day)


func test_scouting_offers_five_and_one_signs_a_day() -> void:
	var s := _season()
	var mine: Team = s.teams.values()[2]
	s.manage(mine.id)
	var c := s.club
	assert_eq(c.candidates.size(), _r().scout_candidates)
	var before := mine.players.size()
	var signed := c.sign(0, mine, _r())
	assert_not_null(signed)
	assert_eq(mine.players.size(), before + 1)
	assert_false(mine.is_registered(signed.id), "he joins the second team")
	assert_null(c.sign(0, mine, _r()), "one a day")
	s.advance()
	assert_eq(c.candidates.size(), _r().scout_candidates, "new ones the next day")
	assert_false(c.signed_today)
	var points := c.points
	assert_true(c.release(signed.id, mine, _r()))
	assert_eq(c.points, points + int(_r().points["release"]))
	assert_false(c.release(mine.first_team()[0].id, mine, _r()), "not from the first team")


func test_team_colours_need_their_players_and_are_capped() -> void:
	var r := _r()
	var team := _team(9)
	var c := Club.for_team(team)
	# Make six regular hitters fast and four powerful.
	var hitters: Array[Player] = []
	for p: Player in team.first_team():
		if not p.is_pitcher():
			hitters.append(p)
	for i: int in 6:
		hitters[i].batting.speed = 80.0
	for i: int in 4:
		hitters[i].batting.power_r = 85.0
		hitters[i].batting.power_l = 85.0
	var actives := TeamColors.active(team, c, r, F.overall(), F.catalog())
	var names: Array[String] = []
	for a: ClubRules.ColorDef in actives:
		names.append(a.name)
	assert_true(names.has("발야구"))
	assert_true(names.has("대포 군단"))
	assert_lte(actives.size(), r.color_limit)
	var d := TeamColors.deltas(hitters[0], actives, team, c, r, F.overall(), F.catalog())
	assert_almost_eq(float(d.get("speed", 0.0)), 2.0, 1e-6)
	assert_almost_eq(float(d.get("power", 0.0)), 2.5, 1e-6)
	for key: String in d:
		assert_lte(d[key], r.color_cap)
	assert_true(TeamColors.deltas(team.rotation()[0], actives, team, c, r, F.overall(), F.catalog()).is_empty(), "a hitters' colour")


func test_my_club_earns_points_from_its_games() -> void:
	var s := _season()
	var mine: Team = s.teams.values()[0]
	s.manage(mine.id)
	var start := s.club.points
	for d: int in 3:
		s.play_day(true)
		s.advance()
	assert_gt(s.club.points, start)


func test_the_franchise_colour_counts_players_who_came_up_through_the_club() -> void:
	var r := _r()
	var team := _team(11)
	var c := Club.for_team(team)
	var franchise: ClubRules.ColorDef = null
	for d: ClubRules.ColorDef in r.colors:
		if d.id == "franchise":
			franchise = d
	assert_eq(TeamColors.level(franchise, team, c, r, F.overall(), F.catalog()), 0)
	# Ten of its own on the first team: the first step.
	var n := 0
	for p: Player in team.first_team():
		if n >= 10:
			break
		c.homegrown[p.id] = true
		n += 1
	assert_eq(TeamColors.level(franchise, team, c, r, F.overall(), F.catalog()), 1)
	for p: Player in team.second_team():
		assert_true(c.homegrown.has(p.id), "the prospects are its own")
