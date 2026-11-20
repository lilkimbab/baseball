class_name FieldingRatings
extends RefCounted
## A fielder's ratings, 1..99, average 50.

## Reaction and route: how much ground he covers.
var range := 50.0
## Catching: fewer errors, quicker transfer.
var hands := 50.0
## Throwing strength.
var arm := 50.0
## Throwing accuracy.
var accuracy := 50.0


func overall() -> float:
	return range * 0.4 + hands * 0.3 + arm * 0.2 + accuracy * 0.1
