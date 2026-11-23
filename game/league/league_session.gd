class_name LeagueSession
extends RefCounted
## The manager league in progress, kept while the screens change: the season (with the
## player's club) and the game about to be played on screen. Saving comes with S9.

const PACK := "res://data/rosters/fiction-2026.json"
const SCREEN := "res://league/league_screen.tscn"
const MATCH := "res://match/manager_match.tscn"

static var season: Season
## The player's game handed to the match screen, until its result is recorded.
static var pending: ScheduledGame
## The save slot this season goes to (one per club).
static var slot := ""


## A new season: the league's ten clubs (league_clubs) in one league, no promotion or
## relegation. The player takes `team_id`. A later season passes its clubs in
## `teams` (an old save of three divisions keeps its thirty, in their division order).
static func start(team_id: String, games: int, seed_value: int, teams: Array[Team] = [], year: int = -1, carry: Club = null) -> Season:
	var clubs := teams if not teams.is_empty() else league_clubs()
	season = Season.create(clubs, 10, games, seed_value, RuleSet.kbo_2026(), LeagueEnvIO.load_default(), PitchCatalogIO.load_default(), LeagueEnvIO.load_overall(), ClubIO.load_default())
	season.season_year = year if year > 0 else league_year()
	# No second teams' league (the user: the futures league is the career's), but each club keeps
	# its second-team men to call up and to trade; an old league of three divisions keeps its
	# second teams' league.
	season.farm = FarmLeague.for_season(season) if season.divisions.size() > 1 else null
	season.manage(team_id)
	season.difficulty = Difficulty.by_id(Settings.difficulty)
	slot = "league_%s" % team_id
	if carry != null:
		season.club = carry
		season.clubs[team_id] = carry
		season.refresh_candidates()
	pending = null
	return season


## The league's clubs (the user: "the league is the first teams of the KBO's clubs only"): the
## ten of the newest real season in the local content pack (built by ./dev kbo, real-like names,
## each club's own first team and its futures players), or, without the pack (a copy from
## GitHub), the fictional league's ten top clubs.
static func league_clubs() -> Array[Team]:
	var packs := RosterIO.local_packs() if not testing() else []
	if not packs.is_empty():
		return RosterIO.load_pack(str(packs[0][0]))
	return RosterIO.load_pack(PACK).slice(0, 10)


## Under the test runner the league is the fictional one, whatever is in the local pack.
static func testing() -> bool:
	var loop := Engine.get_main_loop()
	return loop != null and loop.get_script() != null and str(loop.get_script().resource_path).contains("gut")


## The year a new league starts in: the local pack's season, or 2026.
static func league_year() -> int:
	var packs := RosterIO.local_packs() if not testing() else []
	if not packs.is_empty():
		return int(JsonIO.read_object(str(packs[0][0])).get("season", 2026))
	return 2026


## The league's name on the screens.
static func league_title() -> String:
	return "1군 리그"


## A season of the past played again: the pack's clubs in one league, that
## year's rules and calendar, the club the scenario names (or the one chosen). Ends with the
## comparison to what really happened; there is no next season.
static func start_history(pack: SeasonPack, scenario_id: String, team_id: String, seed_value: int) -> Season:
	var clubs := pack.clubs()
	# The ratings are that year's own: nobody grows during a season played again.
	for t: Team in clubs:
		for p: Player in t.players:
			p.potential = 0.0
	season = Season.create(clubs, clubs.size(), pack.games, seed_value, pack.rule_set(), LeagueEnvIO.load_default(), PitchCatalogIO.load_default(), LeagueEnvIO.load_overall(), ClubIO.load_default())
	season.season_year = pack.year
	season.history = pack
	season.scenario_id = scenario_id
	var calendar := pack.made_schedule()
	if calendar != null:
		season.schedules[0] = calendar
	# That year's first-team size.
	for t: Team in clubs:
		RosterMoves.trim(season, t, season.rules.registered_roster)
	var s := pack.scenario(scenario_id)
	season.manage(s.team if s != null else team_id)
	season.difficulty = Difficulty.by_id(Settings.difficulty)
	slot = "history_%s" % pack.id
	pending = null
	return season


## Next season: the same clubs and players, rearranged by promotion and relegation, a year on.
static func next_season(seed_value: int) -> Season:
	var old := season
	# The winter: retirements, rookies, a year older, the first teams made up again.
	var winter := Development.winter(old)
	var order: Array[Team] = []
	for ids: PackedStringArray in old.next_divisions():
		for id: String in ids:
			order.append(old.teams[id])
	var next := start(old.my_team, old.games_per_team, seed_value, order, old.season_year + 1, old.club)
	next.last_winter = winter
	return next


## Saves the season to its slot (after every day and game, docs/06 section 7).
static func autosave() -> void:
	if season == null or slot == "":
		return
	SaveIO.save_league(slot, season, Time.get_unix_time_from_system())
