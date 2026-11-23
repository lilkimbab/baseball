"""Each real pitcher's pitches for a season of the local content pack: which he throws, how
often, and how hard (the user, 2026-11-23: the real men's real pitches, renamed as they are).
From a season's pitch-by-pitch table in content-local/raw/kbo-pbp/ (one row a pitch: the
pitcher's name and club, the pitch's type and speed), into the roster builder's optional table:

    content-local/raw/kbo-<season>/pitches.csv     id, type, usage, velo, usage_even,
                                                   usage_ahead, usage_behind  (build_roster)
    content-local/raw/kbo-<season>/splits.csv      id, pa_l, ops_l, pa_r, ops_r (build_roster)

    python3 -I tools/kbo/pitch_mix.py 2026

A pitcher is matched to the season's tables (players.csv: ids from the records, real names
kept in the dataset's rows) by his name and club, else by his name alone when only one has it.
A pitch he threw less than MIN_SHARE of the time, or fewer than MIN_PITCHES times, is left
out; six at most. The table's types are as broadcasters call them; where it has one name for
two pitches (a curve or a knuckle curve, a changeup or a circle change) a hard curve is a
knuckle curve now and then and a changeup thrown a lot is now and then a circle change, the
same for the same man every time.

By the count (queue stage 3): each pitch's share when the count is even, when he is ahead
(more strikes than balls) and when he is behind (more balls), so the game's pitchers choose
as each man does; few pitches in a count and his overall share fills in (COUNT_PRIOR). And
each batter's line against left- and right-handed pitchers (a pitcher's hand from the season's
players table), for his own split.
"""
import csv
import hashlib
import os
import sys

import pyarrow.parquet as pq

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PBP = os.path.join(ROOT, "content-local", "raw", "kbo-pbp")
STATS = os.path.join(ROOT, "content-local", "raw", "kaggle-kbo-stats", "kbo_pitching_stats_season_1982-2026.csv")
MIN_SHARE = 0.03
MIN_PITCHES = 15
MOST = 6
# Pitches of a man's own overall mix added to each count's: a count he threw little in leans
# on his overall shares.
COUNT_PRIOR = 40.0
BUCKETS = ("even", "ahead", "behind")
HITS = {"single": 1, "double": 2, "triple": 3, "home_run": 4}


def bucket(balls, strikes):
    if balls is None or strikes is None:
        return "even"
    if strikes > balls:
        return "ahead"
    if balls > strikes:
        return "behind"
    return "even"

# The table's club codes -> the records' club names.
CLUB = {"OB": "두산", "HH": "한화", "LT": "롯데", "HT": "KIA", "SS": "삼성", "SK": "SSG", "WO": "키움", "LG": "LG", "NC": "NC", "KT": "KT"}
# The table's pitch types -> the game's (data/pitch_types.json); two-seamers and sinkers share
# one code there, told apart by the broadcast's own word.
TYPE = {"FF": "four_seam", "SI": "sinker", "FC": "cutter", "SL": "slider", "ST": "sweeper", "SV": "slurve",
        "CU": "curve", "CH": "changeup", "FO": "forkball", "KN": "knuckleball"}


def own(name, salt):
    """A number in [0, 1) from a man's name: the same every time."""
    return int(hashlib.md5((name + salt).encode("utf-8")).hexdigest()[:8], 16) / float(1 << 32)


def main():
    season = sys.argv[1] if len(sys.argv) > 1 else "2026"
    src = os.path.join(PBP, "kbo_pbp_%s.parquet" % season)
    if not os.path.exists(src):
        print("pitch_mix: no pitch table for %s" % season)
        return
    table = pq.read_table(src, columns=["pitcher", "pitcher_name", "batter_name", "home_team", "away_team", "inning_topbot", "pitch_type", "_naver_pitch_name", "release_speed_kmh", "balls", "strikes", "events"]).to_pylist()
    by_count = {}
    # Who pitched for whom: the fielding side.
    counts = {}
    for r in table:
        name = r.get("pitcher_name") or ""
        code = r.get("pitch_type") or ""
        if not name or code not in TYPE:
            continue
        club = r["home_team"] if (r.get("inning_topbot") or "").lower().startswith("top") else r["away_team"]
        key = (name, CLUB.get(club, club))
        kind = TYPE[code]
        if code == "SI" and "투심" in (r.get("_naver_pitch_name") or ""):
            kind = "two_seam"
        entry = counts.setdefault(key, {})
        n, speed, timed = entry.get(kind, (0, 0.0, 0))
        v = r.get("release_speed_kmh")
        entry[kind] = (n + 1, speed + (v or 0.0), timed + (1 if v else 0))
        per = by_count.setdefault(key, {b: {} for b in BUCKETS})[bucket(r.get("balls"), r.get("strikes"))]
        per[kind] = per.get(kind, 0) + 1
    # The records' pitchers of the season: real name and club -> id.
    ids_by = {}
    ids_by_name = {}
    for r in csv.DictReader(open(STATS, encoding="utf-8")):
        if r["Season"] != season:
            continue
        ids_by[(r["Player"], r["Team"])] = "kbo" + r["Id"]
        ids_by_name.setdefault(r["Player"], set()).add("kbo" + r["Id"])
    out = []
    matched = 0
    for (name, club), entry in counts.items():
        pid = ids_by.get((name, club))
        if pid is None and len(ids_by_name.get(name, ())) == 1:
            pid = next(iter(ids_by_name[name]))
        if pid is None:
            continue
        total = sum(n for n, _, _ in entry.values())
        kept = [(k, n, s / t if t else 0.0) for k, (n, s, t) in entry.items() if n >= MIN_PITCHES and n / total >= MIN_SHARE]
        kept.sort(key=lambda e: -e[1])
        kept = kept[:MOST]
        if not kept:
            continue
        matched += 1
        share = sum(n for _, n, _ in kept)
        kinds = [k for k, _, _ in kept]
        overall = {k: n / share for k, n, _ in kept}
        # Each count's shares of his kept pitches, leaning on his overall mix where he threw few.
        in_count = {}
        for b in BUCKETS:
            seen = by_count.get((name, club), {}).get(b, {})
            total = sum(seen.get(k, 0) for k in kinds)
            in_count[b] = {k: (seen.get(k, 0) + COUNT_PRIOR * overall[k]) / (total + COUNT_PRIOR) for k in kinds}
        for kind, n, velo in kept:
            raw_kind = kind
            if kind == "curve" and velo >= 127.0 and own(name, "kc") < 0.35:
                kind = "knuckle_curve"
            elif kind == "changeup" and n / share >= 0.15 and own(name, "cc") < 0.25:
                kind = "circle_change"
            row = {"id": pid, "type": kind, "usage": round(n / share, 4), "velo": round(velo, 1)}
            for b in BUCKETS:
                row["usage_" + b] = round(in_count[b][raw_kind], 4)
            out.append(row)
    dest = os.path.join(ROOT, "content-local", "raw", "kbo-" + season, "pitches.csv")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["id", "type", "usage", "velo", "usage_even", "usage_ahead", "usage_behind"])
        w.writeheader()
        w.writerows(out)
    print("pitch_mix: %s — %d pitchers matched of %d, %d pitches -> %s" % (season, matched, len(counts), len(out), dest))
    splits(season, table)


def splits(season, table):
    """Each batter's plate appearances and OPS against left- and right-handed pitchers. Men are
    found in the records (real names and ids, as the pitch table has them): a batter by his
    name and club; a pitcher's hand from the season's players table by his record id."""
    players = os.path.join(ROOT, "content-local", "raw", "kbo-" + season, "players.csv")
    batting = os.path.join(ROOT, "content-local", "raw", "kaggle-kbo-stats", "kbo_batting_stats_season_1982-2026.csv")
    if not os.path.exists(players) or not os.path.exists(batting):
        return
    hand_of = {r["id"]: r["throws"] for r in csv.DictReader(open(players, encoding="utf-8"))}
    batter_ids = {}
    batter_by_name = {}
    for r in csv.DictReader(open(batting, encoding="utf-8")):
        if r["Season"] != season:
            continue
        batter_ids[(r["Player"], r["Team"])] = "kbo" + r["Id"]
        batter_by_name.setdefault(r["Player"], set()).add("kbo" + r["Id"])
    pitcher_ids = {}
    pitcher_by_name = {}
    for r in csv.DictReader(open(STATS, encoding="utf-8")):
        if r["Season"] != season:
            continue
        pitcher_ids[(r["Player"], r["Team"])] = "kbo" + r["Id"]
        pitcher_by_name.setdefault(r["Player"], set()).add("kbo" + r["Id"])
    lines = {}
    for r in table:
        event = r.get("events")
        if not event:
            continue
        top = (r.get("inning_topbot") or "").lower().startswith("top")
        bat_club = CLUB.get(r["away_team"] if top else r["home_team"])
        pit_club = CLUB.get(r["home_team"] if top else r["away_team"])
        bid = _id_of(r.get("batter_name") or "", bat_club, batter_ids, batter_by_name)
        pid = _id_of(r.get("pitcher_name") or "", pit_club, pitcher_ids, pitcher_by_name)
        hand = hand_of.get(pid or "")
        if not bid or hand not in ("L", "R"):
            continue
        line = lines.setdefault(bid, {"L": [0, 0, 0, 0, 0, 0], "R": [0, 0, 0, 0, 0, 0]})[hand]
        # pa, ab, hits, total bases, walks + hbp, sac flies
        line[0] += 1
        if event in HITS:
            line[1] += 1
            line[2] += 1
            line[3] += HITS[event]
        elif event in ("walk", "hit_by_pitch"):
            line[4] += 1
        elif event == "sac_fly":
            line[5] += 1
        elif event != "sac_bunt" and event != "catcher_interference":
            line[1] += 1
    dest = os.path.join(ROOT, "content-local", "raw", "kbo-" + season, "splits.csv")
    rows = []
    for bid, by_hand in lines.items():
        row = {"id": bid}
        for hand in ("L", "R"):
            pa, ab, h, tb, onb, sf = by_hand[hand]
            obp = (h + onb) / max(ab + onb + sf, 1)
            slg = tb / max(ab, 1)
            row["pa_" + hand.lower()] = pa
            row["ops_" + hand.lower()] = round(obp + slg, 4)
        rows.append(row)
    with open(dest, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["id", "pa_l", "ops_l", "pa_r", "ops_r"])
        w.writeheader()
        w.writerows(rows)
    print("pitch_mix: %s — splits for %d batters -> %s" % (season, len(rows), dest))


def _id_of(name, club, ids, by_name):
    """A man's record id by his name and club, else by his name alone when only one has it."""
    pid = ids.get((name, club))
    if pid is None and len(by_name.get(name, ())) == 1:
        pid = next(iter(by_name[name]))
    return pid



main()
