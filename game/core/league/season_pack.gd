class_name SeasonPack
extends RefCounted
## A season of the past to play again (IDEAS 8): its clubs and their players as
## they were, that year's rules, and what really happened — the final table, the champion,
## the title holders — with scenarios that set the player a goal ("win it with the team that
## finished sixth"). One JSON file:
##
##   {"format": 1, "id", "title", "year", "note",
##    "roster": path of a roster pack (RosterIO; relative to the season file or res://),
##    "teams": [club ids, in the order of the league],
##    "rules": {"games", "extra_innings", "foreign_players", "asia_quota", "registered_roster",
##              "designated_hitter", "pitch_clock", "ties_as_losses"},
##    "schedule": [[day, away, home], ...]   (optional; made from the rules when missing),
##    "postseason": [{"name", "wins", "head_start"}, ...]   (optional; today's KBO when missing),
##    "actual": {"standings": [[id, wins, losses, ties], ...], "champion": id,
##               "leaders": [[category, name, value], ...]},
##    "scenarios": [{"id", "title", "team", "text", "tagline", "path", "stars": [[name, line]],
##                   "goal": {"kind": "double" | "champion" | "rank" | "wins",
##                   "at_most" | "at_least": n}}]}
##
## A scenario is a club that made history that season (2016 두림 그리즐리스, 93 wins): the player
## takes it through the season, the league around it as it was.
##
## The game's own example (fictional clubs) is in data/seasons/; real seasons go in the local
## content pack, content-local/seasons/ (S17's collector makes them; never in git).

const FORMAT := 1
const BUILT_IN := "res://data/seasons"

var path := ""
var id := ""
var title := ""
var year := 2026
var note := ""
var roster := ""
var team_ids := PackedStringArray()
var games := 144
var extra_innings := 11
var foreign_players := 3
var asia_quota := 1
var registered_roster := 29
var designated_hitter := true
var pitch_clock := true
var ties_as_losses := false
## [day, away, home] of each game, or empty.
var schedule: Array = []
## [id, wins, losses, ties], best first.
var standings: Array = []
var champion := ""
## [category, name, value].
var leaders: Array = []
## That year's postseason rounds ({"name", "wins", "head_start"}); empty: the KBO's of today.
var postseason: Array = []
var scenarios: Array[Scenario] = []
## How each club looked that year (name, short name, colours), for screens that need no players.
var looks: Dictionary = {}
## Each club's home park that year and its effect: club id → {"park": name, "HR": ×, "H": ×}
## (H for singles, doubles and triples); runs and home runs at a park against away from it,
## as the record sites keep them. Empty: every park neutral.
var parks: Dictionary = {}


class Scenario:
	var id := ""
	var title := ""
	var team := ""
	var text := ""
	## One line under the title ("93승, 판타스틱 4"), and what the club really did ("정규 시즌
	## 1위 93승 1무 50패 · 한국시리즈 4승 0패").
	var tagline := ""
	var path := ""
	## Its leading men that year: [name, role, [[label, value], ...]] ("권도연", "3루수",
	## [["타율", ".347"], ["홈런", "38"], ["도루", "40"]]).
	var stars: Array = []
	## The last series it won: [wins, losses, against] ([4, 0, "NC"]), or empty.
	var final: Array = []
	## "double" (first in the table and champion), "champion", "rank" (finish at_most), "wins"
	## (at_least).
	var kind := "champion"
	var amount := 0


## Every season pack there is: the game's own, then the local content pack's.
static func available() -> Array[SeasonPack]:
	var out: Array[SeasonPack] = []
	for dir: String in [BUILT_IN, local_dir()]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var names := d.get_files()
		names.sort()
		for file: String in names:
			if file.ends_with(".json"):
				var pack := load_file(dir.path_join(file))
				if pack != null:
					out.append(pack)
	return out


static func local_dir() -> String:
	return LocalContent.dir().path_join("seasons")


static func by_id(pack_id: String) -> SeasonPack:
	for pack: SeasonPack in available():
		if pack.id == pack_id:
			return pack
	return null


static func load_file(file: String) -> SeasonPack:
	var d := JsonIO.read_object(file)
	if d.is_empty() or int(d.get("format", 0)) != FORMAT:
		return null
	var p := SeasonPack.new()
	p.path = file
	p.id = str(d.get("id", file.get_file().get_basename()))
	p.title = str(d.get("title", p.id))
	p.year = int(d.get("year", 2026))
	p.note = str(d.get("note", ""))
	var roster_path := str(d.get("roster", ""))
	p.roster = roster_path if roster_path.begins_with("res://") or roster_path.is_absolute_path() else file.get_base_dir().path_join(roster_path)
	p.team_ids = PackedStringArray(d.get("teams", []) as Array)
	var r: Dictionary = d.get("rules", {})
	p.games = int(r.get("games", 144))
	p.extra_innings = int(r.get("extra_innings", 11))
	p.foreign_players = int(r.get("foreign_players", 3))
	p.asia_quota = int(r.get("asia_quota", 1))
	p.registered_roster = int(r.get("registered_roster", 29))
	p.designated_hitter = bool(r.get("designated_hitter", true))
	p.pitch_clock = bool(r.get("pitch_clock", true))
	p.ties_as_losses = bool(r.get("ties_as_losses", false))
	p.schedule = (d.get("schedule", []) as Array).duplicate(true)
	p.postseason = (d.get("postseason", []) as Array).duplicate(true)
	var actual: Dictionary = d.get("actual", {})
	p.standings = (actual.get("standings", []) as Array).duplicate(true)
	p.champion = str(actual.get("champion", ""))
	p.leaders = (actual.get("leaders", []) as Array).duplicate(true)
	p.looks = (d.get("clubs", {}) as Dictionary).duplicate(true)
	p.parks = (d.get("parks", {}) as Dictionary).duplicate(true)
	for entry: Dictionary in d.get("scenarios", []):
		var s := Scenario.new()
		s.id = str(entry.get("id", ""))
		s.title = str(entry.get("title", ""))
		s.team = str(entry.get("team", ""))
		s.text = str(entry.get("text", ""))
		s.tagline = str(entry.get("tagline", ""))
		s.path = str(entry.get("path", ""))
		s.stars = (entry.get("stars", []) as Array).duplicate(true)
		s.final = (entry.get("final", []) as Array).duplicate(true)
		var goal: Dictionary = entry.get("goal", {})
		s.kind = str(goal.get("kind", "champion"))
		s.amount = int(goal.get("at_most", goal.get("at_least", 0)))
		p.scenarios.append(s)
	return p


func scenario(scenario_id: String) -> Scenario:
	for s: Scenario in scenarios:
		if s.id == scenario_id:
			return s
	return null


## That year's rules.
func rule_set() -> RuleSet:
	var r := RuleSet.kbo_2026()
	r.extra_inning_limit = extra_innings
	r.foreign_players = foreign_players
	r.asia_quota = asia_quota
	r.registered_roster = registered_roster
	r.active_roster = registered_roster - 1
	r.designated_hitter = designated_hitter
	r.ties_as_losses = ties_as_losses
	return r


## A home club's park as the resolver takes it: outcome key → multiplier.
func park_of(home: String) -> Dictionary:
	if not parks.has(home):
		return {}
	var p: Dictionary = parks[home]
	var hits := float(p.get("H", 1.0))
	return {"HR": float(p.get("HR", 1.0)), "1B": hits, "2B": hits, "3B": hits}


## That year's postseason (Postseason.Round list).
func postseason_format() -> Array[Postseason.Round]:
	return Postseason.format_from(postseason) if not postseason.is_empty() else Postseason.kbo()


## A club as it looked that year, without its players (an emblem, a name); from the roster
## pack when the season pack does not say.
func look(team_id: String) -> Team:
	var t := Team.new()
	t.id = team_id
	if looks.has(team_id):
		var l: Dictionary = looks[team_id]
		t.name = str(l.get("name", team_id))
		t.short_name = str(l.get("short", t.name))
		t.primary = Color.from_string(str(l.get("primary", "")), t.primary)
		t.secondary = Color.from_string(str(l.get("secondary", "")), t.secondary)
		t.accent = Color.from_string(str(l.get("accent", "")), t.accent)
		return t
	for c: Team in clubs():
		if c.id == team_id:
			return c
	return t


## The clubs as they were, in the league's order.
func clubs() -> Array[Team]:
	var all := RosterIO.load_pack(roster)
	var out: Array[Team] = []
	for team_id: String in team_ids:
		for t: Team in all:
			if t.id == team_id:
				out.append(t)
	return out


## The season's games from the pack, or null to make them.
func made_schedule() -> Schedule:
	if schedule.is_empty():
		return null
	var s := Schedule.new()
	s.team_ids = team_ids
	var last := 0
	for entry: Array in schedule:
		var g := ScheduledGame.make(int(entry[0]), str(entry[1]), str(entry[2]), 0, 1)
		s.games.append(g)
		last = maxi(last, g.day)
	s.days = last + 1
	return s


## A club's real finish: its place (1 = first) and its record, or place 0 when unknown.
func actual_of(team_id: String) -> Array:
	for i: int in standings.size():
		var row: Array = standings[i]
		if str(row[0]) == team_id:
			return [i + 1, int(row[1]), int(row[2]), int(row[3]) if row.size() > 3 else 0]
	return [0, 0, 0, 0]


## Whether a finished season met a scenario's goal for its club.
static func goal_met(s: Scenario, season: Season) -> bool:
	var d := season.division_of(s.team)
	if d < 0:
		return false
	match s.kind:
		"double":
			return season.champion_of(d) == s.team and season.standings[d].rank_of(s.team) == 1
		"champion":
			return season.champion_of(d) == s.team
		"rank":
			return season.standings[d].rank_of(s.team) <= s.amount
		"wins":
			return season.standings[d].row(s.team).wins >= s.amount
	return false


static func goal_text(s: Scenario) -> String:
	match s.kind:
		"double":
			return "통합 우승"
		"champion":
			return "우승"
		"rank":
			return "정규 시즌 %d위 안" % s.amount
		"wins":
			return "정규 시즌 %d승 이상" % s.amount
	return ""
