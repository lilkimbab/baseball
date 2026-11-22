"""Gives roster packs already built (and calibrated) the names their season's tables now carry —
real-like club and player names (names.py; the user, 2026-11-22) — without building and
calibrating them again: names do not change a rating. Reads content-local/raw/kbo-<season>/
{teams,players}.csv and rewrites content-local/rosters/kbo-<season>.json in place.

    python3 tools/kbo/rename_packs.py [season ...]   (default: every kbo-*.json roster pack)
"""
import csv
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    rosters = os.path.join(ROOT, "content-local", "rosters")
    seasons = sys.argv[1:] or sorted(os.path.basename(p)[4:-5] for p in glob.glob(os.path.join(rosters, "kbo-*.json")))
    for season in seasons:
        raw = os.path.join(ROOT, "content-local", "raw", "kbo-" + season)
        pack_path = os.path.join(rosters, "kbo-%s.json" % season)
        if not (os.path.exists(pack_path) and os.path.exists(os.path.join(raw, "players.csv"))):
            print("rename_packs: %s skipped (no pack or tables)" % season)
            continue
        players = {r["id"]: r["name"] for r in csv.DictReader(open(os.path.join(raw, "players.csv"), encoding="utf-8"))}
        teams = {r["id"]: r for r in csv.DictReader(open(os.path.join(raw, "teams.csv"), encoding="utf-8"))}
        pack = json.load(open(pack_path, encoding="utf-8"))
        pack["name"] = "%s 시즌" % season
        changed = 0
        for t in pack.get("teams", []):
            row = teams.get(t.get("id"))
            if row:
                t["name"] = row["name"]
                t["short"] = row["short"]
        for p in pack.get("players", []):
            if p.get("id") in players and p.get("name") != players[p["id"]]:
                p["name"] = players[p["id"]]
                changed += 1
        for t in pack.get("teams", []):
            for p in t.get("players", []):
                if isinstance(p, dict) and p.get("id") in players and p.get("name") != players[p["id"]]:
                    p["name"] = players[p["id"]]
                    changed += 1
        with open(pack_path, "w", encoding="utf-8") as f:
            json.dump(pack, f, ensure_ascii=False, indent=1)
        print("rename_packs: %s — %d names" % (season, changed))


if __name__ == "__main__":
    main()
