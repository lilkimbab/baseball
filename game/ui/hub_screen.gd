class_name HubScreen
extends Screen
## Home (docs/04 section 5): the club's best player standing in the park on the left, his
## number huge behind him and his name under him; on the right the next game as a match-up
## with the way into it, and the four ways to play as picture cards. Everything else is in
## the bar along the top.

var _clubs: Array[Team] = []


func setup() -> void:
	vantage = &"home"
	back = TITLE
	dock_id = "hub"
	hints = [["ESC", "타이틀 화면"], ["CLICK", "선택"]]


func build() -> void:
	if _clubs.is_empty():
		_clubs = RosterIO.load_pack(LeagueSession.PACK)
	var columns := UiKit.hbox(28)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	_build_star(columns)
	var right := UiKit.vbox(20)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	_build_next(right)
	var cards := UiKit.hbox(16)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(cards)
	var colours := UiTheme.MODE_COLOURS
	var league := ModeTile.make("리그 모드", "", "trophy", func() -> void: go(dock_path("league")), colours["league"], "LEAGUE", "league")
	if LeagueSession.season != null:
		league.status = "진행 중"
	var career := ModeTile.make("전설의 시작", "", "user-circle", func() -> void: go(dock_path("career")), colours["career"], "CAREER", "career")
	if CareerSession.career_season != null:
		career.status = "진행 중"
	cards.add_child(ModeTile.make("친선 경기", "", "baseball", func() -> void: go(QUICK), colours["quick"], "EXHIBITION", "exhibition"))
	cards.add_child(league)
	cards.add_child(career)
	cards.add_child(ModeTile.make("연습 모드", "", "target", func() -> void: go(PRACTICE), colours["practice"], "PRACTICE", "practice"))


## The club (the one managed, the career's, or the first of the league's) and its best hitter.
func _featured() -> Array:
	var team: Team = null
	var player: Player = null
	var season: Season = null
	if CareerSession.career_season != null and LeagueSession.season == null:
		var cs := CareerSession.career_season
		season = cs.season
		team = cs.season.teams.get(cs.career.team_id)
		player = cs.career.player
	elif LeagueSession.season != null:
		season = LeagueSession.season
		team = season.teams[season.my_team]
	else:
		team = _clubs[0] if not _clubs.is_empty() else null
	if team != null and player == null:
		var best := -1.0
		for p: Player in team.first_team():
			var value := p.batting.contact() + p.batting.power() if not p.is_pitcher() else 0.0
			if value > best:
				best = value
				player = p
	return [team, player, season]


func _build_star(parent: Control) -> void:
	var pick := _featured()
	var team: Team = pick[0]
	var player: Player = pick[1]
	var season: Season = pick[2]
	var column := UiKit.vbox(6)
	column.custom_minimum_size.x = 600.0
	parent.add_child(column)
	if player == null:
		return
	# The man, his number huge behind him.
	var stand := Control.new()
	stand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stand.clip_contents = true
	column.add_child(stand)
	var big := UiKit.latin("%d" % player.number, 560, Color(1.0, 1.0, 1.0, 0.08), true)
	big.set_anchors_preset(Control.PRESET_FULL_RECT)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big.add_theme_constant_override("shadow_offset_y", 0)
	stand.add_child(big)
	var stage := PlayerStage.make(600.0, 500.0)
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.show_player(player, team)
	stand.add_child(stage)
	# His name.
	var row := UiKit.hbox(16)
	column.add_child(row)
	row.add_child(UiKit.club_mark(team, 84.0))
	var words := UiKit.vbox(-2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(UiKit.latin("FRANCHISE PLAYER", 17, tint, true))
	words.add_child(UiKit.heading(player.name, 46))
	words.add_child(UiKit.label("%s  ·  %s  ·  No.%d" % [team.name, Position.name_of(player.primary_position()), player.number], 17, UiTheme.DIM, 500))
	row.add_child(words)
	var ovr := ClubRules.player_ovr(player, season.ovr, season.catalog) if season != null else (player.batting.contact() + player.batting.power() + player.batting.eye + player.fielding.overall()) / 4.0
	row.add_child(UiKit.figure(UiTheme.shown_text(ovr), "OVR", UiTheme.rating_color(ovr), 52))
	var card := UiKit.button("선수 카드", func() -> void: PlayerCard.open_for(self, player, season), "identification-card")
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(card)


## The next game as a match-up, with the way into it.
func _build_next(parent: Control) -> void:
	var s := LeagueSession.season
	var away: Team = _clubs[QuickMatchScreen.away_index] if not _clubs.is_empty() else null
	var home: Team = _clubs[QuickMatchScreen.home_index] if _clubs.size() > 1 else null
	var title_text := "친선 경기"
	var caption := "EXHIBITION"
	var colour: Color = UiTheme.MODE_COLOURS["quick"]
	var line := "%d이닝" % Settings.innings
	var action := func() -> void: go(QUICK)
	var word := "경기 설정"
	if s != null:
		var g := s.my_game_today()
		var d := s.division_of(s.my_team)
		title_text = "다음 경기"
		caption = "LEAGUE · DAY %d" % (s.day + 1)
		colour = UiTheme.MODE_COLOURS["league"]
		line = "%s · %d년 시즌" % [LeagueScreen.league_name(s, d), s.season_year]
		word = "리그로 이동"
		action = func() -> void: go(LeagueSession.SCREEN)
		if g != null:
			away = s.teams[g.away]
			home = s.teams[g.home]
			if g.played:
				line += " · 경기 종료 %d : %d" % [g.away_score, g.home_score]
		else:
			away = null
			home = s.teams[s.my_team]
			line += " · 오늘은 경기가 없습니다"
	var p := GlassPanel.make(title_text, "", 0.0, colour, caption)
	parent.add_child(p)
	var row := UiKit.hbox(18)
	p.body.add_child(row)
	if away != null:
		row.add_child(_side(away, "AWAY"))
		row.add_child(UiKit.number("VS", 60, Color(1.0, 1.0, 1.0, 0.9)))
	if home != null:
		row.add_child(_side(home, "HOME"))
	row.add_child(UiKit.spacer(0.0, 0.0, true))
	var right := UiKit.vbox(12)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	var info := UiKit.label(line, 17, UiTheme.DIM, 500)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(info)
	var play := UiKit.button(word, action, "play", "primary", 300.0)
	play.add_theme_font_size_override("font_size", 24)
	play.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(play)


func _side(team: Team, tag: String) -> Control:
	var box := UiKit.hbox(14)
	box.add_child(UiKit.club_mark(team, 96.0))
	var words := UiKit.vbox(-2)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_child(UiKit.latin(tag, 16, UiTheme.DIM, true))
	words.add_child(UiKit.heading(team.name, 26))
	box.add_child(words)
	return box


## Loads a save and opens its screen.
static func load_slot(from: Node, slot: String, mode: String) -> bool:
	if mode == "career":
		var cs := SaveIO.load_career(slot)
		if cs == null:
			return false
		CareerSession.career_season = cs
		CareerSession.career = cs.career
		CareerSession.season = cs.season
		CareerSession.slot = slot
		if from.is_inside_tree():
			Loading.go(from.get_tree(), CareerSession.HUB)
		return true
	var s := SaveIO.load_league(slot)
	if s == null:
		return false
	# A league saved before the second teams had their own league gets one from here on.
	if s.farm == null and s.history == null and s.phase == Season.Phase.REGULAR:
		s.farm = FarmLeague.for_season(s)
	LeagueSession.season = s
	LeagueSession.slot = slot
	if from.is_inside_tree():
		Loading.go(from.get_tree(), LeagueSession.SCREEN)
	return true
