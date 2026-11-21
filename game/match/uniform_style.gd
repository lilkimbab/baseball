class_name UniformStyle
extends RefCounted
## What a team's uniform looks like, plus the player's own name and number.

var jersey := Color(0.93, 0.93, 0.95)
var pants := Color(0.9, 0.9, 0.92)
## Piping, sleeve bands, belt loops.
var trim := Color(0.1, 0.15, 0.35)
## Lettering and numbers.
var ink := Color(0.1, 0.15, 0.35)
var cap := Color(0.1, 0.15, 0.35)
var socks := Color(0.1, 0.15, 0.35)
var jersey_pinstripes := false
var pants_pinstripes := false
var pinstripe := Color(0.25, 0.28, 0.4)
## Word across the chest.
var wordmark := ""
## Letter on the sleeve patch ("" no patch), and a stripe down the side of the trousers.
var patch := ""
var pants_stripe := false
var number := 0
var player_name := ""


static func make(jersey_color: Color, pants_color: Color, trim_color: Color, ink_color: Color, word: String) -> UniformStyle:
	var s := UniformStyle.new()
	s.jersey = jersey_color
	s.pants = pants_color
	s.trim = trim_color
	s.ink = ink_color
	s.cap = trim_color
	s.socks = trim_color
	s.wordmark = word
	return s


## A club's uniform (docs/13 S11-9): at home white with the club colour, the nickname across
## the chest; away the club colour if it is dark enough to carry white lettering, otherwise
## road gray, with the city's name. Some clubs wear pinstripes at home.
static func for_team(t: Team, home: bool) -> UniformStyle:
	var nickname := t.name.substr(t.short_name.length()).strip_edges() if t.name.begins_with(t.short_name) else t.name
	var primary := t.primary
	# A club colour too light to read on white falls back to its accent.
	if primary.get_luminance() > 0.7:
		primary = t.accent
	var s: UniformStyle
	if home:
		s = make(Color(0.95, 0.95, 0.96), Color(0.93, 0.93, 0.94), primary, primary, nickname)
		s.jersey_pinstripes = absi(hash(t.id)) % 3 == 0
		s.pants_pinstripes = s.jersey_pinstripes
		s.pinstripe = primary.lerp(Color.WHITE, 0.55)
	elif primary.get_luminance() < 0.35:
		s = make(primary, Color(0.62, 0.63, 0.66), t.accent, Color(0.97, 0.97, 0.97), t.short_name)
	else:
		s = make(Color(0.63, 0.64, 0.67), Color(0.61, 0.62, 0.65), primary, primary, t.short_name)
	s.cap = primary.darkened(0.15)
	s.socks = primary
	s.patch = t.short_name.substr(0, 1)
	s.pants_stripe = absi(hash(t.id + ":stripe")) % 2 == 0
	return s
