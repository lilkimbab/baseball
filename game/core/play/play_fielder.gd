class_name PlayFielder
extends RefCounted
## One fielder during a play: where he starts and how well he plays where he is.

var kind: Position.Kind = Position.Kind.P
var id := ""
## Where he stands when the pitch is thrown (field x, y).
var pos := Vector2.ZERO
var speed := 50.0
## Fielding ratings scaled by how well he knows the position.
var reach := 50.0
var hands := 50.0
var arm := 50.0
var accuracy := 50.0


static func make(at: Position.Kind, where: Vector2, run: float = 50.0, range_rating: float = 50.0, hands_rating: float = 50.0, arm_rating: float = 50.0, accuracy_rating: float = 50.0) -> PlayFielder:
	var f := PlayFielder.new()
	f.kind = at
	f.pos = where
	f.speed = run
	f.reach = range_rating
	f.hands = hands_rating
	f.arm = arm_rating
	f.accuracy = accuracy_rating
	return f


## Scorecard number: 1 pitcher .. 9 right fielder.
func number() -> int:
	return Position.scoring_number(kind)
