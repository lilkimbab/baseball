class_name SchoolLeague
extends RefCounted
## The high-school league a career begins in (docs/08 R8-3; the user, 2026-11-23: "a third
## tier, a high-school league: real school names, students made up with common names, below the
## pros in skill, the user's player too"). His school's weekend league (주말리그: the schools of
## his region, data/schools.ko.json) is a short season, then its best play off for the
## region's title (왕중왕전); after it the draft (Draft).
##
## The league is a Season like the pros' (its own schedule, table, book, injuries), so the
## career plays it as it plays a pro season: the hub, the games on screen or at once, growth.
## A school's players are students of the first to third year (16 to 18), at the level of
## data "talent" (the pros' second teams are some ten points above); he is one of its third-
## year players, on the team from the start (a school has no second team).

const DATA := "res://data/schools.ko.json"
## A school's squad: six pitchers, two catchers, the seven places, three who play two.
const ROSTER: Array[String] = ["SP", "SP", "SP", "RP", "RP", "RP", "C", "C", "1B", "2B", "SS", "3B", "LF", "CF", "RF", "2B/SS", "LF/RF", "1B/3B"]
## Of a squad, the share in each year (third, second, first).
const YEARS: Array[float] = [0.45, 0.35, 0.2]
## The region's playoff: the top three, one game each (third against second, the winner against
## first).
const PLAYOFF_TEAMS := 3


static func data() -> Dictionary:
	return JsonIO.read_object(DATA)


static func schools() -> Array:
	return data().get("schools", [])


static func school(id: String) -> Dictionary:
	for s: Dictionary in schools():
		if str(s["id"]) == id:
			return s
	return {}


## The schools of a school's weekend league (itself among them).
static func league_of(school_id: String) -> Array:
	var league := str(school(school_id).get("league", ""))
	return schools().filter(func(s: Dictionary) -> bool: return str(s["league"]) == league)


## A school as a side: its students, made from its id and the year (the same every time).
static func team_for(s: Dictionary, year: int, catalog: Dictionary[StringName, PitchType], names: NameTable) -> Team:
	var t := Team.new()
	t.id = str(s["id"])
	t.name = str(s["name"])
	t.short_name = str(s["name"])
	t.stadium = t.id
	t.primary = Color.html(str(s.get("primary", "#223355")))
	t.secondary = Color.html(str(s.get("secondary", "#f2f2f2")))
	t.accent = Color.html(str(s.get("accent", "#88aacc")))
	var talent := float(data().get("talent", 37.0))
	var gen := LeagueGenerator.new(names, catalog, hash("school:%s:%d" % [t.id, year]))
	var rng := Rng.new(hash("school_years:%s:%d" % [t.id, year]))
	for i: int in ROSTER.size():
		var roll := rng.next_float()
		var age := 18 if roll < YEARS[0] else (17 if roll < YEARS[0] + YEARS[1] else 16)
		# A younger student is further from what he will be (the generator takes off for youth).
		var p := gen.player(ROSTER[i], talent + rng.next_normal() * 2.5)
		p.id = "%s_%d_%d" % [t.id, year, i]
		p.born = year - age
		p.number = i + 1
		p.potential = Development.initial_room(age, rng, true)
		t.players.append(p)
		t.registered.append(p.id)
	return t


## His school's season: the schools of its league, each playing `games`, then the playoff.
static func season_for(c: CareerPlayer, school_id: String, year: int, seed_value: int, catalog: Dictionary[StringName, PitchType] = {}) -> Season:
	var cat := catalog if not catalog.is_empty() else PitchCatalogIO.load_default()
	var names := RosterIO.load_names()
	var teams: Array[Team] = []
	for s: Dictionary in league_of(school_id):
		teams.append(team_for(s, year, cat, names))
	# About `season_games` each: so many meetings of each pair (two to four), in a circle with a
	# bye when the league is odd.
	var n := teams.size()
	var meetings := clampi(roundi(float(data().get("season_games", 14)) / maxf(n - 1, 1.0)), 2, 4)
	var games := meetings * (n + n % 2 - 1)
	var season := Season.create(teams, teams.size(), games, seed_value, RuleSet.kbo_2026(), LeagueEnvIO.load_default(), cat, LeagueEnvIO.load_overall(), ClubIO.load_default())
	season.season_year = year
	season.school = true
	var his: Team = season.teams[school_id]
	c.join(his)
	# A school has no second team: he plays from the first day, a third-year student.
	his.registered.append(c.player.id)
	c.first_team = true
	c.player.born = year - 18
	return season


## The region's playoff (its rounds, for Season.postseason_format).
static func playoff() -> Array[Postseason.Round]:
	return [Postseason.Round.make("왕중왕전 준결승", 1), Postseason.Round.make("왕중왕전 결승", 1)]
