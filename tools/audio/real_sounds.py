"""Makes the game's sounds from real recordings (2026-11-23: "the sound is like a
made-up thing; find real recordings — it may stay off git"): the bat, the mitt, the gloves and
tags, steps, and the crowd's beds and cheers, cut from the recordings in
content-local/audio/raw/ and written over the game's own names in content-local/audio/
(GameAudio plays a local file before the game's synthesized one; nothing goes into git).

    .tools/pyenv/bin/python -I tools/audio/real_sounds.py

Each hit is found by ffmpeg's silence detection, cut, levelled to its peak, given the faint
echo of an open ballpark, and turned into the game's tiers by level and tone: a bat's four
tiers by loudness and weight (tier 4 a crushed ball), a jammed ball duller and lower, one off
the end thinner and higher; a mitt's three by the pitch's speed. Several takes of each, so the
same sound is not heard twice running. The crowd's beds are layered from talk and murmur
recordings, filtered as if heard across a ballpark, and looped.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FFMPEG = os.path.join(ROOT, ".tools", "ffmpeg", "node_modules", "ffmpeg-static", "ffmpeg")
RAW = os.path.join(ROOT, "content-local", "audio", "raw", "google")
OUT = os.path.join(ROOT, "content-local", "audio")
# An open park's faint slap-back from the stands, after a compressor that brings a hit's body
# up to the level of the game's mix (a crack is a sharp peak; at the same peak it sounded faint).
PARK = "acompressor=threshold=-30dB:ratio=6:attack=0.3:release=80:makeup=6,aecho=0.8:0.6:70|140:0.14|0.07"


def run(args):
    return subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y"] + args, capture_output=True, text=True)


def onsets(name, noise=-38.0, gap=0.12):
    """The starts of the sounds in a recording (where its silences end)."""
    r = subprocess.run([FFMPEG, "-hide_banner", "-i", os.path.join(RAW, name + ".ogg"), "-af",
                        "silencedetect=noise=%sdB:d=%s" % (noise, gap), "-f", "null", "-"], capture_output=True, text=True)
    starts = [0.0] if not re.search(r"silence_start: 0(\.0+)?\b", r.stderr) else []
    starts += [float(x) for x in re.findall(r"silence_end: ([0-9.]+)", r.stderr)]
    ends = [float(x) for x in re.findall(r"silence_start: ([0-9.]+)", r.stderr)]
    # (A silence that ends at the file's end starts no sound.)
    dur = duration(name)
    return [s for s in starts if s < dur - 0.08], ends


def duration(name):
    r = subprocess.run([FFMPEG, "-hide_banner", "-i", os.path.join(RAW, name + ".ogg")], capture_output=True, text=True)
    m = re.search(r"Duration: (\d+):(\d+):([0-9.]+)", r.stderr)
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3)) if m else 0.0


def peak(path):
    return levels(path)[1]


def duration_of(path):
    r = subprocess.run([FFMPEG, "-hide_banner", "-i", path], capture_output=True, text=True)
    m = re.search(r"Duration: (\d+):(\d+):([0-9.]+)", r.stderr)
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3)) if m else 0.0


def levels(path):
    """A file's mean and peak level (dB)."""
    r = subprocess.run([FFMPEG, "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True)
    mean = re.search(r"mean_volume: (-?[0-9.]+) dB", r.stderr)
    top = re.search(r"max_volume: (-?[0-9.]+) dB", r.stderr)
    return (float(mean.group(1)) if mean else -30.0, float(top.group(1)) if top else 0.0)


def gain_for(tmp, out, fallback_db):
    """How much to raise a cut: to the mean level of the game's own sound of that name (so the
    game's mix stays as it was), its peak kept under -0.5 dB; a new sound to `fallback_db`
    below full at its peak."""
    rel = os.path.relpath(out, OUT)
    own = os.path.join(ROOT, "game", "audio", rel)
    mean, top = levels(tmp)
    if os.path.exists(own):
        want_mean, want_top = levels(own)
        # A hit (shorter than a second) by its peak, which keeps the tiers' differences; a bed
        # or a cheer by its mean level.
        return want_top - top if duration_of(tmp) < 1.0 else min(want_mean - mean, -0.5 - top)
    return -top + fallback_db - 1.0


def cut(name, at, length, out, filters, gain_db=0.0):
    """One sound from a recording: cut, filtered, levelled to `gain_db` below full."""
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".tmp.wav"
    run(["-ss", "%.3f" % max(at - 0.006, 0.0), "-t", "%.3f" % length, "-i", os.path.join(RAW, name + ".ogg"),
         "-af", ",".join(filters + ["afade=t=out:st=%.3f:d=%.3f" % (length * 0.7, length * 0.3)]), "-ac", "1", "-ar", "44100", tmp])
    level = gain_for(tmp, out, gain_db)
    run(["-i", tmp, "-af", "volume=%.2fdB" % level, "-c:a", "libvorbis", "-q:a", "6", out])
    os.remove(tmp)


def main():
    if not os.path.isdir(RAW):
        print("real_sounds: no recordings in", RAW)
        return
    made = 0
    sfx = os.path.join(OUT, "sfx")
    # The bat: four cracks of a wooden bat.
    hits, _ = onsets("wooden_bat_hits")
    for tier in range(1, 5):
        for v, at in enumerate(hits[:4]):
            weight = ["bass=g=%d" % (tier - 1)] if tier > 1 else ["highpass=f=180"]
            pitch = 1.0 + (v - 1.5) * 0.02 - (tier - 2.5) * 0.015
            cut("wooden_bat_hits", at, 0.6, os.path.join(sfx, "bat_solid_%d_%d.ogg" % (tier, v + 1)),
                ["asetrate=48000*%.4f" % pitch, "aresample=44100"] + weight + [PARK], [-10.0, -6.5, -3.0, 0.0][tier - 1])
            made += 1
        for v, at in enumerate(hits[:3]):
            cut("wooden_bat_hits", at, 0.45, os.path.join(sfx, "bat_jam_%d_%d.ogg" % (min(tier, 3), v + 1)),
                ["asetrate=48000*0.88", "aresample=44100", "lowpass=f=1800", PARK], [-11.0, -8.0, -5.0, -5.0][tier - 1])
            cut("wooden_bat_hits", at, 0.4, os.path.join(sfx, "bat_end_%d_%d.ogg" % (min(tier, 3), v + 1)),
                ["asetrate=48000*1.1", "aresample=44100", "highpass=f=650", PARK], [-12.0, -9.0, -6.0, -6.0][tier - 1])
            made += 2
    # The mitt: three pops, three tiers by the pitch's speed.
    pops, _ = onsets("baseball_into_glove")
    for tier in range(1, 4):
        for v, at in enumerate(pops[:3]):
            snap = ["highpass=f=%d" % (120 + 80 * tier)]
            cut("baseball_into_glove", at, 0.35, os.path.join(sfx, "mitt_%d_%d.ogg" % (tier, v + 1)),
                ["asetrate=48000*%.3f" % (0.97 + 0.03 * v), "aresample=44100"] + snap + [PARK], [-9.0, -5.0, -1.5][tier - 1])
            made += 1
    # Gloves and tags.
    snaps, _ = onsets("baseball_glove_tags")
    for v, at in enumerate([s for s in snaps if s > 0.05][:3]):
        cut("baseball_glove_tags", at, 0.3, os.path.join(sfx, "glove_%d.ogg" % (v + 1)), [PARK], -5.0)
        made += 1
    tags, _ = onsets("baseball_glove_tag_out")
    if tags:
        cut("baseball_glove_tag_out", tags[min(1, len(tags) - 1)], 0.45, os.path.join(sfx, "base_tag.ogg"), [PARK], -4.0)
        made += 1
    cut("fist_into_glove", 0.0, 0.3, os.path.join(sfx, "bare_hand.ogg"), [PARK], -8.0)
    # The bat let go (the walk to first) and dropped on dirt.
    cut("wood_bat_falling_in_dirt", 0.0, 0.9, os.path.join(sfx, "bat_drop_1.ogg"), [PARK], -6.0)
    cut("wood_bat_falling_in_grass", 0.0, 0.9, os.path.join(sfx, "bat_drop_2.ogg"), [PARK], -8.0)
    made += 3
    # Steps on dirt from running cleats.
    steps, _ = onsets("running_cleats", -34.0, 0.05)
    for v, at in enumerate(steps[2:5]):
        cut("running_cleats", at, 0.2, os.path.join(sfx, "step_dirt_%d.ogg" % (v + 1)), [], -12.0)
        made += 1
    # The crowd's beds: talk and murmur layered, heard across a park (lowpassed, spread by
    # echoes), quiet to loud; and its cheers.
    crowd = os.path.join(OUT, "crowd")
    os.makedirs(crowd, exist_ok=True)
    beds = {"bed_quiet": ("voices_murmur", "murmuring_and_talking_men", -24.0), "bed_normal": ("crowd_talking", "voices_murmur", -18.0), "bed_loud": ("team_cheer", "crowd_talking", -14.0)}
    for name, (a, b, gain) in beds.items():
        out = os.path.join(crowd, name + ".ogg")
        tmp = out + ".tmp.wav"
        run(["-i", os.path.join(RAW, a + ".ogg"), "-i", os.path.join(RAW, b + ".ogg"), "-filter_complex",
             "[0]atrim=0:40,asetpts=PTS-STARTPTS[x];[1]atrim=0:40,asetpts=PTS-STARTPTS,volume=0.7[y];[x][y]amix=inputs=2:normalize=0,lowpass=f=5200,aecho=0.7:0.5:90|180|260:0.25|0.15|0.08,afade=t=in:d=1,afade=t=out:st=39:d=1",
             "-ac", "1", "-ar", "44100", tmp])
        run(["-i", tmp, "-af", "volume=%.1fdB" % gain_for(tmp, out, gain), "-c:a", "libvorbis", "-q:a", "5", out])
        os.remove(tmp)
        made += 1
    for name, src, at, length, gain in [("cheer", "battle_crowd_celebration", 0.0, 4.0, -4.0), ("cheer_long", "team_cheer", 20.0, 8.0, -3.0),
                                        ("roar", "battle_crowd_celebrate_stutter", 0.0, 5.0, -2.0), ("ooh", "human_group_cry_out", 0.0, 2.5, -6.0)]:
        if os.path.exists(os.path.join(RAW, src + ".ogg")):
            cut(src, at, length, os.path.join(crowd, name + ".ogg"), ["lowpass=f=6000", PARK], gain)
            made += 1
    print("real_sounds: %d sounds -> %s" % (made, OUT))


main()
