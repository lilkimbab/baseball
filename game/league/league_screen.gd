class_name LeagueScreen
extends Control
## The manager league's screen (docs/02 sections 4 and 5, docs/13 S7): start a season with a
## club in the third division, then go day by day. Today's game is played on screen as a
## managed game (감독 지휘) or settled at once (빠른 결과); the other games of the day are
## played as the day begins. The middle shows the division table, the postseason ladder, or
## the season's end (champions, promotion and relegation, awards). The right side runs the
## club: first and second team, training, scouting and traits.
##
## The hub, the menus and saving come with S9; until then this is the league's one screen:
##   ./dev play res://league/league_screen.tscn

const GAME_CHOICES: Array[int] = [36, 72, 144]
const COLUMN := 600.0

var message := ""
var _content: HBoxContainer
var _tab := "roster"
var _games := 36
var _choice := ""
var _rng := Rng.new(1)


func _ready() -> void:
	theme = UiTheme.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_content = HBoxContainer.new()
	_content.add_theme_constant_override("separation", 24)
	_content.position = Vector2(32.0, 28.0)
	add_child(_content)
	_rng = Rng.new(int(Time.get_unix_time_from_system()) % 100000)
	get_viewport().size_changed.connect(_fit)
	_fit()
	if LeagueSession.season != null:
		LeagueSession.season.play_day()
		LeagueSession.autosave()
	refresh()


## The layout is for a 1080-line screen, scaled to the window like the HUD.
func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	var k := UiTheme.scale_for(screen.y)
	scale = Vector2(k, k)
	size = screen / k


func refresh() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if is_inside_tree() and LeagueSession.season != null:
		LeagueSession.autosave()
	if LeagueSession.season == null:
		_build_setup()
	else:
		_build_season()


# --- A new season ---


func _build_setup() -> void:
	var col := _column(1200.0)
	_title(col, "감독 리그 · 새 시즌")
	_line(col, "3부 리그에서 시작한다. 지휘할 구단을 고른다.", UiTheme.DIM)
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	var grid := GridContainer.new()
	grid.columns = 2
	col.add_child(grid)
	for i: int in range(20, mini(30, clubs.size())):
		var t := clubs[i]
		var b := Button.new()
		b.text = ("● " if _choice == t.id else "") + t.name
		b.custom_minimum_size = Vector2(420.0, 0.0)
		b.pressed.connect(func() -> void:
			_choice = t.id
			refresh())
		grid.add_child(b)
	_line(col, "시즌 길이", UiTheme.GOLD)
	var row := HBoxContainer.new()
	col.add_child(row)
	for n: int in GAME_CHOICES:
		var b := Button.new()
		b.text = ("● " if _games == n else "") + "%d경기" % n
		b.pressed.connect(func() -> void:
			_games = n
			refresh())
		row.add_child(b)
	var back := Button.new()
	back.text = "허브로"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(Screen.HUB))
	col.add_child(back)
	var start := Button.new()
	start.text = "시즌 시작"
	start.disabled = _choice == ""
	start.pressed.connect(func() -> void: begin(_choice, _games))
	col.add_child(start)


## Starts a season with a club (also used by tests).
func begin(team_id: String, games: int) -> void:
	LeagueSession.start(team_id, games, _rng.next_int(1000000))
	LeagueSession.season.play_day()
	message = "%s의 시즌이 시작됐다." % LeagueSession.season.teams[team_id].name
	refresh()


# --- The season ---


func _build_season() -> void:
	var s := LeagueSession.season
	_build_today(_column(COLUMN), s)
	var middle := _column(COLUMN + 40.0)
	match s.phase:
		Season.Phase.REGULAR:
			_build_table(middle, s)
		Season.Phase.POSTSEASON:
			_build_ladder(middle, s)
		Season.Phase.OVER:
			_build_end(middle, s)
	_build_club(_column(COLUMN), s)


func _build_today(col: VBoxContainer, s: Season) -> void:
	var team: Team = s.teams[s.my_team]
	var d := s.division_of(s.my_team)
	var phase: String = ["정규 시즌", "포스트시즌", "시즌 종료"][s.phase]
	_title(col, "%d년 %s · %d일째" % [s.season_year, phase, s.day + 1])
	var row := s.standings[d].row(s.my_team)
	_line(col, "%s (%d부)" % [team.name, d + 1], UiTheme.GOLD)
	_line(col, "%d승 %d패 %d무 · %d위 · %.1f경기 차 %s" % [row.wins, row.losses, row.ties, s.standings[d].rank_of(s.my_team), s.standings[d].games_behind(s.my_team), row.streak_text()], UiTheme.INK)
	var g := s.my_game_today()
	if g != null and not g.played:
		var home := g.home == s.my_team
		var other: Team = s.teams[g.opponent_of(s.my_team)]
		var round := ""
		var p := s.postseason_of(g)
		if p != null:
			round = "%s %d차전 · " % [p.round_name(), g.game_in_series]
		_line(col, "오늘: %svs %s (%s)" % [round, other.name, "홈" if home else "원정"], UiTheme.INK)
		_button(col, "감독 지휘로 경기하기", play_on_screen)
		_button(col, "빠른 결과", quick_result)
	else:
		if g != null:
			_line(col, "오늘 경기: %d-%d %s" % [g.runs_of(s.my_team), g.runs_against(s.my_team), _result_word(g)], UiTheme.INK)
		elif s.phase != Season.Phase.OVER:
			_line(col, "오늘은 우리 경기가 없다.", UiTheme.DIM)
		if s.phase != Season.Phase.OVER:
			_button(col, "다음 날", next_day)
	if s.phase != Season.Phase.OVER:
		_button(col, "다음 우리 경기까지", to_next_game)
		_button(col, "정규 시즌 끝까지" if s.phase == Season.Phase.REGULAR else "포스트시즌 끝까지", to_phase_end)
	if message != "":
		_line(col, message, UiTheme.GOLD)
	_button(col, "허브로", func() -> void: get_tree().change_scene_to_file(Screen.HUB))
	_line(col, "최근 경기", UiTheme.DIM)
	var recent: Array[ScheduledGame] = []
	for sched: Schedule in s.schedules:
		for game: ScheduledGame in sched.games:
			if game.played and game.involves(s.my_team):
				recent.append(game)
	for game: ScheduledGame in recent.slice(maxi(recent.size() - 8, 0)):
		var other: Team = s.teams[game.opponent_of(s.my_team)]
		_line(col, "%d일 %s %s %d-%d %s" % [game.day + 1, "vs" if game.home == s.my_team else "@", other.short_name, game.runs_of(s.my_team), game.runs_against(s.my_team), _result_word(game)], UiTheme.DIM, 16)


func _result_word(g: ScheduledGame) -> String:
	var s := LeagueSession.season
	if g.is_tie():
		return "무"
	return "승" if g.winner() == s.my_team else "패"


func _build_table(col: VBoxContainer, s: Season) -> void:
	var d := s.division_of(s.my_team)
	_title(col, "%d부 순위" % (d + 1))
	_row(col, ["", "구단", "승", "패", "무", "승률", "차", "연속"], [40, 220, 50, 50, 50, 70, 60, 80], UiTheme.DIM)
	var i := 0
	for row: StandingsRow in s.standings[d].ranked():
		i += 1
		var mine := row.team_id == s.my_team
		_row(col, [str(i), s.teams[row.team_id].name, str(row.wins), str(row.losses), str(row.ties), row.pct_text(), "%.1f" % s.standings[d].games_behind(row.team_id), row.streak_text()], [40, 220, 50, 50, 50, 70, 60, 80], UiTheme.GOLD if mine else (UiTheme.INK if i <= 4 else UiTheme.DIM))
	_line(col, "상위 4팀이 포스트시즌, 하위 2팀은 강등(1부 제외), 포스트시즌 우승·준우승은 승격(3부부터)", UiTheme.DIM, 15)


func _build_ladder(col: VBoxContainer, s: Season) -> void:
	var d := s.division_of(s.my_team)
	var p := s.postseasons[d]
	_title(col, "%d부 포스트시즌" % (d + 1))
	for i: int in p.seeds.size():
		_line(col, "%d번 시드  %s" % [i + 1, s.teams[p.seeds[i]].name], UiTheme.GOLD if p.seeds[i] == s.my_team else UiTheme.INK)
	for r: int in p.rounds.size():
		var sr := p.rounds[r]
		var state := ("  %s 승리" % s.teams[sr.winner()].short_name) if sr.finished() else ""
		_line(col, "%s (%d전 %d선승): %s %d - %d %s%s" % [Postseason.ROUND_NAMES[r], sr.length(), sr.wins_needed, s.teams[sr.high].short_name, sr.high_wins, sr.low_wins, s.teams[sr.low].short_name, state], UiTheme.INK)
	if not p.seeds.has(s.my_team):
		_line(col, "우리 구단은 포스트시즌에 나가지 못했다.", UiTheme.DIM)


func _build_end(col: VBoxContainer, s: Season) -> void:
	var d := s.division_of(s.my_team)
	_title(col, "%d년 시즌 결과" % s.season_year)
	for div: int in s.divisions.size():
		var p := s.postseasons[div]
		_line(col, "%d부 우승 %s · 준우승 %s" % [div + 1, s.teams[p.champion()].name, s.teams[p.runner_up()].name], UiTheme.GOLD if div == d else UiTheme.INK)
	var moves := s.movements()
	var up: PackedStringArray = moves[d][0]
	var down: PackedStringArray = moves[d][1]
	var verdict := "잔류"
	if up.has(s.my_team):
		verdict = "%d부로 승격!" % d
	elif down.has(s.my_team):
		verdict = "%d부로 강등" % (d + 2)
	elif d == 0 and s.postseasons[0].champion() == s.my_team:
		verdict = "1부 우승! 최종 목표 달성"
	_line(col, "우리 구단: %s" % verdict, UiTheme.GOLD)
	var awards := SeasonAwards.for_division(s, d, s.season_year)
	_line(col, "%d부 시상" % (d + 1), UiTheme.DIM)
	for a: SeasonAwards.Award in [awards.mvp, awards.pitcher, awards.rookie]:
		if a != null:
			_line(col, awards.line(a), UiTheme.INK, 16)
	for a: SeasonAwards.Award in awards.titles:
		_line(col, "%s  %s  %s" % [a.title, awards._name(a.player_id), a.text], UiTheme.DIM, 15)
	_button(col, "다음 시즌", func() -> void:
		LeagueSession.next_season(_rng.next_int(1000000))
		LeagueSession.season.play_day()
		message = "%d년 시즌이 시작됐다." % LeagueSession.season.season_year
		refresh())


# --- The club ---


func _build_club(col: VBoxContainer, s: Season) -> void:
	var c := s.club
	var r := s.club_rules
	var team: Team = s.teams[s.my_team]
	var d := s.division_of(s.my_team)
	_title(col, "구단 운영")
	var cost := r.first_team_cost(team, s.ovr, s.catalog)
	var colours := PackedStringArray()
	for a: ClubRules.ColorDef in TeamColors.active(team, c, r, s.ovr, s.catalog):
		colours.append(a.name)
	_line(col, "포인트 %d · 1군 코스트 %d / %d · 팀 컬러 %s" % [c.points, cost, r.cost_cap(d), ", ".join(colours) if not colours.is_empty() else "없음"], UiTheme.INK, 16)
	var tabs := HBoxContainer.new()
	col.add_child(tabs)
	for pair: Array in [["roster", "1군"], ["farm", "2군"], ["scout", "스카우트"], ["traits", "특성"]]:
		var b := Button.new()
		b.text = ("● " if _tab == pair[0] else "") + str(pair[1])
		b.pressed.connect(func() -> void:
			_tab = pair[0]
			refresh())
		tabs.add_child(b)
	match _tab:
		"roster":
			_build_roster(col, s, team)
		"farm":
			_build_farm(col, s, team)
		"scout":
			_build_scout(col, s, team)
		"traits":
			_build_traits(col, s)


func _player_line(s: Season, p: Player) -> Array[String]:
	var ovr := ClubRules.player_ovr(p, s.ovr, s.catalog)
	var role := String(p.role()) if p.is_pitcher() else Position.code(p.primary_position())
	var tr := ""
	if s.club.traits.has(p.id):
		var item := s.club.traits[p.id]
		tr = "%s%d" % [s.club_rules.traits[item.x].name, item.y + 1]
	return [role, p.name + ("*" if p.is_foreign() else ""), s.club_rules.grade_of(ovr).name, str(roundi(ovr)), s.condition_name(p.id), tr]


func _build_roster(col: VBoxContainer, s: Season, team: Team) -> void:
	_line(col, "훈련은 하루 %d명. 버튼을 누를 때마다 초점이 바뀐다." % s.club_rules.train_per_day, UiTheme.DIM, 15)
	var list := _scroll(col, 760.0)
	for p: Player in team.first_team():
		var row := _row(list, _player_line(s, p), [44, 170, 30, 40, 60, 90], UiTheme.INK, 16)
		_card_button(row, p)
		var focus := s.club.training.get(p.id, "") as String
		var b := Button.new()
		b.text = "훈련: " + (_focus_name(focus) if focus != "" else "없음")
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void:
			_cycle_training(s, p)
			refresh())
		row.add_child(b)
		var down := Button.new()
		down.text = "말소"
		down.add_theme_font_size_override("font_size", 14)
		down.pressed.connect(func() -> void:
			team.unregister(p.id, s.day)
			message = "%s 말소. %d일 뒤 다시 등록할 수 있다." % [p.name, Team.RECALL_DAYS]
			refresh())
		row.add_child(down)


func _build_farm(col: VBoxContainer, s: Season, team: Team) -> void:
	var list := _scroll(col, 760.0)
	for p: Player in team.second_team():
		var row := _row(list, _player_line(s, p), [44, 170, 30, 40, 60, 90], UiTheme.INK, 16)
		_card_button(row, p)
		var up := Button.new()
		up.text = "등록"
		up.add_theme_font_size_override("font_size", 14)
		up.pressed.connect(func() -> void:
			message = register(p)
			refresh())
		row.add_child(up)
		var go := Button.new()
		go.text = "방출"
		go.add_theme_font_size_override("font_size", 14)
		go.pressed.connect(func() -> void:
			s.club.release(p.id, team, s.club_rules)
			message = "%s 방출." % p.name
			refresh())
		row.add_child(go)


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


func _build_scout(col: VBoxContainer, s: Season, team: Team) -> void:
	_line(col, "오늘의 후보 (하루 1명 영입, 2군으로)" + (" · 오늘은 영입했다" if s.club.signed_today else ""), UiTheme.DIM, 15)
	for i: int in s.club.candidates.size():
		var p := s.club.candidates[i]
		var line := _player_line(s, p)
		line[4] = "%d세" % (s.season_year - p.born)
		var row := _row(col, line, [44, 170, 30, 40, 60, 90], UiTheme.INK, 16)
		_card_button(row, p)
		var b := Button.new()
		b.text = "영입"
		b.disabled = s.club.signed_today
		b.pressed.connect(func() -> void:
			var signed := s.club.sign(i, team, s.club_rules)
			message = "%s 영입." % signed.name if signed != null else "영입할 수 없다."
			refresh())
		row.add_child(b)


func _build_traits(col: VBoxContainer, s: Season) -> void:
	var c := s.club
	var r := s.club_rules
	_line(col, "특성 %d개 보유. 같은 특성·같은 단계 두 개를 합치면 한 단계 위(3단계까지)." % c.bag.size(), UiTheme.DIM, 15)
	_button(col, "특성 뽑기 (%d포인트)" % int(r.points.get("trait", 0)), func() -> void:
		var pick := c.buy_trait(r, _rng)
		message = ("%s 특성을 얻었다." % r.traits[pick].name) if pick >= 0 else "포인트가 모자란다."
		refresh())
	var pair := c.mergeable(r)
	if pair.x >= 0:
		_button(col, "합성: %s %d단계 둘 → %d단계" % [r.traits[c.bag[pair.x].x].name, c.bag[pair.x].y + 1, c.bag[pair.x].y + 2], func() -> void:
			c.merge(pair.x, pair.y, r)
			refresh())
	for i: int in c.bag.size():
		var item := c.bag[i]
		var def := r.traits[item.x]
		var row := _row(col, ["%s %d단계" % [def.name, item.y + 1], "타자용" if def.kind == &"batter" else "투수용", def.note], [150, 70, 300], UiTheme.INK, 15)
		var b := Button.new()
		b.text = "장착"
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void:
			message = equip_best(i)
			refresh())
		row.add_child(b)


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


## "보기": the player card over the screen.
func _card_button(row: HBoxContainer, p: Player) -> void:
	var b := Button.new()
	b.text = "보기"
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(func() -> void: PlayerCard.open_for(self, p, LeagueSession.season))
	row.add_child(b)


func _focus_name(focus: String) -> String:
	var names := {"batting": "타격", "running": "주루", "fielding": "수비", "stuff": "구위", "control": "제구", "breaking": "변화"}
	return str(names.get(focus, focus))


func _cycle_training(s: Season, p: Player) -> void:
	var options: Array[String] = ["stuff", "control", "breaking"] if p.is_pitcher() else ["batting", "running", "fielding"]
	var now := s.club.training.get(p.id, "") as String
	var i := options.find(now)
	if i == options.size() - 1:
		s.club.training.erase(p.id)
		return
	var next := options[i + 1]
	if not s.club.assign_training(p.id, next, s.club_rules):
		message = "훈련은 하루 %d명까지." % s.club_rules.train_per_day


# --- Days and games ---


func play_on_screen() -> void:
	var g := LeagueSession.season.my_game_today()
	if g == null or g.played:
		return
	LeagueSession.pending = g
	get_tree().change_scene_to_file(LeagueSession.MATCH)


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


func next_day() -> void:
	var s := LeagueSession.season
	var g := s.my_game_today()
	if g != null and not g.played:
		message = "오늘 경기를 먼저 해야 한다."
		refresh()
		return
	s.advance()
	s.play_day()
	message = ""
	refresh()


## Days go by (our games settled at once) until our next game is today.
func to_next_game() -> void:
	var s := LeagueSession.season
	var guard := 0
	while s.phase != Season.Phase.OVER and guard < 400:
		var g := s.my_game_today()
		if g != null and not g.played:
			break
		s.advance()
		s.play_day()
		guard += 1
	refresh()


## The rest of the regular season (or of the postseason) at once.
func to_phase_end() -> void:
	var s := LeagueSession.season
	var phase := s.phase
	var guard := 0
	while s.phase == phase and guard < 400:
		s.play_day(true)
		s.advance()
		guard += 1
	if s.phase != Season.Phase.OVER:
		s.play_day()
	message = "포스트시즌이 시작됐다." if s.phase == Season.Phase.POSTSEASON else "시즌이 끝났다."
	refresh()


# --- Building blocks ---


func _column(width: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(width, 0.0)
	col.add_theme_constant_override("separation", 6)
	_content.add_child(col)
	return col


func _scroll(col: VBoxContainer, height: float) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0.0, height)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	return list


func _title(col: VBoxContainer, line: String) -> void:
	var l := Label.new()
	l.text = line
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(l)


func _line(col: Control, line: String, color: Color, font_size: int = 20) -> void:
	var l := Label.new()
	l.text = line
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	col.add_child(l)


func _button(col: VBoxContainer, label: String, action: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	col.add_child(b)


func _row(col: Control, cells: Array, widths: Array, color: Color, font_size: int = 18) -> HBoxContainer:
	var row := HBoxContainer.new()
	for i: int in cells.size():
		var l := Label.new()
		l.text = str(cells[i])
		l.custom_minimum_size = Vector2(float(widths[i]) if i < widths.size() else 80.0, 0.0)
		l.clip_text = true
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", color)
		row.add_child(l)
	col.add_child(row)
	return row
