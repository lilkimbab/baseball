class_name PlayChoice
extends RefCounted
## What the player decided during a ball in play (docs/05 2.3, 2.4): the base the fielder
## throws to and how hard (a gauge held and let go), and whether the runners go or hold.
## Without a choice the computer decides, as for a computer team.

## Gauge levels: let go inside GREEN for a firm, accurate throw. Short of it the throw is
## weaker; past it, harder but more often off line.
const GREEN := Vector2(0.7, 1.0)
const FULL := 1.25

## 1 first, 2 second, 3 third, 4 home; 0 for the computer's choice.
var throw_to := 0
## Where the gauge was let go, 0 to FULL.
var gauge := 0.85
## 1 every runner goes, −1 every runner holds (or goes back), 0 the runners' own judgment.
var running := 0
## The fielder the player moves himself (PlayContext.manual_*), Position.Kind.DH for none.
var manual_fielder: Position.Kind = Position.Kind.DH
var manual_track := PackedVector3Array()
var manual_time := -1.0
var manual_at := Vector3.ZERO
var manual_dive := false
var manual_ready := 0.0


func has_any() -> bool:
	return throw_to > 0 or running != 0 or manual_fielder != Position.Kind.DH


## How much faster than his usual throw the fielder's is.
func throw_power() -> float:
	if gauge < GREEN.x:
		return lerpf(0.8, 0.97, clampf(gauge / GREEN.x, 0.0, 1.0))
	if gauge <= GREEN.y:
		return 1.0
	return 1.08


## How much likelier than usual a throw is to be off line.
func throw_wild() -> float:
	if gauge < GREEN.x:
		return 1.0
	if gauge <= GREEN.y:
		return 0.5
	return 3.0


## Seconds added to every runner's sense of his own speed when he judges an extra base or
## breaking for home: negative makes them go, a lot makes them stay.
func running_shift() -> float:
	match running:
		1:
			return -0.8
		-1:
			return 3.0
	return 0.0


func apply(ctx: PlayContext) -> void:
	ctx.throw_to = throw_to
	if throw_to > 0:
		ctx.throw_power = throw_power()
		ctx.throw_wild = throw_wild()
	ctx.running_shift += running_shift()
	ctx.manual_fielder = manual_fielder
	ctx.manual_track = manual_track
	ctx.manual_time = manual_time
	ctx.manual_at = manual_at
	ctx.manual_dive = manual_dive
	ctx.manual_ready = manual_ready
