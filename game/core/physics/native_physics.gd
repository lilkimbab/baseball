class_name NativePhysics
extends RefCounted
## The ball's flight in native code (approved proposal 5): the same drag, Magnus lift,
## gravity and seam-shifted wake as BallSim, integrated in C++ (tools/native, built by
## ./dev native into game/native/bin). When the library is not there — a fresh checkout, a
## platform it was not built for — `enabled` is false and BallSim and PitchModel run their
## own GDScript, which gives the same flights.

const CLASS := &"BallPhysics"

## Whether the native library is loaded and used. Tests turn it off to compare the two; the
## batch simulation turns it off with NATIVE_PHYSICS=0 in the environment (tools/sim_batch.gd).
static var enabled := available()


static func available() -> bool:
	return ClassDB.class_exists(CLASS)


## One RK4 step: [new position, new velocity, new spin].
static func integrate(pos: Vector3, vel: Vector3, spin: Vector3, ssw: Vector3, batted: bool, batted_cd: float,
		dt: float, params: PackedFloat64Array) -> PackedVector3Array:
	return ClassDB.class_call_static(CLASS, &"integrate", pos, vel, spin, ssw, batted, batted_cd, dt, params)


## A pitch from the hand to the front of the plate (see PitchModel.fly_to_plate).
static func fly_to_plate(release: Vector3, velocity: Vector3, spin: Vector3, ssw: Vector3, contact_y: float,
		plate_y: float, dt: float, params: PackedFloat64Array) -> Dictionary:
	return ClassDB.class_call_static(CLASS, &"fly_to_plate", release, velocity, spin, ssw, contact_y, plate_y, dt, params)
