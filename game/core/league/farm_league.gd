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


## A league of one division (docs/08 R8-1) has the KBO's futures league (data/futures.ko.json):
## the clubs' second teams and two teams of their own, north and south, on a calendar of their
## own. An older league of three divisions keeps the old way: each second team plays its club's
## opponent of the day.
const DATA := "res://data/futures.ko.json"
## The futures league's own calendar (null: the old way).
var schedule: Schedule
var north := PackedStringArray()
var south := PackedStringArray()
## Its own teams (not a club's): id -> their data.
var independents: Dictionary[String, Dictionary] = {}
## Second teams with a name of their own: club id -> name.
var names: Dictionary[String, String] = {}
var _own_teams: Dictionary[String, Team] = {}


static func for_season(season: Season) -> FarmLeague:
	var f := FarmLeague.new()
	f._set_up(season)
	return f


func _set_up(season: Season) -> void:
	standings.clear()
	if season.divisions.size() != 1 or season.history != null:
		for ids: PackedStringArray in season.divisions:
			standings.append(Standings.of(ids))
		return
	var d := JsonIO.read_object(DATA)
	for e: Dictionary in (d.get("independents", []) as Array):
		independents[str(e["id"])] = e
	var given: Dictionary = d.get("names", {})
	for key: String in given:
		names[key] = str(given[key])
	var clubs := season.divisions[0]
	var listed_north: Array = d.get("north", [])
	var listed_south: Array = d.get("south", [])
	var rest := PackedStringArray()
	for id: String in clubs:
		if listed_north.has(id):
			north.append(id)
		elif listed_south.has(id):
			south.append(id)
		else:
			rest.append(id)
	# A fictional league's clubs: half north, half south.
	for i: int in rest.size():
		if north.size() <= south.size():
			north.append(rest[i])
		else:
			south.append(rest[i])
	for id: String in independents:
		if listed_north.has(id) or (not listed_south.has(id) and north.size() <= south.size()):
			north.append(id)
		else:
			south.append(id)
	var ids := north + south
	var games := maxi(roundi(season.games_per_team * float(d.get("games", 121)) / 144.0), 10)
	schedule = Schedule.make(ids, games, Rng.new(hash("futures:%d" % season.season_year)))
	standings.append(Standings.of(ids))


## The day's farm games: one for each regular-season first-team game today.
func play_day(season: Season, games: Array[ScheduledGame]) -> void:
	played_today.clear()
	if played_day == season.day or season.phase != Season.Phase.REGULAR:
		return
	played_day = season.day
	var todays: Array[ScheduledGame] = games
	if schedule != null:
		todays = schedule.games_on(season.day) if season.day < schedule.days else ([] as Array[ScheduledGame])
	for g: ScheduledGame in todays:
		var d := 0 if schedule != null else season.division_of(g.home)
		if d < 0 or (schedule == null and season.postseason_of(g) != null):
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


## A club's second team as a side: its unregistered players and its fillers (its name the
## club's with 2군, or its own: names); or one of the league's own teams.
func futures_team(season: Season, team_id: String) -> Team:
	if independents.has(team_id):
		return _own_team(season, team_id)
	var team: Team = season.teams[team_id]
	var view := Team.new()
	view.id = team_id
	view.name = names.get(team_id, team.name + " 2군")
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


## One of the league's own teams (the armed forces', a city's): a full side made once from its
## id, its players at the futures level and its own above or below it (data "level").
func _own_team(season: Season, team_id: String) -> Team:
	if _own_teams.has(team_id):
		return _own_teams[team_id]
	var e: Dictionary = independents[team_id]
	var t := Team.new()
	t.id = team_id
	t.name = str(e.get("name", team_id))
	t.short_name = str(e.get("short", t.name))
	t.primary = Color.html(str(e.get("primary", "#333333")))
	t.secondary = Color.html(str(e.get("secondary", "#ffffff")))
	t.accent = Color.html(str(e.get("accent", "#cccccc")))
	if _names == null:
		_names = RosterIO.load_names()
	var mean := LeagueGenerator.DIVISION_MEANS[0] - LeagueGenerator.FARM_GAP + float(e.get("level", 0.0))
	var gen := LeagueGenerator.new(_names, season.catalog, hash("futures_team:" + team_id))
	var roles: Array[String] = ["SP", "SP", "SP", "SP", "SP", "RP", "RP", "RP", "RP", "RP", "RP", "RP", "C", "C", "1B", "2B", "SS", "3B", "LF", "CF", "RF", "2B/SS", "LF/RF", "1B/3B"]
	for i: int in roles.size():
		var p := gen.player(roles[i], mean)
		p.id = "fo_%s_%d" % [team_id, i]
		p.number = i + 1
		p.potential = 0.0
		t.players.append(p)
	_own_teams[team_id] = t
	return t


## The team on a futures table row: a club's second team or one of the league's own.
func team_of(season: Season, team_id: String) -> Team:
	return futures_team(season, team_id) if independents.has(team_id) or season.teams.has(team_id) else null


## The second-team line of a player (empty lines when he has not played).
func batting(id: String) -> BattingLine:
	return book.batting.get(id, BattingLine.new())


func pitching(id: String) -> PitchingLine:
	return book.pitching.get(id, PitchingLine.new())


## Rebuilds the tables from the results (after loading).
func rebuild(season: Season) -> void:
	north.clear()
	south.clear()
	independents.clear()
	_set_up(season)
	for g: ScheduledGame in results:
		var d := 0 if schedule != null else season.division_of(g.home)
		if d >= 0:
			standings[d].record(g)
