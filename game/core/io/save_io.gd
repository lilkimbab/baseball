class_name SaveIO
extends RefCounted
## Save games (docs/07 section 7, docs/13 S9): a slot is a folder under user://saves with
## meta.json (what the slot holds, for the load screen) and league.json or career.json (the
## whole season: clubs and players as they are now, schedules and results, books, pitcher
## use, condition, the player's club or career). Files are gzip-compressed JSON with a
## "format" number; older formats are brought up to date by MIGRATIONS on loading. A file is
## written to a temporary name first and then renamed, so a crash never leaves half a save.
##
## The standings and the postseason's wins are not stored: they are worked out again from the
## games' scores.

const FORMAT := 1
const ROOT := "user://saves"
## format → Callable(Dictionary) -> Dictionary bringing a save of that format to the next.
const MIGRATIONS := {}


# --- Files ---


static func slot_path(slot: String) -> String:
	return "%s/%s" % [ROOT, slot]


static func write(path: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var tmp := path + ".tmp"
	var file := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return DirAccess.get_open_error()
	if dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	return dir.rename(tmp.get_file(), path.get_file())


static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return migrate(parsed) if parsed is Dictionary else {}


## Brings an older save up to FORMAT, one step at a time.
static func migrate(data: Dictionary) -> Dictionary:
	var out := data
	var f := int(out.get("format", FORMAT))
	while f < FORMAT and MIGRATIONS.has(f):
		var step: Callable = MIGRATIONS[f]
		out = step.call(out)
		f += 1
		out["format"] = f
	return out


## Slots with their summaries, newest first.
static func slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return out
	for name: String in dir.get_directories():
		var meta := read("%s/%s/meta.json" % [ROOT, name])
		if not meta.is_empty():
			meta["slot"] = name
			out.append(meta)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("saved", 0)) > float(b.get("saved", 0)))
	return out


static func delete_slot(slot: String) -> void:
	var path := ProjectSettings.globalize_path(slot_path(slot))
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f: String in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(path)


# --- League and career ---


## What the load screen shows of a save beside its name: the club (its name, id and colours,
## for its emblem) and its record so far.
static func _meta_club(meta: Dictionary, season: Season, club_id: String) -> void:
	var team: Team = season.teams.get(club_id)
	if team == null:
		return
	meta["club"] = team.name
	meta["club_id"] = team.id
	meta["primary"] = team.primary.to_html(false)
	meta["accent"] = team.accent.to_html(false)
	var d := season.division_of(club_id)
	var table: Standings = season.standings[d] if d >= 0 and d < season.standings.size() else null
	var row: StandingsRow = table.row(club_id) if table != null else null
	if row != null:
		meta["record"] = [row.wins, row.losses, row.ties]


static func save_league(slot: String, season: Season, saved_at: float) -> Error:
	var team: Team = season.teams.get(season.my_team)
	var meta := {"format": FORMAT, "mode": "league", "saved": saved_at, "team": team.name if team != null else "", "year": season.season_year, "day": season.day + 1}
	_meta_club(meta, season, season.my_team)
	var err := write(slot_path(slot) + "/meta.json", meta)
	if err != OK:
		return err
	return write(slot_path(slot) + "/league.json", {"format": FORMAT, "season": season_to(season)})


static func load_league(slot: String) -> Season:
	var data := read(slot_path(slot) + "/league.json")
	if data.is_empty():
		return null
	return season_from(data["season"])


static func save_career(slot: String, cs: CareerSeason, saved_at: float) -> Error:
	var meta := {"format": FORMAT, "mode": "career", "saved": saved_at, "team": cs.career.player.name, "year": cs.season.season_year, "day": cs.season.day + 1}
	_meta_club(meta, cs.season, cs.career.team_id)
	meta["first_team"] = cs.career.first_team
	var err := write(slot_path(slot) + "/meta.json", meta)
	if err != OK:
		return err
	return write(slot_path(slot) + "/career.json", {"format": FORMAT, "season": season_to(cs.season), "career": career_to(cs)})


static func load_career(slot: String) -> CareerSeason:
	var data := read(slot_path(slot) + "/career.json")
	if data.is_empty():
		return null
	var season := season_from(data["season"])
	return career_from(data["career"], season)


# --- Seasons ---


static func season_to(s: Season) -> Dictionary:
	var teams: Array = []
	var players: Array = []
	for id: String in _team_order(s):
		var t: Team = s.teams[id]
		var ids: Array = []
		for p: Player in t.players:
			ids.append(p.id)
			players.append(RosterIO.player_to(p, true))
		teams.append({
			"id": t.id, "name": t.name, "short": t.short_name, "stadium": t.stadium,
			"colors": ["#" + t.primary.to_html(false), "#" + t.secondary.to_html(false), "#" + t.accent.to_html(false)],
			"styles": [t.steal_style, t.bunt_style], "players": ids, "registered": Array(t.registered),
			"removed_on": t.removed_on.duplicate(), "rotation_index": t.rotation_index,
			"batting_plan": t.batting_plan.duplicate(true), "rotation_plan": Array(t.rotation_plan), "bullpen_plan": t.bullpen_plan.duplicate(true),
		})
	var schedules: Array = []
	for sched: Schedule in s.schedules:
		var games: Array = []
		for g: ScheduledGame in sched.games:
			games.append(_game_to(g))
		schedules.append({"ids": Array(sched.team_ids), "days": sched.days, "games": games})
	var postseasons: Array = []
	for p: Postseason in s.postseasons:
		var rounds: Array = []
		for r: PlayoffSeries in p.rounds:
			var games: Array = []
			for g: ScheduledGame in r.games:
				games.append(_game_to(g))
			rounds.append({"high": r.high, "low": r.low, "need": r.wins_needed, "start": r.head_start, "games": games})
		postseasons.append({"seeds": Array(p.seeds), "current": p.current, "ready_day": p.ready_day, "rounds": rounds, "format": Postseason.format_to(p.format)})
	var usage := {}
	for id: String in s.usage.outings:
		var list: Array = []
		for o: Vector2i in s.usage.outings[id]:
			list.append([o.x, o.y])
		usage[id] = list
	var recent := {}
	for id: String in s.recent:
		var list: Array = []
		for l: BattingLine in s.recent[id]:
			list.append(fields(l))
		recent[id] = list
	var divisions: Array = []
	for d: PackedStringArray in s.divisions:
		divisions.append(Array(d))
	return {
		"year": s.season_year, "games": s.games_per_team, "day": s.day, "phase": s.phase,
		"my_team": s.my_team, "featured": s.featured, "featured_role": s.featured_role,
		"rng": _state_to(s.rng), "management": s.club_rules != null,
		"teams": teams, "players": players, "divisions": divisions, "schedules": schedules,
		"postseasons": postseasons, "book": book_to(s.book), "postseason_book": book_to(s.postseason_book),
		"usage": usage, "recent": recent, "sitting": s.sitting.duplicate(), "condition": s.condition.duplicate(),
		"streak": s.streak.duplicate(), "starters": s._starters.duplicate(),
		"club": club_to(s.club) if s.club != null else {},
		"farm": _farm_to(s.farm) if s.farm != null else {},
		"grown": s.grown.duplicate(), "played_today": s.played_today.keys(),
		"last_winter": _winter_to(s.last_winter) if s.last_winter != null else {},
		"history": {"pack": s.history.id, "scenario": s.scenario_id} if s.history != null else {},
		"level_games": Array(s.level_games), "difficulty": s.difficulty, "level_days": Array(s.level_days),
		"involvement": [s.involvement_sum, s.involvement_games], "rewarded": s.rewarded,
		"injuries": s.injuries.to_dict(),
	}


static func _farm_to(f: FarmLeague) -> Dictionary:
	var games: Array = []
	for g: ScheduledGame in f.results:
		games.append(_game_to(g))
	return {"games": games, "book": book_to(f.book), "played_day": f.played_day, "played_today": f.played_today.keys()}


static func _farm_from(d: Dictionary, s: Season) -> FarmLeague:
	var f := FarmLeague.new()
	for g: Array in d.get("games", []):
		f.results.append(_game_from(g))
	f.book = book_from(d.get("book", {}))
	f.played_day = int(d.get("played_day", -1))
	for id: Variant in d.get("played_today", []):
		f.played_today[str(id)] = true
	f.rebuild(s)
	return f


static func _winter_to(w: Development.Winter) -> Dictionary:
	return {"year": w.year, "retired": w.retired.duplicate(true), "rookies": w.rookies.duplicate(true), "risers": w.risers.duplicate(true)}


static func _winter_from(d: Dictionary) -> Development.Winter:
	var w := Development.Winter.new()
	w.year = int(d.get("year", 0))
	w.retired = (d.get("retired", []) as Array).duplicate(true)
	w.rookies = (d.get("rookies", []) as Array).duplicate(true)
	w.risers = (d.get("risers", []) as Array).duplicate(true)
	return w


static func season_from(d: Dictionary) -> Season:
	var s := Season.new()
	s.rules = RuleSet.kbo_2026()
	s.env = LeagueEnvIO.load_default()
	s.catalog = PitchCatalogIO.load_default()
	s.ovr = LeagueEnvIO.load_overall()
	if bool(d.get("management", false)):
		s.club_rules = ClubIO.load_default()
	s.season_year = int(d.get("year", 2026))
	s.games_per_team = int(d.get("games", 144))
	s.day = int(d.get("day", 0))
	s.phase = int(d.get("phase", 0)) as Season.Phase
	s.my_team = str(d.get("my_team", ""))
	s.featured = str(d.get("featured", ""))
	s.featured_role = str(d.get("featured_role", ""))
	s.rng = Rng.new()
	s.rng.set_state(_state_from(d.get("rng", [])))
	var players: Dictionary[String, Player] = {}
	for entry: Dictionary in d.get("players", []):
		var p := RosterIO.player_from(entry)
		players[p.id] = p
	for entry: Dictionary in d.get("teams", []):
		var t := Team.new()
		t.id = str(entry["id"])
		t.name = str(entry.get("name", ""))
		t.short_name = str(entry.get("short", ""))
		t.stadium = str(entry.get("stadium", ""))
		var colors: Array = entry.get("colors", [])
		if colors.size() == 3:
			t.primary = Color.from_string(str(colors[0]), t.primary)
			t.secondary = Color.from_string(str(colors[1]), t.secondary)
			t.accent = Color.from_string(str(colors[2]), t.accent)
		var styles: Array = entry.get("styles", [1.0, 1.0])
		t.steal_style = float(styles[0])
		t.bunt_style = float(styles[1])
		for id: Variant in entry.get("players", []):
			if players.has(str(id)):
				t.players.append(players[str(id)])
		t.registered = PackedStringArray(entry.get("registered", []) as Array)
		var removed: Dictionary = entry.get("removed_on", {})
		for id: String in removed:
			t.removed_on[id] = int(removed[id])
		t.rotation_index = int(entry.get("rotation_index", 0))
		t.batting_plan = (entry.get("batting_plan", []) as Array).duplicate(true)
		t.rotation_plan = PackedStringArray(entry.get("rotation_plan", []) as Array)
		t.bullpen_plan = (entry.get("bullpen_plan", {}) as Dictionary).duplicate(true)
		s.teams[t.id] = t
	for ids: Array in d.get("divisions", []):
		s.divisions.append(PackedStringArray(ids))
	for entry: Dictionary in d.get("schedules", []):
		var sched := Schedule.new()
		sched.team_ids = PackedStringArray(entry.get("ids", []) as Array)
		sched.days = int(entry.get("days", 0))
		for g: Array in entry.get("games", []):
			sched.games.append(_game_from(g))
		s.schedules.append(sched)
		var table := Standings.of(sched.team_ids)
		for g: ScheduledGame in sched.games:
			table.record(g)
		s.standings.append(table)
	for entry: Dictionary in d.get("postseasons", []):
		var p := Postseason.new()
		p.seeds = PackedStringArray(entry.get("seeds", []) as Array)
		p.current = int(entry.get("current", 0))
		p.ready_day = int(entry.get("ready_day", 0))
		# A save from before the format was kept: the ladder of four it was then.
		p.format = Postseason.format_from(entry.get("format", []) as Array) if entry.has("format") else Postseason.ladder("결승")
		for r: Dictionary in entry.get("rounds", []):
			var series := PlayoffSeries.make(str(r["high"]), str(r["low"]), int(r["need"]))
			series.head_start = int(r.get("start", 0))
			series.high_wins = series.head_start
			for g: Array in r.get("games", []):
				var game := _game_from(g)
				series.games.append(game)
				if game.played:
					series.record(game)
			p.rounds.append(series)
		s.postseasons.append(p)
	s.book = book_from(d.get("book", {}))
	s.postseason_book = book_from(d.get("postseason_book", {}))
	var usage: Dictionary = d.get("usage", {})
	for id: String in usage:
		var list: Array = []
		for o: Array in usage[id]:
			list.append(Vector2i(int(o[0]), int(o[1])))
		s.usage.outings[id] = list
	var recent: Dictionary = d.get("recent", {})
	for id: String in recent:
		var list: Array = []
		for f: Dictionary in recent[id]:
			var l := BattingLine.new()
			fill(l, f)
			list.append(l)
		s.recent[id] = list
	_ints_into(d.get("sitting", {}), s.sitting)
	_ints_into(d.get("condition", {}), s.condition)
	_ints_into(d.get("streak", {}), s.streak)
	var starters: Dictionary = d.get("starters", {})
	for key: String in starters:
		s._starters[key] = str(starters[key])
	var club: Dictionary = d.get("club", {})
	if not club.is_empty():
		s.club = club_from(club)
		s.clubs[s.club.team_id] = s.club
	var farm: Dictionary = d.get("farm", {})
	if not farm.is_empty():
		s.farm = _farm_from(farm, s)
	var grown: Dictionary = d.get("grown", {})
	for id: String in grown:
		s.grown[id] = float(grown[id])
	for id: Variant in d.get("played_today", []):
		s.played_today[str(id)] = true
	var winter: Dictionary = d.get("last_winter", {})
	if not winter.is_empty():
		s.last_winter = _winter_from(winter)
	s.difficulty = int(d.get("difficulty", Difficulty.Level.PRO))
	var days_at: Array = d.get("level_days", [])
	if days_at.size() == 4:
		s.level_days = PackedInt32Array(days_at)
	var involvement: Array = d.get("involvement", [])
	if involvement.size() == 2:
		s.involvement_sum = float(involvement[0])
		s.involvement_games = int(involvement[1])
	s.rewarded = bool(d.get("rewarded", false))
	s.injuries.load_dict(d.get("injuries", {}))
	var levels: Array = d.get("level_games", [])
	if levels.size() == 4:
		s.level_games = PackedInt32Array(levels)
	# A save from before players had room to grow.
	Development.give_rooms(s.teams.values(), s.season_year)
	var history: Dictionary = d.get("history", {})
	if not history.is_empty():
		s.history = SeasonPack.by_id(str(history.get("pack", "")))
		s.scenario_id = str(history.get("scenario", ""))
		s.rules = s.history.rule_set() if s.history != null else s.rules
		for table: Standings in s.standings:
			table.count_ties_as_losses(s.rules.ties_as_losses)
	return s


static func _team_order(s: Season) -> PackedStringArray:
	var out := PackedStringArray()
	for d: PackedStringArray in s.divisions:
		out.append_array(d)
	return out


static func _game_to(g: ScheduledGame) -> Array:
	return [g.day, g.away, g.home, g.series, g.game_in_series, g.played, g.away_score, g.home_score, g.innings]


static func _game_from(a: Array) -> ScheduledGame:
	var g := ScheduledGame.make(int(a[0]), str(a[1]), str(a[2]), int(a[3]), int(a[4]))
	if bool(a[5]):
		g.finish(int(a[6]), int(a[7]), int(a[8]))
	return g


# --- Books and flat objects ---


static func book_to(b: StatBook) -> Dictionary:
	var bat := {}
	for id: String in b.batting:
		bat[id] = fields(b.batting[id])
	var pit := {}
	for id: String in b.pitching:
		pit[id] = fields(b.pitching[id])
	return {"batting": bat, "pitching": pit}


static func book_from(d: Dictionary) -> StatBook:
	var b := StatBook.new()
	var bat: Dictionary = d.get("batting", {})
	for id: String in bat:
		fill(b.bat(id), bat[id])
	var pit: Dictionary = d.get("pitching", {})
	for id: String in pit:
		fill(b.pitch(id), pit[id])
	return b


## The plain fields (numbers, text, true/false) of an object.
static func fields(obj: Object) -> Dictionary:
	var out := {}
	for prop: Dictionary in obj.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name := str(prop["name"])
		var value: Variant = obj.get(name)
		match typeof(value):
			TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_BOOL:
				out[name] = value
	return out


## Sets plain fields back, as the object's own types (JSON keeps every number as a float).
static func fill(obj: Object, d: Dictionary) -> void:
	for name: String in d:
		var current: Variant = obj.get(name)
		match typeof(current):
			TYPE_INT:
				obj.set(name, int(d[name]))
			TYPE_FLOAT:
				obj.set(name, float(d[name]))
			TYPE_STRING:
				obj.set(name, str(d[name]))
			TYPE_BOOL:
				obj.set(name, bool(d[name]))


static func _ints_into(from: Dictionary, into: Dictionary) -> void:
	for key: Variant in from:
		into[str(key)] = int(from[key])


## Random number state: 64-bit integers, written as text (JSON numbers are doubles).
static func _state_to(rng: Rng) -> Array:
	var out: Array = []
	for v: int in rng.get_state():
		out.append(str(v))
	return out


static func _state_from(a: Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for v: Variant in a:
		out.append(str(v).to_int())
	while out.size() < 4:
		out.append(1)
	return out


# --- The player's club ---


static func club_to(c: Club) -> Dictionary:
	var traits := {}
	for id: String in c.traits:
		traits[id] = [c.traits[id].x, c.traits[id].y]
	var bag: Array = []
	for item: Vector2i in c.bag:
		bag.append([item.x, item.y])
	var candidates: Array = []
	for p: Player in c.candidates:
		candidates.append(RosterIO.player_to(p, true))
	return {
		"team": c.team_id, "points": c.points, "scout_level": c.scout_level, "traits": traits, "bag": bag,
		"homegrown": c.homegrown.keys(), "developed": c.developed.keys(), "gained": c.gained.duplicate(),
		"training": c.training.duplicate(), "candidates": candidates, "signed_today": c.signed_today,
	}


static func club_from(d: Dictionary) -> Club:
	var c := Club.new()
	c.team_id = str(d.get("team", ""))
	c.points = int(d.get("points", 0))
	c.scout_level = int(d.get("scout_level", 1))
	var traits: Dictionary = d.get("traits", {})
	for id: String in traits:
		var a: Array = traits[id]
		c.traits[id] = Vector2i(int(a[0]), int(a[1]))
	for a: Array in d.get("bag", []):
		c.bag.append(Vector2i(int(a[0]), int(a[1])))
	for id: Variant in d.get("homegrown", []):
		c.homegrown[str(id)] = true
	for id: Variant in d.get("developed", []):
		c.developed[str(id)] = true
	var gained: Dictionary = d.get("gained", {})
	for id: String in gained:
		c.gained[id] = float(gained[id])
	var training: Dictionary = d.get("training", {})
	for id: String in training:
		c.training[id] = str(training[id])
	for entry: Dictionary in d.get("candidates", []):
		c.candidates.append(RosterIO.player_from(entry))
	c.signed_today = bool(d.get("signed_today", false))
	return c


# --- The career ---


static func career_to(cs: CareerSeason) -> Dictionary:
	var c := cs.career
	var uses := {}
	for id: StringName in c.pitch_uses:
		uses[String(id)] = c.pitch_uses[id]
	return {
		"player": c.player.id, "position": c.position, "type": c.type_id, "team": c.team_id,
		"first_team": c.first_team, "appearance": c.appearance.duplicate(), "gp": c.gp.duplicate(),
		"popularity": c.popularity, "pitch_uses": uses, "points": c.points, "gear": c.gear.duplicate(),
		"ratings": Array(c.ratings),
		"futures_book": book_to(cs.futures_book), "futures_games": cs.futures_games, "futures_day": cs._futures_day,
		"all_star_done": cs.all_star_done, "all_star_selected": cs.all_star_selected.duplicate(),
		"all_star_today": cs.all_star_today, "derby": cs.derby.duplicate(), "derby_waiting": cs.derby_waiting,
		"log": Array(cs.log),
	}


static func career_from(d: Dictionary, season: Season) -> CareerSeason:
	var c := CareerPlayer.new()
	var team: Team = season.teams.get(str(d.get("team", "")))
	c.team_id = team.id if team != null else ""
	c.player = team.player(str(d.get("player", ""))) if team != null else null
	c.position = str(d.get("position", ""))
	c.type_id = str(d.get("type", ""))
	c.first_team = bool(d.get("first_team", false))
	var appearance: Dictionary = d.get("appearance", {})
	for key: String in appearance:
		c.appearance[key] = str(appearance[key])
	var gp: Dictionary = d.get("gp", {})
	for key: String in gp:
		c.gp[key] = float(gp[key])
	c.popularity = float(d.get("popularity", 0.0))
	var uses: Dictionary = d.get("pitch_uses", {})
	for key: String in uses:
		c.pitch_uses[StringName(key)] = int(uses[key])
	c.points = int(d.get("points", 0))
	var gear: Dictionary = d.get("gear", {})
	for key: String in gear:
		c.gear[key] = str(gear[key])
	c.ratings = PackedFloat64Array(d.get("ratings", []) as Array)
	var cs := CareerSeason.new()
	cs.season = season
	cs.career = c
	cs.rules = CareerIO.load_default()
	cs.futures_book = book_from(d.get("futures_book", {}))
	cs.futures_games = int(d.get("futures_games", 0))
	cs._futures_day = int(d.get("futures_day", -1))
	cs.all_star_done = bool(d.get("all_star_done", false))
	for id: Variant in d.get("all_star_selected", []):
		cs.all_star_selected.append(str(id))
	cs.all_star_today = bool(d.get("all_star_today", false))
	var derby: Dictionary = d.get("derby", {})
	for id: String in derby:
		cs.derby[id] = int(derby[id])
	cs.derby_waiting = bool(d.get("derby_waiting", false))
	cs.log = PackedStringArray(d.get("log", []) as Array)
	return cs
