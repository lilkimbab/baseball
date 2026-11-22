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


## A new season with the roster pack's thirty clubs in three divisions (top first). The player
## takes `team_id`; `order` gives the clubs' division order (a later season's movements).
static func start(team_id: String, games: int, seed_value: int, teams: Array[Team] = [], year: int = 2026, carry: Club = null) -> Season:
	var clubs := teams if not teams.is_empty() else RosterIO.load_pack(PACK)
	season = Season.create(clubs, 10, games, seed_value, RuleSet.kbo_2026(), LeagueEnvIO.load_default(), PitchCatalogIO.load_default(), LeagueEnvIO.load_overall(), ClubIO.load_default())
	season.season_year = year
	season.farm = FarmLeague.for_season(season)
	season.manage(team_id)
	slot = "league_%s" % team_id
	if carry != null:
		season.club = carry
		season.clubs[team_id] = carry
		season.refresh_candidates()
	pending = null
	return season


## A season of the past played again (docs/08 R7): the pack's clubs in one league, that
## year's rules and calendar, the club the scenario names (or the one chosen). Ends with the
## comparison to what really happened; there is no next season.
static func start_history(pack: SeasonPack, scenario_id: String, team_id: String, seed_value: int) -> Season:
	var clubs := pack.clubs()
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
	slot = "history_%s" % pack.id
	pending = null
	return season


## Next season: the same clubs and players, rearranged by promotion and relegation, a year on.
static func next_season(seed_value: int) -> Season:
	var old := season
	# The winter (docs/08 R6): retirements, rookies, a year older, the first teams made up again.
	var winter := Development.winter(old)
	var order: Array[Team] = []
	for ids: PackedStringArray in old.next_divisions():
		for id: String in ids:
			order.append(old.teams[id])
	var next := start(old.my_team, old.games_per_team, seed_value, order, old.season_year + 1, old.club)
	next.last_winter = winter
	return next


## Saves the season to its slot (after every day and game, docs/07 section 7).
static func autosave() -> void:
	if season == null or slot == "":
		return
	SaveIO.save_league(slot, season, Time.get_unix_time_from_system())
