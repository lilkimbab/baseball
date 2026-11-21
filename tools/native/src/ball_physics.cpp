#include "ball_physics.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

using namespace godot;

namespace {

struct D3 {
	double x, y, z;
	D3 operator+(const D3 &o) const { return { x + o.x, y + o.y, z + o.z }; }
	D3 operator-(const D3 &o) const { return { x - o.x, y - o.y, z - o.z }; }
	D3 operator*(double s) const { return { x * s, y * s, z * s }; }
	double dot(const D3 &o) const { return x * o.x + y * o.y + z * o.z; }
	D3 cross(const D3 &o) const { return { y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x }; }
	double length() const { return std::sqrt(dot(*this)); }
};

D3 d3(const Vector3 &v) { return { v.x, v.y, v.z }; }
Vector3 v3(const D3 &d) { return Vector3(real_t(d.x), real_t(d.y), real_t(d.z)); }

struct Params {
	double aero_k, cd0, cd_per_1000_rpm, radius, cl0, cl1, cl2, gravity, spin_tau, bat_cd_spin, bat_cl_a, bat_cl_b;
	explicit Params(const PackedFloat64Array &p) :
			aero_k(p[0]), cd0(p[1]), cd_per_1000_rpm(p[2]), radius(p[3]), cl0(p[4]), cl1(p[5]), cl2(p[6]),
			gravity(p[7]), spin_tau(p[8]), bat_cd_spin(p[9]), bat_cl_a(p[10]), bat_cl_b(p[11]) {}
};

// BallSim.aero / _batted_aero, then gravity and the wake (BallSim.accel).
D3 accel(const Params &c, const D3 &v, const D3 &w, const D3 &ssw, bool batted, double batted_cd) {
	D3 acc = { 0.0, 0.0, -c.gravity };
	acc = acc + ssw;
	const double sp = v.length();
	if (sp < 1e-6) {
		return acc;
	}
	if (batted) {
		const double wl = w.length();
		const double s = c.radius * wl / sp;
		const double cd = batted_cd * (1.0 + c.bat_cd_spin * s * s);
		acc = acc + v * (-c.aero_k * cd * sp);
		if (s > 1e-6) {
			const double cl = 1.0 / (c.bat_cl_a + c.bat_cl_b / s);
			const D3 lift = w.cross(v);
			const double n = lift.length();
			if (n > 1e-9) {
				acc = acc + lift * (c.aero_k * cl * sp * sp / n);
			}
		}
		return acc;
	}
	const D3 vh = v * (1.0 / sp);
	const D3 w_perp = w - vh * w.dot(vh);
	const double w_rpm = w.length() * 60.0 / 6.283185307179586;
	const double cd = c.cd0 + c.cd_per_1000_rpm * (w_rpm / 1000.0);
	const double wp = w_perp.length();
	acc = acc + v * (-c.aero_k * cd * sp);
	if (wp > 1e-6) {
		const double s = c.radius * wp / sp;
		const double cl = c.cl2 * s / (c.cl0 + c.cl1 * s);
		D3 dir = w_perp.cross(v);
		const double n = dir.length();
		if (n > 1e-12) {
			acc = acc + dir * (c.aero_k * cl * sp * sp / n);
		}
	}
	return acc;
}

// One RK4 step (BallSim.integrate): the new position; velocity and spin updated in place.
D3 rk4(const Params &c, const D3 &pos, D3 &vel, D3 &spin, const D3 &ssw, bool batted, double batted_cd, double dt) {
	const D3 k1v = accel(c, vel, spin, ssw, batted, batted_cd);
	const D3 v2 = vel + k1v * (dt * 0.5);
	const D3 k2v = accel(c, v2, spin, ssw, batted, batted_cd);
	const D3 v3_ = vel + k2v * (dt * 0.5);
	const D3 k3v = accel(c, v3_, spin, ssw, batted, batted_cd);
	const D3 v4 = vel + k3v * dt;
	const D3 k4v = accel(c, v4, spin, ssw, batted, batted_cd);
	const D3 np = pos + (vel + v2 * 2.0 + v3_ * 2.0 + v4) * (dt / 6.0);
	vel = vel + (k1v + k2v * 2.0 + k3v * 2.0 + k4v) * (dt / 6.0);
	spin = spin * std::exp(-dt / c.spin_tau);
	return np;
}

} // namespace

PackedVector3Array BallPhysics::integrate(const Vector3 &pos, const Vector3 &vel, const Vector3 &spin, const Vector3 &ssw,
		bool batted, double batted_cd, double dt, const PackedFloat64Array &params) {
	const Params c(params);
	D3 v = d3(vel);
	D3 w = d3(spin);
	const D3 np = rk4(c, d3(pos), v, w, d3(ssw), batted, batted_cd, dt);
	PackedVector3Array out;
	out.push_back(v3(np));
	out.push_back(v3(v));
	out.push_back(v3(w));
	return out;
}

Dictionary BallPhysics::fly_to_plate(const Vector3 &release, const Vector3 &velocity, const Vector3 &spin, const Vector3 &ssw,
		double contact_y, double plate_y, double dt, const PackedFloat64Array &params) {
	const Params c(params);
	D3 pos = d3(release);
	D3 vel = d3(velocity);
	D3 w = d3(spin);
	const D3 s = d3(ssw);
	Dictionary out;
	double t = 0.0;
	while (t < 3.0) {
		const D3 prev_pos = pos;
		const D3 prev_vel = vel;
		const D3 np = rk4(c, pos, vel, w, s, false, 0.0, dt);
		if (prev_pos.y > contact_y && np.y <= contact_y) {
			const double g = (prev_pos.y - contact_y) / (prev_pos.y - np.y);
			out["contact_pos"] = v3(prev_pos + (np - prev_pos) * g);
			out["contact_time"] = t + dt * g;
		}
		if (np.y <= plate_y) {
			const double f = (prev_pos.y - plate_y) / (prev_pos.y - np.y);
			out["plate_pos"] = v3(prev_pos + (np - prev_pos) * f);
			out["plate_vel"] = v3(prev_vel + (vel - prev_vel) * f);
			out["flight_time"] = t + dt * f;
			return out;
		}
		pos = np;
		t += dt;
	}
	out["plate_pos"] = v3(pos);
	out["plate_vel"] = v3(vel);
	out["flight_time"] = t;
	return out;
}

void BallPhysics::_bind_methods() {
	ClassDB::bind_static_method("BallPhysics", D_METHOD("integrate", "pos", "vel", "spin", "ssw", "batted", "batted_cd", "dt", "params"), &BallPhysics::integrate);
	ClassDB::bind_static_method("BallPhysics", D_METHOD("fly_to_plate", "release", "velocity", "spin", "ssw", "contact_y", "plate_y", "dt", "params"), &BallPhysics::fly_to_plate);
}
