#pragma once
// The ball's flight, in native code (approved proposal 5): drag, Magnus lift, gravity and the
// seam-shifted wake integrated with RK4, the same model as game/core/physics/ball_sim.gd
// (docs/04), in double precision. The game uses it when the library is there and its own
// GDScript otherwise.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class BallPhysics : public RefCounted {
	GDCLASS(BallPhysics, RefCounted)

protected:
	static void _bind_methods();

public:
	// params: aero_k, cd0, cd_per_1000_rpm, ball_radius, cl0, cl1, cl2, gravity,
	// spin_decay_tau, bat_cd_spin, bat_cl_a, bat_cl_b (PhysicsConfig.native_params()).
	static PackedVector3Array integrate(const Vector3 &pos, const Vector3 &vel, const Vector3 &spin, const Vector3 &ssw,
			bool batted, double batted_cd, double dt, const PackedFloat64Array &params);
	// A pitch from release to the front of the plate (PitchModel.fly_to_plate): returns
	// plate_pos, plate_vel, flight_time, and contact_pos / contact_time where it crosses
	// contact_y (if it does).
	static Dictionary fly_to_plate(const Vector3 &release, const Vector3 &velocity, const Vector3 &spin, const Vector3 &ssw,
			double contact_y, double plate_y, double dt, const PackedFloat64Array &params);
};

} // namespace godot
