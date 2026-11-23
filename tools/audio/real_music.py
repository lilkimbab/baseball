"""The game's music from real recordings (the user, 2026-11-23: "the home run, win and other
music sounds like a pixel game; bring real ones, as a KBO park plays them" — and then: "not a
military band; something fitting"): modern tracks by Kevin MacLeod (incompetech.com, CC BY 4.0)
in content-local/audio/raw/incompetech/, real fireworks (Wikimedia Commons, public domain) in
raw/commons/, each cut at its liveliest stretch (found by its loudness) and played as through a
ballpark's speakers, written over the game's own names in content-local/audio/music/ (GameAudio
plays a local file before the game's own; nothing goes into git; sources in SOURCES.md).

    python3 -I tools/audio/real_music.py

  homerun     "Raving Energy" (EDM) at its drop, fireworks over it
  win         "Exhilarate" with fireworks
  lose        "Overcast", quiet, fading
  jingle_1-3  between halves: "Pump", "Volatile Reaction", "Big Rock"
  organ_1-6   between batters: short bursts of "Funkorama", "Galactic Rap", "Crunk Knight",
              "Hep Cats", "Movement Proposition", "Take a Chance"
  pressure    a big moment: "Ouroboros", low and tense
  menu        "Rocket", looped
"""
import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FFMPEG = os.path.join(ROOT, ".tools", "ffmpeg", "node_modules", "ffmpeg-static", "ffmpeg")
RAW = os.path.join(ROOT, "content-local", "audio", "raw", "incompetech")
COMMONS = os.path.join(ROOT, "content-local", "audio", "raw", "commons")
GOOGLE = os.path.join(ROOT, "content-local", "audio", "raw", "google")
OUT = os.path.join(ROOT, "content-local", "audio", "music")
# Through a ballpark's speakers: a little thinner, the slap-back from the stands.
PARK = "highpass=f=70,aecho=0.85:0.55:260|470:0.22|0.1"


def run(args):
    r = subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y"] + args, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(r.stderr)


def mean_level(path):
    r = subprocess.run([FFMPEG, "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True)
    m = re.search(r"mean_volume: (-?[0-9.]+) dB", r.stderr)
    p = re.search(r"max_volume: (-?[0-9.]+) dB", r.stderr)
    return (float(m.group(1)) if m else -20.0, float(p.group(1)) if p else 0.0)


def finish(tmp, name):
    """Levelled to the game's own sound of that name (its mean level, peaks under -1 dB)."""
    own = os.path.join(ROOT, "game", "audio", "music", name + ".ogg")
    mean, top = mean_level(tmp)
    want = mean_level(own)[0] if os.path.exists(own) else -16.0
    gain = min(want - mean, -1.0 - top)
    out = os.path.join(OUT, name + ".ogg")
    run(["-i", tmp, "-af", "volume=%.2fdB" % gain, "-c:a", "libvorbis", "-q:a", "6", out])
    os.remove(tmp)
    print("real_music: %s (%.1f dB)" % (name, gain))


def clip(name, src, start, length, fade_in=0.05, fade_out=1.2, extra=None):
    """A cut of a recording, faded, through the park's speakers; `extra` [file, start, gain dB]
    mixed in (fireworks)."""
    tmp = os.path.join(OUT, name + ".tmp.wav")
    fades = "afade=t=in:d=%.2f,afade=t=out:st=%.2f:d=%.2f" % (fade_in, max(length - fade_out, 0.0), fade_out)
    if extra is None:
        run(["-ss", "%.2f" % start, "-t", "%.2f" % length, "-i", os.path.join(RAW, src), "-af", "%s,%s" % (PARK, fades), "-ac", "2", "-ar", "44100", tmp])
    else:
        run(["-ss", "%.2f" % start, "-t", "%.2f" % length, "-i", os.path.join(RAW, src),
             "-ss", "%.2f" % extra[1], "-t", "%.2f" % length, "-i", extra[0],
             "-filter_complex", "[0]%s,aresample=44100,aformat=channel_layouts=stereo[m];[1]aresample=44100,aformat=channel_layouts=stereo,volume=%.1fdB[x];[m][x]amix=inputs=2:duration=first:normalize=0,%s" % (PARK, extra[2], fades),
             "-ac", "2", "-ar", "44100", tmp])
    finish(tmp, name)


def loudest(src, length, after=0.0, before=None):
    """Where in a recording its liveliest `length` seconds start (the loudest stretch)."""
    import array
    import math
    raw = subprocess.run([FFMPEG, "-v", "error", "-i", os.path.join(RAW, src), "-ac", "1", "-ar", "4000", "-f", "s16le", "-"], capture_output=True).stdout
    a = array.array("h", raw)
    per = 4000 // 4
    levels = []
    for i in range(0, len(a), per):
        seg = a[i:i + per]
        levels.append(math.sqrt(sum(x * x for x in seg) / max(len(seg), 1)))
    n = max(int(length * 4), 1)
    best, best_at = -1.0, 0
    last = len(levels) - n if before is None else min(len(levels) - n, int(before * 4))
    for i in range(int(after * 4), max(last, int(after * 4) + 1)):
        v = sum(levels[i:i + n])
        if v > best:
            best, best_at = v, i
    return best_at / 4.0


def main():
    os.makedirs(OUT, exist_ok=True)
    fireworks = os.path.join(COMMONS, "fireworks.ogg")
    clip("homerun", "raving_energy.mp3", loudest("raving_energy.mp3", 9.5, 20.0), 9.5, 0.15, 1.2, [fireworks, 2.0, -4.0])
    clip("win", "exhilarate.mp3", loudest("exhilarate.mp3", 14.0, 10.0), 14.0, 0.3, 2.0, [fireworks, 14.0, -7.0])
    clip("lose", "overcast.mp3", 0.0, 10.0, 0.3, 3.0)
    for i, src in enumerate(["pump.mp3", "volatile_reaction.mp3", "big_rock.mp3"]):
        clip("jingle_%d" % (i + 1), src, loudest(src, 6.0, 2.0, 90.0), 6.0, 0.08, 1.2)
    for i, src in enumerate(["funkorama.mp3", "galactic_rap.mp3", "crunk_knight.mp3", "hep_cats.mp3", "movement_proposition.mp3", "take_a_chance.mp3"]):
        clip("organ_%d" % (i + 1), src, loudest(src, 3.4, 5.0, 100.0), 3.4, 0.06, 0.8)
    # A big moment: tense and low, looping.
    clip("pressure", "ouroboros.mp3", 0.0, 8.0, 0.4, 0.4)
    # The menus: the whole track.
    tmp = os.path.join(OUT, "menu.tmp.wav")
    run(["-i", os.path.join(RAW, "rocket.mp3"), "-af", "afade=t=in:d=0.3,afade=t=out:st=144:d=2.5", "-ac", "2", "-ar", "44100", tmp])
    finish(tmp, "menu")


main()
