extends SceneTree
## A whole career played through without a screen, the way a person would play it, to check that
## everything holds together over the years (the user, 2026-11-23: "check the work functions and
## is balanced before version 1"): every game settled, growth points spent each week, his money spent on training (and
## conditioning from 29), a club's offer before free agency taken half the time, free agency
## filed when eligible with an agent and a counter-offer, the best deal signed, a farewell tour
## from 36, retirement and its settling up; saved and loaded every winter. A line a season.
##
##   ./dev script tools/career_soak.gd -- --position SS --games 144 --seed 3

var _rows := PackedStringArray()


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var position := str(args.get("position", "SS"))
	var games := int(str(args.get("games", "144")))
	var seed_value := int(str(args.get("seed", "3")))
	Profile.tool_run()
	var rules := CareerIO.load_default()
	var spec := PlayerCreator.Spec.new()
	spec.name = "장기%d" % seed_value
	spec.position = position
	spec.type_id = (rules.pitcher_types[0] if CareerRules.is_pitching_position(position) else rules.batter_types[0]).id
	var made := PlayerCreator.create(spec, rules, PitchCatalogIO.load_default())
	var clubs := LeagueSession.league_clubs()
	CareerSession.start(made, clubs[seed_value % clubs.size()].id, games, seed_value)
	CareerSession.career_season.pro_games = games
	var rng := Rng.new(seed_value)
	var started := Time.get_ticks_msec()
	print("soak: %s %s, %d games a season" % [spec.name, position, games])
	print("season | age | club | 1군일 | OVR | 연봉 | 보유 | 투자 | 계약 | FA | 리그연봉총액 | FA신청 | 기념구 | 리그 90+")
	for year: int in 22:
		var cs := CareerSession.career_season
		var c := CareerSession.career
		_invest(cs)
		var guard := 0
		while not cs.season.finished() and guard < 600:
			if cs.all_star_today:
				cs.quick_all_star()
			if cs.derby_waiting:
				cs.quick_derby()
			if cs.has_game():
				cs.quick()
			cs.next_day()
			guard += 1
			if guard % 7 == 0:
				_spend(c, cs.rules)
		_spend(c, cs.rules)
		CareerSession.start_winter()
		_row(cs)
		# Saved and loaded every winter: the career must come back as it was.
		var back := SaveIO.career_from(SaveIO.career_to(cs), cs.season)
		_check(back.career.salary == c.salary and back.career.contract_years == c.contract_years and back.career.moments.size() == c.moments.size() and back.trainer == cs.trainer, "save round trip")
		if c.final_season:
			break
		var age := cs.season.season_year + 1 - c.player.born
		if not cs.extension.is_empty() and rng.chance(0.5):
			CareerFA.accept_extension(cs)
		var club := ""
		if cs.fa_state == "eligible":
			if c.money > 20000:
				CareerFA.hire_agent(cs)
			CareerFA.declare(cs, rng)
			var best := -1
			for i: int in cs.fa_offers.size():
				if best < 0 or FreeAgency.total_of(CareerFA.deal_of(cs.fa_offers[i])) > FreeAgency.total_of(CareerFA.deal_of(cs.fa_offers[best])):
					best = i
			print("   FA %s등급 · 제안 %d건 · 최고 %s" % [cs.fa_grade, cs.fa_offers.size(), FreeAgency.deal_text(CareerFA.deal_of(cs.fa_offers[best]))])
			print("   협상: %s" % CareerFA.ask_more(cs, best, rng))
			for o: Dictionary in cs.fa_offers:
				if str(o["status"]) != "withdrawn" and (club == "" or FreeAgency.total_of(CareerFA.deal_of(o)) > FreeAgency.total_of(CareerFA.deal_of(cs.fa_offers.filter(func(x: Dictionary) -> bool: return str(x["club"]) == club)[0]))):
					club = str(o["club"])
			if club == "":
				CareerFA.stay(cs)
		if age >= 36 and club == "" and not c.final_season:
			CareerLegacy.announce(cs)
		CareerSession.next_season(club)
	var cs := CareerSession.career_season
	var result := CareerSession.retire()
	var c := CareerSession.career
	_check(not result.is_empty(), "retired")
	print("은퇴: %d시즌, %s, 결산 보상 %dP, 영구결번 %s, 명예의 전당 %s" % [c.pro_years, c.legacy_grade, c.legacy_reward, c.number_retired, not (result[2] as PackedStringArray).is_empty()])
	print("영광: 타이틀 %d, 올스타 %d, 우승 %d, 기념구 %d, 계약 %d, 회상 %d장, 작별 선물 %d" % [c.titles_won.size(), c.all_stars, c.championships.size(), c.milestones.size(), c.deals.size(), CareerLegacy.flashback(c).size(), c.tour_gifts.size()])
	print("수입: 누적 %s · 최고 연봉 %s · 보유 %s" % [FreeAgency.money(c.earned), FreeAgency.money(c.best_salary), FreeAgency.money(c.money)])
	print("soak: done in %d s" % ((Time.get_ticks_msec() - started) / 1000))
	quit()


## Growth points spent as a player would: always on the cheapest rating he can still raise.
func _spend(c: CareerPlayer, rules: CareerRules) -> void:
	for field: String in ["batting", "running", "fielding", "pitching"]:
		var guard := 0
		while guard < 200:
			guard += 1
			var best := ""
			var best_cost := INF
			for rating: String in rules.ratings.get(field, []):
				if (field == "pitching") != c.is_pitcher():
					continue
				if Growth.value(c.player, rating) >= Growth.TOP:
					continue
				var price := Growth.cost(c, rating, rules)
				if price < best_cost:
					best_cost = price
					best = rating
			if best == "" or not Growth.raise(c, best, rules):
				break


## Money spent as a player would: the best training he can pay for, conditioning from 29.
func _invest(cs: CareerSeason) -> void:
	for level: int in [3, 2, 1]:
		if CareerMoney.problem(cs, "training", level) == "":
			CareerMoney.buy(cs, "training", level)
			break
	if cs.season.season_year - cs.career.player.born >= 29:
		for level: int in [3, 2, 1]:
			if CareerMoney.problem(cs, "conditioning", level) == "":
				CareerMoney.buy(cs, "conditioning", level)
				break


func _row(cs: CareerSeason) -> void:
	var c := cs.career
	var s := cs.season
	var pays: Array[int] = []
	for id: String in s.divisions[0]:
		pays.append(FreeAgency.payroll(s.teams[id]))
	pays.sort()
	var moves := s.last_winter.free_agents.size() if s.last_winter != null else 0
	var stars := 0
	for id: String in s.divisions[0]:
		for p: Player in (s.teams[id] as Team).players:
			if p.id != c.player.id and RatingScale.shown(ClubRules.player_ovr(p, s.ovr, s.catalog)) >= 90.0:
				stars += 1
	var ovr := RatingScale.shown(ClubRules.player_ovr(c.player, s.ovr, s.catalog))
	var contract := "%s %d년" % [c.contract_kind, c.contract_years] if c.contract_years > 0 else "1년"
	print("%d | %d | %s | %d | %d | %s | %s | T%d C%d | %s | %s | %s~%s | %d | %d | %d" % [s.season_year, s.season_year - c.player.born, s.teams[c.team_id].short_name, cs.first_team_days, roundi(ovr),
		FreeAgency.money(c.salary), FreeAgency.money(c.money), cs.trainer, cs.conditioning, contract, cs.fa_state if cs.fa_state != "" else "-",
		FreeAgency.money(pays[0]) if not pays.is_empty() else "-", FreeAgency.money(pays[-1]) if not pays.is_empty() else "-", moves, c.milestones.size(), stars])


func _check(ok: bool, what: String) -> void:
	if not ok:
		push_error("soak: %s failed" % what)
		print("soak: FAILED %s" % what)
