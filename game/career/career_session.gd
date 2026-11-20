class_name CareerSession
extends RefCounted
## The career in progress, kept while the screens change: the player, his season, and the game
## about to be played on screen. Saving comes with S9.

const CREATE := "res://career/creation_screen.tscn"
const HUB := "res://career/career_screen.tscn"
const MATCH := "res://career/career_match.tscn"
const DERBY := "res://career/home_run_derby.tscn"

static var career: CareerPlayer
static var season: Season
static var career_season: CareerSeason
## What the last game earned, for the hub.
static var last_report: CareerSeason.Report


## A new career: the player joins `team_id`'s second team in a new season of the fictional
## league (every club at today's condition; no club management, the player is not the manager).
static func start(c: CareerPlayer, team_id: String, games: int, seed_value: int) -> void:
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	season = Season.create(clubs, 10, games, seed_value, RuleSet.kbo_2026(), LeagueEnvIO.load_default(), PitchCatalogIO.load_default(), LeagueEnvIO.load_overall(), ClubIO.load_default())
	c.join(season.teams[team_id])
	career = c
	career_season = CareerSeason.start(season, c, CareerIO.load_default())
	last_report = null
