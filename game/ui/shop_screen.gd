class_name ShopScreen
extends Screen
## The shop (docs/02): points earned by playing buy things that the modes in progress use —
## gear for the career's player (each piece raises one rating, as the gear from reward boxes
## does), special training (growth points in one field), and funds for the league club.
## The goods are a list on the left; the one picked is shown on the right with what it does,
## whether it can be bought now, and the button.

const GEAR_PRICE := 400
const TRAINING_PRICE := 250
const TRAINING_GP := 10.0
const FUNDS_PRICE := 200
const FUNDS_POINTS := 50
const FIELD_ICONS := {"batting": "baseball-helmet", "fielding": "shield", "running": "sneaker-move", "pitching": "person-simple-throw"}

static var picked := ""

var message := ""
var _rules: CareerRules


func setup() -> void:
	heading = "상점"
	heading_latin = "STORE"
	subheading = "경기에서 얻은 포인트로 장비와 훈련을 구매합니다"
	vantage = &"stands"
	dock_id = "shop"


## Everything on sale: id, kind, name, effect, price, icon, and what it is (gear, field).
func items() -> Array[Dictionary]:
	if _rules == null:
		_rules = CareerIO.load_default()
	var out: Array[Dictionary] = []
	for g: Dictionary in _rules.gear:
		var rating := str(g.get("rating", ""))
		var field := _rules.field_of(rating)
		out.append({"id": "gear:" + str(g.get("name", "")), "kind": "장비", "name": str(g.get("name", "")), "price": GEAR_PRICE,
			"effect": "%s +%d" % [CareerScreen.RATING_NAMES.get(rating, rating), int(g.get("amount", 1))], "icon": FIELD_ICONS.get(field, "package"),
			"about": "커리어 선수가 착용하는 장비입니다. 능력치가 영구적으로 오릅니다.", "gear": g, "field": field})
	for field: String in ["batting", "running", "fielding", "pitching"]:
		out.append({"id": "gp:" + field, "kind": "훈련", "name": "%s 특별 훈련" % CareerScreen.FIELD_NAMES[field], "price": TRAINING_PRICE,
			"effect": "%s 성장 포인트 +%d" % [CareerScreen.FIELD_NAMES[field], roundi(TRAINING_GP)], "icon": "barbell",
			"about": "커리어 선수의 성장 포인트를 얻습니다. 성장 탭에서 능력치에 사용하세요.", "field": field})
	out.append({"id": "club", "kind": "구단", "name": "구단 운영 자금", "price": FUNDS_PRICE, "effect": "구단 포인트 +%d" % FUNDS_POINTS, "icon": "hand-coins",
		"about": "리그 모드의 구단 포인트를 얻습니다. 특성 뽑기와 스카우트에 사용됩니다."})
	return out


## Why an item cannot be bought now ("" when it can).
func problem(item: Dictionary) -> String:
	var id := str(item["id"])
	if id == "club":
		return "" if LeagueSession.season != null and LeagueSession.season.club != null else "리그 모드를 진행 중일 때 구매할 수 있습니다"
	var c := CareerSession.career
	if CareerSession.career_season == null or c == null:
		return "커리어 모드를 진행 중일 때 구매할 수 있습니다"
	var pitching := str(item.get("field", "")) == "pitching"
	if pitching != c.is_pitcher():
		return "투수 전용 상품입니다" if pitching else "타자 전용 상품입니다"
	if id.begins_with("gear:") and c.gear.has(str(item["name"])):
		return "이미 보유한 장비입니다"
	if Profile.points < int(item["price"]):
		return "포인트가 부족합니다"
	return ""


## Buys an item: the points are taken and the mode it belongs to gets it. Returns what to say.
func buy(id: String) -> String:
	for item: Dictionary in items():
		if str(item["id"]) != id:
			continue
		var why := problem(item)
		if why != "":
			return why
		if Profile.points < int(item["price"]) or not Profile.spend(int(item["price"])):
			return "포인트가 부족합니다"
		if id == "club":
			LeagueSession.season.club.points += FUNDS_POINTS
			LeagueSession.autosave()
		elif id.begins_with("gp:"):
			var c := CareerSession.career
			var field := str(item["field"])
			c.gp[field] = float(c.gp.get(field, 0.0)) + TRAINING_GP
			CareerSession.autosave()
		else:
			var c := CareerSession.career
			var g: Dictionary = item["gear"]
			c.gear[str(item["name"])] = str(g.get("rating", ""))
			Training.grow(c.player, PackedStringArray([str(g.get("rating", ""))]), float(g.get("amount", 1)))
			CareerSession.autosave()
		return "%s 구매 완료" % item["name"]
	return "없는 상품입니다"


func build() -> void:
	var list := items()
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var p := panel("상품 목록", "storefront", columns, 0.0, "GOODS")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var table := DataTable.new()
	table.row_height = 48.0
	table.set_columns([["분류", 90.0, 1], ["상품", 300.0, 0], ["효과", 300.0, 0], ["가격", 110.0, 2], ["상태", 130.0, 1]])
	var chosen: Dictionary = {}
	for item: Dictionary in list:
		var why := problem(item)
		var state := "구매 가능" if why == "" else ("보유 중" if why.begins_with("이미") else ("포인트 부족" if why.begins_with("포인트") else "구매 불가"))
		var at := table.add_row([item["kind"], item["name"], item["effect"], "%d P" % int(item["price"]), state], item["id"],
			{0: tint, 3: UiTheme.ACCENT, 4: UiTheme.GREEN if why == "" else UiTheme.DIM})
		table.dim_rows[at] = why != "" and not why.begins_with("포인트")
		if str(item["id"]) == picked:
			table.selected = at
			chosen = item
	table.row_pressed.connect(func(_row: int, tag: Variant) -> void:
		picked = str(tag)
		message = ""
		refresh())
	p.body.add_child(table)

	var side := panel("상품 정보", "tag", columns, 520.0, "DETAIL")
	if chosen.is_empty():
		side.body.add_child(UiKit.label("목록에서 상품을 선택하세요.", 18, UiTheme.DIM, 500))
	else:
		var why := problem(chosen)
		var top := UiKit.hbox(18)
		side.body.add_child(top)
		top.add_child(UiKit.icon(str(chosen["icon"]), 110.0, tint))
		var words := UiKit.vbox(2)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		words.add_child(UiKit.latin(str({"장비": "GEAR", "훈련": "TRAINING", "구단": "CLUB"}[chosen["kind"]]), 17, tint, true))
		words.add_child(UiKit.heading(str(chosen["name"]), 32))
		words.add_child(UiKit.label(str(chosen["effect"]), 20, UiTheme.GREEN, 600))
		top.add_child(words)
		var about := UiKit.label(str(chosen["about"]), 17, UiTheme.DIM, 500)
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side.body.add_child(about)
		side.body.add_child(UiKit.rule())
		var price := UiKit.hbox(10)
		side.body.add_child(price)
		price.add_child(GradeCoin.make("P", 34.0))
		price.add_child(UiKit.number("%d" % int(chosen["price"]), 44, UiTheme.ACCENT))
		price.add_child(UiKit.spacer(0.0, 0.0, true))
		var have := UiKit.label("보유 %d P" % Profile.points, 17, UiTheme.DIM, 500)
		have.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		price.add_child(have)
		if why != "":
			side.body.add_child(UiKit.label(why, 17, UiTheme.RED if why.begins_with("포인트") else UiTheme.DIM, 600))
		side.body.add_child(UiKit.spacer(0.0, 0.0, true))
		var b := UiKit.button("구매", func() -> void:
			message = buy(str(chosen["id"]))
			refresh(), "shopping-cart", "primary")
		b.add_theme_font_size_override("font_size", 26)
		b.disabled = why != ""
		side.body.add_child(b)
	if message != "":
		side.body.add_child(UiKit.label(message, 18, UiTheme.ACCENT, 600))
	side.body.add_child(UiKit.label("포인트는 경기를 마칠 때마다 지급됩니다 (경기 완료 %dP, 승리 시 +%dP)." % [Profile.GAME_POINTS, Profile.WIN_POINTS], 15, UiTheme.DIM, 500))
