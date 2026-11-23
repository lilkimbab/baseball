"""The play-by-play caster's voice for the game, served on this machine. The voice is the
"남자_M3" sample the user chose (2026-11-23: "M3 is best, it sounds least like an AI — fix only
the reading of numbers, never touch the voice, and use it for every line"): Supertonic 3's M3,
ten steps at speed 1.18; a line with "!" a touch faster (×1.08) and higher (3%, +1.6 dB), as that
sample had; the broadcast microphone's band after it. Numbers are read as a KBO broadcast reads
them (korean_numbers.py). Lines already spoken are kept (content-local/audio/voice_cache/).

    .tools/supertonic-src/py/.venv/bin/python tools/audio/voice_server.py [--port 8765]

    GET /ping                         -> "ok"
    GET /say?text=...&mood=...        -> audio/ogg (the mood is not used: one voice for all)
"""
import hashlib
import io
import os
import subprocess
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ST = os.path.join(ROOT, ".tools", "supertonic-src")
sys.path.insert(0, os.path.join(ST, "py"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
FFMPEG = os.path.join(ROOT, ".tools", "ffmpeg", "node_modules", "ffmpeg-static", "ffmpeg")
CACHE = os.path.join(ROOT, "content-local", "audio", "voice_cache")
VOICE = "M3"
## As the chosen sample: the model's steps, its speed, and for a line with "!" the touch faster
## and higher it was given there.
STEPS = 10
SPEED = 1.18
EXCITED_SPEED = 1.08
EXCITED_LIFT = 1.03
EXCITED_GAIN_DB = 1.6
# Version of the sound, in the cache key: a change to it makes the lines again.
SOUND = 4
CAST = "highpass=f=120,lowpass=f=7500,acompressor=threshold=-22dB:ratio=4:attack=4:release=90:makeup=5,aecho=0.7:0.5:22|41:0.12|0.07"

_lock = threading.Lock()
_tts = None
_style = None


def _load():
    global _tts, _style
    from helper import load_text_to_speech, load_voice_style
    _tts = load_text_to_speech(os.path.join(ST, "assets", "onnx"), False)
    _style = load_voice_style([os.path.join(ST, "assets", "voice_styles", VOICE + ".json")])


def speak(text, mood="calm", part=None):
    """The line as an OGG (bytes), from the cache or made now. (`mood` and `part` are what older
    games ask with; one voice serves every line, and part 1 is always empty.)"""
    import numpy as np
    import soundfile as sf
    from korean_numbers import say
    if part == 1:
        return b""
    key = hashlib.md5(("%s|%s|%d" % (VOICE, text, SOUND)).encode("utf-8")).hexdigest()
    path = os.path.join(CACHE, key + ".ogg")
    if os.path.exists(path):
        with open(path, "rb") as f:
            return f.read()
    excited = "!" in text
    with _lock:
        np.random.seed(int(hashlib.md5(text.encode("utf-8")).hexdigest()[:8], 16))
        wav, _ = _tts(say(text), "ko", _style, STEPS, SPEED * (EXCITED_SPEED if excited else 1.0))
    y = np.asarray(wav[0] if getattr(wav, "ndim", 1) > 1 else wav, dtype=np.float32)
    sr = _tts.sample_rate
    buf = io.BytesIO()
    sf.write(buf, y, sr, format="WAV")
    os.makedirs(CACHE, exist_ok=True)
    lift = "asetrate=%d,aresample=%d,volume=%.1fdB," % (int(sr * EXCITED_LIFT), sr, EXCITED_GAIN_DB) if excited else ""
    made = "%s.%d.tmp" % (path, threading.get_ident())
    out = subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "wav", "-i", "pipe:0", "-af", "%s%s,aresample=44100,apad=pad_dur=0.25" % (lift, CAST),
                          "-ac", "1", "-c:a", "libvorbis", "-q:a", "5", "-f", "ogg", made], input=buf.getvalue(), capture_output=True)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.decode("utf-8", "replace"))
    os.replace(made, path)
    with open(path, "rb") as f:
        return f.read()


COMMENTARY = os.path.join(ROOT, "game", "data", "commentary.ko.json")
POSITIONS = ["투수", "포수", "1루수", "2루수", "3루수", "유격수", "좌익수", "중견수", "우익수"]
CALL_MOODS = {"call_deep": "build", "call_gap": "build", "call_single": "warm", "call_infield": "warm"}


def direction_slots(direction, bats_left):
    """As Commentary.direction_slots in the game: the fielder, the side, the wall, the swing."""
    out = {"field": POSITIONS[direction - 1]}
    left_side, right_side = direction in (5, 6, 7), direction in (3, 4, 9)
    if left_side:
        out["side"] = "왼쪽"
    elif right_side:
        out["side"] = "오른쪽"
    elif direction != 2:
        out["side"] = "가운데"
    if direction >= 7:
        out["wall"] = ["좌측 담장", "가운데 담장", "우측 담장"][direction - 7]
    if direction in (1, 8):
        out["swing"] = "받아쳤습니다"
    elif left_side or right_side:
        out["swing"] = "잡아당겼습니다" if left_side != bats_left else "밀어쳤습니다"
    return out


def calls():
    """Every call the game can make, filled for each direction and side: [(text, mood)]."""
    import json
    import re
    with open(COMMENTARY, encoding="utf-8") as f:
        lines = json.load(f)
    out = []
    for key, mood in CALL_MOODS.items():
        for template in lines.get(key, []):
            slots = set(re.findall(r"{(\w+)}", template))
            for direction in (range(1, 7) if key == "call_infield" else range(7, 10)):
                for bats_left in (False, True):
                    fill = direction_slots(direction, bats_left)
                    if not slots <= set(fill):
                        continue
                    text = template
                    for k in slots:
                        text = text.replace("{%s}" % k, fill[k])
                    if (text, mood) not in out:
                        out.append((text, mood))
    return out


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(url.query)
        if url.path == "/ping":
            self._send(200, b"ok", "text/plain")
            return
        if url.path == "/say":
            text = (q.get("text") or [""])[0].strip()
            if not text:
                self._send(400, b"no text", "text/plain")
                return
            try:
                part = (q.get("part") or [""])[0]
                self._send(200, speak(text, (q.get("mood") or ["calm"])[0], int(part) if part in ("0", "1") else None), "audio/ogg")
            except Exception as e:  # noqa: BLE001  (the game falls back to silence)
                self._send(500, str(e).encode("utf-8"), "text/plain")
            return
        self._send(404, b"", "text/plain")

    def _send(self, code, body, kind):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        # (Closed after each answer: a connection the game's side kept open held it from exiting.)
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)


def main():
    port = 8765
    if "--port" in sys.argv:
        port = int(sys.argv[sys.argv.index("--port") + 1])
    _load()
    # Ready before they are asked: the calls the game makes as a ball goes (the call_* lines of
    # the commentary file, for every direction and either side of the plate).
    def warm():
        try:
            for text, mood in calls():
                speak(text, mood)
            print("voice_server: calls ready", flush=True)
        except Exception as e:  # noqa: BLE001
            print("voice_server: warm-up:", e, flush=True)
    threading.Thread(target=warm, daemon=True).start()
    print("voice_server: %s on 127.0.0.1:%d" % (VOICE, port), flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


main()
