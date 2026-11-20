class_name NameTable
extends RefCounted
## Parts for making up player and team names (data/names.ko.json).

var surnames := PackedStringArray()
var surname_weights := PackedFloat64Array()
var first := PackedStringArray()
var second := PackedStringArray()
var avoid: Dictionary[String, bool] = {}
var city_names := PackedStringArray()
var city_codes := PackedStringArray()
var nicknames := PackedStringArray()
## Per palette entry: primary, secondary, accent.
var colors: Array[PackedColorArray] = []


## A Korean name: surname plus two given-name syllables, never one that is to be avoided.
func person(rng: Rng) -> String:
	for attempt: int in 50:
		var a := first[rng.next_int(first.size())]
		var b := second[rng.next_int(second.size())]
		if a == b:
			continue
		var full := surnames[rng.pick_weighted(surname_weights)] + a + b
		if not avoid.has(full):
			return full
	return surnames[0] + first[0] + second[1]
