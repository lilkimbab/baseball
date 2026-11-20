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
