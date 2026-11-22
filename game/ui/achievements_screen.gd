class_name AchievementsScreen
extends Screen
## The achievements (Achievements): on the left how far along the whole case is — a ring of
## the share done, the medals in each metal, the points they paid — and the kinds to look at;
## on the right the medals of the kind, each with its name, what it asks, how far along, and
## what it pays (points, and for some a signature item). Locked ones stay grey; those that ask
## for a harder game say which.

const MARKS := {"game": "baseball", "batting": "baseball-helmet", "pitching": "person-simple-throw", "league": "trophy",
	"career": "user-circle", "shop": "storefront", "all": "crown"}
const ORDER: Array[String] = ["", "game", "batting", "pitching", "league", "career", "shop"]

static var category := ""


## The ring of the share done.
class Ring extends Control:
	var share := 0.0
	var tint := Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 8.0
		draw_arc(c, r, 0.0, TAU, 96, Color(1.0, 1.0, 1.0, 0.08), 12.0, true)
		if share > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * share, 96, tint, 12.0, true)


func setup() -> void:
	heading = "업적"
	heading_latin = "ACHIEVEMENTS"
	heading_icon = "medal"
	vantage = &"stands"
	dock_id = "achievements"


func build() -> void:
	Achievements.ensure_loaded()
	var book := Achievements.book
	var columns := UiKit.hbox(16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	# The case as a whole.
	var left := panel("달성 현황", "medal", columns, 380.0, "PROGRESS")
	var tally := book.tally()
	var total := book.defs.size()
	var ring_box := Control.new()
	ring_box.custom_minimum_size = Vector2(0.0, 220.0)
	left.body.add_child(ring_box)
	var ring := Ring.new()
	ring.share = float(tally[4]) / maxf(total, 1.0)
	ring.tint = tint
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring_box.add_child(ring)
	var middle := UiKit.vbox(-6)
	middle.set_anchors_preset(Control.PRESET_CENTER)
	middle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	middle.grow_vertical = Control.GROW_DIRECTION_BOTH
	ring_box.add_child(middle)
	var done := UiKit.number("%d" % tally[4], 56, Color.WHITE)
	done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(done)
	var of := UiKit.label("/ %d" % total, 18, UiTheme.DIM, 600)
	of.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(of)
	var metals := UiKit.hbox(10)
	metals.alignment = BoxContainer.ALIGNMENT_CENTER
	left.body.add_child(metals)
	for tier: int in 4:
		var each := UiKit.vbox(0)
		metals.add_child(each)
		each.add_child(TraitBadge.make(tier, "medal", 46.0))
		var n := UiKit.label("%d" % tally[tier], 16, Color.WHITE, 700)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		each.add_child(n)
	var earned := 0
	for d: AchievementBook.Def in book.defs:
		if book.unlocked.has(d.id):
			earned += book.points_for(d)
	var paid := UiKit.hbox(8)
	paid.alignment = BoxContainer.ALIGNMENT_CENTER
	left.body.add_child(paid)
	paid.add_child(GradeCoin.make("P", 22.0))
	paid.add_child(UiKit.label("업적으로 받은 포인트  %d" % earned, 16, UiTheme.INK, 600))
	left.body.add_child(UiKit.rule())
	# The kinds.
	for cat: String in ORDER:
		var mine := 0
		var got := 0
		for d: AchievementBook.Def in book.defs:
			if cat == "" or d.category == cat:
				mine += 1
				got += 1 if book.unlocked.has(d.id) else 0
		var row := DragCard.make("C" + cat, "", [], Color(1.0, 1.0, 1.0, 0.04))
		row.tight()
		row.set_lit(cat == category)
		row.clicked.connect(func(_t: String) -> void:
			category = cat
			refresh())
		var line := UiKit.hbox(10)
		row.add_child(line)
		line.add_child(UiKit.icon(str(MARKS.get(cat, "medal")) if cat != "" else "medal", 20.0, tint if cat == category else UiTheme.DIM))
		var name := UiKit.label("전체" if cat == "" else str(AchievementBook.CATEGORY_NAMES[cat]), 17, Color.WHITE, 700)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name)
		line.add_child(UiKit.label("%d / %d" % [got, mine], 15, UiTheme.ACCENT if got == mine else UiTheme.DIM, 600))
		left.body.add_child(row)
	# The medals.
	var right := panel("전체" if category == "" else str(AchievementBook.CATEGORY_NAMES[category]), "medal", columns, 0.0, "ACHIEVEMENTS")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := UiKit.scroll()
	right.body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	# Unlocked first within each kind, then those closest to done.
	var list: Array[AchievementBook.Def] = []
	for d: AchievementBook.Def in book.defs:
		if category == "" or d.category == category or (category == "" and d.category == "all"):
			list.append(d)
	for d: AchievementBook.Def in list:
		grid.add_child(_medal(book, d))


## One achievement.
func _medal(book: AchievementBook, d: AchievementBook.Def) -> Control:
	var on := book.unlocked.has(d.id)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var frame := UiTheme.flat(Color(1.0, 1.0, 1.0, 0.06 if on else 0.025), 8, Color(TraitBadge.METALS[d.tier][0], 0.6) if on else Color(1.0, 1.0, 1.0, 0.07), 1, 10.0)
	card.add_theme_stylebox_override("panel", frame)
	var line := UiKit.hbox(12)
	card.add_child(line)
	line.add_child(TraitBadge.make(d.tier if on else -1, str(MARKS.get(d.category, "medal")), 64.0))
	var words := UiKit.vbox(1)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(words)
	var top := UiKit.hbox(6)
	words.add_child(top)
	top.add_child(UiKit.label(d.name, 18, Color.WHITE if on else UiTheme.INK, 700))
	top.add_child(UiKit.label(AchievementBook.TIER_NAMES[d.tier], 13, TraitBadge.METALS[d.tier][0] if on else UiTheme.DIM, 700))
	if d.min_level > 0:
		top.add_child(UiKit.badge(Difficulty.NAMES[d.min_level] + ("+" if d.min_level < Difficulty.Level.LEGEND else ""), Color(0.78, 0.42, 1.0)))
	words.add_child(UiKit.label(d.about, 14, UiTheme.DIM, 500))
	var goal := book.goal(d)
	if not on and goal > 1:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0.0, 6.0)
		bar.show_percentage = false
		bar.max_value = goal
		bar.value = book.progress(d)
		bar.add_theme_stylebox_override("background", UiTheme.flat(Color(1.0, 1.0, 1.0, 0.08), 3))
		bar.add_theme_stylebox_override("fill", UiTheme.flat(tint, 3))
		words.add_child(bar)
	var pay := UiKit.hbox(8)
	words.add_child(pay)
	pay.add_child(UiKit.label("+%dP" % book.points_for(d), 14, UiTheme.ACCENT, 700))
	if d.item != "":
		pay.add_child(UiKit.label(str(book.item_names.get(d.item, d.item)), 14, Color(0.78, 0.42, 1.0), 700))
	if not on and goal > 1:
		pay.add_child(UiKit.spacer(0.0, 0.0, true))
		pay.add_child(UiKit.label("%d / %d" % [book.progress(d), goal], 14, UiTheme.DIM, 600))
	elif on and book.unlocked[d.id] != "":
		pay.add_child(UiKit.spacer(0.0, 0.0, true))
		pay.add_child(UiKit.label(book.unlocked[d.id], 13, UiTheme.DIM, 500))
	return card
