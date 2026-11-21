class_name UniformStyle
extends RefCounted
## What a team's uniform looks like, plus the player's own name and number (docs/13 S11-9).
## The kinds of lettering and trim are those of real uniforms: a nickname in script with a tail
## under it or in arched block capitals, block or Tuscan numbers with an outline in a second
## colour, piping or bands at the sleeves, a club patch on one sleeve and a sponsor's on the other.

var jersey := Color(0.93, 0.93, 0.95)
var pants := Color(0.9, 0.9, 0.92)
## Piping, sleeve bands, belt loops.
var trim := Color(0.1, 0.15, 0.35)
## Lettering and numbers.
var ink := Color(0.1, 0.15, 0.35)
## A second colour round the letters and numbers (clear: none).
var outline := Color(0, 0, 0, 0)
var cap := Color(0.1, 0.15, 0.35)
var socks := Color(0.1, 0.15, 0.35)
var undershirt := Color(0.08, 0.12, 0.28)
var jersey_pinstripes := false
var pants_pinstripes := false
var pinstripe := Color(0.25, 0.28, 0.4)
## Word across the chest, and how it is lettered: &"block", &"tuscan" or &"script".
var wordmark := ""
var lettering: StringName = &"block"
## Block and Tuscan words may be arched; a script word may have a tail under it.
var arch := false
var tail := false
## A small number on the front, under the word.
var front_number := true
## The face of the name on the back: &"name" (heavy) or &"name_square".
var name_face: StringName = &"name"
var name_arch := false
## Thin piping round the neck, down the front and at the sleeve ends; bands at the sleeve ends
## (0 none, 1 one broad, 2 two narrow).
var piping := false
var sleeve_bands := 0
## Letter on the sleeve patch and on the cap ("" none), and a stripe down the side of the trousers.
var patch := ""
var cap_letter := ""
var pants_stripe := false
## Sponsors (each as in data/sponsors.ko.json, or empty): a patch on the other sleeve, a small one on the chest.
var sleeve_sponsor: Dictionary = {}
var chest_sponsor: Dictionary = {}
var number := 0
var player_name := ""
## An umpire's dress: a polo shirt with a chest pocket and the league's badge, his number on
## the sleeve, plain black shoes (docs/13 S11-8).
var official := false
## The league's initials, on umpires' caps and badges.
const LEAGUE := "PBL"

static var _data: Dictionary = {}


static func make(jersey_color: Color, pants_color: Color, trim_color: Color, ink_color: Color, word: String) -> UniformStyle:
	var s := UniformStyle.new()
	s.jersey = jersey_color
	s.pants = pants_color
	s.trim = trim_color
	s.ink = ink_color
	s.cap = trim_color
	s.socks = trim_color
	s.undershirt = trim_color.darkened(0.2)
	s.wordmark = word
	s.cap_letter = word.substr(0, 1).to_upper()
	return s


## An umpire's uniform, as KBO and MLB umpires dress: a black polo shirt, charcoal trousers,
## a black cap with the league's initials, his number in white on the sleeve.
static func for_official(umpire_number: int) -> UniformStyle:
	var shirt := Color(0.055, 0.06, 0.075)
	var s := make(shirt, Color(0.25, 0.26, 0.29), shirt, Color(0.95, 0.95, 0.95), "")
	s.official = true
	s.cap = Color(0.05, 0.05, 0.06)
	s.socks = Color(0.05, 0.05, 0.06)
	# The shirt's own cloth shows in the opening of its collar.
	s.undershirt = shirt
	s.cap_letter = LEAGUE
	s.number = umpire_number
	s.front_number = false
	return s


## The colour of the letter on the cap and helmet: white on a dark cap, the lettering's colour
## on a light one.
func cap_ink() -> Color:
	return Color(0.97, 0.97, 0.97) if cap.get_luminance() < 0.55 else (ink if ink.get_luminance() < 0.5 else Color(0.1, 0.1, 0.12))


## The same uniform for another player (his name and number are set afterwards).
func copy() -> UniformStyle:
	var s := UniformStyle.new()
	for property: Dictionary in get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			var value: Variant = get(property["name"])
			s.set(property["name"], (value as Dictionary).duplicate() if value is Dictionary else value)
	return s


## A club's uniform (docs/13 S11-9), as KBO clubs dress: at home white with the club colour and
## the nickname in English across the chest; away the club colour if it is dark enough to carry
## white lettering, otherwise road gray, with the town's name. The kind of lettering, the trim
## and the sponsors are the club's own (from its id), the same every game.
static func for_team(t: Team, home: bool) -> UniformStyle:
	var nickname := t.name.substr(t.short_name.length()).strip_edges() if t.name.begins_with(t.short_name) else t.name
	var data := _uniform_data()
	var mark: String = (data.get("marks", {}) as Dictionary).get(nickname, nickname)
	var town: String = (data.get("towns", {}) as Dictionary).get(t.short_name, t.short_name)
	var primary := t.primary
	# A club colour too light to read on white falls back to its accent.
	if primary.get_luminance() > 0.7:
		primary = t.accent
	# The club's own look, the same every game. (Drawn from a generator seeded by its id: the
	# ids of a league differ by a digit, and their hashes alone fell into two or three looks.)
	var rng := Rng.new(hash(t.id + ":look"))
	var kind: StringName = [&"script", &"block", &"script", &"block", &"tuscan", &"block"][rng.next_int(6)]
	var with_tail := rng.next_int(3) != 0
	var arched := rng.next_int(2) == 0
	var small_number := rng.next_int(4) != 0
	var square_names := rng.next_int(2) == 0
	var arched_names := rng.next_int(3) == 0
	var trim_kind := rng.next_int(4)
	var pinstriped := rng.next_int(3) == 0
	var striped_trousers := rng.next_int(2) == 0
	var sleeve_pick := rng.next_int(1000)
	var chest_pick := rng.next_int(1000)
	var s: UniformStyle
	if home:
		s = make(Color(0.95, 0.95, 0.96), Color(0.93, 0.93, 0.94), primary, primary, mark)
		s.jersey_pinstripes = pinstriped
		s.pants_pinstripes = pinstriped
		s.pinstripe = primary.lerp(Color.WHITE, 0.55)
		s.lettering = kind
		s.outline = _second(primary, s.jersey, t.accent, t.secondary)
	elif primary.get_luminance() < 0.35:
		s = make(primary, Color(0.62, 0.63, 0.66), t.accent, Color(0.97, 0.97, 0.97), town)
		s.lettering = &"tuscan" if kind == &"tuscan" else &"block"
		s.outline = _second(s.ink, primary, t.accent, t.secondary)
	else:
		# Road gray: the club colour, darkened if it is too near the gray to read on it.
		var gray := Color(0.63, 0.64, 0.67)
		var road_ink := primary if absf(primary.get_luminance() - gray.get_luminance()) > 0.28 else primary.darkened(0.55)
		s = make(gray, Color(0.61, 0.62, 0.65), primary, road_ink, town)
		s.lettering = &"tuscan" if kind == &"tuscan" else &"block"
		s.outline = _second(road_ink, gray, t.accent, Color.WHITE)
	if s.lettering == &"script":
		s.tail = with_tail
	else:
		s.wordmark = s.wordmark.to_upper()
		s.arch = arched
	s.front_number = small_number
	s.name_face = &"name_square" if square_names else &"name"
	s.name_arch = arched_names
	# Pinstripes carry no other trim; plain jerseys have piping or bands at the sleeves.
	if not s.jersey_pinstripes:
		s.piping = trim_kind == 0 or trim_kind == 3
		s.sleeve_bands = 1 if trim_kind == 1 else (2 if trim_kind == 2 else 0)
	s.cap = primary.darkened(0.15)
	s.socks = primary
	s.undershirt = primary.darkened(0.3)
	s.cap_letter = mark.substr(0, 1).to_upper()
	s.patch = s.cap_letter
	s.pants_stripe = striped_trousers
	var sponsors: Array = AdStrip.load_sponsors()
	if not sponsors.is_empty():
		s.sleeve_sponsor = sponsors[sleeve_pick % sponsors.size()]
		if chest_pick % 2 == 0:
			s.chest_sponsor = sponsors[(chest_pick / 2) % sponsors.size()]
			if s.chest_sponsor == s.sleeve_sponsor:
				s.chest_sponsor = {}
	return s


## A second colour for the edge of lettering in `ink` on `cloth`: the first of the candidates
## that stands out from both, or none.
static func _second(ink_color: Color, cloth: Color, first: Color, second: Color) -> Color:
	for candidate: Color in [first, second]:
		if _apart(candidate, ink_color) > 0.3 and _apart(candidate, cloth) > 0.18:
			return candidate
	return Color(0, 0, 0, 0)


static func _apart(a: Color, b: Color) -> float:
	return absf(a.r - b.r) * 0.3 + absf(a.g - b.g) * 0.59 + absf(a.b - b.b) * 0.11 + 0.25 * (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0


static func _uniform_data() -> Dictionary:
	if _data.is_empty():
		_data = JsonIO.read_object("res://data/uniforms.json")
	return _data
