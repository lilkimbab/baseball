class_name Commentary
extends RefCounted
## The one-line play-by-play from templates in data/commentary.ko.json.
## Lines use the scorebook's words and, since 2026-11-23, the shapes of real KBO calls (the
## user: "more lines, more varied, after real KBO broadcasts, not made up"): where the ball
## went and which fielder went back for it, pulled or pushed, the pitch of the at-bat, the
## score, the club, the inning, a season's home run count. `pick` chooses among the lines a
## situation has whose slots are known, so the same kind of play reads differently through a
## game without random numbers.

## Slots a line may use beyond the play's own; a line with one that is not known (no fielder
## on a walk, no season in an exhibition) is passed over.
const SLOTS: Array[String] = ["pitch", "field", "side", "wall", "swing", "score", "team", "inning", "pitcher", "hr", "k", "out", "homer"]
## Slots that may be followed by a particle in a template ("{field}이", "{side}으로").
const NAMED: Array[String] = ["name", "runner", "pitcher", "team", "field", "out", "pitch", "side", "wall"]
## The calls made as a ball is hit (MatchSound), by the kind of ball: a long fly (a home run,
## a fly caught at the wall), a ball into the gap, a single to the outfield, one in the infield.
const CALL_KEYS: Array[String] = ["call_deep", "call_gap", "call_single", "call_infield"]

var templates: Dictionary[String, PackedStringArray] = {}


func line(key: String, pick: int, name: String = "", play: String = "", fielders: String = "", runs: int = 0, runner: String = "", base: int = 0, more: Dictionary = {}) -> String:
	var all: PackedStringArray = templates.get(key, PackedStringArray(["{name}, {play}"]))
	var options := PackedStringArray()
	for t: String in all:
		if fits(t, more):
			options.append(t)
	if options.is_empty():
		options.append(all[0])
	var out := options[posmod(pick, options.size())]
	# A line that tells its runs or the score itself gets no tail.
	var told := key.contains("walk_off")
	for said: String in ["{runs}", "{score}", "한 점", "득점", "네 점"]:
		told = told or out.contains(said)
	var values := more.duplicate()
	values.merge({"name": name, "play": play, "fielders": fielders, "runner": runner, "base": str(base), "runs": str(runs)}, true)
	out = fill(out, values)
	if runs > 0 and not told and not key.begins_with("home_run") and templates.has("runs"):
		var tails := PackedStringArray()
		for t: String in templates["runs"]:
			if fits(t, more):
				tails.append(t)
		if not tails.is_empty():
			# (A long line takes the shortest tail, so it stays one line on screen.)
			out += fill(tails[posmod(pick, tails.size())] if out.length() <= 24 else tails[0], values)
	return out


## A call as a ball is hit (no names: the voice has them ready). `group` is one of CALL_KEYS.
func call_line(group: String, pick: int, more: Dictionary) -> String:
	if not templates.has(group):
		return ""
	return line(group, pick, "", "", "", 0, "", 0, more)


## Every slot the template uses is known.
static func fits(template: String, more: Dictionary) -> bool:
	for slot: String in SLOTS:
		if template.contains("{%s}" % slot) and str(more.get(slot, "")) == "":
			return false
	return true


## The template with its slots filled, each particle after a name as the name ends.
static func fill(template: String, values: Dictionary) -> String:
	var out := template
	for slot: String in NAMED:
		if values.has(slot):
			out = _particles(out, "{%s}" % slot, str(values[slot]))
	for slot: Variant in values:
		out = out.replace("{%s}" % slot, str(values[slot]))
	return out


## Where a ball went as a caster says it: the fielder (좌익수), the side (왼쪽), the wall in
## the outfield (좌측 담장), and pulled or pushed by the batter's side (잡아당겼습니다,
## 밀어쳤습니다; 받아쳤습니다 up the middle). `direction` is the fielder's number (1..9).
static func direction_slots(direction: int, bats_left: bool) -> Dictionary:
	if direction < 1 or direction > 9:
		return {}
	var out := {"field": Position.name_of(direction - 1 as Position.Kind)}
	var left_side := direction in [5, 6, 7]
	var right_side := direction in [3, 4, 9]
	if left_side:
		out["side"] = "왼쪽"
	elif right_side:
		out["side"] = "오른쪽"
	elif direction != 2:
		out["side"] = "가운데"
	if direction >= 7:
		out["wall"] = ["좌측 담장", "가운데 담장", "우측 담장"][direction - 7]
	if direction == 8 or direction == 1:
		out["swing"] = "받아쳤습니다"
	elif left_side or right_side:
		out["swing"] = "잡아당겼습니다" if left_side != bats_left else "밀어쳤습니다"
	return out


## "초구", "2구째": the pitch of an at-bat as a caster counts it.
static func pitch_word(n: int) -> String:
	if n <= 0:
		return ""
	return "초구" if n == 1 else "%d구째" % n


## A Korean particle after a name in a template, as the name ends: "{name}을" is 을 after a
## final consonant and 를 after a vowel (이/가, 은/는 likewise; 으로 after a final consonant
## but ㄹ, 로 after a vowel or ㄹ).
static func _particles(text: String, slot: String, word: String) -> String:
	if text.contains(slot + "으로"):
		var c := word.unicode_at(word.length() - 1) if not word.is_empty() else 0
		var plain := c >= 0xAC00 and c <= 0xD7A3 and ((c - 0xAC00) % 28 == 0 or (c - 0xAC00) % 28 == 8)
		text = text.replace(slot + "으로", word + ("로" if plain else "으로"))
	for pair: Array in [["을", "를"], ["이", "가"], ["은", "는"]]:
		text = text.replace(slot + str(pair[0]), word + josa(word, str(pair[0]), str(pair[1])))
	return text


## `with_final` after a word whose last syllable ends in a consonant, else `without`.
static func josa(word: String, with_final: String, without: String) -> String:
	if word.is_empty():
		return with_final
	var c := word.unicode_at(word.length() - 1)
	if c >= 0xAC00 and c <= 0xD7A3:
		return with_final if (c - 0xAC00) % 28 != 0 else without
	# Digits and Latin letters as they are read: most end in a consonant sound in Korean.
	return with_final if "013678LMNR".contains(word.right(1).to_upper()) else without


## The situation's own template for a plate appearance, most telling first: a walk-off, a
## grand slam, a lead taken, a game tied, a run driven in (a solo home run), a jam escaped
## (the half over with runners left); the first the file has, else the plain one.
func best_key(key: String, runs: int, walk_off: bool, go_ahead: bool, tying: bool, escape: bool) -> String:
	for k: String in context_keys(key, runs, walk_off, go_ahead, tying, escape):
		if templates.has(k):
			return k
	return key


static func context_keys(key: String, runs: int, walk_off: bool, go_ahead: bool, tying: bool, escape: bool) -> PackedStringArray:
	var hit := key in ["single", "double", "triple"]
	var out := PackedStringArray()
	if walk_off:
		out.append(key + "_walk_off")
		out.append("walk_off")
	if key == "home_run" and runs == 4:
		out.append("home_run_grand_slam")
	if go_ahead:
		out.append(key + "_go_ahead")
		if hit:
			out.append("hit_go_ahead")
	if tying:
		out.append(key + "_tying")
		if hit:
			out.append("hit_tying")
	if key == "home_run" and runs == 1:
		out.append("home_run_solo")
	elif runs > 0:
		out.append(key + "_rbi")
	if escape:
		out.append(key + "_escape")
	out.append(key)
	return out


## The template for a plate appearance's result; how a strikeout ended is told by `last_call`.
static func key_for(result: PaResult.Kind, last_call: PitchDuel.Result) -> String:
	match result:
		PaResult.Kind.STRIKEOUT:
			if last_call == PitchDuel.Result.CALLED_STRIKE:
				return "strikeout_looking"
			if last_call == PitchDuel.Result.FOUL_TIP:
				return "strikeout_foul_tip"
			return "strikeout_swinging"
		PaResult.Kind.DROPPED_THIRD_STRIKE:
			return "dropped_third_strike"
		PaResult.Kind.WALK:
			return "walk"
		PaResult.Kind.INTENTIONAL_WALK:
			return "intentional_walk"
		PaResult.Kind.HIT_BY_PITCH:
			return "hit_by_pitch"
		PaResult.Kind.SINGLE:
			return "single"
		PaResult.Kind.DOUBLE:
			return "double"
		PaResult.Kind.TRIPLE:
			return "triple"
		PaResult.Kind.HOME_RUN:
			return "home_run"
		PaResult.Kind.GROUND_OUT:
			return "ground_out"
		PaResult.Kind.FLY_OUT:
			return "fly_out"
		PaResult.Kind.LINE_OUT:
			return "line_out"
		PaResult.Kind.POP_OUT:
			return "pop_out"
		PaResult.Kind.DOUBLE_PLAY:
			return "double_play"
		PaResult.Kind.TRIPLE_PLAY:
			return "triple_play"
		PaResult.Kind.SAC_FLY:
			return "sac_fly"
		PaResult.Kind.SAC_BUNT:
			return "sac_bunt"
		PaResult.Kind.FIELDERS_CHOICE:
			return "fielders_choice"
		PaResult.Kind.REACHED_ON_ERROR:
			return "reached_on_error"
	return ""


## How excited the caster is for a line of this template: a home run, a long hit, a walk-off, a
## lead taken shouted ("hot"); a strikeout, a double play, a jam escaped, a run in lifted
## ("warm"); the rest said ("calm").
static func mood_of(key: String) -> StringName:
	# (A catch nobody expected is shouted as a home run is; a fly run down at the wall lifted.)
	if key.begins_with("great_"):
		return &"hot"
	if key.begins_with("fly_out_deep"):
		return &"warm"
	for hot: String in ["home_run", "walk_off", "grand_slam", "go_ahead", "double", "triple"]:
		if key.contains(hot) and not key.begins_with("double_play"):
			return &"hot"
	for warm: String in ["strikeout", "double_play", "escape", "tying", "_rbi", "steal", "caught_stealing", "triple_play"]:
		if key.contains(warm):
			return &"warm"
	return &"calm"
