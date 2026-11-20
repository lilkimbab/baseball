class_name Resolver
extends RefCounted
## Decides what happens next in a game. The stat resolver (plate appearances drawn from
## probabilities) and the physical resolver (S5: pitches and batted balls simulated) both
## produce the same events, so the rules and the record keeping are shared.


## The next event: a substitution, a running play or a plate appearance. Called again after
## each event has been applied, until the game is over.
func next_event(_state: GameState) -> GameEvent:
	return null
