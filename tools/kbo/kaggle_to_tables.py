"""A KBO season from the Kaggle dataset "KBO Player Stats 1982–2026" (netsong, CC BY-NC-SA
4.0; its values are the KBO records site's) into the roster builder's four tables and a season
pack. Everything it writes goes into the local content pack, out of git:

    content-local/raw/kbo-<season>/{teams,players,batting,pitching}.csv  (tools/build_roster.gd)
    content-local/seasons/kbo-<season>.json                                (SeasonPack)

    python3 tools/kbo/kaggle_to_tables.py 2025      one season
    python3 tools/kbo/kaggle_to_tables.py --list    the seasons chosen in the history file

What is real about a season and is not in the dataset — the clubs' names and colours that
year, the final table, the postseason's rounds, the champion, that year's rules, and the
scenarios — is read from the local content pack's content-local/kbo/history.json (curated by
hand, with its sources; never in git). A season that is not in it still builds, with the
dataset's club names, plain colours, a table summed from the pitchers' wins and losses and
today's rules.

What the dataset does not have is filled in: starts (a pitcher averaging 3.5 innings or more a
game is a starter), uniform numbers (made up — the same man keeps his from season to season —
and unique within a club), the three outfield places
(the outfield is one "OF": the quickest of a club's regulars plays centre), the first team (the
men who played most: half pitchers with at least five starters, two catchers).
"""
import csv
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import names  # noqa: E402  (real-like names: the user, 2026-11-22)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "content-local", "raw", "kaggle-kbo-stats")
BATTING = os.path.join(SRC, "kbo_batting_stats_season_1982-2026.csv")
PITCHING = os.path.join(SRC, "kbo_pitching_stats_season_1982-2026.csv")
HISTORY = os.path.join(ROOT, "content-local", "kbo", "history.json")
TODAY = {"games": 144, "extra_innings": 11, "foreign_players": 3, "asia_quota": 0, "registered_roster": 28, "designated_hitter": True, "pitch_clock": True}
STARTER_IP_PER_GAME = 3.5
# The newest season in the dataset (its clubs' futures squads are added, farm_rows).
NEWEST = 2026
FARM_YEARS = 2
FARM_MAX_AGE = 33
# Uniform numbers taken in each club (the futures men draw theirs after the first team).
TAKEN = {}
# The dataset's club names of the season being built -> club ids; its clubs' rows.
CLUB_OF = {}
TEAM_ROWS = []
HISTORY_DATA = {}
POSITION_NAMES = {"C": "포수", "1B": "1루수", "2B": "2루수", "3B": "3루수", "SS": "유격수", "OF": "외야수", "LF": "좌익수", "CF": "중견수", "RF": "우익수", "DH": "지명타자", "IF": "내야수"}
PLAIN = ["#12355B", "#7A1E2B", "#1F6F54", "#5B3A8C", "#8C5A12", "#2B2B2B", "#0E5A7A", "#7A4A1E", "#3C4A8C", "#6A6A1E"]


def load_history():
    if not os.path.exists(HISTORY):
        return {"clubs": {}, "seasons": {}}
    with open(HISTORY, encoding="utf-8") as f:
        return json.load(f)


def park_of(history, season, club_id):
    """A club's home park that season: {"park", "HR", "H"}; neutral when unknown."""
    for era in history.get("parks", {}).get(club_id, []):
        if int(season) <= int(era["until"]):
            return {"park": era["park"], "HR": float(era["HR"]), "H": float(era["H"])}
    return {"park": "", "HR": 1.0, "H": 1.0}


def club_table(history, season, team_names):
    """The dataset's club names of a season -> (id, name, short, primary, secondary, accent):
    the history file's clubs as they were called that year, or plain ones."""
    out = {}
    for cid, c in history.get("clubs", {}).items():
        look = dict(c)
        for era in c.get("eras", []):
            if int(season) <= int(era["until"]):
                look.update(era)
                break
        for name in c.get("data", []):
            out[name] = (cid, look["name"], look["short"], look["primary"], look["secondary"], look["accent"])
    for i, name in enumerate(sorted(n for n in team_names if n not in out)):
        out[name] = ("club%02d" % (i + 1), name, name, PLAIN[i % len(PLAIN)], "#F2F2F2", "#E0A100")
    return out


def outs_of(ip):
    """'78 1/3' -> 235."""
    ip = (ip or "0").strip()
    if not ip or ip == "-":
        return 0
    parts = ip.split()
    whole = int(parts[0]) if parts[0].isdigit() else 0
    frac = 0
    if len(parts) > 1 and "/" in parts[1]:
        frac = int(parts[1].split("/")[0])
    elif "/" in parts[0]:
        whole, frac = 0, int(parts[0].split("/")[0])
    return whole * 3 + frac


def num(x):
    try:
        return int(float(x))
    except (TypeError, ValueError):
        return 0


def foreign(row):
    """Signed abroad: a free selection or a replacement foreign player, with no Korean school
    (초·중) in his career."""
    draft = (row.get("Draft") or "") + (row.get("draft_kbo") or "")
    career = row.get("Career") or ""
    return ("자유선발" in draft or "외국인" in draft) and "초-" not in career and "중-" not in career


def asia_quota(row):
    """Signed on the Asia quota (2026 on); the dataset says so."""
    return "아시아쿼터" in ((row.get("Draft") or "") + (row.get("draft_kbo") or ""))


def main():
    history = load_history()
    HISTORY_DATA.update(history)
    if len(sys.argv) > 1 and sys.argv[1] == "--list":
        print(" ".join(sorted(history.get("seasons", {}))))
        return
    season = sys.argv[1] if len(sys.argv) > 1 else "2025"
    bat = [r for r in csv.DictReader(open(BATTING, encoding="utf-8")) if r["Season"] == season]
    pit = [r for r in csv.DictReader(open(PITCHING, encoding="utf-8")) if r["Season"] == season]
    meta = history.get("seasons", {}).get(season, {})
    rules = dict(TODAY)
    rules.update(meta.get("rules", {}))
    clubs = club_table(history, season, set(r["Team"] for r in bat + pit))
    CLUB_OF.update({name: c[0] for name, c in clubs.items()})
    real = {row[0]: row for row in meta.get("standings", [])}
    registered = int(rules["registered_roster"])
    pitchers_up = min(14, registered // 2)
    out = os.path.join(ROOT, "content-local", "raw", "kbo-" + season)
    os.makedirs(out, exist_ok=True)
    rng = random.Random(int(season))

    def club_of(team):
        return clubs.get(team)

    # A pitcher is a man whose position is P (a hitter's inning in a blow-out is no pitching job).
    pitchers = {r["Id"]: r for r in pit if club_of(r["Team"]) and r["Position"] == "P"}
    hitters = {r["Id"]: r for r in bat if club_of(r["Team"]) and r["Position"] != "P" and r["Id"] not in pitchers}
    teams = {}
    for r in list(pitchers.values()) + list(hitters.values()):
        teams.setdefault(club_of(r["Team"])[0], {"club": club_of(r["Team"]), "p": [], "h": []})
    for r in pitchers.values():
        teams[club_of(r["Team"])[0]]["p"].append(r)
    for r in hitters.values():
        teams[club_of(r["Team"])[0]]["h"].append(r)

    player_rows, bat_rows, pit_rows, team_rows = [], [], [], []
    standings = []
    for tid, t in teams.items():
        club = t["club"]
        games = int(rules["games"])
        # The real table where the history file has it; else summed from the pitchers (a man
        # traded in mid-season brings his whole year, so the sums are a little off).
        if tid in real:
            wins, losses, ties = int(real[tid][1]), int(real[tid][2]), int(real[tid][3])
        else:
            wins = sum(num(r["W"]) for r in t["p"])
            losses = sum(num(r["L"]) for r in t["p"])
            ties = max(games - wins - losses, 0)
        standings.append([tid, wins, losses, ties])
        team_rows.append({"id": tid, "name": club[1], "short": club[2], "stadium": "", "primary": club[3], "secondary": club[4], "accent": club[5],
                          "wins": wins, "losses": losses, "ties": ties, "games": games,
                          "park": park_of(HISTORY_DATA, season, tid)["park"], "pf_hr": park_of(HISTORY_DATA, season, tid)["HR"], "pf_h": park_of(HISTORY_DATA, season, tid)["H"],
                          "rs": sum(num(r["R"]) for r in t["h"]), "ra": sum(num(r["R"]) for r in t["p"])})
        # Pitchers: starters by innings a game; the first team by innings, five starters at least.
        for r in t["p"]:
            g = max(num(r["G"]), 1)
            r["_outs"] = outs_of(r["IP"])
            r["_role"] = "SP" if r["_outs"] / 3.0 / g >= STARTER_IP_PER_GAME and g >= 5 else "RP"
        p_sorted = sorted(t["p"], key=lambda r: -r["_outs"])
        starters = [r for r in p_sorted if r["_role"] == "SP"]
        if len(starters) < 5:
            # Too few: the longest-working of the rest start.
            for r in sorted([r for r in p_sorted if r["_role"] == "RP"], key=lambda r: -(r["_outs"] / max(num(r["G"]), 1))):
                if len(starters) >= 5:
                    break
                r["_role"] = "SP"
                starters.append(r)
        # The foreign players on the first team (the others came in or went during the season):
        # those who played most (by share of a season), as many as that year allowed, and never
        # more than two pitchers among three (the rule since 2014).
        limit = int(rules["foreign_players"])
        f_p = sorted([(r["_outs"] / 432.0, r["Id"]) for r in t["p"] if foreign(r) and not asia_quota(r)], reverse=True)
        f_h = sorted([(num(r["PA"]) / 600.0, r["Id"]) for r in t["h"] if foreign(r) and not asia_quota(r)], reverse=True)
        p_ids = set(i for _, i in f_p)
        chosen = []
        for share, i in sorted(f_p + f_h, reverse=True):
            if len(chosen) >= limit:
                break
            if i in p_ids and limit >= 3 and sum(1 for _, c in chosen if c in p_ids) >= 2:
                continue
            chosen.append((share, i))
        # The Asia quota (2026 on): the one who played most; a second one signed later waits.
        a_all = sorted([(r["_outs"] / 432.0, r["Id"]) for r in t["p"] if asia_quota(r)] + [(num(r["PA"]) / 600.0, r["Id"]) for r in t["h"] if asia_quota(r)], reverse=True)
        allowed_foreign = set(i for _, i in chosen) | set(i for _, i in a_all[:int(rules["asia_quota"])])
        out_foreign = set(i for _, i in f_p + f_h + a_all) - allowed_foreign
        t["foreign_up"] = allowed_foreign
        starters = [r for r in starters if r["Id"] not in out_foreign]
        if len(starters) < 5:
            for r in p_sorted:
                if len(starters) >= 5:
                    break
                if r not in starters and r["Id"] not in out_foreign:
                    r["_role"] = "SP"
                    starters.append(r)
        p_up = set(r["Id"] for r in starters[:5])
        for r in p_sorted:
            if len(p_up) >= pitchers_up:
                break
            if r["Id"] not in out_foreign:
                p_up.add(r["Id"])
        # Hitters: the first team by plate appearances, two catchers at least.
        h_sorted = sorted(t["h"], key=lambda r: -num(r["PA"]))
        catchers = [r for r in h_sorted if r["Position"] == "C" and r["Id"] not in out_foreign][:2]
        h_up = set(r["Id"] for r in catchers)
        for r in h_sorted:
            if len(h_up) >= registered - pitchers_up:
                break
            if r["Id"] not in out_foreign:
                h_up.add(r["Id"])
        # The outfield: the quickest regular in centre, the others left and right in turn.
        ofs = [r for r in h_sorted if r["Position"] == "OF"]
        quick = sorted(ofs[:5], key=lambda r: -((num(r["SB"]) + 2 * num(r["3B"])) / max(num(r["PA"]), 1)))
        centre = quick[0]["Id"] if quick else ""
        side = 0
        # Numbers are not in the records: each man draws his from his own id (so he keeps it
        # from season to season), the men who played most choosing first.
        numbers = {}
        taken = set()
        everyone = [(r["_outs"] / 432.0, r, True) for r in t["p"]] + [(num(r["PA"]) / 600.0, r, False) for r in t["h"]]
        for _, r, is_pitcher in sorted(everyone, key=lambda e: -e[0]):
            numbers[r["Id"]] = draw_number(r, is_pitcher, taken)
        TAKEN[tid] = taken

        def number_for(r):
            return numbers[r["Id"]]

        for r in t["p"]:
            ht, wt = parse_body(r["HtWt"])
            bats, throws = (r["BatThrow"] or "R/R").split("/")
            player_rows.append({"id": "kbo" + r["Id"], "team": tid, "name": names.person(r["Player"], foreign(r) or asia_quota(r)), "number": number_for(r), "born": r["Born"][:4],
                                "height_cm": ht, "weight_kg": wt, "bats": bats, "throws": throws, "positions": r["_role"], "role": r["_role"],
                                "origin": origin_of(r), "registered": 1 if r["Id"] in p_up else 0})
            pit_rows.append({"id": "kbo" + r["Id"], "g": num(r["G"]), "gs": num(r["G"]) if r["_role"] == "SP" else 0, "outs": r["_outs"],
                             "bf": num(r["TBF"]), "so": num(r["SO"]), "bb": num(r["BB"]), "hr": num(r["HR"])})
        for r in t["h"]:
            pos = r["Position"]
            if pos == "OF":
                if r["Id"] == centre:
                    pos = "CF/LF/RF"
                else:
                    pos = ("LF/RF/CF" if side % 2 == 0 else "RF/LF/CF")
                    side += 1
            elif pos == "DH":
                pos = "DH/1B"
            ht, wt = parse_body(r["HtWt"])
            bats, throws = (r["BatThrow"] or "R/R").split("/")
            player_rows.append({"id": "kbo" + r["Id"], "team": tid, "name": names.person(r["Player"], foreign(r) or asia_quota(r)), "number": number_for(r), "born": r["Born"][:4],
                                "height_cm": ht, "weight_kg": wt, "bats": bats, "throws": throws, "positions": pos, "role": "",
                                "origin": origin_of(r), "registered": 1 if r["Id"] in h_up else 0})
            bat_rows.append({"id": "kbo" + r["Id"], "pa": num(r["PA"]), "ab": num(r["AB"]), "h": num(r["H"]), "2b": num(r["2B"]), "3b": num(r["3B"]),
                             "hr": num(r["HR"]), "bb": num(r["BB"]), "hbp": num(r["HBP"]), "so": num(r["SO"]), "sb": num(r["SB"]), "cs": num(r["CS"])})

    # The newest season: each club's futures squad as well (the user: "the futures players are
    # the real second-team men, renamed"). The dataset has first-team records only, so a club's
    # futures men are those who played for it in the two seasons before and have no first-team
    # record this year — at 33 or younger, Koreans (a foreign player who is gone is gone) — with
    # their last season's numbers for their ratings.
    if season == str(NEWEST):
        farm_rows(season, teams, player_rows, bat_rows, pit_rows, rng)
    write(os.path.join(out, "teams.csv"), team_rows)
    TEAM_ROWS[:] = team_rows
    write(os.path.join(out, "players.csv"), player_rows)
    write(os.path.join(out, "batting.csv"), bat_rows)
    write(os.path.join(out, "pitching.csv"), pit_rows)
    # A season to play again goes where the game lists them; a roster-only season (for the
    # quick match) keeps its pack beside its tables, for the calibration.
    listed = os.path.join(ROOT, "content-local", "seasons", "kbo-%s.json" % season)
    if meta.get("pack", True) and meta.get("legend"):
        season_pack(season, meta, rules, standings, hitters, pitchers, bat_rows, pit_rows, player_rows, bool(real), listed)
    else:
        season_pack(season, meta, rules, standings, hitters, pitchers, bat_rows, pit_rows, player_rows, bool(real), os.path.join(out, "season.json"))
        if os.path.exists(listed):
            os.remove(listed)
    print("kaggle_to_tables: %s — %d clubs, %d players (%d hitters, %d pitchers) -> %s" % (season, len(team_rows), len(player_rows), len(bat_rows), len(pit_rows), out))


def draw_number(r, is_pitcher, taken):
    """A uniform number from the man's own id (the same every season), unique in his club."""
    own = random.Random(int(r["Id"]) if r["Id"].isdigit() else r["Id"])
    for _ in range(200):
        pick = own.randint(11, 69) if is_pitcher else own.randint(1, 66)
        if pick not in taken:
            taken.add(pick)
            return pick
    for pick in range(70, 100):
        if pick not in taken:
            taken.add(pick)
            return pick
    return 99


def farm_rows(season, teams, player_rows, bat_rows, pit_rows, rng):
    s = int(season)
    present = set()
    for t in teams.values():
        present.update(r["Id"] for r in t["p"] + t["h"])
    latest_p, latest_h = {}, {}
    for r in csv.DictReader(open(PITCHING, encoding="utf-8")):
        y = int(r["Season"])
        if s - FARM_YEARS <= y < s and r["Position"] == "P" and r["Id"] not in present:
            if r["Id"] not in latest_p or y > int(latest_p[r["Id"]]["Season"]) or (y == int(latest_p[r["Id"]]["Season"]) and outs_of(r["IP"]) > outs_of(latest_p[r["Id"]]["IP"])):
                latest_p[r["Id"]] = r
    for r in csv.DictReader(open(BATTING, encoding="utf-8")):
        y = int(r["Season"])
        if s - FARM_YEARS <= y < s and r["Position"] != "P" and r["Id"] not in present and r["Id"] not in latest_p:
            if r["Id"] not in latest_h or y > int(latest_h[r["Id"]]["Season"]) or (y == int(latest_h[r["Id"]]["Season"]) and num(r["PA"]) > num(latest_h[r["Id"]]["PA"])):
                latest_h[r["Id"]] = r
    added = 0
    for kind, latest in (("p", latest_p), ("h", latest_h)):
        for r in latest.values():
            club = CLUB_OF.get(r["Team"])
            born = int(r["Born"][:4]) if r["Born"][:4].isdigit() else 1980
            if club is None or club not in teams or s - born > FARM_MAX_AGE or foreign(r) or asia_quota(r):
                continue
            ht, wt = parse_body(r["HtWt"])
            bats, throws = (r["BatThrow"] or "R/R").split("/")
            n = draw_number(r, kind == "p", TAKEN.setdefault(club, set()))
            if kind == "p":
                outs = outs_of(r["IP"])
                g = max(num(r["G"]), 1)
                role = "SP" if outs / 3.0 / g >= STARTER_IP_PER_GAME and g >= 5 else "RP"
                player_rows.append({"id": "kbo" + r["Id"], "team": club, "name": names.person(r["Player"], False), "number": n, "born": r["Born"][:4],
                                    "height_cm": ht, "weight_kg": wt, "bats": bats, "throws": throws, "positions": role, "role": role,
                                    "origin": origin_of(r), "registered": 0})
                pit_rows.append({"id": "kbo" + r["Id"], "g": num(r["G"]), "gs": num(r["G"]) if role == "SP" else 0, "outs": outs,
                                 "bf": num(r["TBF"]), "so": num(r["SO"]), "bb": num(r["BB"]), "hr": num(r["HR"])})
            else:
                pos = {"OF": "LF/RF/CF", "DH": "DH/1B"}.get(r["Position"], r["Position"])
                player_rows.append({"id": "kbo" + r["Id"], "team": club, "name": names.person(r["Player"], False), "number": n, "born": r["Born"][:4],
                                    "height_cm": ht, "weight_kg": wt, "bats": bats, "throws": throws, "positions": pos, "role": "",
                                    "origin": origin_of(r), "registered": 0})
                bat_rows.append({"id": "kbo" + r["Id"], "pa": num(r["PA"]), "ab": num(r["AB"]), "h": num(r["H"]), "2b": num(r["2B"]), "3b": num(r["3B"]),
                                 "hr": num(r["HR"]), "bb": num(r["BB"]), "hbp": num(r["HBP"]), "so": num(r["SO"]), "sb": num(r["SB"]), "cs": num(r["CS"])})
            added += 1
    print("kaggle_to_tables: %d futures players from %d-%d" % (added, s - FARM_YEARS, s - 1))


def origin_of(row):
    if asia_quota(row):
        return "asia"
    return "foreign" if foreign(row) else ""


def parse_body(s):
    try:
        h, w = s.replace("cm", "").replace("kg", "").split("/")
        return float(h), float(w)
    except (ValueError, AttributeError):
        return 183.0, 88.0


def write(path, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def pct(w, l):
    return w / (w + l) if w + l else 0.0


def season_pack(season, meta, rules, standings, hitters, pitchers, bat_rows, pit_rows, player_rows, real, path):
    """The season as it really went (the table, the champion, the title holders, that year's
    rules and postseason) and the club that made history in it, with its leading men."""
    if real:
        order_of = {row[0]: i for i, row in enumerate(meta["standings"])}
        standings.sort(key=lambda r: order_of.get(r[0], 99))
    else:
        standings.sort(key=lambda r: -pct(r[1], r[2]))
    names = {p["id"]: p["name"] for p in player_rows}
    games = int(rules["games"])
    q_bat = [b for b in bat_rows if b["pa"] >= int(games * 3.1)] or bat_rows
    avg = max(q_bat, key=lambda b: b["h"] / max(b["ab"], 1))
    hr = max(bat_rows, key=lambda b: b["hr"])
    sb = max(bat_rows, key=lambda b: b["sb"])
    rbi_src = {("kbo" + r["Id"]): num(r["RBI"]) for r in hitters.values()}
    rbi_id = max(rbi_src, key=rbi_src.get)
    era_src = {("kbo" + r["Id"]): (num(r["ER"]) * 27.0 / max(outs_of(r["IP"]), 1)) for r in pitchers.values() if outs_of(r["IP"]) >= games * 3}
    wins_src = {("kbo" + r["Id"]): num(r["W"]) for r in pitchers.values()}
    win_id = max(wins_src, key=wins_src.get)
    so = max(pit_rows, key=lambda p: p["so"])
    sv_src = {("kbo" + r["Id"]): num(r["SV"]) for r in pitchers.values()}
    sv_id = max(sv_src, key=sv_src.get)
    leaders = [
        ["타율", names[avg["id"]], ".%03d" % round(1000 * avg["h"] / max(avg["ab"], 1))],
        ["홈런", names[hr["id"]], str(hr["hr"])],
        ["타점", names[rbi_id], str(rbi_src[rbi_id])],
        ["도루", names[sb["id"]], str(sb["sb"])],
    ]
    if era_src:
        era_id = min(era_src, key=era_src.get)
        leaders.append(["평균자책점", names[era_id], "%.2f" % era_src[era_id]])
    leaders += [
        ["다승", names[win_id], str(wins_src[win_id])],
        ["탈삼진", names[so["id"]], str(so["so"])],
        ["세이브", names[sv_id], str(sv_src[sv_id])],
    ]
    order = [r[0] for r in standings]
    legend = meta.get("legend")
    scenarios = []
    if legend:
        scenario = {k: legend[k] for k in ("title", "tagline", "path", "text", "goal", "final") if k in legend}
        scenario["id"] = "legend"
        scenario["team"] = legend["team"]
        scenario["stars"] = stars(legend, hitters, pitchers)
        scenarios.append(scenario)
    roster = os.path.relpath(os.path.join(ROOT, "content-local", "rosters", "kbo-%s.json" % season), os.path.dirname(path))
    pack = {
        "format": 1,
        "id": "kbo-" + season,
        "title": legend["title"] if legend else "%s 시즌" % season,
        "year": int(season),
        "note": "",
        "roster": roster,
        "teams": order,
        "rules": rules,
        "actual": {"standings": standings, "champion": meta.get("champion", order[0]), "leaders": leaders},
        "scenarios": scenarios,
        # How each club looked that year (for lists that need no players).
        "clubs": {c["id"]: {k: c[k] for k in ("name", "short", "primary", "secondary", "accent")} for c in TEAM_ROWS},
        # Each club's home park and its effect (the resolver plays it; SeasonPack.park_of).
        "parks": {c["id"]: {"park": c["park"], "HR": c["pf_hr"], "H": c["pf_h"]} for c in TEAM_ROWS},
    }
    if meta.get("postseason"):
        pack["postseason"] = meta["postseason"]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(pack, f, ensure_ascii=False, indent=2)
    print("season pack:", path, "|", pack["title"], "| stars", scenarios[0]["stars"] if scenarios else "-")


def stars(legend, hitters, pitchers):
    """The club's leading men that year, from the records: its best hitters by OPS (a regular's
    share of plate appearances) and its pitchers with the most wins (a closer by his saves)."""
    club = legend["team"]
    want = legend.get("stars", {"hitters": 3, "pitchers": 2})
    out = []
    mine = [r for r in hitters.values() if CLUB_OF.get(r["Team"]) == club and num(r["PA"]) >= 300]

    def ops(r):
        ab = max(num(r["AB"]), 1)
        h = num(r["H"])
        tb = h + num(r["2B"]) + 2 * num(r["3B"]) + 3 * num(r["HR"])
        return (h + num(r["BB"]) + num(r["HBP"])) / max(num(r["PA"]), 1) + tb / ab

    for r in sorted(mine, key=ops, reverse=True)[:int(want.get("hitters", 3))]:
        avg = num(r["H"]) / max(num(r["AB"]), 1)
        third = ["도루", str(num(r["SB"]))] if num(r["SB"]) >= 25 else ["타점", str(num(r["RBI"]))]
        out.append([names.person(r["Player"], foreign(r) or asia_quota(r)), POSITION_NAMES.get(r["Position"], "타자"), [["타율", (".%03d" % round(1000 * avg)) if avg < 1 else "1.000"], ["홈런", str(num(r["HR"]))], third]])
    arms = [r for r in pitchers.values() if CLUB_OF.get(r["Team"]) == club and outs_of(r["IP"]) >= 150]
    for r in sorted(arms, key=lambda r: (num(r["W"]), -num(r["ER"]) * 27.0 / max(outs_of(r["IP"]), 1)), reverse=True)[:int(want.get("pitchers", 2))]:
        era = num(r["ER"]) * 27.0 / max(outs_of(r["IP"]), 1)
        out.append([names.person(r["Player"], foreign(r) or asia_quota(r)), "선발 투수", [["승", str(num(r["W"]))], ["패", str(num(r["L"]))], ["평균자책점", "%.2f" % era]]])
    closers = [r for r in pitchers.values() if CLUB_OF.get(r["Team"]) == club and num(r["SV"]) >= 25]
    for r in sorted(closers, key=lambda r: -num(r["SV"]))[:1 if want.get("closer", int(want.get("pitchers", 2)) <= 2) else 0]:
        era = num(r["ER"]) * 27.0 / max(outs_of(r["IP"]), 1)
        out.append([names.person(r["Player"], foreign(r) or asia_quota(r)), "마무리 투수", [["세이브", str(num(r["SV"]))], ["평균자책점", "%.2f" % era]]])
    return out


if __name__ == "__main__":
    main()
