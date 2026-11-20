class_name GameEvent
extends RefCounted
## Something that happened in a game. GameFlow applies it to the game state and the Scorer
## records it. Events are the game's history: replaying them rebuilds the game.

enum Kind { PITCH, PLATE_APPEARANCE, STEAL, PICKOFF, WILD_PITCH, PASSED_BALL, SUBSTITUTION }
## What a single pitch was (Kind.PITCH).
enum Call { BALL, CALLED_STRIKE, SWINGING_STRIKE, FOUL, FOUL_BUNT }
## What a substitution is (Kind.SUBSTITUTION).
enum Change { PITCHER, PINCH_HITTER, PINCH_RUNNER, DEFENSE, POSITION }

var kind: Kind = Kind.PLATE_APPEARANCE
var result: PaResult.Kind = PaResult.Kind.NONE
var call: Call = Call.BALL
## Runner and batter movements in the order they happened. The lead runner comes first, so
## a run that scores ahead of a later out on the same play is listed before it.
var moves: Array[RunnerMove] = []
## Pitches thrown in this plate appearance (plate appearances only).
var pitches := 0
## Fielders who handled the ball, in scorecard numbers: "6-4-3".
var fielders := ""
## Batted ball direction for the play-by-play: a position number 1..9, 0 if none.
var direction := 0

## Substitution: which team (0 away, 1 home), what kind, who leaves and who comes in, and
## the position the incoming player takes.
var team := 0
var change: Change = Change.PITCHER
var out_id := ""
var in_id := ""
var position: Position.Kind = Position.Kind.P


static func plate_appearance(result_kind: PaResult.Kind, move_list: Array[RunnerMove], pitch_count: int = 4) -> GameEvent:
	var e := GameEvent.new()
	e.kind = Kind.PLATE_APPEARANCE
	e.result = result_kind
	e.moves = move_list
	e.pitches = pitch_count
	return e


static func running(event_kind: Kind, move_list: Array[RunnerMove]) -> GameEvent:
	var e := GameEvent.new()
	e.kind = event_kind
	e.moves = move_list
	return e


static func pitch(pitch_call: Call) -> GameEvent:
	var e := GameEvent.new()
	e.kind = Kind.PITCH
	e.call = pitch_call
	return e


static func substitution(team_index: int, what: Change, leaving: String, entering: String, at: Position.Kind) -> GameEvent:
	var e := GameEvent.new()
	e.kind = Kind.SUBSTITUTION
	e.team = team_index
	e.change = what
	e.out_id = leaving
	e.in_id = entering
	e.position = at
	return e
