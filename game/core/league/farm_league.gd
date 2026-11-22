class_name FarmLeague
extends RefCounted
## The second teams' league (퓨처스리그; docs/08 R6, IDEAS 12): on each day of the regular
## season every club's second team plays the second team of the club its first team plays,
## settled at once with the statistical resolver. Its own table per division and its own
## book of numbers; who played feeds the players' growth (Development).
##
## A second team is the club's unregistered players; where it is short of a full side it is
## made up with fillers (FILLERS roles) a little weaker than the club's prospects, so the
## prospects play. Fillers are made from the club's id and are the same every day and after
## loading. A team's starter is the next in its rotation by the games it has played, so a
## loaded season plays the same farm games as one played on.

const FILLERS: Array[String] = ["SP", "SP", "SP", "SP", "SP", "RP", "RP", "RP", "RP", "RP", "C", "C", "1B", "2B", "SS", "3B", "LF", "CF", "RF", "2B/SS", "LF/RF"]
## Fillers are this far below the club's prospects (the second-team level of its division).
const FILLER_GAP := 4.0

var standings: Array[Standings] = []
var book := StatBook.new()
## Every farm game played, in order (a save keeps these and rebuilds the tables from them).
var results: Array[ScheduledGame] = []
## The last day played (a day is played once, however often the season's day is).
var played_day := -1
## Ids of the players who played in a farm game today, for growth.
var played_today: Dictionary[String, bool] = {}

var _fillers: Dictionary[String, Array] = {}
var _names: NameTable


static func for_season(season: Season) -> FarmLeague:
	var f := FarmLeague.new()
	for ids: PackedStringArray in season.divisions:
		f.standings.append(Standings.of(ids))
	return f


## The day's farm games: one for each regular-season first-team game today.
func play_day(season: Season, games: Array[ScheduledGame]) -> void:
	played_today.clear()
	if played_day == season.day or season.phase != Season.Phase.REGULAR:
		return
	played_day = season.day
	for g: ScheduledGame in games:
		var d := season.division_of(g.home)
		if d < 0 or season.postseason_of(g) != null:
			continue
		var away := futures_team(season, g.away)
		var home := futures_team(season, g.home)
		var sim := GameSim.create(away, home, season.rules, season.env, season.catalog, season.ovr,
			season.rng.fork(hash("farm:%d:%s" % [season.day, g.home])), _starter(away, d, g.away), _starter(home, d, g.home))
		sim.play()
		var result := ScheduledGame.new()
		result.day = g.day
		result.away = g.away
		result.home = g.home
		result.finish(sim.state.score[0], sim.state.score[1], sim.state.inning)
		standings[d].record(result)
		results.append(result)
		for id: String in sim.scorer.book.batting:
			book.bat(id).add(sim.scorer.book.batting[id])
			played_today[id] = true
		for id: String in sim.scorer.book.pitching:
			book.pitch(id).add(sim.scorer.book.pitching[id])
			played_today[id] = true


## His turn in the rotation: by the games his team has played in this league.
func _starter(team: Team, d: int, team_id: String) -> Player:
	var starters := team.rotation()
	if starters.is_empty():
		return team.next_starter()
	return starters[standings[d].row(team_id).games() % starters.size()]


## A club's second team as a side: its unregistered players and its fillers.
func futures_team(season: Season, team_id: String) -> Team:
	var team: Team = season.teams[team_id]
	var view := Team.new()
	view.id = team_id
	view.name = team.name + " 2군"
	view.short_name = team.short_name
	view.stadium = team.stadium
	view.primary = team.primary
	view.secondary = team.secondary
	view.accent = team.accent
	view.steal_style = team.steal_style
	view.bunt_style = team.bunt_style
	for p: Player in team.second_team():
		view.players.append(p)
	for p: Player in fillers(season, team_id):
		view.players.append(p)
	return view


## The club's fillers, made once from its id.
func fillers(season: Season, team_id: String) -> Array:
	if _fillers.has(team_id):
		return _fillers[team_id]
	if _names == null:
		_names = RosterIO.load_names()
	var d := maxi(season.division_of(team_id), 0)
	var mean := LeagueGenerator.DIVISION_MEANS[mini(d, LeagueGenerator.DIVISION_MEANS.size() - 1)] - LeagueGenerator.FARM_GAP - FILLER_GAP
	var gen := LeagueGenerator.new(_names, season.catalog, hash("farm_fillers:" + team_id))
	var out: Array = []
	for i: int in FILLERS.size():
		var p := gen.player(FILLERS[i], mean)
		p.id = "ff_%s_%d" % [team_id, i]
		p.potential = 0.0
		out.append(p)
	_fillers[team_id] = out
	return out


## The second-team line of a player (empty lines when he has not played).
func batting(id: String) -> BattingLine:
	return book.batting.get(id, BattingLine.new())


func pitching(id: String) -> PitchingLine:
	return book.pitching.get(id, PitchingLine.new())


## Rebuilds the tables from the results (after loading).
func rebuild(season: Season) -> void:
	standings.clear()
	for ids: PackedStringArray in season.divisions:
		standings.append(Standings.of(ids))
	for g: ScheduledGame in results:
		var d := season.division_of(g.home)
		if d >= 0:
			standings[d].record(g)
