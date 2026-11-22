class_name NameTable
extends RefCounted
## Parts for making up player and team names (data/names.ko.json).

var surnames := PackedStringArray()
var surname_weights := PackedFloat64Array()
var first := PackedStringArray()
var second := PackedStringArray()
## Common given names, used whole.
var given := PackedStringArray()
var avoid: Dictionary[String, bool] = {}
var city_names := PackedStringArray()
var city_codes := PackedStringArray()
var nicknames := PackedStringArray()
## Per palette entry: primary, secondary, accent.
var colors: Array[PackedColorArray] = []
## Foreign and Asia-quota players' name parts, in Korean spelling.
var foreign_first := PackedStringArray()
var foreign_last := PackedStringArray()
var asia_first := PackedStringArray()
var asia_last := PackedStringArray()


## A Korean name: a surname by its share of the population and a common given name whole
## (data/names.ko.json "given"; random syllables made names nobody has), never one to avoid.
func person(rng: Rng) -> String:
	for attempt: int in 50:
		var given_name := ""
		if not given.is_empty():
			given_name = given[rng.next_int(given.size())]
		else:
			var a := first[rng.next_int(first.size())]
			var b := second[rng.next_int(second.size())]
			if a == b:
				continue
			given_name = a + b
		var full := surnames[rng.pick_weighted(surname_weights)] + given_name
		if not avoid.has(full):
			return full
	return surnames[0] + (given[0] if not given.is_empty() else first[0] + second[1])


## A foreign player's name the way Korean broadcasts write it: "제이크 밀러". Asia-quota
## players get Japanese or Taiwanese name parts, written family name first.
func foreigner(rng: Rng, asia: bool = false) -> String:
	if asia and not asia_first.is_empty() and not asia_last.is_empty():
		return "%s %s" % [asia_last[rng.next_int(asia_last.size())], asia_first[rng.next_int(asia_first.size())]]
	if foreign_first.is_empty() or foreign_last.is_empty():
		return person(rng)
	return "%s %s" % [foreign_first[rng.next_int(foreign_first.size())], foreign_last[rng.next_int(foreign_last.size())]]
