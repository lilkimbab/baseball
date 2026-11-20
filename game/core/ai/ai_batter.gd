class_name AiBatter
extends RefCounted
## Minimal batter for stage S3: reads the pitch with some error, swings at what looks like
## a strike, and is early or late by a random amount.

const SWING_AT_STRIKE := 0.72
## Chance of swinging at a pitch that looks just off the edge of the zone. It falls away to
## nothing for one that looks CHASE_RANGE metres outside: nobody swings at a pitch at his head.
const CHASE := 0.45
const CHASE_RANGE := 0.3
## Timing error (standard deviation) as a fraction of the timing window.
const TIMING_SPREAD := 0.55


## Call right after the pitch is released. Schedules a swing on the duel, or leaves it alone.
static func react(duel: PitchDuel, rng: Rng) -> void:
	var settings := duel.settings
	var read := SwingModel.read_sigma(settings, duel.decision.type.family)
	var misread := Vector2(rng.next_normal(), rng.next_normal()) * read
	var seen := Vector2(duel.pitch.plate_pos.x, duel.pitch.plate_pos.z) + misread
	var looks_like_strike := duel.zone.contains(seen.x, seen.y, 0.03)
	var chase := CHASE * clampf(1.0 - duel.zone.distance_outside(seen.x, seen.y) / CHASE_RANGE, 0.0, 1.0)
	if not rng.chance(SWING_AT_STRIKE if looks_like_strike else chase):
		return
	var kind := SwingAttempt.Kind.POWER if rng.chance(0.3) else SwingAttempt.Kind.CONTACT
	var window := SwingModel.timing_window(settings, kind)
	var contact_time := duel.ideal_contact_time + rng.next_normal() * TIMING_SPREAD * window
	var aim := Vector2(duel.ideal_contact_pos.x, duel.ideal_contact_pos.z) + misread
	duel.swing_at(contact_time, kind, aim, true)
