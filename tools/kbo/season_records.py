"""Puts each player's real line for the pack's season into the local roster packs, for what the
park's scoreboard and the broadcast's cards show (the user, 2026-11-23: "the scoreboard shows
that season's numbers, not the overall rating, as a KBO park's does").

    python3 -I tools/kbo/season_records.py            # every content-local/rosters/kbo-*.json

From the Kaggle season tables in content-local/raw/kaggle-kbo-stats (a man traded during the
season has a row for each club: they are added up). A batter gets games, plate appearances, at-bats,
average, home runs, runs batted in, hits, steals, on-base, slugging and OPS; a pitcher games, wins, losses, saves,
holds, ERA, strikeouts and innings. Written as each player's "record" (RosterIO); the packs stay
in content-local.
"""
import csv
import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STATS = os.path.join(ROOT, "content-local", "raw", "kaggle-kbo-stats")


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return 0.0


def outs_of(ip):
    """'123.1' (an inning and a third) -> 370 outs; Kaggle writes thirds as .1 and .2 or as 1/3."""
    s = str(ip).strip()
    if " " in s:
        whole, frac = s.split(" ", 1)
        thirds = {"1/3": 1, "2/3": 2}.get(frac.strip(), 0)
        return int(num(whole)) * 3 + thirds
    if "." in s:
        whole, frac = s.split(".", 1)
        return int(num(whole)) * 3 + min(int(num(frac[:1])), 2)
    return int(num(s)) * 3


def season_rows(path, season):
    rows = {}
    with open(path, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if str(r.get("Season", "")).strip() != str(season):
                continue
            rows.setdefault("kbo" + r["Id"], []).append(r)
    return rows


def batting_record(rows, season):
    t = {k: sum(num(r.get(k)) for r in rows) for k in ("G", "PA", "AB", "H", "2B", "3B", "HR", "TB", "RBI", "SB", "BB", "HBP", "SF", "SO")}
    if t["PA"] <= 0:
        return None
    avg = t["H"] / t["AB"] if t["AB"] > 0 else 0.0
    obp_den = t["AB"] + t["BB"] + t["HBP"] + t["SF"]
    obp = (t["H"] + t["BB"] + t["HBP"]) / obp_den if obp_den > 0 else 0.0
    tb = t["TB"] if t["TB"] > 0 else t["H"] + t["2B"] + 2 * t["3B"] + 3 * t["HR"]
    slg = tb / t["AB"] if t["AB"] > 0 else 0.0
    return {"year": int(season), "g": int(t["G"]), "pa": int(t["PA"]), "ab": int(t["AB"]), "avg": round(avg, 3), "hr": int(t["HR"]), "rbi": int(t["RBI"]),
            "h": int(t["H"]), "sb": int(t["SB"]), "obp": round(obp, 3), "slg": round(slg, 3), "ops": round(obp + slg, 3)}


def pitching_record(rows, season):
    outs = sum(outs_of(r.get("IP")) for r in rows)
    t = {k: sum(num(r.get(k)) for r in rows) for k in ("G", "W", "L", "SV", "HLD", "SO", "ER")}
    if t["G"] <= 0:
        return None
    era = t["ER"] * 27.0 / outs if outs > 0 else 0.0
    return {"year": int(season), "g": int(t["G"]), "w": int(t["W"]), "l": int(t["L"]), "sv": int(t["SV"]), "hld": int(t["HLD"]),
            "era": round(era, 2), "so": int(t["SO"]), "outs": int(outs)}


def main():
    packs = sorted(glob.glob(os.path.join(ROOT, "content-local", "rosters", "kbo-*.json")))
    for path in packs:
        with open(path, encoding="utf-8") as f:
            pack = json.load(f)
        season = pack.get("season")
        if not season:
            continue
        bat = season_rows(os.path.join(STATS, "kbo_batting_stats_season_1982-2026.csv"), season)
        pit = season_rows(os.path.join(STATS, "kbo_pitching_stats_season_1982-2026.csv"), season)
        given = 0
        for p in pack.get("players", []):
            pitcher = any(code in ("SP", "RP", "P") for code in p.get("positions", {}))
            rec = pitching_record(pit[p["id"]], season) if pitcher and p["id"] in pit else None
            if rec is None and p["id"] in bat:
                rec = batting_record(bat[p["id"]], season)
            if rec is not None:
                p["record"] = rec
                given += 1
            else:
                p.pop("record", None)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(pack, f, ensure_ascii=False, indent=1)
        print("season_records: %s %s: %d of %d players" % (os.path.basename(path), season, given, len(pack.get("players", []))))


main()
