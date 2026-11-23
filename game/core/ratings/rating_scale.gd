class_name RatingScale
extends RefCounted
## How high a rating goes (the user, 2026-11-23: "raise the highest overall a little, to about
## 130 — make no such players now, keep things as they are; it is for special players later,
## or a career built up by really working at it"). Every player is made, trained and grown by
## the clubs within NATURAL, as before; only the career's own growth (Growth.raise, at a steep
## price past NATURAL) and a special man made so may pass it, up to MAX. Shown, a rating over
## 99 reads one for one (UiTheme.shown), in the diamond tier.

const NATURAL := 99.0
const MAX := 130.0


## A rating as a share for the engine's effects: 0..1 up to NATURAL as it always was, then on
## at half the slope (1.16 at MAX), so a man past 99 is better still and no curve built for
## 0..1 is thrown far off its range.
static func norm(rating: float) -> float:
	var n := clampf(rating / NATURAL, 0.0, 1.0)
	if rating > NATURAL:
		n += (minf(rating, MAX) - NATURAL) / NATURAL * 0.5
	return n


## A rating as the screens show it (UiTheme.shown; free agency prices men by it): the engine's
## 20..99 with the league's average at 50, shown so that the average reads 68 — one for one up
## to 65, squeezed above it so that 99 stays 99, one for one again past 99 to MAX.
static func shown(value: float) -> float:
	if value <= 65.0:
		return maxf(value + 18.0, 1.0)
	if value > NATURAL:
		return minf(value, MAX)
	return minf(83.0 + (value - 65.0) * 16.0 / 34.0, 99.0)
