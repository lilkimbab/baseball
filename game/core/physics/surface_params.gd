class_name SurfaceParams
extends RefCounted
## How the ball reacts to one kind of surface (docs/04, section 8.2).

## Normal restitution: fraction of the approach speed kept after a bounce.
var restitution := 0.45
## Coulomb friction coefficient during a bounce.
var friction := 0.55
## Rolling deceleration (m/s^2) at low speed.
var roll_decel := 3.0
## Extra rolling deceleration per m/s of speed (1/s).
var roll_drag := 0.0
## True for surfaces the ball can roll on; false for walls and nets.
var is_ground := true
