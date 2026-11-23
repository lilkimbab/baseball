extends GutTest
## The career player's free agency (CareerFA) and what his money buys (CareerMoney).

const F := preload("res://tests/core/rules/rules_fixture.gd")


func after_each() -> void:
	CareerSession.career_season = null
	CareerSession.season = null
	CareerSession.career = null


func _pro(seed_value: int = 61) -> CareerSeason:
	var spec := PlayerCreator.Spec.new()
	spec.name = "FA%d" % seed_value
	spec.position = "SS"
	spec.type_id = "contact"
	var c := PlayerCreator.create(spec, CareerIO.load_default(), F.catalog())
	CareerSession.start(c, LeagueSession.league_clubs()[4].id, 36, seed_value)
	var cs := CareerSession.career_season
	cs.pro_games = 36
	FreeAgency.ensure(cs.season)
	return cs


## Makes him a star of the league (ratings), on the first team.
func _star(cs: CareerSeason) -> void:
	var b := cs.career.player.batting
	b.contact_r = 92.0
	b.contact_l = 92.0
	b.power_r = 85.0
	b.power_l = 85.0
	b.eye = 85.0
	cs.career.player.fielding.range = 85.0
	FreeAgency.forget(cs.season)


func test_the_better_he_is_the_more_clubs_bid_and_the_bigger_the_deal() -> void:
	var cs := _pro()
	var weak := CareerFA.market(cs, Rng.new(1))
	_star(cs)
	var strong := CareerFA.market(cs, Rng.new(1))
	assert_gt(strong.size(), weak.size(), "a star hears from more clubs: %d against %d" % [strong.size(), weak.size()])
	var best := 0
	for o: Dictionary in strong:
		best = maxi(best, FreeAgency.total_of(CareerFA.deal_of(o)))
		assert_gte(int(o["limit"]), CareerFA.value_of(o) - 100, "a club's limit is at least what it offers")
		assert_true(str(o["role"]) in ["주전 보장", "주전 경쟁", "백업 역할"])
	assert_true(strong.any(func(o: Dictionary) -> bool: return str(o["club"]) == cs.career.team_id), "his own club bids")
	assert_gt(best, 300000, "a star's deal runs to tens of 억: %s" % FreeAgency.money(best))


func test_asking_for_more_raises_the_deal_until_the_club_s_limit() -> void:
	var cs := _pro()
	_star(cs)
	cs.fa_offers = CareerFA.market(cs, Rng.new(2))
	var o: Dictionary = cs.fa_offers[0]
	o["limit"] = roundi(CareerFA.value_of(o) * 1.1)
	var before := CareerFA.value_of(o)
	CareerFA.ask_more(cs, 0, Rng.new(1))
	assert_almost_eq(float(CareerFA.value_of(o)), before * 1.08, before * 0.02, "8% more")
	CareerFA.ask_more(cs, 0, Rng.new(1))
	assert_true(str(o["status"]) in ["final", "withdrawn"], "past its limit: its last word, or it walks")
	assert_almost_eq(float(CareerFA.value_of(o)), before * 1.08, before * 0.02, "no more than the limit")


func test_signing_fixes_the_salary_pays_the_bonus_and_restarts_the_clock() -> void:
	var cs := _pro()
	_star(cs)
	var c := cs.career
	cs.fa_offers = CareerFA.market(cs, Rng.new(4))
	CareerFA.hire_agent(cs)
	var money := c.money
	var o: Dictionary = cs.fa_offers[0]
	var deal := CareerFA.deal_of(o)
	CareerFA.sign(cs, str(o["club"]))
	assert_eq(c.salary, int(deal[2]))
	assert_eq(c.contract_years, int(deal[0]))
	assert_eq(c.contract_kind, "FA")
	assert_eq(c.fa_count, 1)
	var fee := roundi(FreeAgency.total_of(deal) * CareerFA.AGENT_FEE / 100.0) * 100
	assert_eq(c.money, money + int(deal[1]) - fee, "the bonus at once, less the agent's fee")
	assert_false(CareerFA.ready(c, cs.season.total_days()))


func test_a_deal_s_salary_holds_through_its_years_and_its_option_pays() -> void:
	var cs := _pro()
	var c := cs.career
	c.contract_years = 3
	c.contract_length = 3
	c.contract_kind = "FA"
	c.salary = 50000
	c.contract_total = 160000
	c.contract_option = [5000, "hitter"]
	var bat := cs.season.book.bat(c.player.id)
	bat.pa = 200
	bat.ab = 170
	bat.hits = 70
	bat.walks = 30
	bat.home_runs = 15
	var money := c.money + CareerContract.TITLE_PRIZE * CareerContract.titles(cs).size()
	CareerContract.winter(cs, Rng.new(1))
	assert_eq(c.salary, 50000, "no renewal while the deal runs")
	assert_eq(c.contract_years, 2)
	assert_eq(c.money, money + 5000, "the option met (qualifying, OPS over .850)")


func test_his_money_buys_training_conditioning_and_giving() -> void:
	var cs := _pro()
	var c := cs.career
	c.money = 12000
	assert_eq(CareerMoney.problem(cs, "training", 3), "%s 원 부족" % FreeAgency.money(50000 - 12000))
	assert_string_contains(CareerMoney.buy(cs, "training", 1), "개인 트레이너")
	assert_eq(c.money, 10000)
	assert_almost_eq(CareerMoney.growth_share(cs), 1.1, 1e-6)
	# Up a grade: the difference only.
	assert_eq(CareerMoney.price_now(cs, "training", 2), 8000)
	CareerMoney.buy(cs, "training", 2)
	assert_eq(c.money, 2000)
	assert_eq(cs.trainer, 2)
	c.money = 3000
	CareerMoney.buy(cs, "conditioning", 1)
	assert_almost_eq(float(cs.season.injuries.scales[c.player.id]), 0.8, 1e-6, "fewer days out")
	assert_almost_eq(CareerMoney.decline_share(cs), 0.75, 1e-6)
	c.money = 5000
	var pop := c.popularity
	CareerMoney.buy(cs, "donations", 1)
	assert_almost_eq(c.popularity, pop + 5.0, 1e-6)
	assert_ne(CareerMoney.problem(cs, "donations", 1), "", "once a season")
	assert_eq(ShopScreen.money_price({"price": 400}), 4000, "gear of 400 points for 4,000만 원")


func test_the_deal_and_the_spending_are_saved() -> void:
	var cs := _pro()
	var c := cs.career
	c.contract_years = 2
	c.contract_length = 4
	c.contract_total = 400000
	c.contract_kind = "FA"
	c.contract_option = [4000, "hitter"]
	c.fa_count = 1
	c.fa_since = 3
	cs.trainer = 2
	cs.invest_paid = {"training": 10000}
	cs.fa_state = "declared"
	cs.fa_offers = [{"club": c.team_id, "years": 3, "bonus": 1000, "annual": 9000, "option": [], "role": "주전 보장", "need": 2.0, "limit": 12000, "asks": 2, "status": "", "rank": 3}]
	var back := SaveIO.career_from(SaveIO.career_to(cs), cs.season)
	assert_eq(back.career.contract_years, 2)
	assert_eq(back.career.contract_length, 4)
	assert_eq(back.career.contract_option, [4000, "hitter"])
	assert_eq(back.career.fa_since, 3)
	assert_eq(back.trainer, 2)
	assert_eq(back.fa_state, "declared")
	assert_eq(int((back.fa_offers[0] as Dictionary)["annual"]), 9000)
