class_name CareerSession
extends RefCounted
## The career in progress, kept while the screens change: the player, his season, and the game
## about to be played on screen. Saving comes with S9.

const CREATE := "res://career/creation_screen.tscn"
const HUB := "res://career/career_screen.tscn"
const MATCH := "res://career/career_match.tscn"
const DERBY := "res://career/home_run_derby.tscn"
const DRAFT := "res://career/draft_screen.tscn"
const RETIRE := "res://career/retire_screen.tscn"
## His retirement at his park (FarewellScene), on to the settling up (RETIRE).
const FAREWELL := "res://career/farewell_scene.tscn"

static var career: CareerPlayer
static var season: Season
static var career_season: CareerSeason
## What the last game earned, for the hub.
static var last_report: CareerSeason.Report
static var slot := ""
## The draft after his high-school season, once it has been held.
static var draft: Draft


## A new career: the player joins `team_id`'s second team in a new season of the league's ten
## clubs (every club at today's condition; no club management, the player is not the manager).
static func start(c: CareerPlayer, team_id: String, games: int, seed_value: int, year: int = -1) -> void:
	# The league's ten clubs (the KBO's, renamed, when the local pack has them: the user, 2026-
	# 11-23, "the same as the league") in one league, with the futures league of twelve.
	var clubs := LeagueSession.league_clubs()
	season = Season.create(clubs, clubs.size(), games, seed_value, RuleSet.kbo_2026(), LeagueEnvIO.load_default(), PitchCatalogIO.load_default(), LeagueEnvIO.load_overall(), ClubIO.load_default())
	season.season_year = year if year > 0 else LeagueSession.league_year()
	season.farm = FarmLeague.for_season(season)
	c.join(season.teams[team_id])
	career = c
	career_season = CareerSeason.start(season, c, CareerIO.load_default())
	last_report = null
	slot = "career_%s" % c.player.id


## A new career from high school: his third year at `school_id` in its weekend
## league; after it the draft decides his club. `games` is the length of his pro seasons.
static func start_school(c: CareerPlayer, school_id: String, games: int, seed_value: int) -> void:
	season = SchoolLeague.season_for(c, school_id, LeagueSession.league_year(), seed_value)
	career = c
	career_season = CareerSeason.start(season, c, CareerIO.load_default())
	career_season.pro_games = games
	career_season.log.append("%d년 %s 3학년, 고교리그 시작" % [season.season_year, season.teams[school_id].name])
	last_report = null
	draft = null
	slot = "career_%s" % c.player.id


## The draft at the end of his high-school season (held once; the same draft every time for the
## same season).
static func hold_draft() -> Draft:
	if draft == null and career_season != null and season != null and season.school:
		draft = Draft.run(career, season, LeagueSession.league_clubs(), hash("draft:%s:%d" % [career.player.id, season.season_year]))
	return draft


## Into the pros after the draft: the club that picked him (or offered a developmental
## contract), next season, starting in its second team.
static func turn_pro() -> void:
	var d := hold_draft()
	if d == null:
		return
	var c := career
	var cs := career_season
	var school: Team = season.teams.get(c.team_id)
	if school != null:
		school.players.erase(c.player)
		school.registered.erase(c.player.id)
	var picked := d.his
	c.drafted = "%d KBO 신인 드래프트 %d라운드 %d순위" % [d.year + 1, picked.round, picked.number] if picked != null else "%d 육성선수 계약" % (d.year + 1)
	c.signing_bonus = d.bonus()
	c.money += c.signing_bonus
	c.salary = CareerContract.MINIMUM
	var keep_log := cs.log.duplicate()
	start(c, d.team_id(), cs.pro_games, hash("pro:%s" % c.player.id) % 100000, d.year + 1)
	career_season.pro_games = cs.pro_games
	career_season.log = keep_log
	career_season.log.append("%s · %s 입단 (계약금 %s)" % [c.drafted, season.teams[c.team_id].name, Draft.money_text(c.signing_bonus)])
	# The cutscene: called on the draft stage, the club's jersey held up.
	var club_name: String = season.teams[c.team_id].name
	if picked != null:
		career_season.cue(&"draft", "%d KBO 신인 드래프트" % (d.year + 1), "%s %d라운드 %d순위" % [club_name, picked.round, picked.number], PackedStringArray(["계약금 %s" % Draft.money_text(c.signing_bonus), "%s 출신" % (school.name if school != null else "")]))
		CareerLegacy.note(c, d.year + 1, "draft", "%s %d라운드 %d순위" % [club_name, picked.round, picked.number], "%s 출신 · 계약금 %s 원" % [school.name if school != null else "", FreeAgency.money(c.signing_bonus)], c.team_id)
	else:
		career_season.cue(&"contract", "%d 육성선수 계약" % (d.year + 1), "%s 입단" % club_name, PackedStringArray(["연봉 %s" % Draft.money_text(c.salary)]))
	draft = null


## The winter after a pro season (CareerContract): the season into his record, his new salary,
## released or a free agent. Held once a season; what he was told stays on the season.
static func start_winter() -> void:
	var cs := career_season
	if cs == null or cs.season.school or not cs.season.finished() or cs.events_seen.has("winter:%d" % cs.season.season_year):
		return
	cs.events_seen.append("winter:%d" % cs.season.season_year)
	var rng := Rng.new(hash("winter:%s:%d" % [career.player.id, cs.season.season_year]))
	cs.winter_lines = CareerContract.winter(cs, rng)
	var clubs: Array = cs.season.teams.keys()
	if career.released:
		var others: Array = clubs.filter(func(id: String) -> bool: return id != career.team_id)
		if not others.is_empty():
			cs.release_team = str(others[rng.next_int(others.size())])
			cs.winter_lines.append("%s의 입단 테스트에 합격했습니다 (연봉 %s)." % [cs.season.teams[cs.release_team].name, Draft.money_text(CareerContract.MINIMUM)])
	elif career.final_season:
		# The farewell tour is over (CareerLegacy): the ceremony waits.
		cs.winter_lines.append("은퇴 투어를 마쳤습니다 (작별 선물 %d개). 이제 은퇴식이 남았습니다." % career.tour_gifts.size())
	else:
		if CareerLegacy.should_retire(cs):
			cs.winter_lines.append("구단이 은퇴를 권유했습니다. 은퇴 투어를 발표하면 다음 시즌이 마지막 시즌이 됩니다.")
		# Free agency (CareerFA): the grade by last season's salary, his to file or not; or, a
		# winter before it, his club's offer of a deal of several years.
		career.player.salary = cs.last_salary
		FreeAgency.ensure(cs.season)
		if CareerFA.ready(career, cs.season.total_days()):
			cs.fa_state = "eligible"
			cs.fa_grade = str(FreeAgency.grades(cs.season, [career.player] as Array[Player]).get(career.player.id, "C"))
			cs.winter_lines.append("FA 등급: %s등급 (직전 연봉 %s 원 기준)" % [cs.fa_grade, FreeAgency.money(cs.last_salary)])
		else:
			cs.extension = CareerFA.extension_offer(cs)
			if not cs.extension.is_empty():
				cs.winter_lines.append("%s에서 비FA 다년계약을 제안했습니다: %s" % [cs.season.teams[career.team_id].name, FreeAgency.deal_text(cs.extension)])
		career.player.salary = career.salary if career.contract_years <= 0 else roundi(float(career.contract_total) / maxi(career.contract_length, 1) / 100.0) * 100
	for line: String in cs.winter_lines:
		cs.log.append("%d년 겨울: %s" % [cs.season.season_year, line])
	_winter_cues(cs)


## The winter's cutscenes: his club's championship, his titles at the awards, a better
## contract (or a new club after a release).
static func _winter_cues(cs: CareerSeason) -> void:
	var year := cs.season.season_year
	var team: Team = cs.season.teams[career.team_id]
	if cs.season.champion_of(0) == career.team_id:
		career.championships.append(year)
		CareerLegacy.note(career, year, "champion", "%s 우승" % team.name, "%d 한국시리즈" % year, team.id)
		cs.cue(&"champion", "%d 한국시리즈" % year, "%s 우승!" % team.name, PackedStringArray(["%d년 통합 챔피언" % year if cs.season.standings[0].ranked()[0].team_id == career.team_id else "%d년 챔피언" % year]))
	var won := CareerContract.titles(cs)
	if not won.is_empty():
		var names := PackedStringArray()
		for t: String in won:
			names.append(award_name(t))
			career.titles_won.append([year, award_name(t)])
		CareerLegacy.note(career, year, "title", " · ".join(names), "%d KBO 시상식" % year, team.id)
		cs.cue(&"award", "%d KBO 시상식" % year, names[0], PackedStringArray(names.slice(1)) + PackedStringArray(["상금 %s" % Draft.money_text(CareerContract.TITLE_PRIZE * won.size())]))
	if career.released and cs.release_team != "":
		cs.cue(&"contract", "%d 입단 테스트 합격" % (year + 1), "%s 입단" % cs.season.teams[cs.release_team].name, PackedStringArray(["연봉 %s" % Draft.money_text(CareerContract.MINIMUM)]))
	else:
		for line: String in cs.winter_lines:
			if line.begins_with("연봉 인상"):
				cs.cue(&"contract", "%d 연봉 계약" % (year + 1), "연봉 %s" % Draft.money_text(career.salary), PackedStringArray([line, team.name]))


## A title as the awards call it (KBO: 홈런왕, 타격왕, 평균자책점 1위).
static func award_name(title: String) -> String:
	match title:
		"타율":
			return "타격왕"
		"평균자책점":
			return "평균자책점 1위"
	return title + "왕"



## The next season (after the winter): the league's winter (retirements, rookies, everyone a
## year older), a new season of the same clubs, and he in his club (a free agent's choice of
## `fa_club` with its offer; released, the club that signed him). He starts on the first team
## when he spent most of the last season there and stays with his club.
static func next_season(fa_club: String = "") -> void:
	var cs := career_season
	if cs == null or cs.season.school or not cs.season.finished():
		return
	start_winter()
	var old := cs.season
	var c := career
	var to := c.team_id
	var fa_cue: Array = []
	var news := PackedStringArray()
	var rng := Rng.new(hash("market:%s:%d" % [c.player.id, old.season_year]))
	if c.released and cs.release_team != "":
		to = cs.release_team
	if fa_club != "":
		# His free agency (CareerFA): the deal, and an A or B man's compensation player.
		var o := CareerFA.sign(cs, fa_club)
		if not o.is_empty():
			to = fa_club
			var deal := CareerFA.deal_of(o)
			var staying := fa_club == c.team_id
			var line := "FA %s: %s (%s등급) %s %s" % ["잔류" if staying else "이적", c.player.name, cs.fa_grade, old.teams[fa_club].name, FreeAgency.deal_text(deal)]
			cs.log.append("%d년 %s" % [old.season_year, line])
			news.append(line)
			var more := PackedStringArray([FreeAgency.deal_text(deal)])
			if not (o["option"] as Array).is_empty():
				more.append(CareerFA.option_text(o["option"]))
			fa_cue = [&"contract", "%d FA 계약" % (old.season_year + 1), "%s %s" % [old.teams[fa_club].name, "잔류" if staying else "입단"], more]
	var from_id := c.team_id
	if to != from_id:
		var from: Team = old.teams[from_id]
		from.players.erase(c.player)
		from.registered.erase(c.player.id)
		(old.teams[to] as Team).players.append(c.player)
		if fa_club == to:
			var moved_ids: Array[String] = [c.player.id]
			var pick := FreeAgency.compensate(old, cs.fa_grade, from_id, to, c.player.id, moved_ids, rng)
			var paid := roundi(cs.last_salary * float(FreeAgency.COMPENSATION.get(cs.fa_grade, 1.5)) / 100.0) * 100
			var line := "FA 보상: %s → %s (%s보상금 %s 원)" % [old.teams[to].name, old.teams[from_id].name, "보상선수 %s, " % pick if pick != "" else "", FreeAgency.money(paid)]
			cs.log.append("%d년 %s" % [old.season_year, line])
			news.append(line)
	# The league's free agents go to market (FreeAgency), then the winter: his conditioning makes
	# his decline gentler (CareerMoney).
	c.player.salary = c.salary if c.contract_years <= 0 else roundi(float(c.contract_total) / maxi(c.contract_length, 1) / 100.0) * 100
	for signing: FreeAgency.Signing in FreeAgency.offseason(old, rng, c.player.id):
		var line := FreeAgency.news(old, signing)
		news.append(line)
		if signing.grade == "A" or signing.to == to or signing.from == to:
			cs.log.append("%d년 겨울 %s" % [old.season_year, line])
	old.decline_scales[c.player.id] = CareerMoney.decline_share(cs)
	var w := Development.winter(old)
	w.free_agents = news
	var moved := to != from_id
	var start_first := not moved and not c.released and float(cs.first_team_days) / maxi(old.total_days(), 1) >= 0.5
	c.released = false
	c.team_id = to
	var clubs: Array[Team] = []
	for id: String in old.divisions[0]:
		clubs.append(old.teams[id])
	season = Season.create(clubs, clubs.size(), cs.pro_games, hash("career:%s:%d" % [c.player.id, old.season_year + 1]) % 100000, RuleSet.kbo_2026(), old.env, old.catalog, old.ovr, ClubIO.load_default())
	season.season_year = old.season_year + 1
	season.farm = FarmLeague.for_season(season)
	season.last_winter = w
	var team: Team = season.teams[to]
	team.registered.erase(c.player.id)
	if start_first:
		team.registered.append(c.player.id)
		season.career_player = c.player.id
		RosterMoves.trim(season, team, season.rules.registered_roster)
		if not team.registered.has(c.player.id):
			team.registered.append(c.player.id)
	c.first_team = start_first
	var next := CareerSeason.start(season, c, cs.rules)
	next.pro_games = cs.pro_games
	next.log = cs.log.duplicate()
	next.log.append("%d년 시즌 시작 · %s %s" % [season.season_year, team.name, "1군" if start_first else "2군"])
	career_season = next
	if not fa_cue.is_empty():
		next.cue(fa_cue[0], fa_cue[1], fa_cue[2], fa_cue[3])
	last_report = null


## He retires (in a winter, after the winter's business): his last season into
## his record, the hall of fame's marks checked (he goes in or not), the career closed. Returns
## [first-team batting, pitching, the marks met, titles].
static func retire() -> Array:
	var cs := career_season
	if cs == null or career == null or career.retired or cs.season.school or not cs.season.finished():
		return []
	start_winter()
	var c := career
	var titles := 0
	for line: String in cs.log:
		if line.contains("타이틀"):
			titles += 1
	var sum := CareerContract.totals(c)
	var bat: BattingLine = sum[0]
	var pitch: PitchingLine = sum[1]
	if not c.titles_won.is_empty():
		titles = maxi(titles, c.titles_won.size())
	var met := HallOfFame.marks(c, bat, pitch, titles, cs.pro_games)
	# The settling up (CareerLegacy): his grade, its reward (into the shop's wallet), his number
	# retired.
	var settled := c.legacy_grade != ""
	CareerLegacy.settle(cs, bat, pitch, not met.is_empty())
	if not settled and not Profile.tool_run() and DisplayServer.get_name() != "headless":
		Profile.earn(c.legacy_reward)
	c.retired = true
	var age := cs.season.season_year - c.player.born
	cs.log.append("%d년 은퇴 (%d세, 프로 %d시즌)" % [cs.season.season_year, age, c.pro_years])
	cs.log.append("커리어 결산: %s (결산 보상 %dP)%s" % [c.legacy_grade, c.legacy_reward, " · 등번호 %d 영구결번" % c.player.number if c.number_retired else ""])
	Achievements.check_career(cs)
	if not met.is_empty():
		cs.log.append("명예의 전당 헌액: %s" % ", ".join(met))
		HallOfFame.add({"name": c.player.name, "position": c.position, "years": c.pro_years, "retired": cs.season.season_year,
			"club": cs.season.teams[c.team_id].name, "marks": Array(met), "line": _career_line(c, bat, pitch)})
	autosave()
	return [bat, pitch, met, titles]


## His career in a line ("17시즌 2,104안타 312홈런 타율 .301").
static func _career_line(c: CareerPlayer, bat: BattingLine, pitch: PitchingLine) -> String:
	if c.is_pitcher():
		return "%d시즌 %d승 %d패 %d세이브 평균자책점 %.2f" % [c.pro_years, pitch.wins, pitch.losses, pitch.saves, pitch.era()]
	return "%d시즌 %d안타 %d홈런 타율 %s" % [c.pro_years, bat.hits, bat.home_runs, BattingLine.rate_text(bat.average())]


## The points his reward boxes, the derby and the all-star game gave him go into the wallet the
## shop spends (Profile): they piled up on the career before with nothing to buy.
static func settle_points() -> int:
	if career == null or career.points <= 0 or DisplayServer.get_name() == "headless":
		return 0
	var paid := career.points
	Profile.earn(paid)
	career.points = 0
	return paid


static func autosave() -> void:
	if career_season == null or slot == "":
		return
	SaveIO.save_career(slot, career_season, Time.get_unix_time_from_system())
