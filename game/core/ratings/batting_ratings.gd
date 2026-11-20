class_name BattingRatings
extends RefCounted
## A hitter's ratings, 1..99 with the league average at 50 and one standard deviation 15.
## Contact and power are split by the hand of the pitcher faced.

var contact_r := 50.0
var contact_l := 50.0
var power_r := 50.0
var power_l := 50.0
var eye := 50.0
var speed := 50.0
var baserunning := 50.0
var bunt := 50.0
var clutch := 50.0


func contact_vs(pitcher_throws: StringName) -> float:
	return contact_l if pitcher_throws == &"L" else contact_r


func power_vs(pitcher_throws: StringName) -> float:
	return power_l if pitcher_throws == &"L" else power_r


func contact() -> float:
	return (contact_r * 2.0 + contact_l) / 3.0


func power() -> float:
	return (power_r * 2.0 + power_l) / 3.0
