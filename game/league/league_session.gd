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


## A new season with the roster pack's thirty clubs in three divisions (top first). The player
## takes `team_id`; `order` gives the clubs' division order (a later season's movements).
static func start(team_id: String, games: int, seed_value: int, teams: Array[Team] = [], year: int = 2026, carry: Club = null) -> Season:
	var clubs := teams if not teams.is_empty() else RosterIO.load_pack(PACK)
	season = Season.create(clubs, 10, games, seed_value, RuleSet.kbo_2026(), LeagueEnvIO.load_default(), PitchCatalogIO.load_default(), LeagueEnvIO.load_overall(), ClubIO.load_default())
	season.season_year = year
	season.manage(team_id)
	if carry != null:
		season.club = carry
		season.clubs[team_id] = carry
		season.refresh_candidates()
	pending = null
	return season


## Next season: the same clubs and players, rearranged by promotion and relegation, a year on.
static func next_season(seed_value: int) -> Season:
	var old := season
	var order: Array[Team] = []
	for ids: PackedStringArray in old.next_divisions():
		for id: String in ids:
			order.append(old.teams[id])
	return start(old.my_team, old.games_per_team, seed_value, order, old.season_year + 1, old.club)
