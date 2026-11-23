class_name LeagueScreen
extends Screen
## The league mode: start a season with a club in the
## third division, then go day by day. Its tabs: today (the day's game as a match-up — played
## on screen as a managed game or settled at once — beside the division table, the postseason
## ladder or the season's end), the first team, the second team, scouting and traits. In the
## lists a player is picked with a click: he stands on the right with his main ratings and
## what can be done with him.

const GAME_CHOICES: Array[int] = [36, 72, 144]
## The mark on each trait's badge.
const TRAIT_MARKS := {
	"precision": "target", "slugger": "fire", "table_setter": "flag-pennant", "speedster": "person-simple-run",
	"utility": "stack", "iron_glove": "shield", "balanced_batter": "chart-polar", "clutch": "lightning",
	"strikeout": "hand-fist", "grounder": "drop", "fly_ball": "cloud", "pinpoint": "crosshair",
	"closer": "lock", "workhorse": "timer", "balanced_pitcher": "chart-polar", "escape": "door-open",
}
## The ratings a trait raises, as the screens name them.
const EFFECT_NAMES := {
	"contact": "컨택트", "power": "파워", "eye": "선구안", "speed": "주력", "baserunning": "주력",
	"range": "수비 범위", "hands": "포구", "arm": "송구 파워", "accuracy": "송구 정확도", "clutch": "득점권", "movement": "구위",
	"command": "제구", "control": "제구", "velocity": "구속", "composure": "위기관리", "stamina": "체력",
}
const SEASON_TABS: Array[Array] = [["home", "오늘"], ["roster", "1군"], ["lineup", "라인업"], ["farm", "2군"], ["trade", "트레이드"], ["scout", "스카우트"], ["traits", "특성"], ["records", "기록실"]]
const FOCUS_NAMES := {"batting": "타격", "running": "주루", "fielding": "수비", "stuff": "구위", "control": "제구", "breaking": "변화"}

var message := ""
var _tab := "home"
var _games := 144
var _choice := ""
## The player picked in a list (his id), and the trait picked in the bag (its index).
var _picked := ""
var _picked_trait := -1
## The trait shown beside the badge case (its index in ClubRules.traits).
var _trait_view := -1
## The line-up tab: the row picked first ("L3" the fourth batter, "B<id>" a man
## on the bench, "R2" the third starter), and whether two batters trade order or positions.
var _lineup_pick := ""
## The man pinned to be compared with the next one picked (his id).
var _compare_id := ""
## The records room: which board (batting leaders, pitching leaders, the clubs) and which
## division (-1: the player's own).
var _records_view := "batting"
var _records_division := -1
## The second-team tab: its players or its league's table.
var _farm_view := "players"
## A new season: the fictional league or a season of the past; for the latter
## the pack and the scenario chosen ("" for a club of one's own choice).
var _setup_mode := "league"
var _pack_id := ""
var _scenario_id := ""
var _rng := Rng.new(1)


func setup() -> void:
	heading = "리그 모드"
	heading_latin = "LEAGUE"
	vantage = &"dugout"
	dock_id = "league"


func _ready() -> void:
	_rng = Rng.new(int(Time.get_unix_time_from_system()) % 100000)
	if LeagueSession.season != null:
		LeagueSession.season.play_day()
		LeagueSession.autosave()
	super._ready()


func refresh() -> void:
	if is_inside_tree() and LeagueSession.season != null:
		# The league follows the difficulty setting (how strong the other clubs are).
		LeagueSession.season.difficulty = Difficulty.by_id(Settings.difficulty)
		Achievements.check_league(LeagueSession.season)
		LeagueSession.autosave()
	super.refresh()
	_season_end_scenes.call_deferred()


## Seasons whose ending has been shown (this run of the game).
static var _ended_shown: Dictionary[String, bool] = {}


## When the season is over: his club's championship (its best man lifting the cup), and the
## awards his men won (MVP, best pitcher, rookie of the year), once each (Ceremony).
func _season_end_scenes() -> void:
	var s := LeagueSession.season
	if s == null or not s.finished() or not is_inside_tree() or Ceremony.showing:
		return
	var key := "%d:%s:%d" % [s.season_year, s.my_team, s.get_instance_id()]
	if _ended_shown.has(key):
		return
	_ended_shown[key] = true
	var d := s.division_of(s.my_team)
	var team: Team = s.teams[s.my_team]
	var list: Array = []
	var post := s.postseasons[d] if d < s.postseasons.size() else null
	var awards := SeasonAwards.for_division(s, d, s.season_year)
	if post != null and post.finished() and post.champion() == s.my_team:
		var star := team.player(awards.mvp.player_id) if awards.mvp != null and awards.mvp.team_id == s.my_team else null
		if star == null:
			for p: Player in team.first_team():
				if star == null or ClubRules.player_ovr(p, s.ovr, s.catalog) > ClubRules.player_ovr(star, s.ovr, s.catalog):
					star = p
		list.append([&"champion", "%d %s" % [s.season_year, post.round_name(post.format.size() - 1)], "%s 우승!" % team.name, PackedStringArray(["정규 시즌 %d위" % s.standings[d].rank_of(s.my_team)]), team, null, star])
	for a: SeasonAwards.Award in [awards.mvp, awards.pitcher, awards.rookie]:
		if a != null and a.team_id == s.my_team and team.player(a.player_id) != null:
			list.append([&"award", "%d KBO 시상식" % s.season_year, a.title, PackedStringArray([a.text]), team, null, team.player(a.player_id)])
	Ceremony.play_all(self, list)


func build() -> void:
	if LeagueSession.season == null:
		_build_setup()
	else:
		_build_season()


# --- A new season ---


func _build_setup() -> void:
	content.add_child(UiKit.segmented(["league", "history"], ["리그", "역사적 시즌"], _setup_mode, func(id: String) -> void:
		_setup_mode = id
		_choice = ""
		refresh()))
	if _setup_mode == "history":
		_build_history_setup()
		return
	set_heading("리그 모드")
	# The league's ten clubs, each a card: emblem, name, strength.
	var clubs := _league_clubs()
	var columns := UiKit.hbox(16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var left := panel("구단 선택", "users-three", columns, 0.0, "SELECT CLUB")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	left.body.add_child(grid)
	var chosen: Team = null
	if _choice == "" and not clubs.is_empty():
		_choice = clubs[0].id
	for t: Team in clubs:
		if t.id == _choice:
			chosen = t
		grid.add_child(_club_card(t, t.id == _choice))
	var right := panel("새 시즌", "flag-pennant", columns, 600.0, "NEW SEASON")
	if chosen != null:
		var top := UiKit.hbox(18)
		right.body.add_child(top)
		top.add_child(UiKit.club_mark(chosen, 128.0))
		var words := UiKit.vbox(4)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		words.add_child(UiKit.latin("YOUR CLUB", 17, tint, true))
		words.add_child(UiKit.heading(chosen.name, 36))
		words.add_child(StatBar.make("종합 전력", _strength(chosen), -1.0, 100.0))
		top.add_child(words)
		# Its best men, a face each.
		right.body.add_child(UiKit.caption("주요 선수"))
		var stars := UiKit.hbox(8)
		right.body.add_child(stars)
		var men := chosen.first_team()
		men.sort_custom(func(x: Player, y: Player) -> bool: return _ovr_of(x) > _ovr_of(y))
		for man: Player in men.slice(0, 4):
			var card := UiKit.vbox(0)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stars.add_child(card)
			var face := PortraitStudio.face(self, man, chosen, 76.0)
			face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			card.add_child(face)
			var name := UiKit.label(man.name, 15, Color.WHITE, 700)
			name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name.clip_text = true
			card.add_child(name)
			var role := ("선발" if man.role() == &"SP" else "구원") if man.is_pitcher() else Position.code(man.primary_position())
			var line := UiKit.label("%s · OVR %s" % [role, UiTheme.shown_text(_ovr_of(man))], 13, UiTheme.DIM, 600)
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card.add_child(line)
	right.body.add_child(UiKit.rule())
	right.body.add_child(UiKit.selector("시즌 길이", ["36", "72", "144"], ["36경기", "72경기", "144경기"], str(_games), func(v: String) -> void:
		_games = int(v)
		refresh()))
	var levels: Array = []
	for level_id: String in Difficulty.IDS:
		levels.append(level_id)
	right.body.add_child(UiKit.selector("난이도", levels, Difficulty.NAMES, Settings.difficulty, func(v: String) -> void:
		Settings.difficulty = v
		Settings.save_file()
		refresh()))
	var start := UiKit.button("시즌 시작", func() -> void: begin(_choice, _games), "play", "primary")
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	start.add_theme_font_size_override("font_size", 26)
	start.disabled = _choice == ""
	right.body.add_child(start)


## The league's clubs for the choice, read once per screen.
var _clubs_cache: Array[Team] = []


func _league_clubs() -> Array[Team]:
	if _clubs_cache.is_empty():
		_clubs_cache = LeagueSession.league_clubs()
	return _clubs_cache


func _catalog() -> Dictionary[StringName, PitchType]:
	if _pitch_catalog.is_empty():
		_pitch_catalog = PitchCatalogIO.load_default()
	return _pitch_catalog


var _pitch_catalog: Dictionary[StringName, PitchType] = {}
var _overall: Overall


## A man's overall before a season exists (the club choice).
func _ovr_of(p: Player) -> float:
	if _overall == null:
		_overall = LeagueEnvIO.load_overall()
	return ClubRules.player_ovr(p, _overall, _catalog())


## One club to choose: its emblem over its name, and its strength.
func _club_card(t: Team, on: bool) -> DragCard:
	var card := DragCard.make("T" + t.id, "", [], Color(1.0, 1.0, 1.0, 0.04))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.set_lit(on)
	card.clicked.connect(func(_tag: String) -> void:
		_choice = t.id
		refresh())
	var box := UiKit.vbox(4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)
	var mark := UiKit.club_mark(t, 84.0)
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(mark)
	var name := UiKit.label(t.name, 16, Color.WHITE, 700)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	box.add_child(name)
	var power := _strength(t)
	var line := UiKit.label("전력 %s" % UiTheme.shown_text(power), 14, UiTheme.rating_color(power), 700)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)
	return card


## What a division is called: the league (one since R8-1), "2부 리그" in an old save of three,
## a season of the past by its year.
static func league_name(s: Season, d: int) -> String:
	if s.history != null:
		return "%d 시즌" % s.season_year
	if s.school:
		var first: String = s.divisions[0][0] if not s.divisions.is_empty() and not s.divisions[0].is_empty() else ""
		return "%s 주말리그" % str(SchoolLeague.school(first).get("league", "고교"))
	return LeagueSession.league_title() if s.divisions.size() == 1 else "%d부 리그" % (d + 1)


## A club's strength as one number: its first team's batting, pitching and fielding.
static func _strength(team: Team) -> float:
	var total := 0.0
	var n := 0
	for p: Player in team.first_team():
		total += (p.pitching.control + p.pitching.composure) * 0.5 if p.is_pitcher() else (p.batting.contact() + p.batting.power() + p.fielding.overall()) / 3.0
		n += 1
	return total / maxf(n, 1.0)


## Starts a season with a club (also used by tests).
func begin(team_id: String, games: int) -> void:
	LeagueSession.start(team_id, games, _rng.next_int(1000000))
	LeagueSession.season.play_day()
	message = "%s의 시즌이 시작되었습니다." % LeagueSession.season.teams[team_id].name
	_tab = "home"
	refresh()


# --- The season ---


func _build_season() -> void:
	var s := LeagueSession.season
	var team: Team = s.teams[s.my_team]
	var d := s.division_of(s.my_team)
	var standing := s.standings[d].row(s.my_team)
	var phase: String = ["정규 시즌", "포스트시즌", "시즌 종료"][s.phase]
	var where := league_name(s, d)
	if s.history != null:
		var sc := s.history.scenario(s.scenario_id)
		where = "%s%s" % [sc.title if sc != null else s.history.title, " · 목표 %s" % SeasonPack.goal_text(sc) if sc != null else ""]
	set_heading(team.name, "" if _tab == "home" else "%s · %d일차 · %d승 %d패 %d무 · %d위" % [where, s.day + 1, standing.wins, standing.losses, standing.ties, s.standings[d].rank_of(s.my_team)])
	if tab_bar != null:
		var ids: Array = []
		var labels: Array = []
		for pair: Array in SEASON_TABS:
			# A season of the past is played as it was: no trades.
			if pair[0] == "trade" and s.history != null:
				continue
			ids.append(pair[0])
			labels.append(pair[1])
		var tabs := UiKit.tabs(ids, labels, _tab, func(id: String) -> void:
			_tab = id
			_picked = ""
			_picked_trait = -1
			refresh())
		for b: Node in tabs.get_children():
			(b as GameButton).tint = tint
		tab_bar.add_child(tabs)
	match _tab:
		"roster":
			_build_list("roster", team.first_team(), s, team, "훈련은 하루 %d명까지 지정할 수 있습니다." % s.club_rules.train_per_day)
		"farm":
			_build_farm(s, team)
		"scout":
			_build_scout(s, team)
		"traits":
			_build_traits(s)
		"trade":
			_build_trade(s, team)
		"lineup":
			_build_lineup(s, team)
		"records":
			_build_records(s)
		_:
			_build_home(s, team, d)


## The club's home page (laid out as a real game's team hub: the user, "too much empty space,
## text crammed small"): a band in the club's colours with its emblem, name and season in big
## figures; under it the next game with its probable starters and the way into it, the club's
## running figures, its last ten games, its leaders, and the table.
func _build_home(s: Season, team: Team, d: int) -> void:
	content.add_child(_home_band(s, team, d))
	var columns := UiKit.hbox(16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var left := UiKit.vbox(14)
	left.custom_minimum_size.x = 540.0
	columns.add_child(left)
	_build_today(left, s)
	_build_club(left, s, team, d)
	var middle := UiKit.vbox(14)
	middle.custom_minimum_size.x = 470.0
	columns.add_child(middle)
	_build_form(middle, s)
	_build_team_leaders(middle, s, team)
	match s.phase:
		Season.Phase.REGULAR:
			_build_table(columns, s)
		Season.Phase.POSTSEASON:
			_build_ladder(columns, s)
		Season.Phase.OVER:
			_build_end(columns, s)


## The band: emblem, name, where and when, and the season in five figures.
func _home_band(s: Season, team: Team, d: int) -> Control:
	var hero := UiKit.band(team.primary, 150.0)
	var row := UiKit.hbox(22)
	hero.get_child(1).add_child(row)
	row.add_child(UiKit.club_mark(team, 112.0))
	var words := UiKit.vbox(0)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	words.add_child(UiKit.heading(team.name, 46))
	var phase: String = ["정규 시즌", "포스트시즌", "시즌 종료"][s.phase]
	words.add_child(UiKit.label("%s · %d %s · %d일차" % [league_name(s, d), s.season_year, phase, s.day + 1], 20, Color(1.0, 1.0, 1.0, 0.8), 600))
	var r := s.standings[d].row(s.my_team)
	var gb := s.standings[d].games_behind(s.my_team)
	for f: Array in [["%d위" % s.standings[d].rank_of(s.my_team), "순위"], ["%d-%d-%d" % [r.wins, r.losses, r.ties], "승-패-무"], [r.pct_text(), "승률"],
			["%.1f" % gb if gb > 0.0 else "-", "게임차"], [r.streak_text() if r.games() > 0 else "-", "연속"]]:
		var t := UiKit.tile(str(f[0]), str(f[1]), 118.0, 28)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t)
	row.add_child(UiKit.spacer(8.0))
	return hero


## The next game: today's, or the next one on the calendar; the two clubs, the park, the
## probable starters, and the ways forward.
func _build_today(parent: Control, s: Season) -> void:
	var g := s.my_game_today()
	var ahead := g
	if ahead == null or ahead.played:
		ahead = _next_game(s) if g == null or g.played else g
	if g != null and g.played:
		ahead = g
	var title := "오늘의 경기" if g != null and g == ahead else "다음 경기"
	# The all-star break (LeagueAllStar): its panel first while the game or the derby is on.
	if LeagueAllStar.due(s):
		LeagueAllStar.hold(s)
		_announce_all_stars(s)
	if LeagueAllStar.on(s):
		_build_all_star(parent, s)
	var p := panel(title, "calendar-blank", parent, 0.0, "DAY %d" % ((ahead.day if ahead != null else s.day) + 1))
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if ahead != null:
		var row := UiKit.hbox(18)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		p.body.add_child(row)
		row.add_child(UiKit.club_side(s.teams[ahead.away], "AWAY", 84.0, 24))
		if ahead.played:
			row.add_child(UiKit.number("%d : %d" % [ahead.away_score, ahead.home_score], 60, Color.WHITE))
		else:
			row.add_child(UiKit.number("VS", 52, Color(1.0, 1.0, 1.0, 0.9)))
		row.add_child(UiKit.club_side(s.teams[ahead.home], "HOME", 84.0, 24))
		var post := s.postseason_of(ahead)
		var where := MatchScene.home_def(s.teams[ahead.home]).name
		p.body.add_child(_centered("%s%s" % ["%s %d차전 · " % [post.round_name(), ahead.game_in_series] if post != null else "", where], UiTheme.ACCENT if post != null else UiTheme.DIM, 17))
		if not ahead.played:
			var arms := UiKit.hbox(12)
			p.body.add_child(arms)
			for side: String in [ahead.away, ahead.home]:
				var club: Team = s.teams[side]
				var starter := s.starter_for(club, ahead.day)
				var cell := UiKit.well(8.0)
				cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				arms.add_child(cell)
				var inside := UiKit.hbox(8)
				cell.add_child(inside)
				inside.add_child(PortraitStudio.face(self, starter, club, 64.0))
				var box := UiKit.vbox(0)
				inside.add_child(box)
				box.add_child(UiKit.label("%s 선발" % club.short_name, 14, UiTheme.DIM, 500))
				box.add_child(UiKit.heading(starter.name if starter != null else "-", 21))
				var line: PitchingLine = s.book.pitching.get(starter.id) if starter != null else null
				box.add_child(UiKit.label("%d승 %d패 · %s" % [line.wins, line.losses, "%.2f" % line.era() if line.outs > 0 else "-"] if line != null else "첫 등판", 15, UiTheme.INK, 600))
		else:
			var word := _result_word(ahead)
			p.body.add_child(_centered({"승": "승리", "패": "패배", "무": "무승부"}[word], {"승": UiTheme.GREEN, "패": UiTheme.RED, "무": UiTheme.DIM}[word], 24))
	else:
		p.body.add_child(UiKit.label("시즌이 끝났습니다.", 20, UiTheme.DIM, 500))
	p.body.add_child(UiKit.spacer(0.0, 0.0, true))
	var actions := UiKit.hbox(10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	p.body.add_child(actions)
	if g != null and not g.played:
		# Three ways to play it: every pitch himself, as the manager, or at once.
		var play := UiKit.button("직접 플레이", func() -> void:
			ManagerMatch.full_control_next = true
			play_on_screen(), "play", "primary", 240.0)
		play.add_theme_font_size_override("font_size", 24)
		actions.add_child(play)
		actions.add_child(UiKit.button("감독 모드", func() -> void:
			ManagerMatch.full_control_next = false
			play_on_screen(), "strategy"))
		actions.add_child(UiKit.button("빠른 결과", quick_result, "fast-forward"))
	elif s.phase != Season.Phase.OVER:
		actions.add_child(UiKit.button("다음 날", next_day, "caret-right", "primary", 200.0))
	if s.phase != Season.Phase.OVER:
		actions.add_child(UiKit.button("다음 경기까지", to_next_game, "skip-forward"))
		actions.add_child(UiKit.button("정규 시즌 끝까지" if s.phase == Season.Phase.REGULAR else "포스트시즌 끝까지", to_phase_end, "fast-forward"))
	if message != "":
		p.body.add_child(_centered(message, UiTheme.ACCENT))
	# Injuries since he last looked, and who was called up in their place.
	for line: String in s.news:
		p.body.add_child(_centered(line, UiTheme.ORANGE))


## The club's next game not played yet (regular season; the postseason's are made a day at a
## time), or null.
func _next_game(s: Season) -> ScheduledGame:
	var best: ScheduledGame = null
	for sched: Schedule in s.schedules:
		for game: ScheduledGame in sched.games:
			if not game.played and game.involves(s.my_team) and game.day >= s.day and (best == null or game.day < best.day):
				best = game
	return best


func _centered(text: String, colour: Color, font_size: int = 18) -> Label:
	var l := UiKit.label(text, font_size, colour, 600)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## The club's running figures: its points, the first team's cost against the cap, the first
## team, and the team colours it has earned.
func _build_club(parent: Control, s: Season, team: Team, d: int) -> void:
	var p := panel("구단", "chart-bar", parent, 0.0, "CLUB")
	var c := s.club
	var r := s.club_rules
	var figures := UiKit.hbox(10)
	p.body.add_child(figures)
	for pair: Array in [["%d" % c.points, "구단 포인트"], ["%d / %d" % [r.first_team_cost(team, s.ovr, s.catalog), r.cost_cap(d)], "1군 코스트"], ["%d" % team.first_team().size(), "1군 등록"]]:
		var t := UiKit.tile(str(pair[0]), str(pair[1]), 0.0, 26)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		figures.add_child(t)
	var colours := TeamColors.active(team, c, r, s.ovr, s.catalog)
	if not colours.is_empty():
		var row := UiKit.hbox(6)
		p.body.add_child(row)
		for a: ClubRules.ColorDef in colours:
			row.add_child(UiKit.badge(a.name, UiTheme.GOLD))


## The last ten games, newest last: win or loss, the score, the other club's emblem.
func _build_form(parent: Control, s: Season) -> void:
	var recent: Array[ScheduledGame] = []
	for sched: Schedule in s.schedules:
		for game: ScheduledGame in sched.games:
			if game.played and game.involves(s.my_team):
				recent.append(game)
	for post: Postseason in s.postseasons:
		for sr: PlayoffSeries in post.rounds:
			for game: ScheduledGame in sr.games:
				if game.played and game.involves(s.my_team):
					recent.append(game)
	var last := recent.slice(maxi(recent.size() - 10, 0))
	var w := 0
	var l := 0
	for game: ScheduledGame in last:
		var word := _result_word(game)
		w += int(word == "승")
		l += int(word == "패")
	var p := panel("최근 10경기", "chart-bar", parent, 0.0, "%d승 %d패" % [w, l] if not last.is_empty() else "FORM")
	if last.is_empty():
		p.body.add_child(UiKit.label("아직 치른 경기가 없습니다.", 17, UiTheme.DIM, 500))
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	p.body.add_child(grid)
	for game: ScheduledGame in last:
		var other: Team = s.teams[game.opponent_of(s.my_team)]
		var word := _result_word(game)
		var cell := UiKit.well(6.0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var box := UiKit.hbox(6)
		cell.add_child(box)
		box.add_child(UiKit.club_mark(other, 30.0))
		var words := UiKit.vbox(-4)
		box.add_child(words)
		words.add_child(UiKit.heading(word, 18, {"승": UiTheme.GREEN, "패": UiTheme.RED, "무": UiTheme.DIM}[word]))
		words.add_child(UiKit.latin("%d-%d" % [game.runs_of(s.my_team), game.runs_against(s.my_team)], 18, Color.WHITE))


## The club's leaders this season in six tiles: average (qualified), home runs, runs batted in,
## wins, earned-run average (qualified), saves.
func _build_team_leaders(parent: Control, s: Season, team: Team) -> void:
	var p := panel("팀 기록", "trophy", parent, 0.0, "TEAM LEADERS")
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var games := LeagueRecords.games_played(s, s.my_team)
	var need_pa := maxi(roundi(games * 3.1), 1)
	var need_outs := maxi(games * 3, 1)
	var best: Dictionary = {}
	for man: Player in team.players:
		var b: BattingLine = s.book.batting.get(man.id)
		if b != null and b.pa > 0:
			_lead(best, "타율", man, b.average(), BattingLine.rate_text(b.average()), b.pa >= need_pa, true)
			_lead(best, "홈런", man, b.home_runs, "%d" % b.home_runs, true, true)
			_lead(best, "타점", man, b.rbi, "%d" % b.rbi, true, true)
		var q: PitchingLine = s.book.pitching.get(man.id)
		if q != null and q.outs > 0:
			_lead(best, "다승", man, q.wins, "%d" % q.wins, true, true)
			_lead(best, "평균자책점", man, q.era(), "%.2f" % q.era(), q.outs >= need_outs, false)
			_lead(best, "세이브", man, q.saves, "%d" % q.saves, true, true)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	p.body.add_child(grid)
	for cat: String in ["타율", "홈런", "타점", "다승", "평균자책점", "세이브"]:
		var cell := UiKit.well(8.0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var entry: Array = best.get(cat, [])
		var inside := UiKit.hbox(6)
		cell.add_child(inside)
		inside.add_child(PortraitStudio.face(self, entry[0] if not entry.is_empty() else null, team, 58.0))
		var box := UiKit.vbox(-2)
		inside.add_child(box)
		box.add_child(UiKit.caption(cat))
		box.add_child(UiKit.number(str(entry[2]) if not entry.is_empty() else "-", 30, Color.WHITE))
		box.add_child(UiKit.label((entry[0] as Player).name if not entry.is_empty() else "", 16, UiTheme.INK, 600))


## Keeps the best of a category: [player, value, text].
static func _lead(best: Dictionary, cat: String, man: Player, value: float, text: String, counts: bool, high: bool) -> void:
	if not counts or (high and value <= 0.0):
		return
	var now: Array = best.get(cat, [])
	if now.is_empty() or (value > float(now[1]) if high else value < float(now[1])):
		best[cat] = [man, value, text]


func _result_word(g: ScheduledGame) -> String:
	var s := LeagueSession.season
	if g.is_tie():
		return "무"
	return "승" if g.winner() == s.my_team else "패"


func _build_table(parent: Control, s: Season) -> void:
	var d := s.division_of(s.my_team)
	var p := panel("%s 순위" % league_name(s, d), "ranking", parent, 0.0, "STANDINGS")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var table := DataTable.new()
	table.row_height = 46.0
	table.set_columns([["순위", 56.0, 1], ["구단", 200.0, 0], ["승", 56.0, 2], ["패", 56.0, 2], ["무", 56.0, 2], ["승률", 76.0, 2], ["게임차", 76.0, 2], ["연속", 76.0, 2]])
	var berths := s.postseason_format(d).size() + 1
	var i := 0
	for row: StandingsRow in s.standings[d].ranked():
		i += 1
		var colours := {0: UiTheme.ACCENT if i <= berths else UiTheme.DIM}
		var at := table.add_row([str(i), s.teams[row.team_id].name, str(row.wins), str(row.losses), str(row.ties), row.pct_text(), "%.1f" % s.standings[d].games_behind(row.team_id), row.streak_text()], row.team_id, colours)
		if row.team_id == s.my_team:
			table.selected = at
	p.body.add_child(table)


func _build_ladder(parent: Control, s: Season) -> void:
	var d := s.division_of(s.my_team)
	var post := s.postseasons[d]
	var p := panel("포스트시즌" if s.history != null else "%d부 포스트시즌" % (d + 1), "trophy", parent, 0.0, "POSTSEASON")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i: int in post.seeds.size():
		var row := UiKit.hbox(12)
		p.body.add_child(row)
		row.add_child(UiKit.number("%d" % (i + 1), 30, UiTheme.ACCENT))
		row.add_child(UiKit.club_mark(s.teams[post.seeds[i]], 44.0))
		row.add_child(UiKit.heading(s.teams[post.seeds[i]].name, 22, Color.WHITE if post.seeds[i] == s.my_team else Color(1.0, 1.0, 1.0, 0.75)))
	p.body.add_child(UiKit.rule())
	for r: int in post.rounds.size():
		var sr := post.rounds[r]
		var state := ("  ·  %s 승리" % s.teams[sr.winner()].short_name) if sr.finished() else ""
		var well := UiKit.well(12.0)
		p.body.add_child(well)
		var length := "%d전 %d선승" % [sr.length(), sr.wins_needed] if sr.head_start == 0 else "%s 1승 어드밴티지 · 최대 %d경기" % [s.teams[sr.high].short_name, sr.length()]
		well.add_child(UiKit.label("%s (%s)   %s  %d - %d  %s%s" % [post.round_name(r), length, s.teams[sr.high].short_name, sr.high_won(), sr.low_wins, s.teams[sr.low].short_name, state], 19, UiTheme.INK, 600))
	if not post.seeds.has(s.my_team):
		p.body.add_child(UiKit.label("포스트시즌에 진출하지 못했습니다.", 18, UiTheme.DIM, 500))


func _build_end(parent: Control, s: Season) -> void:
	if s.history != null:
		_build_history_end(parent, s)
		return
	if one_season(s):
		_build_one_season_end(parent, s)
		return
	var d := s.division_of(s.my_team)
	var p := panel("%d년 시즌 결과" % s.season_year, "trophy", parent, 0.0, "FINAL")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var moves := s.movements()
	var up: PackedStringArray = moves[d][0]
	var down: PackedStringArray = moves[d][1]
	var verdict := "잔류"
	if up.has(s.my_team):
		verdict = "%d부 리그 승격" % d
	elif down.has(s.my_team):
		verdict = "%d부 리그 강등" % (d + 2)
	elif d == 0 and s.postseasons[0].champion() == s.my_team:
		verdict = "%s 우승" % s.postseasons[0].round_name(s.postseasons[0].format.size() - 1)
	p.body.add_child(UiKit.latin("RESULT", 18, tint, true))
	p.body.add_child(UiKit.heading(verdict, 44, UiTheme.ACCENT))
	for div: int in s.divisions.size():
		var post := s.postseasons[div]
		p.body.add_child(UiKit.label("%d부 리그   우승 %s  ·  준우승 %s" % [div + 1, s.teams[post.champion()].name, s.teams[post.runner_up()].name], 18, UiTheme.INK if div == d else UiTheme.DIM, 600))
	p.body.add_child(UiKit.rule())
	var awards := SeasonAwards.for_division(s, d, s.season_year)
	p.body.add_child(UiKit.caption("%d부 리그 시상" % (d + 1)))
	for a: SeasonAwards.Award in [awards.mvp, awards.pitcher, awards.rookie]:
		if a != null:
			p.body.add_child(UiKit.label(awards.line(a), 17, UiTheme.INK, 600))
	for a: SeasonAwards.Award in awards.titles:
		p.body.add_child(UiKit.label("%s  %s  %s" % [a.title, awards._name(a.player_id), a.text], 15, UiTheme.DIM, 500))
	p.body.add_child(UiKit.spacer(0.0, 0.0, true))
	p.body.add_child(UiKit.button("다음 시즌 시작", func() -> void:
		LeagueSession.next_season(_rng.next_int(1000000))
		LeagueSession.season.play_day()
		message = "%d년 시즌이 시작되었습니다." % LeagueSession.season.season_year
		refresh(), "play", "primary"))


## What a season with one club pays at its end (the user, 2026-11-23: one club, one season,
## then the rewards and a new one; the manager's mode pays least): by the final place, each
## postseason series won and the title; times the season's length (144 games pay it all), its
## difficulty (the days at each level, Difficulty.REWARDS) and how much he played himself (two
## fifths for a season left wholly to the computer, all of it for one played wholly).
const PLACE_POINTS: Array[int] = [2400, 1900, 1600, 1350, 1150, 950, 800, 650, 500, 400]
const SERIES_POINTS := 600
const TITLE_POINTS := 2000


## {"lines": [[words, points]...], "length", "difficulty", "involvement", "total"}.
static func season_reward(s: Season) -> Dictionary:
	var d := s.division_of(s.my_team)
	var lines: Array = []
	var place := s.standings[d].rank_of(s.my_team)
	var base := PLACE_POINTS[clampi(place - 1, 0, PLACE_POINTS.size() - 1)]
	lines.append(["정규 시즌 %d위" % place, base])
	var post := s.postseasons[d] if d < s.postseasons.size() else null
	if post != null:
		var won := 0
		for sr: PlayoffSeries in post.rounds:
			if sr.finished() and sr.winner() == s.my_team:
				won += 1
		if won > 0:
			lines.append(["포스트시즌 시리즈 %d승" % won, won * SERIES_POINTS])
			base += won * SERIES_POINTS
		if post.finished() and post.champion() == s.my_team:
			lines.append(["우승", TITLE_POINTS])
			base += TITLE_POINTS
	var length := clampf(float(s.games_per_team) / 144.0, 0.1, 1.0)
	var days := 0
	var weighted := 0.0
	for level: int in 4:
		days += s.level_days[level]
		weighted += s.level_days[level] * Difficulty.reward(level, "points")
	var difficulty := weighted / days if days > 0 else Difficulty.reward(s.difficulty, "points")
	var played := s.involvement_sum / maxf(float(s.involvement_games), 1.0)
	var involvement := 0.4 + 0.6 * clampf(played, 0.0, 1.0)
	return {"lines": lines, "length": length, "difficulty": difficulty, "involvement": involvement, "played": played,
		"total": roundi(base * length * difficulty * involvement)}


## The end of a season with one club: the verdict, the reward (paid once), the awards, and a
## new season with any club.
func _build_one_season_end(parent: Control, s: Season) -> void:
	var d := s.division_of(s.my_team)
	var team: Team = s.teams[s.my_team]
	var post := s.postseasons[d] if d < s.postseasons.size() else null
	var p := panel("%d 시즌 결과" % s.season_year, "trophy", parent, 0.0, "FINAL")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var reward := season_reward(s)
	if not s.rewarded:
		s.rewarded = true
		Profile.earn(int(reward["total"]))
		LeagueSession.autosave()
	var top := UiKit.hbox(18)
	p.body.add_child(top)
	top.add_child(UiKit.club_mark(team, 110.0))
	var words := UiKit.vbox(2)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(words)
	words.add_child(UiKit.latin("RESULT", 18, tint, true))
	var champion := post != null and post.finished() and post.champion() == s.my_team
	words.add_child(UiKit.heading("%s 우승" % post.round_name(post.format.size() - 1) if champion else "정규 시즌 %d위" % s.standings[d].rank_of(s.my_team), 40, UiTheme.ACCENT))
	if post != null and post.finished():
		words.add_child(UiKit.label("우승 %s  ·  준우승 %s" % [s.teams[post.champion()].name, s.teams[post.runner_up()].name], 17, UiTheme.INK, 600))
	p.body.add_child(UiKit.rule())
	# The reward, line by line.
	p.body.add_child(UiKit.caption("시즌 보상"))
	for line: Array in reward["lines"]:
		var row := UiKit.hbox(8)
		p.body.add_child(row)
		var what := UiKit.label(str(line[0]), 17, UiTheme.INK, 600)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(what)
		row.add_child(UiKit.label("+%d" % int(line[1]), 17, Color.WHITE, 700))
	for factor: Array in [["시즌 길이 %d경기" % s.games_per_team, float(reward["length"])], ["평균 난이도", float(reward["difficulty"])],
			["직접 플레이 %d%%" % roundi(100.0 * float(reward["played"])), float(reward["involvement"])]]:
		var row := UiKit.hbox(8)
		p.body.add_child(row)
		var what := UiKit.label(str(factor[0]), 16, UiTheme.DIM, 600)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(what)
		row.add_child(UiKit.label("×%.2f" % float(factor[1]), 16, UiTheme.DIM, 600))
	var total := UiKit.hbox(8)
	p.body.add_child(total)
	total.add_child(GradeCoin.make("P", 26.0))
	total.add_child(UiKit.number("+%d" % int(reward["total"]), 34, UiTheme.ACCENT))
	p.body.add_child(UiKit.rule())
	var awards := SeasonAwards.for_division(s, d, s.season_year)
	p.body.add_child(UiKit.caption("시상"))
	for a: SeasonAwards.Award in [awards.mvp, awards.pitcher, awards.rookie]:
		if a != null:
			p.body.add_child(UiKit.label(awards.line(a), 16, UiTheme.INK, 600))
	p.body.add_child(UiKit.spacer(0.0, 0.0, true))
	p.body.add_child(UiKit.button("새 시즌 (구단 선택)", func() -> void:
		# The season is over: its save goes, and a new one starts with any club.
		SaveIO.delete_slot(LeagueSession.slot)
		LeagueSession.season = null
		LeagueSession.slot = ""
		_choice = ""
		message = ""
		refresh(), "play", "primary"))


# --- Seasons of the past ---


## The clubs that made history: each a club in one season of the past — 2016 두림
## 그리즐리스, 93 wins — played through that season with the league around it as it was. Laid out
## as a real game's team page (the user: "too much empty space, the text crammed small in one
## corner"): left, the clubs as rows of colour, emblem, year and line; right, the club picked —
## a band in its colours with the emblem, the name and its leading man standing in the uniform,
## its season in big figures, two lines of story, its leading men as cards, the rules as chips.
func _build_history_setup() -> void:
	set_heading("역사적 시즌")
	var entries := history_entries()
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var left := panel("역사를 쓴 구단", "trophy", columns, 560.0, "LEGENDS")
	var list := UiKit.vbox(6)
	var scroll := UiKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	left.body.add_child(scroll)
	var chosen: SeasonPack = null
	var sc: SeasonPack.Scenario = null
	for e: Array in entries:
		var pack: SeasonPack = e[0]
		var it: SeasonPack.Scenario = e[1]
		var on := pack.id == _pack_id and it.id == _scenario_id
		if on:
			chosen = pack
			sc = it
		list.add_child(_legend_row(pack, it, on))
	var right := panel("", "", columns, 0.0, "")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if sc == null:
		return
	var team: Team = null
	for t: Team in _legend_clubs(chosen):
		if t.id == sc.team:
			team = t
	if team == null:
		team = chosen.look(sc.team)
	right.body.add_child(_legend_hero(chosen, sc, team))
	var story := UiKit.label(sc.text, 19, UiTheme.INK, 500)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size.x = 300.0
	story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.body.add_child(story)
	if not sc.stars.is_empty():
		right.body.add_child(CenteredPanel.section("주요 선수"))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		right.body.add_child(grid)
		for star: Array in sc.stars.slice(0, 8):
			grid.add_child(_star_card(star, team, _player_named(team, str(star[0]))))
	right.body.add_child(UiKit.spacer(0.0, 0.0, true))
	var foot := UiKit.hbox(8)
	right.body.add_child(foot)
	for chip: String in rules_line(chosen).split(" · "):
		var b := UiKit.badge(chip, Color(1.0, 1.0, 1.0, 0.1), false)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		foot.add_child(b)
	foot.add_child(UiKit.spacer(0.0, 0.0, true))
	var start := UiKit.button("시작  ·  목표 %s" % SeasonPack.goal_text(sc), func() -> void: begin_history(chosen, sc.id, ""), "play", "primary", 380.0)
	start.add_theme_font_size_override("font_size", 26)
	foot.add_child(start)


## One club of the list: a strip of its colour, its emblem, the year big, its name and line.
func _legend_row(pack: SeasonPack, it: SeasonPack.Scenario, on: bool) -> Button:
	var look := pack.look(it.team)
	var row := Button.new()
	row.toggle_mode = true
	row.button_pressed = on
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0.0, 72.0)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var box := StyleBoxFlat.new()
		# Picked: the brand red the tables use for a picked row; else a faint plate.
		box.bg_color = Color(UiTheme.BRAND, 0.55) if on or state.begins_with("pressed") or state == "hover_pressed" else Color(1.0, 1.0, 1.0, 0.08 if state == "hover" else 0.035)
		if state == "focus":
			box.bg_color = Color(0, 0, 0, 0)
		box.border_width_left = 6
		box.border_color = look.primary.lightened(0.25) if look.primary.get_luminance() < 0.2 else look.primary
		row.add_theme_stylebox_override(state, box)
	row.pressed.connect(func() -> void:
		_pack_id = pack.id
		_scenario_id = it.id
		_choice = ""
		GameAudio.ui(get_tree(), "ui/select")
		refresh())
	var line := UiKit.hbox(14)
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 18.0
	line.offset_right = -12.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var mark := UiKit.club_mark(look, 50.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(mark)
	var year := UiKit.number("%d" % pack.year, 34, UiTheme.ACCENT if not on else Color.WHITE)
	year.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	year.custom_minimum_size.x = 74.0
	line.add_child(year)
	var words := UiKit.vbox(0)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(UiKit.heading(look.name, 23))
	words.add_child(UiKit.label(it.tagline, 17, Color(1.0, 1.0, 1.0, 0.75) if on else UiTheme.DIM, 500))
	line.add_child(words)
	for c: Node in [mark, year, words]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c: Node in words.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


## The top of the club picked: a band in its colours with the emblem, the year and name, its
## line, its season in four big figures, and its leading man standing in the uniform.
func _legend_hero(pack: SeasonPack, it: SeasonPack.Scenario, team: Team) -> Control:
	var hero := MarginContainer.new()
	hero.custom_minimum_size.y = 268.0
	var band := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(team.primary.lerp(Color.BLACK, 0.1), 0.95))
	grad.set_color(1, Color(team.primary, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	band.texture = tex
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	hero.add_child(band)
	var inner := MarginContainer.new()
	for side: String in ["left", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 16)
	hero.add_child(inner)
	var row := UiKit.hbox(26)
	inner.add_child(row)
	var mark := UiKit.club_mark(team, 150.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var words := UiKit.vbox(2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(words)
	words.add_child(UiKit.number("%d" % pack.year, 34, UiTheme.ACCENT))
	words.add_child(UiKit.heading(team.name, 52))
	var line_colour := team.secondary if team.secondary.get_luminance() > 0.35 and team.secondary.get_luminance() < 0.9 else Color(1.0, 1.0, 1.0, 0.85)
	words.add_child(UiKit.label(it.tagline, 26, line_colour, 700))
	words.add_child(UiKit.spacer(0.0, 8.0))
	var figures := UiKit.hbox(10)
	words.add_child(figures)
	var real := pack.actual_of(it.team)
	var w := int(real[1])
	var l := int(real[2])
	var t := int(real[3])
	var decided := w + l + (t if pack.ties_as_losses else 0)
	for f: Array in [["%d위" % int(real[0]), "정규 시즌"], ["%d-%d-%d" % [w, t, l], "승-무-패"], [BattingLine.rate_text(float(w) / maxf(decided, 1.0)), "승률"],
			["%d-%d" % [int(it.final[0]), int(it.final[1])] if it.final.size() >= 2 else "-", "한국시리즈 vs %s" % str(it.final[2]) if it.final.size() >= 3 else "한국시리즈"]]:
		var well := UiKit.well(10.0)
		well.custom_minimum_size.x = 150.0
		well.add_child(UiKit.figure(str(f[0]), str(f[1]), Color.WHITE, 26))
		figures.add_child(well)
	var star := _star_player(pack, it, team)
	if star != null:
		var stage := PlayerStage.make(200.0, 268.0)
		stage.show_player(star, team)
		row.add_child(stage)
	return hero


## A leading man as a card: his name, his place, his season in two or three figures.
func _star_card(star: Array, team: Team, man: Player) -> Control:
	var card := UiKit.well(8.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inside := UiKit.hbox(6)
	card.add_child(inside)
	if man != null:
		inside.add_child(PortraitStudio.face(self, man, team, 62.0))
	var box := UiKit.vbox(1)
	inside.add_child(box)
	var top := UiKit.hbox(8)
	box.add_child(top)
	var strip := ColorRect.new()
	strip.color = team.primary.lightened(0.3) if team.primary.get_luminance() < 0.2 else team.primary
	strip.custom_minimum_size = Vector2(4.0, 26.0)
	top.add_child(strip)
	top.add_child(UiKit.heading(str(star[0]), 20))
	if star.size() >= 3 and star[2] is Array:
		box.add_child(UiKit.label(str(star[1]), 15, UiTheme.DIM, 500))
		var figures := UiKit.hbox(14)
		box.add_child(figures)
		for pair: Array in star[2]:
			figures.add_child(UiKit.figure(str(pair[1]), str(pair[0]), Color.WHITE, 20))
	else:
		box.add_child(UiKit.label(str(star[1]), 16, UiTheme.DIM, 500))
	return card


## A hitter's season for a table: average, home runs, runs batted in, OPS.
static func _bat_cells(s: Season, p: Player) -> Array:
	var b: BattingLine = s.book.batting.get(p.id)
	if b == null or b.pa == 0:
		return ["-", "-", "-", "-"]
	return [BattingLine.rate_text(b.average()), "%d" % b.home_runs, "%d" % b.rbi, BattingLine.rate_text(b.ops())]


## A pitcher's season for a table: won-lost and earned-run average.
static func _pitch_cells(s: Season, p: Player) -> Array:
	var q: PitchingLine = s.book.pitching.get(p.id)
	if q == null or q.outs == 0:
		return ["-", "-"]
	return ["%d-%d" % [q.wins, q.losses], "%.2f" % q.era()]


## A man's season in a few words for a mixed list: a hitter's average, home runs and OPS, a
## pitcher's won-lost, saves and earned-run average.
static func _season_words(s: Season, p: Player) -> String:
	if p.is_pitcher():
		var q: PitchingLine = s.book.pitching.get(p.id)
		if q == null or q.outs == 0:
			return "-"
		return "%d승 %d패%s · %.2f" % [q.wins, q.losses, " %d세" % q.saves if q.saves > 0 else "", q.era()]
	var b: BattingLine = s.book.batting.get(p.id)
	if b == null or b.pa == 0:
		return "-"
	return "%s · %d홈런 · OPS %s" % [BattingLine.rate_text(b.average()), b.home_runs, BattingLine.rate_text(b.ops())]


## Asks for a face for a table's row and puts it in when it comes.
func _face_later(table: DataTable, row: int, p: Player, team: Team) -> void:
	if PortraitStudio.cached(p, team) != null:
		return
	PortraitStudio.request(self, p, team, func(face: Texture2D) -> void:
		if is_instance_valid(table):
			table.set_portrait(row, face))


static func _player_named(team: Team, who: String) -> Player:
	for p: Player in team.players:
		if p.name == who:
			return p
	return null


## The club's leading man that year, as a player of its roster pack (the first of its stars
## found there), to stand in the uniform.
func _star_player(pack: SeasonPack, it: SeasonPack.Scenario, team: Team) -> Player:
	for star: Array in it.stars:
		for p: Player in team.players:
			if p.name == str(star[0]) and not p.is_pitcher():
				return p
	return null


## The clubs of a season's roster pack, read once a session (a pack is a few hundred players).
static var _legend_cache: Dictionary = {}
static func _legend_clubs(pack: SeasonPack) -> Array:
	if not _legend_cache.has(pack.id):
		_legend_cache[pack.id] = pack.clubs()
	return _legend_cache[pack.id]


## Every legendary club there is, newest season first: [pack, scenario]. The game's own example
## (fictional clubs) only when there are no real seasons.
static func history_entries() -> Array:
	var real: Array = []
	var example: Array = []
	for pack: SeasonPack in SeasonPack.available():
		for it: SeasonPack.Scenario in pack.scenarios:
			(example if pack.path.begins_with(SeasonPack.BUILT_IN) else real).append([pack, it])
	var out := real if not real.is_empty() else example
	out.sort_custom(func(x: Array, y: Array) -> bool: return (x[0] as SeasonPack).year > (y[0] as SeasonPack).year)
	return out


## That year's rules in one line.
static func rules_line(pack: SeasonPack) -> String:
	var parts := PackedStringArray(["%d경기" % pack.games, "연장 %d회" % pack.extra_innings, "외국인 %d명" % pack.foreign_players, "1군 %d명" % pack.registered_roster])
	if pack.asia_quota > 0:
		parts.append("아시아쿼터 %d명" % pack.asia_quota)
	if pack.ties_as_losses:
		parts.append("무승부는 패")
	return " · ".join(parts)


## A grey note that wraps within its panel.
static func _wrapped(text: String, font_size: int) -> Label:
	var l := UiKit.label(text, font_size, UiTheme.DIM, 500)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200.0
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Starts a season of the past (also used by tests).
func begin_history(pack: SeasonPack, scenario_id: String, team_id: String) -> void:
	LeagueSession.start_history(pack, scenario_id, team_id, _rng.next_int(1000000))
	LeagueSession.season.play_day()
	var sc := pack.scenario(scenario_id)
	message = "%s · 목표 %s" % [sc.title, SeasonPack.goal_text(sc)] if sc != null else pack.title
	_tab = "home"
	refresh()


## The end of a season of the past: this season's table beside the real one, the champions,
## the title holders then and now, and the scenario's verdict.
func _build_history_end(parent: Control, s: Season) -> void:
	var pack := s.history
	var p := panel(pack.title, "trophy", parent, 0.0, "THEN AND NOW")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := pack.scenario(s.scenario_id)
	var top := UiKit.hbox(12)
	p.body.add_child(top)
	var verdict := UiKit.vbox(2)
	verdict.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(verdict)
	if sc != null:
		var met := SeasonPack.goal_met(sc, s)
		verdict.add_child(UiKit.heading("%s %s" % [SeasonPack.goal_text(sc), "성공" if met else "실패"], 40, UiTheme.GREEN if met else UiTheme.RED))
		if sc.path != "":
			verdict.add_child(UiKit.label("실제: %s" % sc.path, 17, UiTheme.DIM, 500))
	var buttons := UiKit.vbox(6)
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(buttons)
	buttons.add_child(UiKit.button("같은 시즌 다시", func() -> void: begin_history(pack, s.scenario_id, s.my_team), "arrows-clockwise", "primary"))
	buttons.add_child(UiKit.button("다른 구단 고르기", func() -> void:
		LeagueSession.season = null
		_setup_mode = "history"
		refresh(), "calendar-blank"))
	var table := DataTable.new()
	table.set_columns([["순위", 60.0, 1], ["팀", 160.0, 0], ["이번", 130.0, 2], ["실제 순위", 100.0, 2], ["실제", 130.0, 2], ["차이", 80.0, 2]])
	var rows := s.standings[0].ranked()
	for i: int in rows.size():
		var r := rows[i]
		var actual := pack.actual_of(r.team_id)
		var shift := int(actual[0]) - (i + 1) if int(actual[0]) > 0 else 0
		table.add_row(["%d" % (i + 1), (s.teams[r.team_id] as Team).short_name, "%d-%d-%d" % [r.wins, r.losses, r.ties], "%d위" % int(actual[0]) if int(actual[0]) > 0 else "-",
			"%d-%d-%d" % [int(actual[1]), int(actual[2]), int(actual[3])] if int(actual[0]) > 0 else "-", ("▲%d" % shift) if shift > 0 else (("▼%d" % -shift) if shift < 0 else "-")],
			r.team_id, {0: UiTheme.ACCENT, 1: tint if r.team_id == s.my_team else UiTheme.INK, 5: UiTheme.GREEN if shift > 0 else (UiTheme.RED if shift < 0 else UiTheme.DIM)})
	table.custom_minimum_size.y = 48.0 + 38.0 * rows.size()
	p.body.add_child(table)
	var now := s.champion_of(0)
	p.body.add_child(UiKit.label("우승  이번: %s  ·  실제: %s" % [(s.teams[now] as Team).name if now != "" else "-", (s.teams[pack.champion] as Team).name if s.teams.has(pack.champion) else "-"], 18, UiTheme.INK, 600))
	if not pack.leaders.is_empty():
		p.body.add_child(CenteredPanel.section("타이틀  실제 → 이번"))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 30)
		p.body.add_child(grid)
		var lines := PackedStringArray()
		for entry: Array in pack.leaders:
			var mine := ""
			for c: LeagueRecords.Category in LeagueRecords.batting_categories() + LeagueRecords.pitching_categories():
				if c.name == str(entry[0]):
					var board := LeagueRecords.leaders(s, 0, c, 1)
					if not board.is_empty():
						var who := (s.teams[board[0].team_id] as Team).player(board[0].player_id)
						mine = "%s %s" % [who.name if who != null else "", board[0].text]
			lines.append("%s  %s %s → %s" % [str(entry[0]), str(entry[1]), str(entry[2]), mine])
		for line: String in lines:
			grid.add_child(UiKit.label(line, 15, UiTheme.DIM, 500))


# --- The club's players ---


func _player_line(s: Season, p: Player) -> Array[String]:
	var ovr := ClubRules.player_ovr(p, s.ovr, s.catalog)
	var role := String(p.role()) if p.is_pitcher() else Position.code(p.primary_position())
	var tr := ""
	if s.club.traits.has(p.id):
		var item := s.club.traits[p.id]
		tr = "%s %d" % [s.club_rules.traits[item.x].name, item.y + 1]
	return [role, p.name + (" ★" if p.is_foreign() else ""), s.club_rules.grade_of(ovr).name, UiTheme.shown_text(ovr), s.condition_name(p.id), tr]


## A list of players (the first team, the second team or the day's candidates) with the one
## picked standing beside it.
func _build_list(kind: String, players: Array[Player], s: Season, team: Team, _note: String) -> void:
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var titles := {"roster": ["1군 로스터", "ROSTER"], "farm": ["2군", "FARM"], "scout": ["스카우트", "SCOUTING"]}
	var p := panel("%s  %d명" % [titles[kind][0], players.size()], "users-three", columns, 0.0, str(titles[kind][1]))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var table := DataTable.new()
	# A face beside every name, as the reference games list their players.
	table.row_height = 54.0
	table.set_columns([["선수", 250.0, 0], ["포지션", 70.0, 1], ["등급", 56.0, 1], ["OVR", 60.0, 2], ["나이" if kind == "scout" else "컨디션", 76.0, 1], ["시즌 기록", 230.0, 0], ["특성", 110.0, 0], ["훈련", 70.0, 1]])
	var picked: Player = null
	var dress: Team = team if kind != "scout" else null
	for player: Player in players:
		var line: Array = _player_line(s, player)
		var ovr := float(line[3])
		var cells: Array = [line[1], line[0], line[2], line[3], line[4], _season_words(s, player) if kind != "scout" else "-", line[5]]
		if kind == "scout":
			cells[4] = "%d세" % (s.season_year - player.born)
		var focus := s.club.training.get(player.id, "") as String
		cells.append(str(FOCUS_NAMES.get(focus, "-")) if kind == "roster" else "-")
		var at := table.add_row(cells, player.id, {1: UiTheme.CYAN if player.is_pitcher() else UiTheme.GREEN, 2: UiTheme.ACCENT, 3: UiTheme.rating_color(ovr), 5: UiTheme.INK, 7: UiTheme.ACCENT}, PortraitStudio.cached(player, dress))
		if PortraitStudio.cached(player, dress) == null:
			PortraitStudio.request(self, player, dress, func(face: Texture2D) -> void:
				if is_instance_valid(table):
					table.set_portrait(at, face))
		if player.id == _picked:
			table.selected = at
			picked = player
	table.row_pressed.connect(func(_row: int, tag: Variant) -> void:
		_picked = str(tag)
		refresh())
	if picked == null and not players.is_empty():
		# Someone is always shown (the panel beside a list is never empty in a real game).
		picked = players[0]
		table.selected = 0
	p.body.add_child(table)
	if message != "":
		p.body.add_child(UiKit.label(message, 17, UiTheme.ACCENT, 600))
	_build_picked(columns, kind, picked, s, team)


## The day's candidates as the scouts' reports (the other screens list players in tables;
## five men to choose one from read better as reports): each a card with his face, what he
## plays, his age, his rating and the room the scouts see in him, and his tools as bars. The
## one picked stands beside them with the signing.
func _build_scout(s: Season, team: Team) -> void:
	var columns := UiKit.hbox(16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var title := "영입 후보  %d명" % s.club.candidates.size() + ("  ·  오늘 영입 완료" if s.club.signed_today else "")
	var p := panel(title, "binoculars", columns, 0.0, "SCOUTING")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var picked: Player = null
	for man: Player in s.club.candidates:
		if man.id == _picked:
			picked = man
	if picked == null and not s.club.candidates.is_empty():
		picked = s.club.candidates[0]
	if s.club.candidates.is_empty():
		p.body.add_child(UiKit.label("오늘의 후보를 모두 만났습니다", 18, UiTheme.DIM, 600))
	for man: Player in s.club.candidates:
		p.body.add_child(_scout_card(s, man, picked == man))
	# What club points buy here: a better scouting staff, and another report today.
	var desk := UiKit.hbox(8)
	p.body.add_child(desk)
	desk.add_child(UiKit.badge("스카우트 Lv.%d" % s.club.scout_level, UiTheme.ACCENT))
	desk.add_child(UiKit.label("구단 포인트 %d" % s.club.points, 15, UiTheme.DIM, 600))
	var note := UiKit.label(message, 15, UiTheme.ACCENT, 600)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.clip_text = true
	desk.add_child(note)
	var price := s.club.scout_upgrade_price(s.club_rules)
	var upgrade := UiKit.button("레벨 업  %d" % price if price > 0 else "최고 레벨", func() -> void:
		message = "스카우트 Lv.%d: 더 좋은 후보를 찾습니다." % (s.club.scout_level + 1) if s.club.upgrade_scout(s.club_rules) else "구단 포인트가 부족합니다."
		if message.begins_with("스카우트"):
			s.refresh_candidates(1 + int(s.club.reported_today))
		refresh(), "binoculars")
	upgrade.disabled = price == 0 or s.club.points < price
	desk.add_child(upgrade)
	var report_price := int(s.club_rules.points.get("scout_report", 60))
	var report := UiKit.button("새 후보  %d" % report_price, func() -> void:
		if s.club.buy_report(s.club_rules):
			s.refresh_candidates(2)
			_picked = ""
			message = "새 보고서가 도착했습니다."
		refresh(), "arrows-clockwise")
	report.disabled = s.club.reported_today or s.club.points < report_price
	desk.add_child(report)
	_build_picked(columns, "scout", picked, s, team)


## One candidate's report.
func _scout_card(s: Season, man: Player, on: bool) -> DragCard:
	var card := DragCard.make("S" + man.id, "", [], Color(1.0, 1.0, 1.0, 0.04))
	card.tight()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.set_lit(on)
	card.clicked.connect(func(_t: String) -> void:
		_picked = man.id
		refresh())
	var line := UiKit.hbox(14)
	card.add_child(line)
	line.add_child(PortraitStudio.face(self, man, null, 78.0))
	var who := UiKit.vbox(0)
	who.custom_minimum_size.x = 170.0
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(who)
	var role := ("선발 투수" if man.role() == &"SP" else "구원 투수") if man.is_pitcher() else Position.name_of(man.primary_position())
	who.add_child(UiKit.label(role, 14, UiTheme.CYAN if man.is_pitcher() else UiTheme.GREEN, 700))
	who.add_child(UiKit.label(man.name + (" ★" if man.is_foreign() else ""), 20, Color.WHITE, 700))
	who.add_child(UiKit.label("%d세 · %s" % [s.season_year - man.born, Development.stars_text(Development.stars(man, s.club.scout_level))], 14, UiTheme.ACCENT, 600))
	var ovr := ClubRules.player_ovr(man, s.ovr, s.catalog)
	var mark := UiKit.vbox(-6)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.custom_minimum_size.x = 64.0
	line.add_child(mark)
	var number := UiKit.number(UiTheme.shown_text(ovr), 34, UiTheme.rating_color(ovr))
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.add_child(number)
	var grade := UiKit.caption("OVR · %s" % s.club_rules.grade_of(ovr).name)
	grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.add_child(grade)
	# His tools, two columns of small bars.
	var tools := GridContainer.new()
	tools.columns = 2
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tools.add_theme_constant_override("h_separation", 14)
	tools.add_theme_constant_override("v_separation", 0)
	line.add_child(tools)
	var pairs: Array = [["구위", man.pitching.stuff(s.catalog)], ["제구", man.pitching.control], ["체력", man.pitching.stamina], ["변화구", man.pitching.breaking(s.catalog)]] if man.is_pitcher() \
		else [["컨택트", man.batting.contact()], ["파워", man.batting.power()], ["선구안", man.batting.eye], ["주력", man.batting.speed], ["수비", man.fielding.overall()]]
	for pair: Array in pairs:
		var bar := StatBar.make(str(pair[0]), float(pair[1]), -1.0, 62.0)
		bar.custom_minimum_size = Vector2(150.0, 26.0)
		tools.add_child(bar)
	return card


## The player picked in a list: the man, his main ratings, and what can be done with him.
func _build_picked(parent: Control, kind: String, p: Player, s: Season, team: Team) -> void:
	var side := panel("선수 정보", "identification-card", parent, 520.0, "PLAYER")
	if p == null:
		return
	var ovr := ClubRules.player_ovr(p, s.ovr, s.catalog)
	var top := UiKit.hbox(8)
	side.body.add_child(top)
	var stage := PlayerStage.make(250.0, 360.0)
	stage.show_player(p, team)
	top.add_child(stage)
	var words := UiKit.vbox(2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_child(UiKit.latin("No.%d" % p.number, 22, tint, true))
	words.add_child(UiKit.heading(p.name, 34))
	var role := ("선발 투수" if p.role() == &"SP" else "구원 투수") if p.is_pitcher() else Position.name_of(p.primary_position())
	words.add_child(UiKit.label("%s · %d세" % [role, s.season_year - p.born], 17, UiTheme.DIM, 500))
	words.add_child(UiKit.label("%dcm · %dkg" % [roundi(p.height_cm), roundi(p.weight_kg)], 17, UiTheme.DIM, 500))
	var figures := UiKit.hbox(18)
	figures.add_child(UiKit.figure(UiTheme.shown_text(ovr), "OVR", UiTheme.rating_color(ovr), 44))
	figures.add_child(UiKit.figure(s.club_rules.grade_of(ovr).name, "등급", UiTheme.ACCENT, 44))
	words.add_child(figures)
	# The room the scouts see in him, and his second-team numbers.
	if s.season_year - p.born <= 27 and p.potential >= 0.0:
		words.add_child(UiKit.label("잠재력 %s" % Development.stars_text(Development.stars(p, s.club.scout_level if s.club != null else 1)), 17, UiTheme.ACCENT, 600))
	if kind == "farm" and s.farm != null:
		words.add_child(UiKit.label("2군 " + farm_line(s, p), 15, UiTheme.DIM, 500))
	top.add_child(words)
	if p.is_pitcher():
		side.body.add_child(StatBar.make("구위", p.pitching.stuff(s.catalog), -1.0, 100.0))
		side.body.add_child(StatBar.make("제구", p.pitching.control, -1.0, 100.0))
		side.body.add_child(StatBar.make("체력", p.pitching.stamina, -1.0, 100.0))
		side.body.add_child(StatBar.make("변화구", p.pitching.breaking(s.catalog), -1.0, 100.0))
	else:
		side.body.add_child(StatBar.make("컨택트", p.batting.contact(), -1.0, 100.0))
		side.body.add_child(StatBar.make("파워", p.batting.power(), -1.0, 100.0))
		side.body.add_child(StatBar.make("선구안", p.batting.eye, -1.0, 100.0))
		side.body.add_child(StatBar.make("주력", p.batting.speed, -1.0, 100.0))
		side.body.add_child(StatBar.make("수비", p.fielding.overall(), -1.0, 100.0))
	side.body.add_child(UiKit.spacer(0.0, 0.0, true))
	_compare_buttons(side.body, p, s)
	var actions := UiKit.hbox(8)
	side.body.add_child(actions)
	actions.add_child(UiKit.button("선수 카드", func() -> void: PlayerCard.open_for(self, p, s), "identification-card"))
	match kind:
		"roster":
			var focus := s.club.training.get(p.id, "") as String
			actions.add_child(UiKit.button("훈련: %s" % str(FOCUS_NAMES.get(focus, "없음")), func() -> void:
				_cycle_training(s, p)
				refresh(), "barbell"))
			actions.add_child(UiKit.button("말소", func() -> void:
				team.unregister(p.id, s.day)
				message = "%s 선수를 말소했습니다. %d일 뒤 다시 등록할 수 있습니다." % [p.name, Team.RECALL_DAYS]
				_picked = ""
				refresh(), "arrow-right"))
		"farm":
			actions.add_child(UiKit.button("1군 등록", func() -> void:
				message = register(p)
				refresh(), "plus", "primary"))
			actions.add_child(UiKit.button("방출", func() -> void:
				s.club.release(p.id, team, s.club_rules)
				message = "%s 선수를 방출했습니다." % p.name
				_picked = ""
				refresh(), "trash"))
		"scout":
			var sign := UiKit.button("영입", func() -> void:
				var signed := s.club.sign(s.club.candidates.find(p), team, s.club_rules)
				message = "%s 선수를 영입했습니다(2군)." % signed.name if signed != null else "영입할 수 없습니다(2군 정원 %d명)." % s.club_rules.second_team_size
				_picked = ""
				refresh(), "handshake", "primary")
			sign.disabled = s.club.signed_today
			actions.add_child(sign)


# --- The second team ---


## The second team: its men with their age, the room the scouts see in them, their numbers in
## the second teams' league and what they have grown this season; the moves the staff advise;
## and the second teams' table with last winter's comings and goings.
func _build_farm(s: Season, team: Team) -> void:
	var bar := UiKit.hbox(16)
	content.add_child(bar)
	# The league has no second teams' league (the career has the futures): the men off the
	# first-team entry and last winter; an old league of three divisions keeps its futures.
	var futures := s.farm != null
	if futures:
		bar.add_child(UiKit.segmented(["players", "table"], ["2군 선수", "퓨처스 순위 · 지난 겨울"], _farm_view, func(id: String) -> void:
			_farm_view = id
			refresh()))
	if _farm_view == "table" and futures:
		_build_farm_table(s, team)
		return
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var players := team.second_team()
	var p := panel("2군  %d명" % players.size(), "users-three", columns, 0.0, "FUTURES" if futures else "SECOND TEAM")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var advice := RosterMoves.advice(s, team)
	var advised: Dictionary[String, bool] = {}
	for m: RosterMoves.Move in advice:
		advised[m.up.id] = true
		var row := UiKit.hbox(10)
		row.add_child(UiKit.icon("arrow-u-up-left", 20.0, UiTheme.GREEN))
		row.add_child(UiKit.label("콜업 추천: %s ↔ %s (%s)" % [m.up.name, m.down.name, m.reason], 16, UiTheme.GREEN, 600))
		row.add_child(UiKit.spacer(0.0, 0.0, true))
		var move := m
		row.add_child(UiKit.button("맞바꾸기", func() -> void:
			if RosterMoves.apply(s, team, move):
				message = "%s 선수를 1군에 올리고 %s 선수를 2군으로 보냈습니다." % [move.up.name, move.down.name]
			refresh(), "swap"))
		p.body.add_child(row)
	var table := DataTable.new()
	table.row_height = 50.0
	table.portrait_column = 1
	table.set_columns([["포지션", 80.0, 1], ["선수", 240.0, 0], ["나이", 60.0, 1], ["OVR", 70.0, 2], ["잠재력", 120.0, 1], ["2군 기록" if futures else "시즌 기록", 280.0, 0], ["올해 성장", 100.0, 2]])
	var picked: Player = null
	var level := s.club.scout_level if s.club != null else 1
	for player: Player in players:
		var ovr := ClubRules.player_ovr(player, s.ovr, s.catalog)
		var role := String(player.role()) if player.is_pitcher() else Position.code(player.primary_position())
		var grown := float(s.grown.get(player.id, 0.0))
		var at := table.add_row([role, player.name + ("  ▲" if advised.has(player.id) else ""), "%d" % (s.season_year - player.born), UiTheme.shown_text(ovr),
			Development.stars_text(Development.stars(player, level)), farm_line(s, player) if futures else _season_words(s, player), "+%.1f" % grown if grown >= 0.05 else "-"], player.id,
			{0: UiTheme.CYAN if player.is_pitcher() else UiTheme.GREEN, 1: UiTheme.GREEN if advised.has(player.id) else UiTheme.INK, 3: UiTheme.rating_color(ovr), 4: UiTheme.ACCENT, 6: UiTheme.GREEN},
			PortraitStudio.cached(player, team))
		_face_later(table, at, player, team)
		if player.id == _picked:
			table.selected = at
			picked = player
	table.row_pressed.connect(func(_row: int, tag: Variant) -> void:
		_picked = str(tag)
		refresh())
	if picked == null and not players.is_empty():
		picked = players[0]
		table.selected = 0
	p.body.add_child(table)
	if message != "":
		p.body.add_child(UiKit.label(message, 17, UiTheme.ACCENT, 600))
	_build_picked(columns, "farm", picked, s, team)


## A man's numbers in the second teams' league, in one line.
static func farm_line(s: Season, p: Player) -> String:
	if s.farm == null:
		return "-"
	if p.is_pitcher():
		var l := s.farm.pitching(p.id)
		if l.outs == 0:
			return "-"
		return "%s이닝 · 평균자책점 %.2f" % [l.innings_text(), l.era()]
	var b := s.farm.batting(p.id)
	if b.pa == 0:
		return "-"
	return "%d타석 · 타율 %s · OPS %s" % [b.pa, BattingLine.rate_text(b.average()), BattingLine.rate_text(b.ops())]


## The second teams' table of the player's division, and last winter's comings and goings.
func _build_farm_table(s: Season, team: Team) -> void:
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var d := s.division_of(s.my_team)
	var own_calendar := s.farm != null and s.farm.schedule != null
	if s.farm != null:
		var left := panel("퓨처스리그" if own_calendar else "퓨처스리그 %d부" % (d + 1), "ranking", columns, 0.0, "FUTURES LEAGUE")
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The KBO's two futures leagues (north, south), or an old league's one table.
		var groups: Array = [["북부리그", s.farm.north], ["남부리그", s.farm.south]] if own_calendar else [["", PackedStringArray()]]
		var standings := s.farm.standings[0 if own_calendar else d]
		for group: Array in groups:
			var ids: PackedStringArray = group[1]
			if str(group[0]) != "":
				left.body.add_child(UiKit.caption(str(group[0])))
			var table := DataTable.new()
			table.set_columns([["순위", 60.0, 1], ["팀", 240.0, 0], ["경기", 70.0, 2], ["승", 60.0, 2], ["패", 60.0, 2], ["무", 60.0, 2], ["승률", 80.0, 2], ["게임차", 80.0, 2]])
			var rows: Array[StandingsRow] = []
			for r: StandingsRow in standings.ranked():
				if ids.is_empty() or ids.has(r.team_id):
					rows.append(r)
			for i: int in rows.size():
				var r := rows[i]
				var side := s.farm.team_of(s, r.team_id)
				var behind := (rows[0].wins - r.wins + r.losses - rows[0].losses) * 0.5
				table.add_row(["%d" % (i + 1), side.name if side != null else r.team_id, str(r.games()), str(r.wins), str(r.losses), str(r.ties), BattingLine.rate_text(r.pct()) if r.wins + r.losses > 0 else "-", "-" if i == 0 else "%.1f" % behind],
					r.team_id, {0: UiTheme.ACCENT, 1: tint if r.team_id == s.my_team else UiTheme.INK})
			table.custom_minimum_size.y = 48.0 + 38.0 * rows.size()
			left.body.add_child(table)
	var right := panel("지난 겨울", "snowflake" if UiTheme.icon("snowflake") != null else "calendar-blank", columns, 640.0 if s.farm != null else 0.0, "WINTER")
	if s.farm == null:
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var w := s.last_winter
	if w == null:
		right.body.add_child(UiKit.label("첫 시즌입니다.", 16, UiTheme.DIM, 500))
		return
	var ours_out: Array = w.retired.filter(func(r: Array) -> bool: return str(r[0]) == team.id)
	var ours_in: Array = w.rookies.filter(func(r: Array) -> bool: return str(r[0]) == team.id)
	right.body.add_child(UiKit.label("리그 전체 은퇴 %d명 · 신인 %d명" % [w.retired.size(), w.rookies.size()], 17, UiTheme.INK, 600))
	right.body.add_child(CenteredPanel.section("우리 구단 은퇴"))
	if ours_out.is_empty():
		right.body.add_child(UiKit.label("없음", 16, UiTheme.DIM, 500))
	for r: Array in ours_out:
		right.body.add_child(UiKit.label("%s (%s · %d세)" % [str(r[1]), str(r[3]), int(r[2])], 16, UiTheme.INK, 500))
	right.body.add_child(CenteredPanel.section("우리 구단 신인"))
	for r: Array in ours_in:
		var p := team.player(str(r[1]))
		if p != null:
			right.body.add_child(UiKit.label("%s  %s · %d세  %s" % [p.name, String(p.role()) if p.is_pitcher() else Position.code(p.primary_position()), s.season_year - p.born, Development.stars_text(Development.stars(p, s.club.scout_level if s.club != null else 1))], 16, UiTheme.INK, 500))
	right.body.add_child(CenteredPanel.section("지난 시즌 가장 많이 자란 선수"))
	for r: Array in w.risers.slice(0, 5):
		var club: Team = s.teams.get(str(r[0]))
		var p := club.player(str(r[1])) if club != null else null
		if p != null:
			right.body.add_child(UiKit.label("%s (%s)  +%.1f" % [p.name, club.short_name, float(r[2])], 16, UiTheme.GREEN if club.id == team.id else UiTheme.INK, 500))


# --- The records room ---


## The division's leaders in each category (the first five, qualifying men only for rates)
## or its clubs' batting and pitching side by side. A name opens his card.
func _build_records(s: Season) -> void:
	var d := _records_division if _records_division >= 0 else s.division_of(s.my_team)
	var bar := UiKit.hbox(16)
	content.add_child(bar)
	var views: Array = ["batting", "pitching", "clubs"]
	var words: Array = ["타자 순위", "투수 순위", "팀 기록"]
	bar.add_child(UiKit.segmented(views, words, _records_view, func(id: String) -> void:
		_records_view = id
		refresh()))
	if _records_view == "winter":
		_build_farm_table(s, s.teams[s.my_team])
		return
	bar.add_child(UiKit.spacer(0.0, 0.0, true))
	var ids: Array = []
	var labels: Array = []
	for i: int in s.divisions.size():
		ids.append(str(i))
		labels.append("%d부" % (i + 1))
	bar.add_child(UiKit.segmented(ids, labels, str(d), func(id: String) -> void:
		_records_division = int(id)
		refresh()))
	content.add_child(UiKit.label("규정타석 %d · 규정이닝 %d" % [LeagueRecords.qualifying_pa(s, s.my_team), LeagueRecords.qualifying_outs(s, s.my_team) / 3], 15, UiTheme.DIM, 500))
	var scroll := UiKit.scroll()
	content.add_child(scroll)
	if _records_view == "clubs":
		_build_club_records(scroll, s, d)
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var categories := LeagueRecords.batting_categories() if _records_view == "batting" else LeagueRecords.pitching_categories()
	for c: LeagueRecords.Category in categories:
		_leader_card(grid, s, c, LeagueRecords.leaders(s, d, c, 5))


func _leader_card(parent: Control, s: Season, c: LeagueRecords.Category, board: Array[LeagueRecords.Entry]) -> void:
	var card := GlassPanel.make(c.name, "", 0.0, tint, "규정" if c.qualified else "")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	if board.is_empty():
		card.body.add_child(UiKit.label("아직 기록이 없습니다.", 16, UiTheme.DIM, 500))
		return
	for i: int in board.size():
		var e := board[i]
		var p := find_player(s, e.player_id)
		var club: Team = s.teams[e.team_id]
		var row := UiKit.hbox(10)
		card.body.add_child(row)
		var place := UiKit.latin("%d" % (i + 1), 20, UiTheme.ACCENT if i == 0 else UiTheme.DIM, true)
		place.custom_minimum_size.x = 22.0
		row.add_child(place)
		if i == 0 and p != null:
			# The leader's face, as the record pages show the man on top.
			row.add_child(PortraitStudio.face(self, p, club, 54.0))
		row.add_child(UiKit.club_mark(club, 24.0))
		var name := GameButton.make(p.name if p != null else e.player_id, func() -> void:
			if p != null:
				PlayerCard.open_for(self, p, s), "", "tab")
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if e.team_id == s.my_team:
			name.add_theme_color_override("font_color", tint)
		row.add_child(name)
		row.add_child(UiKit.latin(e.text, 22 if i == 0 else 20, Color.WHITE if i == 0 else UiTheme.INK, false))


## The clubs of a division in the order of the table, batting and pitching added up.
func _build_club_records(parent: Control, s: Season, d: int) -> void:
	var table := DataTable.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.set_columns([["순위", 60.0, 1], ["팀", 200.0, 0], ["경기", 70.0, 2], ["타율", 80.0, 2], ["OPS", 80.0, 2], ["홈런", 70.0, 2], ["득점", 70.0, 2], ["도루", 70.0, 2], ["평균자책점", 110.0, 2], ["실점", 70.0, 2], ["탈삼진", 80.0, 2], ["WHIP", 80.0, 2]])
	var rows := LeagueRecords.clubs(s, d)
	for i: int in rows.size():
		var team_id := str(rows[i][0])
		var bat: BattingLine = rows[i][1]
		var pitch: PitchingLine = rows[i][2]
		var club: Team = s.teams[team_id]
		var mine := team_id == s.my_team
		table.add_row(["%d" % (i + 1), club.short_name, str(LeagueRecords.games_played(s, team_id)),
			BattingLine.rate_text(bat.average()) if bat.ab > 0 else "-", BattingLine.rate_text(bat.ops()) if bat.pa > 0 else "-",
			str(bat.home_runs), str(bat.runs), str(bat.stolen_bases),
			"%.2f" % pitch.era() if pitch.outs > 0 else "-", str(pitch.runs), str(pitch.strikeouts), "%.2f" % pitch.whip() if pitch.outs > 0 else "-"],
			team_id, {0: UiTheme.ACCENT, 1: tint if mine else UiTheme.INK})
	table.custom_minimum_size.y = 48.0 + 38.0 * rows.size()
	var card := GlassPanel.make("팀 기록" if LeagueSession.season.history != null else "%d부 팀 기록" % (d + 1), "table", 0.0, tint, "CLUBS")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.body.add_child(table)
	parent.add_child(card)


## Comparing two men: pin one, pick another, open the two side by side. While
## one is pinned his name stays in the panel with a way to let him go.
func _compare_buttons(parent: Control, p: Player, s: Season) -> void:
	var pinned := find_player(s, _compare_id)
	var row := UiKit.hbox(8)
	parent.add_child(row)
	if pinned == null or pinned.id == p.id:
		row.add_child(UiKit.button("비교 대상으로" if pinned == null else "비교 대상 해제", func() -> void:
			_compare_id = p.id if pinned == null else ""
			message = "%s 선수를 비교 대상으로 정했습니다. 비교할 선수를 고르세요." % p.name if pinned == null else ""
			# The next click picks the other man (in the line-up it would trade places).
			_lineup_pick = ""
			_picked = ""
			refresh(), "chart-polar"))
		return
	var compare := UiKit.button("%s 선수와 비교" % pinned.name, func() -> void: PlayerCompare.open_for(self, pinned, p, s), "chart-polar", "primary")
	compare.disabled = not PlayerCompare.comparable(pinned, p)
	if compare.disabled:
		compare.tooltip_text = "투수는 투수끼리, 타자는 타자끼리 비교합니다."
	row.add_child(compare)
	row.add_child(UiKit.button("해제", func() -> void:
		_compare_id = ""
		refresh(), "x"))


## A player of the league by id: on a club or among today's scouting candidates.
static func find_player(s: Season, id: String) -> Player:
	if id == "":
		return null
	for team_id: String in s.teams:
		var p := (s.teams[team_id] as Team).player(id)
		if p != null:
			return p
	for p: Player in s.club.candidates:
		if p.id == id:
			return p
	return null


# --- The line-up and the rotation ---


## The line-up as a manager sets it (the user: "a big ballpark, the line-up small beside it,
## the players dragged onto their positions; the rotation, the set-up men and the closer too;
## the batting order; recommendations kept"): the nine on a big diamond as cards (face, order,
## name, rating, average), the bench under it; beside it the batting order, and the pitching
## staff — five starters, two set-up men, the closer, the rest of the bullpen. A card dragged
## onto another: a bench player onto a position takes it, two fielders swap positions, two
## order slots swap; a pitcher onto a starter's or a reliever's place takes it. The computer's
## choices are marked 추천, and 추천대로 sets them all.
func _build_lineup(s: Season, team: Team) -> void:
	var manager := AiManager.new(s.env, s.catalog, s.ovr)
	var plan := LineupPlan.current(team, manager, s.rules)
	var rec := _recommended_order(s, team)
	var columns := UiKit.hbox(14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	# The diamond.
	var left := panel("라인업", "baseball", columns, 0.0, "LINEUP")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := UiKit.hbox(8)
	left.body.add_child(top)
	var problems := LineupPlan.problems(plan, team)
	var note := UiKit.label("  ·  ".join(problems) if not problems.is_empty() else message, 16, UiTheme.RED if not problems.is_empty() else UiTheme.ACCENT, 600)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.clip_text = true
	top.add_child(note)
	top.add_child(UiKit.button("추천대로", func() -> void:
		team.batting_plan = []
		team.batting_plan = LineupPlan.current(team, AiManager.new(s.env, s.catalog, s.ovr), s.rules)
		team.rotation_plan = PackedStringArray()
		team.bullpen_plan = _recommended_bullpen(s, team)
		message = "추천 라인업과 투수진으로 맞췄습니다."
		refresh(), "sparkle", "primary"))
	top.add_child(UiKit.button("매 경기 자동", func() -> void:
		team.batting_plan = []
		team.rotation_plan = PackedStringArray()
		team.bullpen_plan = {}
		message = "라인업과 투수진을 컴퓨터에게 맡겼습니다."
		refresh(), "arrows-clockwise"))
	var board := Control.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.custom_minimum_size = Vector2(0.0, 330.0)
	left.body.add_child(board)
	var field := FieldDiagram.new()
	field.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.add_child(field)
	var spots: Dictionary = {}
	for i: int in 9:
		var p := team.player(str(plan[i][0]))
		if p == null:
			continue
		var kind := Position.from_code(str(plan[i][1]))
		var card := _lineup_card(s, team, p, "L%d" % i, i, kind)
		board.add_child(card)
		# The designated hitter waits by the dugout.
		spots[card] = Vector2(FieldDiagram.SPOTS[kind]) if FieldDiagram.SPOTS.has(kind) else Vector2(0.1, 0.9)
	board.resized.connect(func() -> void:
		for card: Control in spots:
			var at: Vector2 = spots[card]
			card.position = (at * board.size - card.size * 0.5).clamp(Vector2.ZERO, board.size - card.size))
	board.ready.connect(func() -> void: board.resized.emit.call_deferred(), CONNECT_ONE_SHOT)
	var bench_row := UiKit.hbox(8)
	left.body.add_child(bench_row)
	bench_row.add_child(UiKit.label("후보", 16, UiTheme.DIM, 700))
	var bench := HFlowContainer.new()
	bench.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bench.add_theme_constant_override("h_separation", 5)
	bench.add_theme_constant_override("v_separation", 5)
	bench_row.add_child(bench)
	for p: Player in LineupPlan.bench(plan, team):
		bench.add_child(_chip(s, team, p, "B" + p.id, "bat", ["bat"], rec.has(p.id)))
	# The batting order and the staff.
	var right := UiKit.vbox(12)
	right.custom_minimum_size.x = 560.0
	columns.add_child(right)
	var order := panel("타순", "list-numbers", right, 0.0, "BATTING ORDER")
	var rows := UiKit.vbox(3)
	order.body.add_child(rows)
	var head := UiKit.hbox(8)
	rows.add_child(head)
	var head_name := UiKit.label("선수", 13, UiTheme.DIM, 600)
	head_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_name.custom_minimum_size.x = 0.0
	head.add_child(UiKit.spacer(60.0, 0.0))
	head.add_child(head_name)
	for word: Array in [["수비", 30.0], ["타율", 48.0], ["홈런", 48.0], ["OPS", 48.0]]:
		var h := UiKit.label(str(word[0]), 13, UiTheme.DIM, 600)
		h.custom_minimum_size.x = float(word[1])
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if str(word[0]) != "수비" else HORIZONTAL_ALIGNMENT_LEFT
		head.add_child(h)
	for i: int in 9:
		var p := team.player(str(plan[i][0]))
		if p == null:
			continue
		var row := DragCard.make("O%d" % i, "bat", ["bat"])
		row.tight()
		row.dropped.connect(func(from: String, to: String) -> void: _lineup_drop(from, to, s, team))
		row.clicked.connect(func(t: String) -> void: _lineup_pressed(t, s, team))
		row.set_lit(_lineup_pick == "O%d" % i)
		var line := UiKit.hbox(8)
		row.add_child(line)
		var n := UiKit.number("%d" % (i + 1), 20, UiTheme.ACCENT)
		n.custom_minimum_size.x = 20.0
		line.add_child(n)
		line.add_child(PortraitStudio.face(self, p, team, 26.0))
		var name := UiKit.label(p.name, 16, Color.WHITE, 700)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name)
		var where := UiKit.label(Position.code(Position.from_code(str(plan[i][1]))), 15, UiTheme.GREEN, 600)
		where.custom_minimum_size.x = 30.0
		line.add_child(where)
		var cells := _bat_cells(s, p)
		for k: int in [0, 1, 3]:
			var cell := UiKit.label(str(cells[k]), 15, UiTheme.INK if k == 0 else UiTheme.DIM, 600)
			cell.custom_minimum_size.x = 48.0
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			line.add_child(cell)
		rows.add_child(row)
	_build_staff(right, s, team)


## One fielder on the diamond: his face, his place in the order, name, rating and average.
func _lineup_card(s: Season, team: Team, p: Player, card_tag: String, at: int, kind: Position.Kind) -> DragCard:
	var fits := kind == Position.Kind.DH or p.aptitude(kind) > 0.0
	var card := DragCard.make(card_tag, "bat", ["bat"], Color(0.05, 0.06, 0.08, 0.92))
	card.tight()
	card.custom_minimum_size = Vector2(176.0, 0.0)
	card.dropped.connect(func(from: String, to: String) -> void: _lineup_drop(from, to, s, team))
	card.clicked.connect(func(t: String) -> void: _lineup_pressed(t, s, team))
	card.set_lit(_lineup_pick == card_tag)
	var line := UiKit.hbox(6)
	card.add_child(line)
	line.add_child(PortraitStudio.face(self, p, team, 44.0))
	var words := UiKit.vbox(0)
	line.add_child(words)
	var top := UiKit.hbox(5)
	words.add_child(top)
	# His place in the order, small beside his position (the user: the badge was too big).
	top.add_child(UiKit.label("%d번" % (at + 1), 13, UiTheme.ACCENT, 700))
	top.add_child(UiKit.label(Position.code(kind), 13, UiTheme.GREEN if fits else UiTheme.RED, 700))
	words.add_child(UiKit.label(p.name, 16, Color.WHITE, 700))
	words.add_child(UiKit.label("OVR %s · %s" % [UiTheme.shown_text(ClubRules.player_ovr(p, s.ovr, s.catalog)), str(_bat_cells(s, p)[0])], 13, UiTheme.DIM, 600))
	return card


## A player as a small card to drag (the bench, the rest of the bullpen).
func _chip(s: Season, team: Team, p: Player, chip_tag: String, kind: String, take: Array[String], recommended: bool) -> DragCard:
	var chip := DragCard.make(chip_tag, kind, take)
	chip.tight()
	chip.dropped.connect(func(from: String, to: String) -> void: _lineup_drop(from, to, s, team))
	chip.clicked.connect(func(t: String) -> void: _lineup_pressed(t, s, team))
	chip.set_lit(_lineup_pick == chip_tag)
	var line := UiKit.hbox(5)
	chip.add_child(line)
	line.add_child(PortraitStudio.face(self, p, team, 24.0))
	line.add_child(UiKit.label(p.name, 15, Color.WHITE, 600))
	line.add_child(UiKit.label(UiTheme.shown_text(ClubRules.player_ovr(p, s.ovr, s.catalog)), 14, UiTheme.rating_color(ClubRules.player_ovr(p, s.ovr, s.catalog)), 700))
	if recommended:
		line.add_child(UiKit.label("추천", 12, UiTheme.GOLD, 600))
	return chip


## The pitching staff: the five starters in their order, the two set-up men and the closer,
## the rest of the bullpen and any starters beyond five to drag in.
func _build_staff(parent: Control, s: Season, team: Team) -> void:
	var p := panel("투수진", "baseball", parent, 0.0, "PITCHING STAFF")
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var starters := team.rotation()
	var pen := _bullpen(s, team)
	var rec_pen := _recommended_bullpen(s, team)
	var rec_rotation := _recommended_rotation(s, team)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	p.body.add_child(grid)
	for i: int in mini(5, starters.size()):
		grid.add_child(_staff_slot(s, team, "R%d" % i, "선발 %d" % (i + 1), starters[i], ["sp"], ""))
	var rec_setup: Array = rec_pen["setup"]
	for k: int in 2:
		var id := str((pen["setup"] as Array)[k]) if (pen["setup"] as Array).size() > k else ""
		var want := str(rec_setup[k]) if rec_setup.size() > k else ""
		var hint := team.player(want).name if want != "" and not (pen["setup"] as Array).has(want) else ""
		grid.add_child(_staff_slot(s, team, "SU%d" % k, "셋업", team.player(id) if id != "" else null, ["rp"], hint))
	var closer_hint := team.player(str(rec_pen["closer"])).name if str(rec_pen["closer"]) not in ["", str(pen["closer"])] else ""
	grid.add_child(_staff_slot(s, team, "CL", "마무리", team.player(str(pen["closer"])) if str(pen["closer"]) != "" else null, ["rp"], closer_hint))
	var pool := HFlowContainer.new()
	pool.add_theme_constant_override("h_separation", 6)
	pool.add_theme_constant_override("v_separation", 6)
	p.body.add_child(UiKit.label("불펜 · 대기 선발", 15, UiTheme.DIM, 600))
	p.body.add_child(pool)
	var used: Dictionary = {str(pen["closer"]): true}
	for id: Variant in pen["setup"]:
		used[str(id)] = true
	for i: int in mini(5, starters.size()):
		used[starters[i].id] = true
	for man: Player in team.first_team():
		if man.is_pitcher() and not used.has(man.id):
			var recommended := str(rec_pen["closer"]) == man.id or rec_setup.has(man.id) or rec_rotation.has(man.id)
			pool.add_child(_chip(s, team, man, "P" + man.id, "sp" if man.role() == &"SP" else "rp", [], recommended))


## A place in the staff: what it is (선발 1, 셋업, 마무리), the man in it, his season.
func _staff_slot(s: Season, team: Team, slot_tag: String, title: String, man: Player, take: Array[String], hint: String) -> DragCard:
	var slot := DragCard.make(slot_tag, take[0] if man != null else "", take, Color(0.05, 0.06, 0.08, 0.85))
	slot.tight()
	slot.dropped.connect(func(from: String, to: String) -> void: _lineup_drop(from, to, s, team))
	slot.clicked.connect(func(t: String) -> void: _lineup_pressed(t, s, team))
	slot.set_lit(_lineup_pick == slot_tag)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line := UiKit.hbox(6)
	slot.add_child(line)
	var label := UiKit.label(title, 14, UiTheme.ACCENT if slot_tag.begins_with("R") else (UiTheme.RED if slot_tag == "CL" else UiTheme.CYAN), 700)
	label.custom_minimum_size.x = 52.0
	line.add_child(label)
	if man == null:
		line.add_child(UiKit.label("비어 있음", 15, UiTheme.DIM, 500))
		return slot
	line.add_child(PortraitStudio.face(self, man, team, 30.0))
	var words := UiKit.vbox(-3)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(words)
	var top := UiKit.hbox(6)
	words.add_child(top)
	top.add_child(UiKit.label(man.name, 16, Color.WHITE, 700))
	# The computer would have put someone else here: his name, small.
	if hint != "":
		top.add_child(UiKit.label("추천 " + hint, 12, UiTheme.GOLD, 600))
	var cells := _pitch_cells(s, man)
	words.add_child(UiKit.label("OVR %s · %s · %s" % [UiTheme.shown_text(ClubRules.player_ovr(man, s.ovr, s.catalog)), cells[0], cells[1]], 13, UiTheme.DIM, 600))
	return slot


## The order the computer would play (to mark its choices): ids of its nine.
func _recommended_order(s: Season, team: Team) -> Dictionary:
	var kept := team.batting_plan
	team.batting_plan = []
	var plan := LineupPlan.current(team, AiManager.new(s.env, s.catalog, s.ovr), s.rules)
	team.batting_plan = kept
	var out: Dictionary = {}
	for entry: Array in plan:
		out[str(entry[0])] = true
	return out


## The computer's five starters: the starters by overall.
func _recommended_rotation(s: Season, team: Team) -> Dictionary:
	var kept := team.rotation_plan
	team.rotation_plan = PackedStringArray()
	var starters := team.rotation()
	team.rotation_plan = kept
	starters.sort_custom(func(a: Player, b: Player) -> bool: return ClubRules.player_ovr(a, s.ovr, s.catalog) > ClubRules.player_ovr(b, s.ovr, s.catalog))
	var out: Dictionary = {}
	for i: int in mini(5, starters.size()):
		out[starters[i].id] = true
	return out


## The computer's bullpen: the best reliever closes, the next two set up (as AiManager does).
func _recommended_bullpen(s: Season, team: Team) -> Dictionary:
	var relievers: Array[Player] = []
	for man: Player in team.first_team():
		if man.is_pitcher() and man.role() != &"SP":
			relievers.append(man)
	relievers.sort_custom(func(a: Player, b: Player) -> bool: return Overall.pitcher(a, s.catalog) > Overall.pitcher(b, s.catalog))
	var setup: Array = []
	for i: int in range(1, mini(3, relievers.size())):
		setup.append(relievers[i].id)
	return {"closer": relievers[0].id if not relievers.is_empty() else "", "setup": setup}


## The bullpen as it stands: the manager's, filled from the computer's where he has not chosen.
func _bullpen(s: Season, team: Team) -> Dictionary:
	var rec := _recommended_bullpen(s, team)
	if team.bullpen_plan.is_empty():
		return rec
	var setup: Array = (team.bullpen_plan.get("setup", []) as Array).duplicate()
	while setup.size() < 2:
		setup.append("")
	return {"closer": str(team.bullpen_plan.get("closer", "")), "setup": setup}


## A card dropped on another (see _build_lineup): the batting order and positions, or the staff.
func _lineup_drop(from: String, to: String, s: Season, team: Team) -> void:
	_lineup_pick = ""
	message = ""
	if to.begins_with("R") or to.begins_with("SU") or to == "CL":
		_staff_drop(from, to, s, team)
		refresh()
		return
	var plan := LineupPlan.current(team, AiManager.new(s.env, s.catalog, s.ovr), s.rules)
	var i_from := int(from.substr(1)) if from.begins_with("L") or from.begins_with("O") else -1
	var i_to := int(to.substr(1)) if to.begins_with("L") or to.begins_with("O") else -1
	if from.begins_with("B") and i_to >= 0:
		LineupPlan.bring_in(plan, i_to, from.substr(1))
		message = "%s 선수가 %d번 타순에 들어갑니다." % [team.player(from.substr(1)).name, i_to + 1]
	elif i_from >= 0 and to.begins_with("B"):
		LineupPlan.bring_in(plan, i_from, to.substr(1))
		message = "%s 선수가 %d번 타순에 들어갑니다." % [team.player(to.substr(1)).name, i_from + 1]
	elif i_from >= 0 and i_to >= 0 and to.begins_with("L") and from.begins_with("L"):
		LineupPlan.swap_positions(plan, i_from, i_to)
		message = "수비 위치를 맞바꿨습니다."
	elif i_from >= 0 and i_to >= 0:
		LineupPlan.swap_order(plan, i_from, i_to)
		message = "타순을 맞바꿨습니다."
	else:
		return
	team.batting_plan = plan
	refresh()


## A pitcher dropped on a starter's or a reliever's place: he takes it, and whoever had it goes
## where he came from (or back to the bullpen). Starters start, relievers relieve.
func _staff_drop(from: String, to: String, s: Season, team: Team) -> void:
	var rotation := PackedStringArray()
	for man: Player in team.rotation():
		rotation.append(man.id)
	var pen := _bullpen(s, team)
	var slots: Dictionary = {"CL": str(pen["closer"])}
	for k: int in 2:
		slots["SU%d" % k] = str((pen["setup"] as Array)[k])
	for i: int in rotation.size():
		slots["R%d" % i] = rotation[i]
	var mover := from.substr(1) if from.begins_with("P") else str(slots.get(from, ""))
	if mover == "" or not slots.has(to) or team.player(mover) == null:
		return
	if (team.player(mover).role() == &"SP") != to.begins_with("R"):
		message = "선발 투수는 선발 로테이션에, 불펜 투수는 셋업과 마무리에 넣을 수 있습니다."
		return
	# Where he is now (a starter beyond the five is in the rotation too).
	var source := ""
	for t: String in slots:
		if slots[t] == mover:
			source = t
	var held := str(slots[to])
	slots[to] = mover
	if source != "":
		slots[source] = held
	for i: int in rotation.size():
		rotation[i] = str(slots["R%d" % i])
	team.rotation_plan = rotation
	team.bullpen_plan = {"closer": slots["CL"], "setup": [slots["SU0"], slots["SU1"]]}
	message = "%s 선수를 %s" % [team.player(mover).name, "선발 로테이션에 넣었습니다." if to.begins_with("R") else ("셋업맨으로 정했습니다." if to.begins_with("SU") else "마무리로 정했습니다.")]


## A click without a drag: the first card picked is lit, the second does what dropping the
## first on it would (a bench man or a reliever in the pool picked second goes to the first).
func _lineup_pressed(tag: String, s: Season, team: Team) -> void:
	var first := _lineup_pick
	if first == "" or first == tag:
		_lineup_pick = "" if first == tag else tag
		refresh()
		return
	if tag.begins_with("B") or tag.begins_with("P"):
		_lineup_drop(tag, first, s, team)
	else:
		_lineup_drop(first, tag, s, team)
	_lineup_pick = ""
	refresh()


## A league of one season with a club (the user: "one club, one season, then the
## rewards and a new one"): the clubs' first and second teams, no second teams' league.
static func one_season(s: Season) -> bool:
	return s.farm == null and s.history == null and s.divisions.size() == 1


# --- Trades (Trade) ---


var _trade_club := ""
var _trade_give := PackedStringArray()
var _trade_get := PackedStringArray()


## My men on the left, the other club's on the right, best first; up to three picked on each
## side; between them what goes and what comes, how the other club sees it, and the offer.
func _build_trade(s: Season, team: Team) -> void:
	var others: Array = []
	for id: String in s.divisions[s.division_of(s.my_team)]:
		if id != s.my_team:
			others.append(id)
	if _trade_club == "" or not others.has(_trade_club):
		_trade_club = str(others[0]) if not others.is_empty() else ""
	var theirs: Team = s.teams.get(_trade_club)
	var bar := UiKit.hbox(12)
	content.add_child(bar)
	var open := Trade.open(s)
	var left_days := Trade.deadline(s) - s.day
	bar.add_child(UiKit.badge("트레이드 마감 %d일차" % (Trade.deadline(s) + 1), UiTheme.ACCENT if open else UiTheme.RED))
	bar.add_child(UiKit.label(("남은 %d일" % left_days) if open else "이번 시즌 트레이드는 끝났습니다", 16, UiTheme.DIM, 600))
	var note := UiKit.label(message, 16, UiTheme.ACCENT, 600)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.clip_text = true
	bar.add_child(note)
	var columns := UiKit.hbox(14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var left := panel("%s  보낼 선수" % team.short_name, "arrow-right", columns, 0.0, "GIVE")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.body.add_child(_trade_list(s, team, _trade_give, true))
	# The deal between the two lists.
	var middle := panel("트레이드", "swap", columns, 380.0, "DEAL")
	if theirs != null:
		var pick := UiKit.selector("상대", others, others.map(func(id: Variant) -> String: return (s.teams[id] as Team).name), _trade_club, func(v: String) -> void:
			_trade_club = v
			_trade_get = PackedStringArray()
			message = ""
			refresh())
		middle.body.add_child(pick)
		var mark := UiKit.club_mark(theirs, 84.0)
		mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		middle.body.add_child(mark)
		var weigh := Trade.weigh(s, team, theirs, _trade_give, _trade_get)
		middle.body.add_child(UiKit.caption("보내는 선수"))
		for id: String in _trade_give:
			middle.body.add_child(UiKit.label(team.player(id).name, 17, Color.WHITE, 700))
		middle.body.add_child(UiKit.caption("받는 선수"))
		for id: String in _trade_get:
			middle.body.add_child(UiKit.label(theirs.player(id).name, 17, Color.WHITE, 700))
		if not _trade_give.is_empty() and not _trade_get.is_empty():
			# How the other club sees it: what it gets against what it gives.
			var gets := float(weigh["get"])
			var gives := float(weigh["give"])
			var share := gets / maxf(gets + gives * Trade.MARGIN, 1.0)
			middle.body.add_child(UiKit.caption("상대 구단의 평가"))
			var meter := ProgressBar.new()
			meter.custom_minimum_size = Vector2(0.0, 10.0)
			meter.show_percentage = false
			meter.max_value = 1.0
			meter.value = share
			meter.add_theme_stylebox_override("background", UiTheme.flat(Color(1.0, 1.0, 1.0, 0.08), 4))
			meter.add_theme_stylebox_override("fill", UiTheme.flat(UiTheme.GREEN if share >= 0.5 else (UiTheme.ACCENT if share >= 0.44 else UiTheme.RED), 4))
			middle.body.add_child(meter)
			middle.body.add_child(UiKit.label("받아들일 만함" if share >= 0.5 else ("조금 부족함" if share >= 0.44 else "크게 부족함"), 15, UiTheme.INK, 600))
		middle.body.add_child(UiKit.spacer(0.0, 0.0, true))
		var offer := UiKit.button("제안하기", func() -> void:
			var w := Trade.weigh(s, team, theirs, _trade_give, _trade_get)
			message = str(w["reason"])
			if bool(w["accepted"]):
				Trade.apply(s, team, theirs, _trade_give, _trade_get)
				_trade_give = PackedStringArray()
				_trade_get = PackedStringArray()
				LeagueSession.autosave()
			refresh(), "handshake", "primary")
		offer.disabled = not open or _trade_give.is_empty() or _trade_get.is_empty()
		middle.body.add_child(offer)
		var right := panel("%s  받을 선수" % theirs.short_name, "arrow-left", columns, 0.0, "GET")
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.body.add_child(_trade_list(s, theirs, _trade_get, false))


## A club's men as rows to pick (first team and second), best first.
func _trade_list(s: Season, club: Team, picked: PackedStringArray, mine: bool) -> Control:
	var scroll := UiKit.scroll()
	var rows := UiKit.vbox(3)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var men := club.players.duplicate()
	men.sort_custom(func(x: Player, y: Player) -> bool: return ClubRules.player_ovr(x, s.ovr, s.catalog) > ClubRules.player_ovr(y, s.ovr, s.catalog))
	for man: Player in men:
		var on := picked.has(man.id)
		var row := DragCard.make("X" + man.id, "", [], Color(1.0, 1.0, 1.0, 0.04))
		row.tight()
		row.set_lit(on)
		row.clicked.connect(func(_t: String) -> void:
			var list := _trade_give if mine else _trade_get
			if list.has(man.id):
				list.remove_at(list.find(man.id))
			elif list.size() < Trade.MAX_MEN:
				list.append(man.id)
			if mine:
				_trade_give = list
			else:
				_trade_get = list
			message = ""
			refresh())
		var line := UiKit.hbox(8)
		row.add_child(line)
		line.add_child(PortraitStudio.face(self, man, club, 30.0))
		var name := UiKit.label(man.name, 16, Color.WHITE if on else UiTheme.INK, 700)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_text = true
		line.add_child(name)
		line.add_child(UiKit.label(("선발" if man.role() == &"SP" else "구원") if man.is_pitcher() else Position.code(man.primary_position()), 14, UiTheme.CYAN if man.is_pitcher() else UiTheme.GREEN, 600))
		line.add_child(UiKit.label("%d세" % (s.season_year - man.born), 14, UiTheme.DIM, 500))
		line.add_child(UiKit.label("1군" if club.is_registered(man.id) else "2군", 13, UiTheme.ACCENT if club.is_registered(man.id) else UiTheme.DIM, 600))
		var o := ClubRules.player_ovr(man, s.ovr, s.catalog)
		var ovr := UiKit.label(UiTheme.shown_text(o), 16, UiTheme.rating_color(o), 700)
		ovr.custom_minimum_size.x = 34.0
		ovr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(ovr)
		rows.add_child(row)
	return scroll


## Puts a second-team player on the first team, within the roster rules and the cost cap.
func register(p: Player) -> String:
	var s := LeagueSession.season
	var team: Team = s.teams[s.my_team]
	var problem := team.registration_problem(p.id, s.day, s.rules)
	if problem != "":
		return "등록할 수 없다: " + problem
	var cost := s.club_rules.first_team_cost(team, s.ovr, s.catalog) + s.club_rules.grade_of(ClubRules.player_ovr(p, s.ovr, s.catalog)).cost
	var cap := s.club_rules.cost_cap(s.division_of(s.my_team))
	if cost > cap:
		return "등록할 수 없다: 1군 코스트 %d이 상한 %d을 넘는다" % [cost, cap]
	team.register(p.id, s.day, s.rules)
	return "%s 1군 등록." % p.name


## The traits as badges (as the reference games show special abilities): every trait the
## league has, batters' and pitchers', its metal the best stage the club holds (grey: none
## yet). The one picked stands beside it: what each stage gives, how many the club holds, who
## wears it, and the draw, the merge and the fitting.
func _build_traits(s: Season) -> void:
	var c := s.club
	var r := s.club_rules
	if _trait_view < 0 or _trait_view >= r.traits.size():
		_trait_view = 0
		for item: Vector2i in c.bag:
			_trait_view = item.x
			break
	var columns := UiKit.hbox(16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var p := panel("특성 배지", "sparkle", columns, 0.0, "TRAITS")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for kind: StringName in [&"batter", &"pitcher"]:
		var head := UiKit.hbox(8)
		p.body.add_child(head)
		head.add_child(UiKit.icon("baseball-helmet" if kind == &"batter" else "person-simple-throw", 20.0, tint))
		head.add_child(UiKit.label("타자 특성" if kind == &"batter" else "투수 특성", 17, Color.WHITE, 700))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		p.body.add_child(grid)
		for i: int in r.traits.size():
			if r.traits[i].kind == kind:
				grid.add_child(_trait_tile(s, i))
	var side := panel("특성 관리", "sliders-horizontal", columns, 470.0, "MANAGE")
	_trait_detail(side.body, s, _trait_view)


## One badge in the case: the metal of the best stage held, the name, how many are held.
func _trait_tile(s: Season, index: int) -> DragCard:
	var def := s.club_rules.traits[index]
	var held := _trait_stages(s, index)
	var best := -1
	for stage: int in held:
		best = maxi(best, stage)
	var tile := DragCard.make("T%d" % index, "", [], Color(1.0, 1.0, 1.0, 0.035))
	tile.tight()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.set_lit(index == _trait_view)
	tile.clicked.connect(func(_t: String) -> void:
		_trait_view = index
		_picked_trait = -1
		message = ""
		refresh())
	var box := UiKit.vbox(0)
	tile.add_child(box)
	box.add_child(TraitBadge.make(best, str(TRAIT_MARKS.get(def.id, "sparkle")), 96.0))
	var name := UiKit.label(def.name, 16, Color.WHITE if best >= 0 else UiTheme.DIM, 700)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name)
	var gives := PackedStringArray()
	for key: String in def.effect:
		if not gives.has(str(EFFECT_NAMES.get(key, key))):
			gives.append(str(EFFECT_NAMES.get(key, key)))
	var effect := UiKit.label(" · ".join(gives.slice(0, 3)), 13, UiTheme.INK if best >= 0 else Color(1.0, 1.0, 1.0, 0.3), 500)
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect.clip_text = true
	box.add_child(effect)
	var worn := _trait_wearers(s, index).size()
	var parts := PackedStringArray()
	if not held.is_empty():
		parts.append("보유 %d" % held.size())
	if worn > 0:
		parts.append("장착 %d" % worn)
	var words := "  ·  ".join(parts) if not parts.is_empty() else "미보유"
	var sub := UiKit.label(words, 13, UiTheme.ACCENT if held.size() + worn > 0 else Color(1.0, 1.0, 1.0, 0.3), 600)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	return tile


## The trait picked: its badge, what each stage gives, those held and worn, and what can be done.
func _trait_detail(body: Control, s: Season, index: int) -> void:
	var c := s.club
	var r := s.club_rules
	var def := r.traits[index]
	var held := _trait_stages(s, index)
	var wearers := _trait_wearers(s, index)
	var best := -1
	for stage: int in held:
		best = maxi(best, stage)
	for man: Player in wearers:
		best = maxi(best, c.traits[man.id].y)
	# The club's points and the draw.
	var purse := UiKit.hbox(12)
	body.add_child(purse)
	purse.add_child(UiKit.icon("coins", 26.0, UiTheme.ACCENT))
	purse.add_child(UiKit.number("%d" % c.points, 30, UiTheme.ACCENT))
	var purse_words := UiKit.label("구단 포인트", 15, UiTheme.DIM, 600)
	purse_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	purse.add_child(purse_words)
	var draw := UiKit.button("특성 뽑기  %d" % int(r.points.get("trait", 0)), func() -> void:
		var pick := c.buy_trait(r, _rng)
		if pick >= 0:
			_trait_view = pick
			message = "%s 특성을 얻었습니다." % r.traits[pick].name
		else:
			message = "포인트가 부족합니다."
		refresh(), "gift", "primary")
	draw.disabled = c.points < int(r.points.get("trait", 0))
	purse.add_child(draw)
	body.add_child(UiKit.spacer(0.0, 4.0))
	# The badge itself.
	var top := UiKit.hbox(14)
	body.add_child(top)
	top.add_child(TraitBadge.make(best, str(TRAIT_MARKS.get(def.id, "sparkle")), 92.0))
	var words := UiKit.vbox(2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(words)
	words.add_child(UiKit.latin("BATTER" if def.kind == &"batter" else "PITCHER", 16, tint, true))
	words.add_child(UiKit.heading(def.name, 30))
	words.add_child(UiKit.label(def.note, 15, UiTheme.INK, 500))
	# What each stage gives; the stages held are lit.
	var stages := UiKit.vbox(4)
	body.add_child(stages)
	for stage: int in r.trait_tiers.size():
		var row := UiKit.hbox(10)
		stages.add_child(row)
		var on := held.has(stage) or wearers.any(func(man: Player) -> bool: return c.traits[man.id].y == stage)
		var metal: Color = TraitBadge.METALS[mini(stage, 2)][0]
		var mark := UiKit.label("%d단계" % (stage + 1), 15, metal if on else UiTheme.DIM, 700)
		mark.custom_minimum_size.x = 52.0
		row.add_child(mark)
		var parts := PackedStringArray()
		var named: Dictionary = {}
		for key: String in def.effect:
			# Two engine ratings shown as one (주력, 제구): the larger of the two.
			var shown := str(EFFECT_NAMES.get(key, key))
			named[shown] = maxf(float(named.get(shown, 0.0)), def.effect[key] * r.trait_tiers[stage])
		for shown: String in named:
			parts.append("%s +%s" % [shown, String.num(float(named[shown]), 1).trim_suffix(".0")])
		row.add_child(UiKit.label("  ".join(parts), 15, Color.WHITE if on else UiTheme.DIM, 600))
	# Held, worn, and what to do with them.
	# The stages held as a merging path: two of a stage make one of the next.
	var counts: Dictionary = {}
	for stage: int in held:
		counts[stage] = int(counts.get(stage, 0)) + 1
	var path := UiKit.hbox(6)
	path.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(path)
	for stage: int in r.trait_tiers.size():
		if stage > 0:
			var arrow := UiKit.label("2 ▸", 15, UiTheme.DIM, 700)
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			path.add_child(arrow)
		var step := UiKit.vbox(0)
		path.add_child(step)
		var n := int(counts.get(stage, 0))
		step.add_child(TraitBadge.make(stage if n > 0 else -1, str(TRAIT_MARKS.get(def.id, "sparkle")), 70.0))
		var count := UiKit.label("%d단계 ×%d" % [stage + 1, n], 14, TraitBadge.METALS[mini(stage, 2)][0] if n > 0 else UiTheme.DIM, 700)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		step.add_child(count)
	var team: Team = s.teams[s.my_team]
	# Who wears it, and who would (the best of the right kind without a trait): a press on one
	# of those fits him with the best stage held.
	var top_bag := -1
	for i: int in c.bag.size():
		if c.bag[i].x == index and (top_bag < 0 or c.bag[i].y > c.bag[top_bag].y):
			top_bag = i
	body.add_child(UiKit.label("장착한 선수" if not wearers.is_empty() else "장착 후보", 15, UiTheme.DIM, 700))
	var men: Array[Player] = wearers.duplicate()
	if men.is_empty():
		for man: Player in team.first_team():
			if not c.traits.has(man.id) and (def.kind == &"pitcher") == man.is_pitcher():
				men.append(man)
		men.sort_custom(func(a: Player, b: Player) -> bool: return ClubRules.player_ovr(a, s.ovr, s.catalog) > ClubRules.player_ovr(b, s.ovr, s.catalog))
	for man: Player in men.slice(0, 3):
		var row := DragCard.make("W" + man.id, "", [], Color(1.0, 1.0, 1.0, 0.04))
		row.tight()
		var line := UiKit.hbox(10)
		row.add_child(line)
		line.add_child(PortraitStudio.face(self, man, team, 34.0))
		var who := UiKit.label(man.name, 16, Color.WHITE, 700)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(who)
		var o := ClubRules.player_ovr(man, s.ovr, s.catalog)
		line.add_child(UiKit.label(("선발" if man.role() == &"SP" else "구원") if man.is_pitcher() else Position.code(man.primary_position()), 14, UiTheme.CYAN if man.is_pitcher() else UiTheme.GREEN, 600))
		line.add_child(UiKit.label("OVR " + UiTheme.shown_text(o), 14, UiTheme.rating_color(o), 700))
		if c.traits.has(man.id):
			line.add_child(UiKit.badge("%d단계" % (c.traits[man.id].y + 1), TraitBadge.METALS[mini(c.traits[man.id].y, 2)][0]))
		elif top_bag >= 0:
			line.add_child(UiKit.label("장착 ▸", 14, UiTheme.ACCENT, 700))
			row.clicked.connect(func(_t: String) -> void:
				var name := def.name
				if c.equip(man, top_bag, r):
					message = "%s에게 %s 장착." % [man.name, name]
				refresh())
		body.add_child(row)
	body.add_child(UiKit.spacer(0.0, 0.0, true))
	if message != "":
		body.add_child(UiKit.label(message, 16, UiTheme.ACCENT, 600))
	var actions := UiKit.hbox(8)
	body.add_child(actions)
	# The best one held goes on the best man of the right kind who has none.
	var equip := UiKit.button("장착", func() -> void:
		message = equip_best(top_bag)
		refresh(), "check", "primary")
	equip.disabled = top_bag < 0
	equip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(equip)
	var pair := Vector2i(-1, -1)
	for i: int in c.bag.size():
		for j: int in range(i + 1, c.bag.size()):
			if pair.x < 0 and c.bag[i] == c.bag[j] and c.bag[i].x == index and c.bag[i].y < r.trait_tiers.size() - 1:
				pair = Vector2i(i, j)
	var merge := UiKit.button("합성" if pair.x < 0 else "합성: %d단계 둘 → %d단계" % [c.bag[pair.x].y + 1, c.bag[pair.x].y + 2], func() -> void:
		c.merge(pair.x, pair.y, r)
		message = "%s %d단계가 됐습니다." % [def.name, c.bag[c.bag.size() - 1].y + 1] if not c.bag.is_empty() else ""
		refresh(), "stack")
	merge.disabled = pair.x < 0
	merge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(merge)


## Stages of a trait in the club's bag (one entry for each held).
func _trait_stages(s: Season, index: int) -> Array[int]:
	var out: Array[int] = []
	for item: Vector2i in s.club.bag:
		if item.x == index:
			out.append(item.y)
	return out


## The club's players wearing a trait.
func _trait_wearers(s: Season, index: int) -> Array[Player]:
	var out: Array[Player] = []
	var team: Team = s.teams[s.my_team]
	for id: String in s.club.traits:
		if s.club.traits[id].x == index and team.player(id) != null:
			out.append(team.player(id))
	return out


## Puts a bag trait on the first-team player of the right kind who has none, the best first.
func equip_best(index: int) -> String:
	var s := LeagueSession.season
	var team: Team = s.teams[s.my_team]
	var def := s.club_rules.traits[s.club.bag[index].x]
	var best: Player = null
	var best_ovr := -1.0
	for p: Player in team.first_team():
		if s.club.traits.has(p.id) or (def.kind == &"pitcher") != p.is_pitcher():
			continue
		var o := ClubRules.player_ovr(p, s.ovr, s.catalog)
		if o > best_ovr:
			best_ovr = o
			best = p
	if best == null or not s.club.equip(best, index, s.club_rules):
		return "장착할 선수가 없다."
	return "%s에게 %s 장착." % [best.name, def.name]


func _cycle_training(s: Season, p: Player) -> void:
	var options: Array[String] = ["stuff", "control", "breaking"] if p.is_pitcher() else ["batting", "running", "fielding"]
	var now := s.club.training.get(p.id, "") as String
	var i := options.find(now)
	if i == options.size() - 1:
		s.club.training.erase(p.id)
		return
	var next := options[i + 1]
	if not s.club.assign_training(p.id, next, s.club_rules):
		message = "훈련은 하루 %d명까지 지정할 수 있습니다." % s.club_rules.train_per_day


# --- Days and games ---


func play_on_screen() -> void:
	var s := LeagueSession.season
	var g := s.my_game_today()
	if g == null or g.played:
		return
	LeagueSession.pending = g
	var d := s.division_of(s.my_team)
	var post := s.postseason_of(g)
	var title := league_name(s, d) if post == null else "%s %d차전" % [post.round_name(), g.game_in_series]
	var info := {"away": s.teams[g.away], "home": s.teams[g.home], "title": title,
		"line": "%d년 시즌 %d일차 · %s" % [s.season_year, s.day + 1, MatchScene.home_def(s.teams[g.home]).name]}
	# Each club's record so far, under its name on the loading screen.
	for side: int in 2:
		var id: String = g.away if side == 0 else g.home
		var division := s.division_of(id)
		if division >= 0:
			var r := s.standings[division].row(id)
			if r != null:
				info["record%d" % side] = "%d승 %d패 %d무" % [r.wins, r.losses, r.ties]
	go(LeagueSession.MATCH, info)


## Settles today's game at once.
func quick_result() -> void:
	var s := LeagueSession.season
	var g := s.my_game_today()
	if g == null or g.played:
		return
	var sim := s.prepare(g)
	sim.play()
	s.record(g, sim.state, sim.scorer.book)
	message = "빠른 결과: %d-%d %s" % [g.runs_of(s.my_team), g.runs_against(s.my_team), _result_word(g)]
	refresh()


## The all-star break: his men picked, the game (himself or at once) and the derby (his
## hitter, himself or at once), and what it paid.
func _build_all_star(parent: Control, s: Season) -> void:
	var p := panel("올스타 브레이크", "star", parent, 0.0, "ALL-STAR")
	var mine := LeagueAllStar.of_my_club(s)
	var names := PackedStringArray()
	for id: String in mine:
		names.append(s.teams[s.my_team].player(id).name)
	p.body.add_child(UiKit.label("우리 구단 선정: %s" % (", ".join(names) if not names.is_empty() else "없음"), 18, UiTheme.INK, 600))
	for line: Variant in s.all_star.get("paid", []):
		p.body.add_child(UiKit.label(str(line), 16, UiTheme.ACCENT, 600))
	var row := UiKit.hbox(10)
	p.body.add_child(row)
	var game: Array = s.all_star.get("game", [])
	if game.is_empty():
		row.add_child(UiKit.button("올스타전 직접 플레이", func() -> void:
			go(ALL_STAR_MATCH, {"title": "올스타전", "away": LeagueAllStar.teams(s)[0], "home": LeagueAllStar.teams(s)[1]}), "play", "primary"))
		row.add_child(UiKit.button("올스타전 빠른 결과", func() -> void:
			LeagueAllStar.quick_game(s)
			LeagueSession.autosave()
			refresh(), "fast-forward"))
	else:
		var sides := ["청팀", "백팀"]
		p.body.add_child(UiKit.label("올스타전: %s %d : %d %s" % [sides[0], int(game[0]), int(game[1]), sides[1]], 17, UiTheme.INK, 600))
	if not LeagueAllStar.derby_over(s):
		var his := LeagueAllStar.my_derby_man(s)
		if his != "":
			var man := s.teams[s.my_team].player(his)
			row.add_child(UiKit.button("홈런 더비 (%s) 직접" % man.name, func() -> void:
				HomeRunDerby.league_batter = man
				go(DERBY, {"title": "홈런 더비"}), "fire"))
		row.add_child(UiKit.button("홈런 더비 빠른 결과", func() -> void:
			LeagueAllStar.quick_derby(s)
			LeagueSession.autosave()
			refresh(), "fast-forward"))
	else:
		var best := LeagueAllStar.winner(s)
		var who := LeagueAllStar._find(s, best)
		p.body.add_child(UiKit.label("홈런 더비 우승: %s (%d개)" % [who.name if who != null else best, int((s.all_star["derby"] as Dictionary).get(best, 0))], 17, UiTheme.INK, 600))


## The fans' vote announced as the break begins (AllStarVote): both teams' best twelve, his
## club's men lit.
func _announce_all_stars(s: Season) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var selected: Array[String] = []
	selected.assign(s.all_star.get("selected", []))
	var mine := LeagueAllStar.of_my_club(s)
	var said := "우리 구단 %d명 선정 · 구단 포인트 +%d" % [mine.size(), LeagueAllStar.CLUB_PER_MAN * mine.size()] if not mine.is_empty() else "이번 올스타에는 우리 구단 선수가 뽑히지 못했습니다"
	AllStarVote.play(self, "%d 올스타 팬 투표 최종 결과" % s.season_year, AllStar.board(s, 0, selected, null, s.my_team), said, s)


const ALL_STAR_MATCH := "res://league/all_star_match.tscn"
const DERBY := "res://career/home_run_derby.tscn"


func next_day() -> void:
	var s := LeagueSession.season
	s.news.clear()
	var g := s.my_game_today()
	if g != null and not g.played:
		message = "오늘 경기를 먼저 진행해야 합니다."
		refresh()
		return
	if LeagueAllStar.on(s):
		LeagueAllStar.settle(s)
	s.advance()
	s.play_day()
	message = ""
	refresh()


## Days go by (our games settled at once) until our next game is today.
func to_next_game() -> void:
	var s := LeagueSession.season
	s.news.clear()
	var guard := 0
	while s.phase != Season.Phase.OVER and guard < 400:
		var g := s.my_game_today()
		if g != null and not g.played:
			break
		if LeagueAllStar.due(s) or LeagueAllStar.on(s):
			LeagueAllStar.settle(s)
		s.advance()
		s.play_day()
		guard += 1
	refresh()


## The rest of the regular season (or of the postseason) at once.
func to_phase_end() -> void:
	var s := LeagueSession.season
	s.news.clear()
	var phase := s.phase
	var guard := 0
	while s.phase == phase and guard < 400:
		s.play_day(true)
		if LeagueAllStar.due(s) or LeagueAllStar.on(s):
			LeagueAllStar.settle(s)
		s.advance()
		guard += 1
	if s.phase != Season.Phase.OVER:
		s.play_day()
	message = "포스트시즌이 시작되었습니다." if s.phase == Season.Phase.POSTSEASON else "시즌이 종료되었습니다."
	refresh()
