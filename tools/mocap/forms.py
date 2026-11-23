#!/usr/bin/env python3
"""Picks the game's pitching and batting forms from the OBP trials.

    python3 tools/mocap/forms.py            (./dev mocap forms)

Pitching: every trial is measured — the arm's angle at release (the line from the throwing
shoulder to the hand, seen by the catcher, against the horizontal), how high the front knee
comes up, the tempo from the top of the leg lift to release — and only trials that start
before the leg lift are used (at least 0.6 s of the delivery before the knee is highest). One
trial per pitcher, his fastest. Twenty are kept: four overhand (52° and up), twelve
three-quarter (33-52°, those nearest 44° first), four low three-quarter and sidearm (under
33°), spread over leg lift and tempo within each, with left-handers among them (their own
trials, not mirrored). The recorded pitchers' arms are low (half of them under 35°; a
professional's is about 45° on average), and taking every slot evenly made most of the
game's pitchers look sidearm: "팔각도가 이상하다" (2026-11-22).

Batting: every swing is measured — how high the hands are at address against the batter's
height, how far the front foot comes up before it lands (a leg kick, a toe tap or no stride),
and how high the barrel meets the ball. One swing per batter. Twenty are kept, spread over
stance and stride, with left-handed batters among them. For each batting form the same
batter's swings at the highest and lowest contact are kept too ("<id>_high", "<id>_low"), to
blend by pitch height in the game (S10-3).

Writes the clips to content-local/animations/{pitch,swing}/<id>.json and the catalogues to
content-local/forms/{pitch,swing}.json. All of it stays in content-local/: OBP is CC BY-NC-SA.
"""
import csv
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import convert_obp  # noqa: E402

ROOT = os.path.join(HERE, "..", "..")
RAW = convert_obp.RAW
OUT_ANIM = os.path.join(ROOT, "content-local", "animations")
OUT_FORMS = os.path.join(ROOT, "content-local", "forms")
PRE_ROLL = 0.6
# Trials that failed the game's motion check (tools/motion_report.gd --forms): left out.
EXCLUDE = os.path.join(ROOT, "content-local", "forms", "exclude.txt")


def excluded():
    if not os.path.exists(EXCLUDE):
        return set()
    with open(EXCLUDE) as handle:
        return set(line.strip() for line in handle if line.strip())
PITCH_COUNTS = {"overhand": 4, "three_quarter": 12, "sidearm": 4}
# The arm angle the three-quarter forms are taken nearest to.
THREE_QUARTER_MIDDLE = 44.0
LEFT_PITCHERS = 4
SWING_COUNT = 20
LEFT_BATTERS = 6


def rows_by_trial(path):
    """Yields (trial, header index, rows) for each trial of a landmarks table."""
    with open(path, newline="") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        idx = {name: i for i, name in enumerate(header)}
        current, rows = None, []
        for row in reader:
            if row[0] != current:
                if rows:
                    yield current, idx, rows
                current, rows = row[0], []
            rows.append(row)
        if rows:
            yield current, idx, rows


def value(row, idx, name):
    try:
        return float(row[idx[name]])
    except (KeyError, ValueError, IndexError):
        return None


def read_table(name, key):
    with open(os.path.join(RAW, name), newline="") as handle:
        return {r[key]: r for r in csv.DictReader(handle)}


def spread(items, count, key):
    """`count` items spread evenly over the order of `key`."""
    ordered = sorted(items, key=key)
    if len(ordered) <= count:
        return ordered
    step = (len(ordered) - 1) / max(count - 1, 1)
    picked = []
    for i in range(count):
        picked.append(ordered[round(i * step)])
    return picked


# --- Pitching ---


def pitch_metrics():
    poi = read_table("pitching_poi_metrics.csv", "session_pitch")
    out = {}
    for trial, idx, rows in rows_by_trial(os.path.join(RAW, "pitching", "landmarks.csv")):
        release = value(rows[0], idx, "BR_time")
        peak = value(rows[0], idx, "pkh_time")
        start = value(rows[0], idx, "time")
        if release is None or peak is None or trial not in poi:
            continue
        at = min(rows, key=lambda r: abs((value(r, idx, "time") or 0.0) - release))
        s = [value(at, idx, "shoulder_jc_" + a) for a in "xyz"]
        h = [value(at, idx, "hand_jc_" + a) for a in "xyz"]
        if None in s or None in h:
            continue
        angle = math.degrees(math.atan2(h[2] - s[2], abs(h[1] - s[1])))
        knees = [value(r, idx, "lead_knee_jc_z") for r in rows]
        knees = [k for k in knees if k is not None]
        try:
            speed = float(poi[trial]["pitch_speed_mph"])
        except ValueError:
            speed = 0.0
        out[trial] = {
            "trial": trial, "pitcher": trial.split("_")[0], "hand": poi[trial]["p_throws"].strip()[:1] or "R",
            "arm_angle": round(angle, 1), "leg_lift": round(max(knees) - knees[0], 3) if knees else 0.0,
            "tempo": round(release - peak, 3), "pre_roll": round(peak - start, 3), "mph": speed,
        }
    return out


def slot_of(angle):
    if angle >= 52.0:
        return "overhand"
    if angle >= 33.0:
        return "three_quarter"
    return "sidearm"


def pick_pitches(metrics):
    best = {}
    skip = excluded()
    for m in metrics.values():
        if m["pre_roll"] < PRE_ROLL or m["trial"] in skip:
            continue
        b = best.get(m["pitcher"])
        if b is None or m["mph"] > b["mph"]:
            best[m["pitcher"]] = m
    pitchers = list(best.values())
    for m in pitchers:
        m["slot"] = slot_of(m["arm_angle"])
    chosen = []
    for slot, count in PITCH_COUNTS.items():
        pool = [m for m in pitchers if m["slot"] == slot]
        if slot == "three_quarter":
            # The common arm, not the edges of the class.
            pool.sort(key=lambda m: abs(m["arm_angle"] - THREE_QUARTER_MIDDLE))
            pool = pool[: max(count * 2, count + 4)]
        lefties = [m for m in pool if m["hand"] == "L"]
        # Left-handers first, about their share, then the rest spread over lift and tempo.
        want_left = min(len(lefties), max(1, round(count * LEFT_PITCHERS / 20.0)))
        take = spread(lefties, want_left, lambda m: (m["leg_lift"], m["tempo"]))
        rest = [m for m in pool if m not in take]
        take += spread(rest, count - len(take), lambda m: (m["leg_lift"], m["tempo"]))
        chosen += take
    # A slot with too few pitchers leaves room for more of the others.
    left = [m for m in pitchers if m not in chosen]
    if len(chosen) < sum(PITCH_COUNTS.values()) and left:
        chosen += spread(left, sum(PITCH_COUNTS.values()) - len(chosen), lambda m: (m["arm_angle"], m["leg_lift"]))
    return chosen


def pitch_name(m):
    slot = {"overhand": "오버핸드", "three_quarter": "스리쿼터", "sidearm": "사이드암"}[m["slot"]]
    lift = "하이 킥" if m["leg_lift"] >= 0.7 else ("낮은 킥" if m["leg_lift"] < 0.5 else "보통 킥")
    tempo = "빠른 템포" if m["tempo"] < 0.8 else ("느린 템포" if m["tempo"] >= 1.0 else "보통 템포")
    return "%s %s · %s · %s" % ("좌완" if m["hand"] == "L" else "우완", slot, lift, tempo)


# --- Batting ---


def swing_metrics():
    meta = read_table("hitting_metadata.csv", "session_swing")
    out = {}
    for trial, idx, rows in rows_by_trial(os.path.join(RAW, "hitting", "landmarks.csv")):
        contact = value(rows[0], idx, "contact_time")
        if contact is None or trial not in meta:
            continue
        side = meta[trial]["hitter_side"].strip()[:1] or "R"
        lead = "lajc_z" if side == "R" else "rajc_z"
        t0 = value(rows[0], idx, "time")
        before = [r for r in rows if (value(r, idx, "time") or 0.0) - t0 <= contact - t0]
        feet = [value(r, idx, lead) for r in before]
        feet = [f for f in feet if f is not None]
        hands = [value(r, idx, "lwjc_z") for r in rows[:60]]
        hands = [x for x in hands if x is not None]
        at = min(rows, key=lambda r: abs((value(r, idx, "time") or 0.0) - contact))
        sweet = value(at, idx, "sweet_spot_z")
        try:
            height = float(meta[trial]["session_height_in"]) * 0.0254
        except ValueError:
            height = 1.83
        if not feet or not hands or sweet is None:
            continue
        stand = sorted(feet[: max(len(feet) // 4, 1)])[len(feet[: max(len(feet) // 4, 1)]) // 2]
        out[trial] = {
            "trial": trial, "batter": meta[trial]["session"], "hand": side,
            "hands": round(sum(hands) / len(hands) / height, 3), "stride": round(max(feet) - stand, 3),
            "contact": round(sweet, 3), "speed": float(meta[trial].get("blast_bat_speed_mph_x") or 0.0),
        }
    return out


def stride_kind(m):
    if m["stride"] >= 0.12:
        return "leg_kick"
    if m["stride"] >= 0.04:
        return "toe_tap"
    return "no_stride"


def pick_swings(metrics):
    by_batter = {}
    skip = excluded()
    for m in metrics.values():
        if m["trial"] in skip:
            continue
        by_batter.setdefault(m["batter"], []).append(m)
    batters = []
    for swings in by_batter.values():
        if len(swings) < 2:
            continue
        main = max(swings, key=lambda m: m["speed"])
        main = dict(main)
        main["high"] = max(swings, key=lambda m: m["contact"])["trial"]
        main["low"] = min(swings, key=lambda m: m["contact"])["trial"]
        main["stride_kind"] = stride_kind(main)
        batters.append(main)
    lefties = [m for m in batters if m["hand"] == "L"]
    take = spread(lefties, min(LEFT_BATTERS, len(lefties)), lambda m: (m["stride"], m["hands"]))
    rest = [m for m in batters if m not in take]
    # Every kind of stride, then spread over stance.
    for kind in ("leg_kick", "toe_tap", "no_stride"):
        pool = [m for m in rest if m["stride_kind"] == kind and m not in take]
        if pool and not any(m["stride_kind"] == kind for m in take):
            take.append(max(pool, key=lambda m: m["speed"]))
    rest = [m for m in batters if m not in take]
    take += spread(rest, SWING_COUNT - len(take), lambda m: (m["stride"], m["hands"]))
    return take[:SWING_COUNT]


def swing_name(m):
    stance = "높은 자세" if m["hands"] >= 0.80 else ("낮은 자세" if m["hands"] < 0.76 else "보통 자세")
    stride = {"leg_kick": "레그 킥", "toe_tap": "토 탭", "no_stride": "노 스트라이드"}[m["stride_kind"]]
    return "%s · %s · %s" % ("좌타" if m["hand"] == "L" else "우타", stance, stride)


def note_failures():
    """Adds the trials behind the forms the last motion check failed to the excluded list."""
    failing = os.path.join(OUT_FORMS, "failing.txt")
    if not os.path.exists(failing):
        return 0
    with open(failing) as handle:
        ids = [line.strip() for line in handle if line.strip()]
    trials = []
    for kind in ("pitch", "swing"):
        path = os.path.join(OUT_FORMS, kind + ".json")
        if not os.path.exists(path):
            continue
        with open(path) as handle:
            for f in json.load(handle)["forms"]:
                if f["id"] in ids or any(i.startswith(f["id"] + "_") for i in ids):
                    # "OBP pitching 2916_4" or "OBP hitting 48_2 (high 48_5, low 48_1)"
                    words = f["source"].replace("(", " ").replace(")", " ").replace(",", " ").split()
                    trials += [w for w in words if "_" in w]
    with open(EXCLUDE, "a") as handle:
        for t in trials:
            handle.write(t + "\n")
    os.remove(failing)
    return len(trials)


def main():
    os.makedirs(OUT_FORMS, exist_ok=True)
    added = note_failures()
    if added:
        print("forms: %d trials left out after the motion check" % added)
    pitches = pick_pitches(pitch_metrics())
    catalog = []
    for i, m in enumerate(pitches):
        form = "p%02d" % (i + 1)
        convert_obp.convert("pitch", m["trial"], os.path.join(OUT_ANIM, "pitch", form + ".json"))
        catalog.append({"id": form, "name": pitch_name(m), "hand": m["hand"], "slot": m["slot"],
                        "arm_angle": m["arm_angle"], "leg_lift": m["leg_lift"], "tempo": m["tempo"],
                        "source": "OBP pitching %s" % m["trial"]})
    with open(os.path.join(OUT_FORMS, "pitch.json"), "w") as handle:
        json.dump({"format": 1, "licence": convert_obp.LICENCE, "forms": catalog}, handle, ensure_ascii=False, indent=1)
    swings = pick_swings(swing_metrics())
    catalog = []
    for i, m in enumerate(swings):
        form = "b%02d" % (i + 1)
        convert_obp.convert("swing", m["trial"], os.path.join(OUT_ANIM, "swing", form + ".json"))
        convert_obp.convert("swing", m["high"], os.path.join(OUT_ANIM, "swing", form + "_high.json"))
        convert_obp.convert("swing", m["low"], os.path.join(OUT_ANIM, "swing", form + "_low.json"))
        catalog.append({"id": form, "name": swing_name(m), "hand": m["hand"], "stride": m["stride_kind"],
                        "hands": m["hands"], "stride_height": m["stride"], "contact": m["contact"],
                        "source": "OBP hitting %s (high %s, low %s)" % (m["trial"], m["high"], m["low"])})
    with open(os.path.join(OUT_FORMS, "swing.json"), "w") as handle:
        json.dump({"format": 1, "licence": convert_obp.LICENCE, "forms": catalog}, handle, ensure_ascii=False, indent=1)
    print("forms: %d pitching (%d left-handed), %d batting (%d left-handed)" % (
        len(pitches), sum(1 for m in pitches if m["hand"] == "L"), len(swings), sum(1 for m in swings if m["hand"] == "L")))


if __name__ == "__main__":
    main()
