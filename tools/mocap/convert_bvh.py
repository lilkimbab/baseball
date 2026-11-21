"""Converts CMU motion-capture BVH files (the cgspeed / una-dinosauria release) into the
game's joint clips (game/match/joint_clip.gd), for running, stopping and throwing
(docs/13 S12, approved proposals 3 and 4: recorded fielding and running, motion matching).

    python3 tools/mocap/convert_bvh.py <bvh folder> <out folder>

Each clip is turned so the figure starts facing -Z with +X to its right, scaled so its legs
(hip to ankle) are LEG_M long, and run in place: the hips' travel over the ground is taken
out of every joint and kept as the extra joint "Root" (its x and z the distance gone, y 0),
which the motion matcher reads for speed and direction. Joint names are the game's:
Left/Right UpperArm, LowerArm, Hand, HandTip, UpperLeg, LowerLeg, Foot; ThoraxTop and
ThoraxBottom. The CMU data is free to use (mocap.cs.cmu.edu); like the other recorded
motion it stays in content-local/.
"""
import json
import math
import os
import sys

import numpy as np

LEG_M = 0.87
# Game joint <- BVH joint.
MAP = {
    "LeftUpperLeg": "LeftUpLeg", "LeftLowerLeg": "LeftLeg", "LeftFoot": "LeftFoot",
    "RightUpperLeg": "RightUpLeg", "RightLowerLeg": "RightLeg", "RightFoot": "RightFoot",
    "LeftUpperArm": "LeftArm", "LeftLowerArm": "LeftForeArm", "LeftHand": "LeftHand", "LeftHandTip": "LeftFingerBase",
    "RightUpperArm": "RightArm", "RightLowerArm": "RightForeArm", "RightHand": "RightHand", "RightHandTip": "RightFingerBase",
    "ThoraxTop": "Neck", "ThoraxBottom": "Spine",
}


class Joint:
    def __init__(self, name, parent):
        self.name = name
        self.parent = parent
        self.offset = np.zeros(3)
        self.channels = []
        self.children = []


def parse(path):
    with open(path) as f:
        tokens = f.read().split()
    i = 0
    joints = []
    stack = []
    root = None
    while tokens[i] != "MOTION":
        t = tokens[i]
        if t in ("ROOT", "JOINT"):
            j = Joint(tokens[i + 1], stack[-1] if stack else None)
            if j.parent:
                j.parent.children.append(j)
            else:
                root = j
            joints.append(j)
            stack.append(j)
            i += 2
        elif t == "End":
            j = Joint(stack[-1].name + "_end", stack[-1])
            stack[-1].children.append(j)
            stack.append(j)
            i += 2
        elif t == "OFFSET":
            stack[-1].offset = np.array([float(x) for x in tokens[i + 1:i + 4]])
            i += 4
        elif t == "CHANNELS":
            n = int(tokens[i + 1])
            stack[-1].channels = tokens[i + 2:i + 2 + n]
            i += 2 + n
        elif t == "}":
            stack.pop()
            i += 1
        else:
            i += 1
    frames = int(tokens[i + 2])
    frame_time = float(tokens[i + 5])
    data = np.array([float(x) for x in tokens[i + 6:]]).reshape(frames, -1)
    return root, joints, data, frame_time


def rot(axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    if axis == "X":
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    if axis == "Y":
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def positions(root, joints, row):
    """World positions of every joint (and end site) for one frame."""
    out = {}
    col = [0]

    def walk(j, parent_pos, parent_rot):
        pos = parent_pos + parent_rot @ j.offset
        r = parent_rot
        if j.channels:
            vals = row[col[0]:col[0] + len(j.channels)]
            col[0] += len(j.channels)
            local = np.eye(3)
            for ch, v in zip(j.channels, vals):
                if ch.endswith("position"):
                    pos = pos + parent_rot @ (np.array([v if ch[0] == a else 0.0 for a in "XYZ"]))
                else:
                    local = local @ rot(ch[0], v)
            r = parent_rot @ local
        out[j.name] = pos
        for c in j.children:
            walk(c, pos, r)

    walk(root, np.zeros(3), np.eye(3))
    return out


def convert(path, out_dir):
    root, joints, data, frame_time = parse(path)
    frames = [positions(root, joints, row) for row in data]
    first = frames[0]
    # Facing at the start: across the hips is to the right, up is +Y.
    right = first["RightUpLeg"] - first["LeftUpLeg"]
    right[1] = 0.0
    right /= np.linalg.norm(right)
    up = np.array([0.0, 1.0, 0.0])
    forward = np.cross(up, right)
    # Into the game's figure space: +X right, +Y up, -Z forward.
    basis = np.stack([right, up, -forward])
    leg = np.linalg.norm(first["LeftUpLeg"] - first["LeftLeg"]) + np.linalg.norm(first["LeftLeg"] - first["LeftFoot"])
    scale = LEG_M / leg
    start = first["Hips"].copy()
    start[1] = 0.0
    names = list(MAP.keys())
    rows = []
    root_track = []
    lowest = 1e9
    for fr in frames:
        travel = fr["Hips"] - start
        travel[1] = 0.0
        row = []
        for n in names:
            p = basis @ ((fr[MAP[n]] - start - travel) * scale)
            row.extend(p.tolist())
            if n.endswith("Foot"):
                lowest = min(lowest, p[1])
        r = basis @ (travel * scale)
        row.extend([float(r[0]), 0.0, float(r[2])])
        root_track.append(r)
        rows.append(row)
    # Feet on the ground: the lowest the ankles get is the standing ankle height.
    ground = lowest - 0.08
    for row in rows:
        for k in range(len(names)):
            row[k * 3 + 1] -= ground
    name = os.path.splitext(os.path.basename(path))[0]
    distance = float(np.linalg.norm(root_track[-1] - root_track[0]))
    clip = {
        "kind": "locomotion", "side": "R", "source": "CMU %s" % name, "fps": round(1.0 / frame_time, 3),
        "ankle_height": 0.08, "joints": names + ["Root"], "events": {},
        "frames": [[round(v, 4) for v in row] for row in rows],
    }
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, name + ".json"), "w") as f:
        json.dump(clip, f)
    duration = (len(rows) - 1) * frame_time
    print("convert_bvh: %s %d frames %.2f s, went %.1f m (%.1f m/s)" % (name, len(rows), duration, distance, distance / max(duration, 1e-6)))


def main():
    src, out = sys.argv[1], sys.argv[2]
    for f in sorted(os.listdir(src)):
        if f.endswith(".bvh"):
            convert(os.path.join(src, f), out)


main()
