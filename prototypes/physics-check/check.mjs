// Feasibility + constant validation for the design docs.
// Field coords: +x = 1B side, +y = home -> CF, +z = up. SI units.
import RAPIER from '@dimforge/rapier3d-compat';

const G = 9.81, RHO = 1.2, M = 0.145, R = 0.0366;
const A = Math.PI * R * R;
const K = (RHO * A) / (2 * M);
const CD0 = +(process.env.CD0 ?? 0.33), CD_SPIN = +(process.env.CDS ?? 0.02);
const CL0 = 0.583, CL1 = 2.333, CL2 = +(process.env.CL2 ?? 1.05);
const TAU = 25;                              // spin decay time constant (s)

const v3 = (x, y, z) => ({ x, y, z });
const add = (a, b) => v3(a.x + b.x, a.y + b.y, a.z + b.z);
const sub = (a, b) => v3(a.x - b.x, a.y - b.y, a.z - b.z);
const mul = (a, s) => v3(a.x * s, a.y * s, a.z * s);
const dot = (a, b) => a.x * b.x + a.y * b.y + a.z * b.z;
const cross = (a, b) => v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
const len = (a) => Math.sqrt(dot(a, a));
const norm = (a) => mul(a, 1 / (len(a) || 1));
const rpm = (r) => (r * 2 * Math.PI) / 60;
const kmh = (k) => k / 3.6;

function aeroAccel(v, w) {
  const sp = len(v);
  if (sp < 1e-6) return v3(0, 0, 0);
  const vh = mul(v, 1 / sp);
  const wPar = mul(vh, dot(w, vh));
  const wPerp = sub(w, wPar);                 // active spin only
  const wRpm = (len(w) * 60) / (2 * Math.PI);
  const cd = CD0 + CD_SPIN * (wRpm / 1000);
  const S = (R * len(wPerp)) / sp;
  const cl = S > 0 ? (CL2 * S) / (CL0 + CL1 * S) : 0;
  const drag = mul(v, -K * cd * sp);
  const dir = len(wPerp) > 0 ? norm(cross(wPerp, v)) : v3(0, 0, 0);
  const mag = mul(dir, K * cl * sp * sp);
  return add(drag, mag);
}

// Seam-shifted wake (Smith & Smith 2021): a push the spin does not explain, set per pitch.
let SSW = v3(0, 0, 0);
function accel(v, w) { return add(add(aeroAccel(v, w), v3(0, 0, -G)), SSW); }

// RK4 reference integrator (free flight only)
function fly(p0, v0, w0, stop, dt = 1 / 1000) {
  let p = p0, v = v0, w = w0, t = 0;
  while (t < 15) {
    const k1v = accel(v, w), k1p = v;
    const v2 = add(v, mul(k1v, dt / 2)), k2v = accel(v2, w), k2p = v2;
    const v3_ = add(v, mul(k2v, dt / 2)), k3v = accel(v3_, w), k3p = v3_;
    const v4 = add(v, mul(k3v, dt)), k4v = accel(v4, w), k4p = v4;
    const np = add(p, mul(add(add(k1p, mul(k2p, 2)), add(mul(k3p, 2), k4p)), dt / 6));
    const nv = add(v, mul(add(add(k1v, mul(k2v, 2)), add(mul(k3v, 2), k4v)), dt / 6));
    if (stop(np)) {
      // linear interpolate to the stop surface for accuracy
      return { p: np, v: nv, t: t + dt };
    }
    p = np; v = nv; t += dt; w = mul(w, Math.exp(-dt / TAU));
  }
  return { p, v, t };
}

// ---------- 1. Pitches ----------
const REL = v3(-0.55, 16.76, 1.80);          // RHP release point
const PLATE_FRONT = 0.432;
function pitch(name, speedKmh, spinRpm, eff, tiltDeg, sswAccel = 0, sswDeg = 0) {
  // tiltDeg: direction of Magnus force in catcher's view, 0 = straight up, +90 = toward +x (1B side)
  const target = v3(0, PLATE_FRONT, 0.75);
  // aim solver: shoot, measure miss, correct (3 iterations)
  let aim = target;
  let res, v0, w0;
  for (let i = 0; i < 6; i++) {
    const dir = norm(sub(aim, REL));
    v0 = mul(dir, kmh(speedKmh));
    // Magnus force dir f (perp to v): build from tilt. force ∝ w × v  =>  w ∝ v × f
    const up = v3(0, 0, 1);
    const right = norm(cross(mul(dir, -1), up));        // catcher view: right = +x (1B side)
    const upPerp = norm(cross(right, mul(dir, -1)));
    const t = (tiltDeg * Math.PI) / 180;
    const f = add(mul(upPerp, Math.cos(t)), mul(right, Math.sin(t)));
    const wAct = mul(norm(cross(dir, f)), rpm(spinRpm) * eff);
    const wGyro = mul(dir, rpm(spinRpm) * Math.sqrt(Math.max(0, 1 - eff * eff)));
    w0 = add(wAct, wGyro);
    const s = (sswDeg * Math.PI) / 180;
    SSW = mul(add(mul(upPerp, Math.cos(s)), mul(right, Math.sin(s))), sswAccel);
    res = fly(REL, v0, w0, (p) => p.y <= PLATE_FRONT);
    aim = add(aim, sub(target, v3(res.p.x, PLATE_FRONT, res.p.z)));
  }
  SSW = v3(0, 0, 0);
  const noSpin = fly(REL, v0, v3(0, 0, 0), (p) => p.y <= PLATE_FRONT);
  // drag-only reference with same Cd (so the difference is Magnus only)
  const savedCl2 = CL2;
  const dx = (res.p.x - noSpin.p.x) * 100, dz = (res.p.z - noSpin.p.z) * 100;
  console.log(
    `${name.padEnd(10)} ${speedKmh}km/h ${spinRpm}rpm eff${eff}  t=${res.t.toFixed(3)}s  ` +
    `plateSpeed=${(len(res.v) * 3.6).toFixed(1)}km/h (${((len(res.v) / kmh(speedKmh) - 1) * 100).toFixed(1)}%)  ` +
    `move x=${dx.toFixed(1)}cm z=${dz.toFixed(1)}cm  totalDrop=${((REL.z - res.p.z) * 100).toFixed(0)}cm  missAfterSolve=${(len(sub(res.p, v3(0, res.p.y, 0.75))) * 100 - Math.abs(res.p.x) * 0).toFixed(2)}cm`
  );
}
console.log('== 1. Pitch flight (RHP, release 16.76 m, RK4) ==');
pitch('4-seam', 145, 2300, 0.90, -12);
pitch('2-seam', 142, 2150, 0.794, -39.9, 0.9, -115);
pitch('cutter', 138, 2350, 0.50, 25);
pitch('slider', 132, 2400, 0.35, 75);
pitch('sweeper', 128, 2600, 0.60, 85);
pitch('curve', 120, 2500, 0.75, 160);
pitch('changeup', 130, 1750, 0.699, -46.7, 1.0, -110);
pitch('splitter', 132, 1300, 0.49, -17.7, 0.8, -160);

// ---------- 2. Batted ball carry ----------
console.log('\n== 2. Batted ball carry (RK4, from z=1.0 m) ==');
function batted(evKmh, laDeg, spinRpm) {
  const la = (laDeg * Math.PI) / 180;
  const v0 = v3(0, kmh(evKmh) * Math.cos(la), kmh(evKmh) * Math.sin(la));
  const w0 = v3(rpm(spinRpm), 0, 0);       // backspin for +y travel
  const r = fly(v3(0, 0, 1.0), v0, w0, (p) => p.z <= 0, 1 / 500);
  console.log(`EV ${evKmh}km/h LA ${laDeg}° spin ${spinRpm}rpm -> carry ${r.p.y.toFixed(1)} m, hang ${r.t.toFixed(2)} s`);
  return r;
}
batted(160, 28, 2000);
batted(170, 28, 2200);
batted(150, 30, 2200);
batted(145, 20, 1800);
batted(175, 25, 2000);
batted(130, 45, 3000);

// ---------- 3. Bat-ball collision model ----------
console.log('\n== 3. Collision model (pitch 128 km/h at plate, descending 6°, bat 115 km/h, attack +8°) ==');
function collide({ pitchKmh = 128, descentDeg = 6, batKmh = 115, attackDeg = 8, d = 0.0, yawDeg = 0, eA = 0.20, kf = +(process.env.KF ?? 0.55), rBat = 0.033, mem = +(process.env.MEM ?? 0.1) }) {
  const de = (descentDeg * Math.PI) / 180, at = (attackDeg * Math.PI) / 180, yaw = (yawDeg * Math.PI) / 180;
  const vBall = v3(0, -kmh(pitchKmh) * Math.cos(de), -kmh(pitchKmh) * Math.sin(de));
  // bat axis: along x rotated by yaw about z (yaw>0 = barrel ahead = pull side for RHB -> -x)
  const axis = v3(Math.cos(yaw), Math.sin(yaw), 0);
  const fwd = norm(cross(v3(0, 0, 1), axis));               // horizontal normal to bat, toward pitcher at yaw=0
  const vBat = add(mul(fwd, kmh(batKmh) * Math.cos(at)), v3(0, 0, kmh(batKmh) * Math.sin(at)));
  // contact normal: ball centre is offset d above the bat axis; rest of the offset is along swing direction
  const Rsum = R + rBat;
  const sinT = d / Rsum;
  if (Math.abs(sinT) >= 1) return null;
  const n = norm(add(mul(fwd, Math.sqrt(1 - sinT * sinT)), v3(0, 0, sinT)));
  const vRel = sub(vBall, vBat);
  const vn = dot(vRel, n);
  const vRelN = mul(n, vn);
  const vRelT = sub(vRel, vRelN);
  const wBall = v3(-rpm(2000), 0, 0);                       // incoming backspin-ish (travelling -y)
  const u = add(vRelT, mul(cross(wBall, mul(n, -R)), mem));           // slip velocity at the contact point
  const outRel = add(mul(n, -eA * vn), sub(vRelT, mul(u, (2 / 7) * kf)));
  const vOut = add(vBat, outRel);
  const wOut = add(mul(wBall, mem), mul(cross(n, u), ((5 / 7) * kf) / R));
  const ev = len(vOut) * 3.6;
  const la = (Math.atan2(vOut.z, Math.hypot(vOut.x, vOut.y)) * 180) / Math.PI;
  const spray = (Math.atan2(vOut.x, vOut.y) * 180) / Math.PI;  // + = toward 1B side
  const wRpm = (len(wOut) * 60) / (2 * Math.PI);
  return { ev, la, spray, wRpm, vOut, wOut };
}
for (const dcm of [-3, -2, -1, 0, 1, 1.5, 2, 2.5, 3, 4, 5]) {
  const c = collide({ d: dcm / 100 });
  const f = fly(v3(0, 0.6, 0.8), c.vOut, c.wOut, (p) => p.z <= 0, 1 / 500);
  console.log(`d=${String(dcm).padStart(4)}cm  EV ${c.ev.toFixed(0)}km/h  LA ${c.la.toFixed(1)}°  spin ${c.wRpm.toFixed(0)}rpm  carry ${Math.hypot(f.p.x, f.p.y).toFixed(0)}m`);
}
console.log('-- yaw sweep at d=1.5cm --');
for (const yaw of [-40, -20, -10, 0, 10, 20, 40]) {
  const c = collide({ d: 0.015, yawDeg: yaw });
  console.log(`batYaw=${String(yaw).padStart(4)}°  EV ${c.ev.toFixed(0)}km/h  LA ${c.la.toFixed(1)}°  spray ${c.spray.toFixed(1)}°`);
}

// ---------- 4. Rapier: same flight via physics engine + bounce/roll ----------
await RAPIER.init();
console.log('\n== 4. Rapier', RAPIER.version(), '(dt = 1/240, CCD) ==');
function rapierFly(p0, v0, w0, { maxT = 12, log = false, rollDecel = 3.0 } = {}) {
  const world = new RAPIER.World({ x: 0, y: 0, z: -G });
  world.timestep = 1 / 240;
  const ground = world.createCollider(
    RAPIER.ColliderDesc.cuboid(300, 300, 0.5).setTranslation(0, 0, -0.5).setRestitution(0.45).setFriction(0.55)
  );
  const wall = world.createCollider(
    RAPIER.ColliderDesc.cuboid(60, 0.3, 1.3).setTranslation(0, 122.3, 1.3).setRestitution(0.35).setFriction(0.5)
  );
  const body = world.createRigidBody(
    RAPIER.RigidBodyDesc.dynamic().setTranslation(p0.x, p0.y, p0.z).setLinvel(v0.x, v0.y, v0.z).setAngvel(w0).setCcdEnabled(true)
  );
  world.createCollider(
    RAPIER.ColliderDesc.ball(R).setMass(M).setRestitution(0.45).setFriction(0.55)
      .setRestitutionCombineRule(RAPIER.CoefficientCombineRule.Min)
      .setFrictionCombineRule(RAPIER.CoefficientCombineRule.Min),
    body
  );
  let t = 0, first = null, bounces = 0, wasAir = true, wallHit = null, maxZ = 0;
  const marks = {};
  while (t < maxT) {
    const v = body.linvel(), w = body.angvel(), p = body.translation();
    const a = aeroAccel(v, w);
    body.resetForces(true);
    body.addForce({ x: a.x * M, y: a.y * M, z: a.z * M }, true);
    const grounded = p.z < R + 0.004;
    if (grounded && Math.abs(v.z) < 0.6) {
      // rolling resistance: constant deceleration opposite to horizontal velocity
      const hs = Math.hypot(v.x, v.y);
      if (hs > 0.05) body.addForce({ x: (-v.x / hs) * rollDecel * M, y: (-v.y / hs) * rollDecel * M, z: 0 }, true);
    }
    world.step();
    t += world.timestep;
    const q = body.translation(), qv = body.linvel();
    maxZ = Math.max(maxZ, q.z);
    const air = q.z > R + 0.004;
    if (wasAir && !air) { bounces++; if (!first) first = { t, d: Math.hypot(q.x, q.y) }; }
    wasAir = air;
    if (!wallHit && q.y > 121.9 && qv.y < 0) wallHit = { t, z: q.z };
    for (const dist of [20, 30, 40]) if (!marks[dist] && Math.hypot(q.x, q.y) >= dist) marks[dist] = t;
    if (Math.hypot(qv.x, qv.y, qv.z) < 0.3 && !air) break;
  }
  const end = body.translation();
  world.free();
  return { first, bounces, t, rest: Math.hypot(end.x, end.y), wallHit, marks, maxZ };
}
{
  const la = (28 * Math.PI) / 180;
  const ref = fly(v3(0, 0, 1.0), v3(0, kmh(160) * Math.cos(la), kmh(160) * Math.sin(la)), v3(rpm(2000), 0, 0), (p) => p.z <= R, 1 / 1000);
  const r = rapierFly(v3(0, 0, 1.0), v3(0, kmh(160) * Math.cos(la), kmh(160) * Math.sin(la)), v3(rpm(2000), 0, 0));
  console.log(`fly ball 160/28°: RK4 carry ${ref.p.y.toFixed(2)} m @${ref.t.toFixed(2)}s | Rapier first bounce ${r.first.d.toFixed(2)} m @${r.first.t.toFixed(2)}s, wallHit=${JSON.stringify(r.wallHit)}, rest ${r.rest.toFixed(1)} m`);
}
for (const [ev, laDeg] of [[150, -5], [160, 2], [120, -10], [140, 8]]) {
  const la = (laDeg * Math.PI) / 180;
  const r = rapierFly(v3(0, 0.6, 0.8), v3(0, kmh(ev) * Math.cos(la), kmh(ev) * Math.sin(la)), v3(-rpm(1500), 0, 0));
  console.log(`grounder EV ${ev} LA ${laDeg}°: first bounce ${r.first?.d.toFixed(1)} m @${r.first?.t.toFixed(2)}s, t@20m=${r.marks[20]?.toFixed(2)} t@30m=${r.marks[30]?.toFixed(2)} t@40m=${r.marks[40]?.toFixed(2)}, bounces=${r.bounces}, rest ${r.rest.toFixed(0)} m after ${r.t.toFixed(1)}s`);
}
// determinism: same inputs twice -> identical result
{
  const run = () => JSON.stringify(rapierFly(v3(0, 0.6, 0.8), v3(3, kmh(150), -2), v3(-rpm(1500), 30, 10)));
  console.log('deterministic repeat:', run() === run());
}
// throughput: how many physics steps/sec in this environment
{
  const world = new RAPIER.World({ x: 0, y: 0, z: -G });
  world.timestep = 1 / 240;
  world.createCollider(RAPIER.ColliderDesc.cuboid(300, 300, 0.5).setTranslation(0, 0, -0.5));
  const b = world.createRigidBody(RAPIER.RigidBodyDesc.dynamic().setTranslation(0, 0, 1).setLinvel(0, 40, 15).setCcdEnabled(true));
  world.createCollider(RAPIER.ColliderDesc.ball(R).setMass(M), b);
  const t0 = performance.now(); const N = 200000;
  for (let i = 0; i < N; i++) world.step();
  const ms = performance.now() - t0;
  console.log(`throughput: ${(N / (ms / 1000) / 1000).toFixed(0)}k steps/s  (= ${(N / 240 / (ms / 1000)).toFixed(0)}x realtime for one ball)`);
}
