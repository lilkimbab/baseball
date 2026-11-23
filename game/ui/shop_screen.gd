class_name ShopScreen
extends Screen
## The shop: points earned by playing buy things that the modes in progress use —
## gear for the career's player (each piece raises one rating, as the gear from reward boxes
## does), special training (growth points in one field), and funds for the league club.
## Laid out as a store (the user: "real 3D models, a little flashy, so it feels like buying the
## real thing"): the products on a shelf, each its own model (ProductStage) on a turntable;
## the one picked large, turning under the spotlight, in three grades — standard, pro, elite —
## dearer and better (the user: "a different design by price, a real difference in what they
## do, the dear ones finer without being garish").

const GEAR_PRICE := 400
const TRAINING_PRICE := 250
const TRAINING_GP := 10.0
const FUNDS_PRICE := 200
const FUNDS_POINTS := 50
const GRADES: Array[String] = ["스탠다드", "프로", "엘리트", "시그니처"]
const GRADE_LATIN: Array[String] = ["STANDARD", "PRO", "ELITE", "SIGNATURE"]
## The signature grade: not for sale; each piece is earned by an achievement at 올스타 or
## harder (data/achievements.ko.json) and then taken for nothing (the user: "special items by
## difficulty too").
const SIGNATURE := 3
## By grade: what gear adds to its rating and costs; growth points and price of training; the
## club points and price of funds.
const GEAR_AMOUNT: Array[int] = [1, 2, 3, 4]
const GEAR_PRICES: Array[int] = [GEAR_PRICE, 1000, 2200, 0]
const TRAINING_GPS: Array[float] = [TRAINING_GP, 25.0, 50.0]
const TRAINING_PRICES: Array[int] = [TRAINING_PRICE, 550, 1000]
const FUNDS_AMOUNTS: Array[int] = [FUNDS_POINTS, 150, 400, 1000]
const FUNDS_PRICES: Array[int] = [FUNDS_PRICE, 550, 1300, 0]

## The product picked (its base id) and the grade shown.
static var picked := ""
static var picked_grade := 0

var message := ""
var _rules: CareerRules


func setup() -> void:
	heading = "상점"
	heading_latin = "STORE"
	vantage = &"stands"
	dock_id = "shop"


## Everything on sale, every grade: id (the base id, with ":1" or ":2" for the higher grades),
## base, grade, kind, name, effect, price, and what it is (gear, field).
func items() -> Array[Dictionary]:
	if _rules == null:
		_rules = CareerIO.load_default()
	var out: Array[Dictionary] = []
	for g: Dictionary in _rules.gear:
		var rating := str(g.get("rating", ""))
		var base_name := str(g.get("name", ""))
		for grade: int in 4:
			var base := "gear:" + base_name
			out.append({"id": base + ("" if grade == 0 else ":%d" % grade), "base": base, "grade": grade, "kind": "장비",
				"base_name": base_name, "name": base_name + ("" if grade == 0 else " " + GRADES[grade]), "price": GEAR_PRICES[grade],
				"effect": "%s +%d" % [CareerScreen.RATING_NAMES.get(rating, rating), GEAR_AMOUNT[grade] * int(g.get("amount", 1))],
				"gear": g, "amount": GEAR_AMOUNT[grade] * int(g.get("amount", 1)), "field": _rules.field_of(rating)})
	for field: String in ["batting", "running", "fielding", "pitching"]:
		for grade: int in 3:
			var base := "gp:" + field
			out.append({"id": base + ("" if grade == 0 else ":%d" % grade), "base": base, "grade": grade, "kind": "훈련",
				"base_name": "%s 특별 훈련" % CareerScreen.FIELD_NAMES[field], "name": "%s 특별 훈련%s" % [CareerScreen.FIELD_NAMES[field], "" if grade == 0 else " " + GRADES[grade]],
				"price": TRAINING_PRICES[grade], "effect": "%s 성장 포인트 +%d" % [CareerScreen.FIELD_NAMES[field], roundi(TRAINING_GPS[grade])], "gp": TRAINING_GPS[grade], "field": field})
	for grade: int in 4:
		out.append({"id": "club" + ("" if grade == 0 else ":%d" % grade), "base": "club", "grade": grade, "kind": "구단", "base_name": "구단 운영 자금",
			"name": "구단 운영 자금" + ("" if grade == 0 else " " + GRADES[grade]), "price": FUNDS_PRICES[grade], "effect": "구단 포인트 +%d" % FUNDS_AMOUNTS[grade], "funds": FUNDS_AMOUNTS[grade]})
	return out


## The grade of a piece of gear the career's player already has (−1 none).
static func owned_grade(base_name: String) -> int:
	var c := CareerSession.career
	if c == null:
		return -1
	for grade: int in range(SIGNATURE, -1, -1):
		if c.gear.has(base_name + ("" if grade == 0 else " " + GRADES[grade])):
			return grade
	return -1


## Why an item cannot be bought now ("" when it can). `with_money`: paid from the career
## player's own money (gear only: CareerMoney.SHOP_RATE won a point) instead of points.
func problem(item: Dictionary, with_money: bool = false) -> String:
	var id := str(item["id"])
	if int(item["grade"]) == SIGNATURE:
		var key := "club" if id.begins_with("club") else "gear:" + str(item["base_name"])
		if not Achievements.has_item(key):
			var source := Achievements.source_of(key)
			return "업적 '%s' 달성 보상 (%s)" % [source.name, source.about] if source != null else "업적 보상"
		if id.begins_with("club") and int(Profile.owned.get(id, 0)) > 0:
			return "이미 받았습니다"
	if id.begins_with("club"):
		if LeagueSession.season == null or LeagueSession.season.club == null:
			return "리그 모드를 진행 중일 때 구매할 수 있습니다"
		return "포인트가 부족합니다" if Profile.points < int(item["price"]) else ""
	var c := CareerSession.career
	if CareerSession.career_season == null or c == null:
		return "전설의 시작을 진행 중일 때 구매할 수 있습니다"
	var pitching := str(item.get("field", "")) == "pitching"
	if pitching != c.is_pitcher():
		return "투수 전용 상품입니다" if pitching else "타자 전용 상품입니다"
	if id.begins_with("gear:") and owned_grade(str(item["base_name"])) >= int(item["grade"]):
		return "이미 보유한 장비입니다" if owned_grade(str(item["base_name"])) == int(item["grade"]) else "더 좋은 등급을 보유하고 있습니다"
	if with_money:
		if not id.begins_with("gear:"):
			return "보유 금액으로는 장비만 구매할 수 있습니다"
		if CareerSession.career_season.season.school:
			return "프로 입단 후에 보유 금액으로 구매할 수 있습니다"
		var short := money_price(item) - c.money
		return "보유 금액이 %s 원 부족합니다" % FreeAgency.money(short) if short > 0 else ""
	if Profile.points < int(item["price"]):
		return "포인트가 부족합니다"
	return ""


## Buys an item: the points are taken and the mode it belongs to gets it (a better grade of gear
## he has adds only what it adds over the one he has). Returns what to say.
func buy(id: String, with_money: bool = false) -> String:
	for item: Dictionary in items():
		if str(item["id"]) != id:
			continue
		var why := problem(item, with_money)
		if why != "":
			return why
		if with_money:
			CareerSession.career.money -= money_price(item)
		elif not Profile.spend(int(item["price"])):
			return "포인트가 부족합니다"
		Profile.owned[id] = int(Profile.owned.get(id, 0)) + 1
		Profile.save_file()
		Achievements.bought()
		if id.begins_with("club"):
			LeagueSession.season.club.points += int(item["funds"])
			LeagueSession.autosave()
		elif id.begins_with("gp:"):
			var c := CareerSession.career
			var field := str(item["field"])
			c.gp[field] = float(c.gp.get(field, 0.0)) + float(item["gp"])
			CareerSession.autosave()
		else:
			var c := CareerSession.career
			var g: Dictionary = item["gear"]
			var had := owned_grade(str(item["base_name"]))
			var already := GEAR_AMOUNT[had] * int(g.get("amount", 1)) if had >= 0 else 0
			c.gear[str(item["name"])] = str(g.get("rating", ""))
			Training.grow(c.player, PackedStringArray([str(g.get("rating", ""))]), float(int(item["amount"]) - already))
			CareerSession.autosave()
			Achievements.check_career(CareerSession.career_season)
		return "%s 구매 완료" % item["name"]
	return "없는 상품입니다"


## A piece of gear's price in won (10,000 won), bought with the career player's own money.
static func money_price(item: Dictionary) -> int:
	return int(item["price"]) * CareerMoney.SHOP_RATE


## Each item's model on the shelf (ProductStage): the game's own bat, gloves, spikes and guard,
## and a rosin bag, dumbbells and coins made for the shop.
const MODELS := {"가벼운 배트": "light_bat", "묵직한 배트": "heavy_bat", "가죽 장갑": "glove", "스파이크": "spikes", "보호대": "elbow_guard",
	"투수 글러브": "pitcher_glove", "로진백": "rosin"}
const KIND_COLOURS := {"장비": Color(0.95, 0.55, 0.12), "훈련": Color(0.2, 0.78, 0.42), "구단": Color(1.0, 0.78, 0.25)}

static var kind_filter := ""


static func model_of(item: Dictionary) -> String:
	return str(MODELS.get(str(item.get("base_name", item["name"])), "training" if str(item["kind"]) == "훈련" else ("coins" if str(item["kind"]) == "구단" else "light_bat")))


## The store as games lay one out: the kinds as tabs, the products on a shelf (each its model,
## its name, what it does and its price range); the one picked large on the right in the grade
## chosen, with the way to buy it.
func build() -> void:
	var list := items()
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var left := UiKit.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(UiKit.segmented(["", "장비", "훈련", "구단"], ["전체", "장비", "훈련", "구단 자금"], kind_filter, func(id: String) -> void:
		kind_filter = id
		refresh()))
	var p := panel("", "", left, 0.0, "")
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := UiKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var grades: Dictionary = {}
	for item: Dictionary in list:
		if not grades.has(item["base"]):
			grades[item["base"]] = []
		(grades[item["base"]] as Array).append(item)
	for base: String in grades:
		var family: Array = grades[base]
		if kind_filter != "" and str(family[0]["kind"]) != kind_filter:
			continue
		grid.add_child(_card(family, base == picked))
	var side := panel("", "", columns, 560.0, "")
	if grades.has(picked):
		var family: Array = grades[picked]
		_detail(side, family[clampi(picked_grade, 0, family.size() - 1)], family)
	else:
		_detail(side, {}, [])


## One product as a card on the shelf: its model (in the best grade he has, else standard), its
## name, what the grades add and what they cost.
func _card(family: Array, on: bool) -> Button:
	var first: Dictionary = family[0]
	var card := Button.new()
	card.custom_minimum_size = Vector2(0.0, 262.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1.0, 1.0, 1.0, 0.11 if state == "hover" else 0.05)
		if state == "focus":
			box.bg_color = Color(0, 0, 0, 0)
		box.set_corner_radius_all(6)
		if on:
			box.set_border_width_all(3)
			box.border_color = UiTheme.BRAND
		card.add_theme_stylebox_override(state, box)
	card.pressed.connect(func() -> void:
		picked = str(first["base"])
		picked_grade = 0
		message = ""
		refresh())
	var box := UiKit.vbox(3)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10.0
	box.offset_right = -10.0
	box.offset_top = 10.0
	box.offset_bottom = -10.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var shown := maxi(owned_grade(str(first["base_name"])), 0) if str(first["kind"]) == "장비" else 0
	box.add_child(_art_tile(family[shown], 140.0, false))
	box.add_child(UiKit.heading(str(first["base_name"]), 20))
	var top: Dictionary = family[mini(2, family.size() - 1)]
	box.add_child(UiKit.label("%s ~ %s" % [str(first["effect"]), str(top["effect"]).get_slice(" ", str(top["effect"]).get_slice_count(" ") - 1)], 16, UiTheme.GREEN, 600))
	var price := UiKit.hbox(6)
	box.add_child(price)
	price.add_child(GradeCoin.make("P", 22.0))
	price.add_child(UiKit.number("%d ~ %d" % [int(first["price"]), int(top["price"])], 22, UiTheme.ACCENT))
	if owned_grade(str(first["base_name"])) >= 0 and str(first["kind"]) == "장비":
		price.add_child(UiKit.spacer(0.0, 0.0, true))
		price.add_child(UiKit.badge(GRADES[owned_grade(str(first["base_name"]))], UiTheme.GREEN))
	for c: Node in box.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


## The item's model on its turntable, over a fade of its kind's colour (on the shelf one frame
## is drawn: a shelf of them costs nothing once shown).
func _art_tile(item: Dictionary, height: float, faded: bool, turning: bool = false) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size.y = height
	var colour: Color = KIND_COLOURS.get(str(item["kind"]), UiTheme.ACCENT)
	var back := StyleBoxFlat.new()
	# A dark showcase, the grade's colour along its foot.
	back.bg_color = Color(0.075, 0.08, 0.095, 0.95).lerp(colour.darkened(0.8), 0.25) if not faded else Color(0.12, 0.12, 0.13, 0.85)
	back.set_corner_radius_all(4)
	back.border_width_bottom = 3
	back.border_color = ProductStage.GRADE_RINGS[int(item.get("grade", 0))]
	tile.add_theme_stylebox_override("panel", back)
	var stage := ProductStage.make(height * 1.45, height, not turning)
	stage.show_item(model_of(item), int(item.get("grade", 0)))
	stage.modulate = Color(1.0, 1.0, 1.0, 1.0 if not faded else 0.4)
	tile.add_child(stage)
	return tile


## The product picked, large: the grades as tabs, the model turning, name, what it does, price,
## the points he has, the button.
func _detail(side: GlassPanel, chosen: Dictionary, _family: Array) -> void:
	var points := UiKit.hbox(8)
	side.body.add_child(points)
	points.add_child(UiKit.label("보유 포인트", 18, UiTheme.DIM, 600))
	points.add_child(UiKit.spacer(0.0, 0.0, true))
	points.add_child(GradeCoin.make("P", 28.0))
	points.add_child(UiKit.number("%d" % Profile.points, 34, UiTheme.ACCENT))
	side.body.add_child(UiKit.rule())
	if chosen.is_empty():
		_guide(side)
		return
	var ids: Array = []
	var words: Array = []
	for item: Dictionary in _family:
		ids.append(str(int(item["grade"])))
		words.append(GRADES[int(item["grade"])])
	side.body.add_child(UiKit.segmented(ids, words, str(int(chosen["grade"])), func(id: String) -> void:
		picked_grade = int(id)
		message = ""
		refresh()))
	var why := problem(chosen)
	side.body.add_child(_art_tile(chosen, 300.0, false, true))
	var head := UiKit.hbox(10)
	side.body.add_child(head)
	head.add_child(UiKit.latin(GRADE_LATIN[int(chosen["grade"])], 20, ProductStage.GRADE_RINGS[int(chosen["grade"])], true))
	head.add_child(UiKit.latin(str({"장비": "GEAR", "훈련": "TRAINING", "구단": "CLUB"}[chosen["kind"]]), 18, UiTheme.DIM, true))
	side.body.add_child(UiKit.heading(str(chosen["name"]), 34))
	side.body.add_child(UiKit.label(str(chosen["effect"]), 24, UiTheme.GREEN, 700))
	side.body.add_child(UiKit.spacer(0.0, 0.0, true))
	if why != "":
		side.body.add_child(UiKit.label(why, 18, UiTheme.RED if why.begins_with("포인트") else UiTheme.DIM, 600))
	if message != "":
		side.body.add_child(UiKit.label(message, 18, UiTheme.ACCENT, 600))
	var b := UiKit.button("구매  ·  %d P" % int(chosen["price"]) if int(chosen["grade"]) != SIGNATURE else "받기", func() -> void:
		message = buy(str(chosen["id"]))
		refresh(), "shopping-cart", "gold")
	b.add_theme_font_size_override("font_size", 26)
	b.disabled = why != ""
	side.body.add_child(b)
	# Gear for the career's player may be paid from his salary instead (CareerMoney).
	if str(chosen["id"]).begins_with("gear:") and int(chosen["grade"]) != SIGNATURE and CareerSession.career_season != null and CareerSession.career != null:
		var with_money := problem(chosen, true)
		var m := UiKit.button("보유 금액으로 구매  ·  %s 원" % FreeAgency.money(money_price(chosen)), func() -> void:
			message = buy(str(chosen["id"]), true)
			refresh(), "coins", "button")
		m.add_theme_font_size_override("font_size", 20)
		m.disabled = with_money != ""
		side.body.add_child(m)
		side.body.add_child(UiKit.label("보유 금액 %s 원%s" % [FreeAgency.money(CareerSession.career.money), "" if with_money == "" else "  ·  " + with_money], 15, UiTheme.DIM, 500))


## Before anything is picked: how points are earned, the day's goals as they stand, and what is
## owned already.
func _guide(side: GlassPanel) -> void:
	side.body.add_child(UiKit.caption("포인트 얻는 법"))
	side.body.add_child(UiKit.label("경기 완료 +%d P · 승리 +%d P" % [Profile.GAME_POINTS, Profile.WIN_POINTS], 18, UiTheme.INK, 600))
	side.body.add_child(UiKit.label("어려운 난이도일수록 더 받고, 오늘의 목표와 업적에서도 받습니다", 15, UiTheme.DIM, 500))
	side.body.add_child(UiKit.rule())
	side.body.add_child(UiKit.caption("오늘의 목표"))
	for g: Array in Profile.goals_today():
		var met := Profile.met.has(str(g[0]))
		var have := mini(int(Profile.today.get(str(g[2]), 0)), int(g[3]))
		var row := UiKit.hbox(8)
		side.body.add_child(row)
		var words := UiKit.label(str(g[1]), 18, UiTheme.GREEN if met else UiTheme.INK, 600)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(words)
		row.add_child(UiKit.label("완료" if met else "%d/%d" % [have, int(g[3])], 16, UiTheme.GREEN if met else UiTheme.DIM, 600))
		row.add_child(UiKit.number("+%d" % int(g[4]), 18, UiTheme.ACCENT))
	side.body.add_child(UiKit.rule())
	side.body.add_child(UiKit.caption("가진 것"))
	var any := false
	for item: Dictionary in items():
		var n := int(Profile.owned.get(str(item["id"]), 0))
		if n > 0:
			any = true
			side.body.add_child(UiKit.label("%s  ×%d" % [str(item["name"]), n], 17, UiTheme.INK, 600))
	if not any:
		side.body.add_child(UiKit.label("아직 없습니다. 왼쪽에서 골라 보세요", 16, UiTheme.DIM, 500))
