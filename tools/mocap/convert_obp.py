#!/usr/bin/env python3
"""Converts Driveline OpenBiomechanics Project (OBP) trials into joint-position clips.

The game's player figures are driven by joint positions, and OBP's "landmarks" tables are
joint centres per frame, so a trial maps almost directly onto a clip: change the axes to the
figure's space, put the origin under the player, and keep the event times.

    python3 tools/mocap/convert_obp.py list pitch
    python3 tools/mocap/convert_obp.py pitch 3037_2 content-local/animations/pitch/default.json
    python3 tools/mocap/convert_obp.py swing 48_2 content-local/animations/swing/default.json

Input is read from content-local/raw/obp/ ("./dev mocap" downloads it). OBP data is
CC BY-NC-SA 4.0 and may not be used by anyone employed by or associated with a professional
sports organisation; clips made from it stay in content-local/, outside git.

Clip space: metres, +X = the player's right, +Y = up, -Z = the way the player faces at
address (the plate, for both pitcher and batter). The origin is on the ground under the
pitcher's pivot foot, or between the batter's feet.
"""
import csv
import json
import math
import os
import sys

RAW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "content-local", "raw", "obp")
# Height given to the ankle joint of a foot standing flat. The lab's zero height is not a
# dependable ground level, so the ground is taken to be this far below a standing ankle.
ANKLE_HEIGHT = 0.08
LICENCE = "Derived from the Driveline OpenBiomechanics Project (openbiomechanics.org), CC BY-NC-SA 4.0. Non-commercial use only."

# Clip joint -> OBP column stem. Pitching tables name limbs by role (throwing arm, lead leg),
# so the side they belong to depends on the throwing hand. "A" is the throwing/pivot side.
PITCH_JOINTS = {
    "AUpperArm": "shoulder_jc", "ALowerArm": "elbow_jc", "AHand": "wrist_jc", "AHandTip": "hand_jc",
    "BUpperArm": "glove_shoulder_jc", "BLowerArm": "glove_elbow_jc", "BHand": "glove_wrist_jc", "BHandTip": "glove_hand_jc",
    "AUpperLeg": "rear_hip", "ALowerLeg": "rear_knee_jc", "AFoot": "rear_ankle_jc",
    "BUpperLeg": "lead_hip", "BLowerLeg": "lead_knee_jc", "BFoot": "lead_ankle_jc",
    "ThoraxTop": "thorax_prox", "ThoraxBottom": "thorax_dist", "ThoraxRight": "thorax_ap",
}
SWING_JOINTS = {
    "RightUpperArm": "rsjc", "RightLowerArm": "rejc", "RightHand": "rwjc", "RightHandTip": "rhjc",
    "LeftUpperArm": "lsjc", "LeftLowerArm": "lejc", "LeftHand": "lwjc", "LeftHandTip": "lhjc",
    "RightUpperLeg": "right_hip", "RightLowerLeg": "rkjc", "RightFoot": "rajc",
    "LeftUpperLeg": "left_hip", "LeftLowerLeg": "lkjc", "LeftFoot": "lajc",
    "ThoraxTop": "thorax_prox", "ThoraxBottom": "thorax_dist", "ThoraxRight": "thorax_ap",
    # The hands' point on the handle and the barrel's sweet spot, from the bat sensor.
    "BatGrip": "blast_hand", "BatSweetSpot": "sweet_spot",
}


def read_trial(kind, trial):
    """Rows of one trial from the landmarks table, as dicts of floats (None where missing)."""
    path = os.path.join(RAW, "pitching" if kind == "pitch" else "hitting", "landmarks.csv")
    rows = []
    with open(path, newline="") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        for row in reader:
            if row[0] != trial:
                if rows:
                    break
                continue
            values = {}
            for name, cell in zip(header[1:], row[1:]):
                try:
                    values[name] = float(cell)
                except ValueError:
                    values[name] = None
            rows.append(values)
    if not rows:
        sys.exit("trial %s not found in %s" % (trial, path))
    return rows


def point(row, stem):
    x, y, z = row.get(stem + "_x"), row.get(stem + "_y"), row.get(stem + "_z")
    return None if x is None or y is None or z is None else (x, y, z)


def median(values):
    ordered = sorted(values)
    return ordered[len(ordered) // 2]


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def side_of(kind, trial):
    """'R' or 'L': the throwing hand, or the side of the plate the batter stands on."""
    name, key, column = ("pitching_poi_metrics.csv", "session_pitch", "p_throws") if kind == "pitch" \
        else ("hitting_metadata.csv", "session_swing", "hitter_side")
    with open(os.path.join(RAW, name), newline="") as handle:
        for row in csv.DictReader(handle):
            if row[key] == trial:
                return row[column].strip().upper()[:1] or "R"
    return "R"


def speeds(track, dt, window):
    """Fastest joint speed (m/s) over `window` frames, per frame."""
    out = []
    for i in range(len(track)):
        j = min(i + window, len(track) - 1)
        if j == i:
            out.append(out[-1] if out else 0.0)
            continue
        out.append(max(math.dist(a, b) for a, b in zip(track[i], track[j])) / ((j - i) * dt))
    return out


def mirrored_name(name):
    if name.startswith("Right"):
        return "Left" + name[5:]
    if name.startswith("Left"):
        return "Right" + name[4:]
    return name


def convert(kind, trial, out_path, start=None, mirror_left=True):
    """A left-handed trial is stored as its mirror image, a right-handed motion ("side": "R",
    "original_side": "L"): the game shows a left-hander on a mirrored figure, so the motion
    on screen is the left-hander's own. Figures, bats and grips then only ever deal with one
    hand."""
    rows = read_trial(kind, trial)
    side = side_of(kind, trial)
    stems = PITCH_JOINTS if kind == "pitch" else SWING_JOINTS
    if kind == "pitch":
        own, other = ("Right", "Left") if side == "R" else ("Left", "Right")
        names = [n.replace("A", own, 1) if n[0] == "A" else n.replace("B", other, 1) if n[0] == "B" and n[1].isupper() else n for n in stems]
    else:
        names = list(stems)
    column = dict(zip(names, stems.values()))
    # The time column is rounded to four places, so one step (0.0028) is not the frame time:
    # over two seconds it would put the events several frames out. Use the whole span.
    dt = (rows[-1]["time"] - rows[0]["time"]) / (len(rows) - 1)
    time0 = rows[0]["time"]

    # Missing samples repeat the last good one.
    last = {}
    lab = []
    for row in rows:
        frame = {}
        for name in names:
            p = point(row, column[name]) or last.get(name) or (0.0, 0.0, 0.0)
            last[name] = p
            frame[name] = p
        lab.append(frame)

    # Ground and origin, from the first second: under the pivot ankle for a pitcher, between
    # the ankles for a batter.
    settle = lab[:max(int(1.0 / dt), 30)]
    lead_foot = ("Left" if side == "R" else "Right") + "Foot"
    rear_foot = ("Right" if side == "R" else "Left") + "Foot"
    if kind == "pitch":
        ox = median([f[rear_foot][0] for f in settle])
        oy = median([f[rear_foot][1] for f in settle])
        oz = median([f[rear_foot][2] for f in settle]) - ANKLE_HEIGHT
    else:
        ox = (median([f[lead_foot][0] for f in settle]) + median([f[rear_foot][0] for f in settle])) * 0.5
        oy = (median([f[lead_foot][1] for f in settle]) + median([f[rear_foot][1] for f in settle])) * 0.5
        oz = min(median([f[lead_foot][2] for f in settle]), median([f[rear_foot][2] for f in settle])) - ANKLE_HEIGHT

    def to_clip(p):
        x, y, z = p[0] - ox, p[1] - oy, p[2] - oz
        if kind == "pitch":
            # Lab: +x toward the plate, +y to the pitcher's left as he faces it, +z up.
            return (-y, z, -x)
        # Lab: +x toward the pitcher, +y toward the third-base side, +z up. A right-handed
        # batter faces -y (the plate) with the pitcher on his left.
        return (-x, z, y) if side == "R" else (x, z, -y)

    track = []
    for frame in lab:
        # thorax_ap is a point 0.1 m along the ribcage's side-to-side axis. Make sure it is
        # stored on the right-hand side whichever way the table has it.
        top, lateral = frame["ThoraxTop"], sub(frame["ThoraxRight"], frame["ThoraxTop"])
        if dot(lateral, sub(frame["RightUpperArm"], frame["LeftUpperArm"])) < 0.0:
            frame["ThoraxRight"] = sub(top, lateral)
        track.append([to_clip(frame[name]) for name in names])

    def event(col):
        value = rows[0].get(col)
        return None if value is None else value - time0

    speed = speeds(track, dt, max(int(0.1 / dt), 1))
    events = {}
    if kind == "pitch":
        for name, col in (("knee_peak", "pkh_time"), ("foot_plant", "fp_100_time"), ("max_layback", "MER_time"), ("release", "BR_time")):
            if event(col) is not None:
                events[name] = event(col)
        if start is None:
            # Begin at the last quiet moment before the leg lift, so the clip opens on the set
            # position instead of on whatever the pitcher did before coming set.
            start = 0.0
            limit = int((events.get("knee_peak", 0.0) - 0.3) / dt)
            for i in range(max(limit, 0), -1, -1):
                if speed[i] < 0.15:
                    start = i * dt
                    break
    else:
        for name, col in (("foot_plant", "fp_100_time"), ("contact", "contact_time")):
            if event(col) is not None:
                events[name] = event(col)
        start = start or 0.0
        contact = int(events["contact"] / dt)
        lead = names.index(lead_foot)
        grip = names.index("BatGrip")
        sweet = names.index("BatSweetSpot")
        standing = median([f[lead][1] for f in track[:int(1.0 / dt)]])
        step = max(int(0.02 / dt), 1)
        # Stride: a little before the front foot last leaves the ground ahead of the swing.
        plant = int(events.get("foot_plant", events["contact"]) / dt)
        lifted = max(range(plant), key=lambda i: track[i][lead][1])
        stride = lifted
        while stride > 0 and track[stride][lead][1] - standing > 0.03:
            stride -= 1
        events["stride"] = max(stride * dt - 0.12, 0.0)
        # Launch: the last moment before contact at which the hands were still slow.
        launch = contact
        while launch > step and math.dist(track[launch][grip], track[launch - step][grip]) / (step * dt) > 2.0:
            launch -= 1
        events["launch"] = launch * dt
        # Finish: the barrel has wrapped around and all but stopped.
        finish = contact
        while finish < len(track) - step - 1 and math.dist(track[finish + step][sweet], track[finish][sweet]) / (step * dt) > 3.0:
            finish += 1
        events["finish"] = finish * dt

    original_side = side
    if mirror_left and side == "L":
        order = [names.index(mirrored_name(n)) for n in names]
        mirrored = []
        for frame in track:
            flipped = [(-p[0], p[1], p[2]) for p in frame]
            mirrored.append([flipped[order[i]] for i in range(len(names))])
        track = mirrored
        # ThoraxRight is a point on the right of the ribcage: keep it there.
        top_i, right_i = names.index("ThoraxTop"), names.index("ThoraxRight")
        ra, la = names.index("RightUpperArm"), names.index("LeftUpperArm")
        for frame in track:
            lateral = sub(frame[right_i], frame[top_i])
            if dot(lateral, sub(frame[ra], frame[la])) < 0.0:
                frame[right_i] = sub(frame[top_i], lateral)
        side = "R"

    first = int(round(start / dt))
    track = track[first:]
    events = {name: round(t - first * dt, 4) for name, t in events.items()}
    frames = [[round(v, 4) for p in frame for v in p] for frame in track]

    clip = {
        "format": 1, "kind": kind, "side": side, "original_side": original_side, "fps": round(1.0 / dt, 3),
        "duration": round((len(frames) - 1) * dt, 4), "ankle_height": ANKLE_HEIGHT,
        "source": "OBP %s %s" % ("pitching" if kind == "pitch" else "hitting", trial),
        "licence": LICENCE, "events": events, "joints": names, "frames": frames,
    }
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w") as handle:
        json.dump(clip, handle, separators=(",", ":"))
    print("convert_obp: %s -> %s (%s, %d frames, %.2f s from %.2f s, events %s)" % (
        trial, out_path, side, len(frames), clip["duration"], first * dt, events))


def list_trials(kind):
    """Prints the trials sorted by pitch speed or exit velocity, fastest first."""
    name, key, speed, side = ("pitching_poi_metrics.csv", "session_pitch", "pitch_speed_mph", "p_throws") if kind == "pitch" \
        else ("hitting_poi_metrics.csv", "session_swing", "exit_velo_mph_x", None)
    sides = {}
    if kind == "swing":
        with open(os.path.join(RAW, "hitting_metadata.csv"), newline="") as handle:
            sides = {r["session_swing"]: r["hitter_side"] for r in csv.DictReader(handle)}
    found = []
    with open(os.path.join(RAW, name), newline="") as handle:
        for row in csv.DictReader(handle):
            try:
                found.append((float(row[speed]), row[key], row[side] if side else sides.get(row[key], "?")))
            except (ValueError, KeyError):
                pass
    found.sort(reverse=True)
    for mph, trial, hand in found[:15]:
        print("%-10s %s  %.1f mph (%.0f km/h)" % (trial, hand, mph, mph * 1.609))
    print("... %d trials" % len(found))


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "list":
        list_trials(sys.argv[2])
    elif len(sys.argv) >= 4 and sys.argv[1] in ("pitch", "swing"):
        convert(sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else None)
    else:
        sys.exit(__doc__)
