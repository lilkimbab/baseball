"""Turns broadcast recordings the user provides into candidate play-by-play lines for the game
(the user, 2026-11-23: "take the real broadcasts and change them a little"). Nothing is fetched
from anywhere: the recordings are the user's, in content-local/raw/broadcast/ (any audio or
video ffmpeg reads), and everything this writes stays in content-local (not in git).

    .tools/supertonic-src/py/.venv/bin/python tools/audio/broadcast_lines.py [--model small]

1. Transcribes each recording offline (faster-whisper, Korean) into
   content-local/broadcast/<name>.txt with its times.
2. Sorts the sentences by the situation they call (home run, strikeout, double play, ...) by
   their words.
3. Makes each a template: player names, numbers and clubs become the game's slots ({name},
   {runs}, ...) as far as can be told, so a line is a way of saying, not a copy of a moment.
   Writes content-local/broadcast/candidates.json: situation -> [template, ...], for choosing
   and rewording into game/data/commentary.ko.json.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "content-local", "raw", "broadcast")
OUT = os.path.join(ROOT, "content-local", "broadcast")
MEDIA = (".mp3", ".mp4", ".m4a", ".wav", ".ogg", ".webm", ".mkv", ".aac", ".flac", ".mov")

# A situation by the words a caster uses for it (the first that matches).
SITUATIONS = [
    ("home_run", ("홈런", "넘어갑니다", "넘어갔습니다", "담장을 넘", "아치")),
    ("walk_off", ("끝내기",)),
    ("strikeout_swinging", ("헛스윙 삼진", "헛스윙",)),
    ("strikeout_looking", ("루킹 삼진", "서서 삼진", "지켜봅니다")),
    ("double_play", ("병살",)),
    ("double", ("2루타", "이루타", "가르는")),
    ("triple", ("3루타", "삼루타")),
    ("single", ("안타",)),
    ("walk", ("볼넷", "포볼")),
    ("hit_by_pitch", ("몸에 맞는", "사구", "데드볼")),
    ("fly_out", ("뜬공", "플라이", "잡아냅니다", "잡았습니다")),
    ("ground_out", ("땅볼",)),
    ("steal", ("도루",)),
    ("pitch", ("직구", "슬라이더", "커브", "체인지업", "포크", "스트라이크", "볼 카운트", "풀카운트")),
    ("great_play", ("호수비", "다이빙", "슈퍼 캐치", "그림 같은")),
]


FFMPEG = os.path.join(ROOT, ".tools", "ffmpeg", "node_modules", "ffmpeg-static", "ffmpeg")


def transcribe(model, path):
    # (Decoded by ffmpeg into 16 kHz mono samples: faster-whisper's own decoder did not take
    # this PyAV.)
    import subprocess
    import numpy as np
    raw = subprocess.run([FFMPEG, "-v", "error", "-i", path, "-ac", "1", "-ar", "16000", "-f", "s16le", "-"], capture_output=True).stdout
    audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    segments, _ = model.transcribe(audio, language="ko", vad_filter=True, beam_size=5)
    return [(s.start, s.end, s.text.strip()) for s in segments if s.text.strip()]


def template(text):
    """A sentence as a way of saying: numbers and runs to slots; a name before a comma or a
    particle at the start (Korean names: two to four syllables) to {name}."""
    t = re.sub(r"\s+", " ", text).strip()
    t = re.sub(r"(\d+)\s*점", "{runs}점", t)
    t = re.sub(r"^([가-힣]{2,4})(,|\s?선수|의|이|가|은|는)", lambda m: "{name}" + m.group(2), t)
    return t


def situation(text):
    for name, words in SITUATIONS:
        if any(w in text for w in words):
            return name
    return ""


def main():
    model_name = sys.argv[sys.argv.index("--model") + 1] if "--model" in sys.argv else "small"
    files = sorted(f for f in os.listdir(SRC) if f.lower().endswith(MEDIA)) if os.path.isdir(SRC) else []
    if not files:
        print("broadcast_lines: no recordings in", SRC)
        return
    from faster_whisper import WhisperModel
    model = WhisperModel(model_name, device="cpu", compute_type="int8")
    os.makedirs(OUT, exist_ok=True)
    found = {}
    for f in files:
        txt = os.path.join(OUT, os.path.splitext(f)[0] + ".txt")
        if os.path.exists(txt):
            lines = [l.split("\t", 2) for l in open(txt, encoding="utf-8").read().splitlines() if "\t" in l]
            segments = [(float(a), float(b), c) for a, b, c in lines]
        else:
            segments = transcribe(model, os.path.join(SRC, f))
            with open(txt, "w", encoding="utf-8") as out:
                for a, b, c in segments:
                    out.write("%.2f\t%.2f\t%s\n" % (a, b, c))
        for _, _, text in segments:
            kind = situation(text)
            if kind:
                found.setdefault(kind, [])
                t = template(text)
                if t not in found[kind]:
                    found[kind].append(t)
        print("broadcast_lines: %s, %d sentences" % (f, len(segments)))
    with open(os.path.join(OUT, "candidates.json"), "w", encoding="utf-8") as out:
        json.dump(found, out, ensure_ascii=False, indent=1)
    print("broadcast_lines: %s" % ", ".join("%s %d" % (k, len(v)) for k, v in found.items()))


main()
