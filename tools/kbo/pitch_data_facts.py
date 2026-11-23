"""What the pitch table says, to set beside tools/pitch_data_report.gd (queue stage 3): the
league's OPS against the same and the other hand, and the pitchers' fastball share when the
count is even, when they are ahead and when behind (each pitcher counted once).

    .tools/pyenv/bin/python -I tools/kbo/pitch_data_facts.py 2025
"""
import csv
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    season = sys.argv[1] if len(sys.argv) > 1 else "2025"
    raw = os.path.join(ROOT, "content-local", "raw", "kbo-" + season)
    bats = {r["id"]: r["bats"] for r in csv.DictReader(open(os.path.join(raw, "players.csv"), encoding="utf-8"))}
    total = {"same": [0, 0.0], "other": [0, 0.0]}
    for r in csv.DictReader(open(os.path.join(raw, "splits.csv"), encoding="utf-8")):
        b = bats.get(r["id"], "S")
        if b == "S":
            continue
        for hand in ("l", "r"):
            pa = int(r["pa_" + hand])
            side = "same" if hand.upper() == b else "other"
            total[side][0] += pa
            total[side][1] += pa * float(r["ops_" + hand])
    for side in ("same", "other"):
        print("pitch_data_facts: OPS against the %s hand %.3f (%d PA)" % (side, total[side][1] / max(total[side][0], 1), total[side][0]))
    types = json.load(open(os.path.join(ROOT, "game", "data", "pitch_types.json"), encoding="utf-8"))
    entries = types["types"] if isinstance(types, dict) and "types" in types else types
    family = {str(t["id"]): str(t.get("family", "")) for t in entries}
    shares = {"even": [], "ahead": [], "behind": []}
    per = {}
    for r in csv.DictReader(open(os.path.join(raw, "pitches.csv"), encoding="utf-8")):
        if not r.get("usage_even"):
            continue
        p = per.setdefault(r["id"], {"even": 0.0, "ahead": 0.0, "behind": 0.0})
        if family.get(r["type"], "") == "fastball":
            for b in shares:
                p[b] += float(r["usage_" + b])
    for pid, p in per.items():
        for b in shares:
            shares[b].append(p[b])
    for b in ("even", "ahead", "behind"):
        print("pitch_data_facts: fastballs when %s: %.1f%%" % (b, 100.0 * sum(shares[b]) / max(len(shares[b]), 1)))


main()
