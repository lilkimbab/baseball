class_name AiBatter
extends RefCounted
## The computer batter (docs/02 section 8.2). He reads where the pitch will
## cross the plate with an error that depends on his eye and the kind of pitch, decides to
## swing by what it looks like and the count, and times his swing with an error that grows
## when a slower pitch fools him.

## Chance of swinging at what looks like a strike, by balls and strikes.
const SWING_ZONE := [
	[0.65, 0.81, 0.92],
	[0.75, 0.83, 0.93],
	[0.78, 0.85, 0.94],
	[0.08, 0.81, 0.94],
]
## Chance of chasing a pitch that looks just off the zone; it falls to nothing for one that
## looks, or is, CHASE_RANGE out.
const CHASE := [
	[0.37, 0.45, 0.60],
	[0.35, 0.45, 0.60],
	[0.31, 0.43, 0.58],
	[0.00, 0.31, 0.56],
]
const CHASE_RANGE := 0.30
## Timing error (standard deviation) as a fraction of the timing window.
const TIMING_SPREAD := 0.50
## A pitch slower than the speed he is geared for makes him early by this share of the
## window for every 10 km/h of difference, and a faster one late; less with a good eye.
const FOOLED_PER_10KMH := 0.20
## What he is geared for: the pitcher's fastball, pulled toward the last pitch he saw in this
## plate appearance by this share (a fastball after a curve looks quicker).
const LAST_PITCH_PULL := 0.4
## A breaking ball or change-up drops more than he expects: he aims this far above it
## (metres, at an average eye), topping it or swinging over it.
const FOOLED_DROP := 0.010
const FOOLED_DROP_SPREAD := 0.012
## Batters tend to be a touch early: the share of the window by which the average swing
## leads the ball (it pulls more balls than it pushes).
const EARLY := 0.15
## Weak spots: worse read and timing there.
const WEAK_READ := 1.5
const WEAK_TIMING := 1.3


## Practice mode: no count, no weak spots.
static func react(duel: PitchDuel, rng: Rng) -> void:
	decide(duel, 1, 1, PackedInt32Array(), duel.decision.type.speed_kmh, rng)


## The speed a batter is geared for: the pitcher's fastball, moved toward the last pitch of
## this plate appearance (none yet: negative).
static func expected_speed(fastball_kmh: float, last_kmh: float) -> float:
	if last_kmh <= 0.0:
		return fastball_kmh
	return lerpf(fastball_kmh, last_kmh, LAST_PITCH_PULL)


## Call right after the pitch is released. Schedules a swing on the duel, or leaves it alone.
## `expect_kmh` is the speed he is geared for (expected_speed).
static func decide(duel: PitchDuel, balls: int, strikes: int, weak: PackedInt32Array, expect_kmh: float, rng: Rng) -> void:
	var settings := duel.settings
	var crossing := Vector3(duel.pitch.plate_pos.x, Field.PLATE_FRONT_Y, duel.pitch.plate_pos.z)
	var in_weak := weak.has(AiPitcher.cell_of(duel.zone, crossing))
	var read := SwingModel.read_sigma(settings, duel.decision.type.family) * (WEAK_READ if in_weak else 1.0)
	var misread := Vector2(rng.next_normal(), rng.next_normal()) * read
	var seen := Vector2(crossing.x, crossing.z) + misread
	var b := mini(balls, 3)
	var s := mini(strikes, 2)
	# With two strikes he protects a little off the edges.
	var margin := 0.05 if s == 2 else 0.02
	var looks_like_strike := duel.zone.contains(seen.x, seen.y, margin)
	var looks_off := clampf(1.0 - duel.zone.distance_outside(seen.x, seen.y) / CHASE_RANGE, 0.0, 1.0)
	var is_off := clampf(1.0 - duel.zone.distance_outside(crossing.x, crossing.z) / CHASE_RANGE, 0.0, 1.0)
	var chase: float = CHASE[b][s] * looks_off * is_off
	var swing_chance: float = SWING_ZONE[b][s] if looks_like_strike else chase
	if not rng.chance(swing_chance):
		return
	var power_share := 0.12 if s == 2 else (0.50 if b > s else 0.36)
	power_share *= lerpf(0.6, 1.4, RatingScale.norm(settings.power))
	var kind := SwingAttempt.Kind.POWER if rng.chance(power_share) else SwingAttempt.Kind.CONTACT
	var window := SwingModel.timing_window(settings, kind)
	# Positive: slower than he expected, so he is early; negative: quicker, so he is late.
	var fooled := (expect_kmh - duel.decision.type.speed_kmh * duel.decision.effort) / 10.0 \
		* FOOLED_PER_10KMH * lerpf(1.3, 0.6, RatingScale.norm(settings.eye))
	var spread := TIMING_SPREAD * (WEAK_TIMING if in_weak else 1.0)
	var contact_time := duel.ideal_contact_time + (rng.next_normal() * spread - fooled - EARLY) * window
	var aim := Vector2(duel.ideal_contact_pos.x, duel.ideal_contact_pos.z) + misread
	if not duel.swing_at(contact_time, kind, aim, true):
		return
	if duel.decision.type.family != &"fastball":
		var drop := (FOOLED_DROP + rng.next_normal() * FOOLED_DROP_SPREAD) * lerpf(1.4, 0.6, RatingScale.norm(settings.eye))
		duel.swing.offset_bias = -drop


## Squares to bunt: only at something near the zone, the bat angled down a line.
static func bunt(duel: PitchDuel, rng: Rng) -> void:
	var seen := Vector2(duel.pitch.plate_pos.x, duel.pitch.plate_pos.z) \
		+ Vector2(rng.next_normal(), rng.next_normal()) * SwingModel.read_sigma(duel.settings, duel.decision.type.family)
	if duel.zone.distance_outside(seen.x, seen.y) > 0.08:
		return
	if not duel.swing_at(duel.ideal_contact_time, SwingAttempt.Kind.BUNT, Vector2(duel.ideal_contact_pos.x, duel.ideal_contact_pos.z), true):
		return
	duel.swing.bunt_angle = rng.next_range(14.0, 26.0) * (1.0 if rng.chance(0.5) else -1.0)


## Two or three of the nine cells of the zone where a batter hits worse, fixed per player.
static func weak_cells(player_id: String) -> PackedInt32Array:
	var rng := Rng.new(hash(player_id) & 0x7fffffff, 17)
	var cells := PackedInt32Array()
	var count := 2 + rng.next_int(2)
	while cells.size() < count:
		var c := rng.next_int(9)
		if not cells.has(c):
			cells.append(c)
	return cells
