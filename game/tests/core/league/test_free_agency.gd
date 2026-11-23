extends GutTest
## Contracts and the free agents' market (FreeAgency): what a man is worth, the KBO's grades and
## compensation, the cap, and a winter's market measured against the KBO's.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _season(games: int = 36) -> Season:
	var clubs := LeagueSession.league_clubs()
	return Season.create(clubs, clubs.size(), games, 5, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), ClubIO.load_default())


func test_worth_rises_with_standing_and_falls_with_age() -> void:
	var last := 0
	for z: float in [-1.0, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5]:
		var v := FreeAgency.market_value(z, 28)
		assert_gte(v, last, "more for a better man")
		last = v
	assert_eq(FreeAgency.market_value(-3.0, 28), FreeAgency.MINIMUM, "the league's minimum at the bottom")
	assert_lte(FreeAgency.market_value(5.0, 28), 250000, "25억 a year at most")
	assert_lt(FreeAgency.market_value(1.5, 34), FreeAgency.market_value(1.5, 30), "less from 32 on")
	assert_gt(FreeAgency.market_years(2.0, 28), FreeAgency.market_years(0.0, 28))
	assert_eq(FreeAgency.market_years(2.0, 35), 1, "a year at 35")


func test_a_deal_adds_up_and_reads_as_the_news_writes_it() -> void:
	var deal := FreeAgency.terms(200000, 4)
	assert_eq(int(deal[0]), 4)
	assert_almost_eq(float(FreeAgency.total_of(deal)), 800000.0, 400.0, "four years of 20억")
	assert_gt(int(deal[1]), 0, "a signing bonus")
	assert_string_contains(FreeAgency.deal_text(deal), "4년 총액 80억")
	assert_eq(FreeAgency.money(125000), "12억 5,000만")
	assert_eq(FreeAgency.money(3000), "3,000만")


func test_every_man_gets_a_contract_and_the_clubs_pay_like_kbo_clubs() -> void:
	var s := _season()
	FreeAgency.ensure(s)
	var pays: Array[int] = []
	for id: String in s.teams:
		var team: Team = s.teams[id]
		for p: Player in team.players:
			assert_gte(p.salary, FreeAgency.MINIMUM, p.name)
		pays.append(FreeAgency.payroll(team))
	pays.sort()
	var mean := 0.0
	for x: int in pays:
		mean += x
	mean /= pays.size()
	gut.p("payrolls %s .. %s, mean %s" % [FreeAgency.money(pays[0]), FreeAgency.money(pays[-1]), FreeAgency.money(roundi(mean))])
	# The KBO's in 2025: 키움 lowest, 삼성 132억 highest, none over the 137억 line.
	assert_between(mean, 550000.0, 1200000.0, "about 55억 to 120억 on average")
	assert_lte(pays[-1], FreeAgency.CAP, "under the cap")


func test_the_grades_follow_the_kbo_rules() -> void:
	var s := _season()
	FreeAgency.ensure(s)
	var team: Team = s.teams[s.divisions[0][0]]
	var men := team.players.duplicate()
	men.sort_custom(func(a: Player, b: Player) -> bool: return a.salary > b.salary)
	var top: Player = men[0]
	top.salary = 999999
	top.fa_count = 0
	top.contract_years = 0
	top.born = s.season_year - 29
	var low: Player = men[-1]
	low.born = s.season_year - 29
	var old: Player = men[1]
	old.born = s.season_year - 36
	var g := FreeAgency.grades(s, [top, low, old] as Array[Player])
	assert_eq(g[top.id], "A", "his club's best paid and the league's")
	assert_eq(g[low.id], "C")
	assert_eq(g[old.id], "C", "35 and older")
	assert_eq(FreeAgency.PROTECT["A"], 20)
	assert_eq(FreeAgency.PROTECT["B"], 25)


func test_a_winter_market_moves_some_keeps_most_and_compensates() -> void:
	var s := _season()
	s.play_regular_season()
	var before := {}
	for id: String in s.teams:
		for p: Player in (s.teams[id] as Team).players:
			before[p.id] = id
	var signed := FreeAgency.offseason(s, Rng.new(3))
	assert_gt(signed.size(), 5, "a free agent class")
	var moved := 0
	for x: FreeAgency.Signing in signed:
		assert_eq(x.player.contract_years, int(x.deal[0]), "his deal set")
		assert_eq(x.player.service, 0, "the clock starts again")
		assert_eq(FreeAgency.club_of(s, x.player), x.to)
		if x.to != x.from:
			moved += 1
			assert_gt(x.compensation_money, 0, "the old club is paid")
			if x.grade != "C" and x.compensation != "":
				# The compensation player went the other way.
				var back := false
				for p: Player in (s.teams[x.from] as Team).players:
					back = back or p.name == x.compensation
				assert_true(back, "%s went to %s" % [x.compensation, x.from])
		gut.p(FreeAgency.news(s, x))
	assert_between(float(moved) / signed.size(), 0.2, 0.8, "some move, many stay")
	for id: String in s.teams:
		assert_lte(FreeAgency.payroll(s.teams[id]), roundi(FreeAgency.CAP * 1.1), "the clubs keep about to the cap")


func test_the_season_is_counted_and_the_deals_run_down() -> void:
	var s := _season()
	FreeAgency.ensure(s)
	var team: Team = s.teams[s.divisions[0][0]]
	var regular: Player = team.first_team().filter(func(p: Player) -> bool: return p.origin == &"")[0]
	regular.contract_years = 2
	var service := regular.service
	var book := s.book.bat(regular.id)
	book.pa = 300
	FreeAgency.count_season(s)
	assert_eq(regular.service, service + 1, "a season on the first team counted")
	assert_eq(regular.contract_years, 1)
