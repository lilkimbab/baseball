"""The play-by-play caster's voice for the game, served on this machine (the user, 2026-11-23:
the M3 voice, a male caster with the tension of a KBO broadcast, numbers read as a broadcast
reads them). The game sends a line and how excited it is; this speaks it with Supertonic 3
(M3), reads its numbers as a KBO caster would (korean_numbers.py), lifts it by the moment
(hype.py: faster, higher, louder toward the end on a home run or a long hit), gives it a
broadcast microphone's sound, and answers with an OGG. Lines already spoken are kept
(content-local/audio/voice_cache/) and answered at once.

    .tools/supertonic-src/py/.venv/bin/python tools/audio/voice_server.py [--port 8765]

    GET /ping                         -> "ok"
    GET /say?text=...&mood=hot|warm|calm  -> audio/ogg
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
SPEED = 1.18
STEPS = 6
# Semitones up, tempo, the voice's edge, by how excited the line is (as announcer_voice.py).
MOODS = {"hot": (3.0, 1.12, "equalizer=f=3200:t=q:w=1.2:g=5,asoftclip=type=tanh:threshold=0.7,"),
         "warm": (1.5, 1.07, "equalizer=f=3000:t=q:w=1.2:g=3,"),
         "calm": (0.5, 1.03, "")}
CAST = "highpass=f=120,lowpass=f=7500,acompressor=threshold=-22dB:ratio=4:attack=4:release=90:makeup=5,aecho=0.7:0.5:22|41:0.12|0.07"

_lock = threading.Lock()
_tts = None
_style = None


def _load():
    global _tts, _style
    from helper import load_text_to_speech, load_voice_style
    _tts = load_text_to_speech(os.path.join(ST, "assets", "onnx"), False)
    _style = load_voice_style([os.path.join(ST, "assets", "voice_styles", VOICE + ".json")])


def speak(text, mood):
    """The line as an OGG (bytes), from the cache or made now."""
    import numpy as np
    import soundfile as sf
    from korean_numbers import say
    mood = mood if mood in MOODS else "calm"
    key = hashlib.md5(("%s|%s|%s|%.2f" % (VOICE, mood, text, SPEED)).encode("utf-8")).hexdigest()
    path = os.path.join(CACHE, key + ".ogg")
    if os.path.exists(path):
        with open(path, "rb") as f:
            return f.read()
    steps_up, tempo, edge = MOODS[mood]
    with _lock:
        wav, _ = _tts(say(text), "ko", _style, STEPS, SPEED)
    y = np.asarray(wav[0] if getattr(wav, "ndim", 1) > 1 else wav, dtype=np.float32)
    sr = _tts.sample_rate
    y = y * (0.95 / (np.max(np.abs(y)) or 1.0))
    buf = io.BytesIO()
    sf.write(buf, y, sr, format="WAV")
    os.makedirs(CACHE, exist_ok=True)
    # Higher and faster by the moment (the rate raises the pitch; the tempo puts the pace right),
    # louder toward the end on an excited line, then the broadcast's sound.
    rate = 2.0 ** (steps_up / 12.0)
    lift = "asetrate=%d,aresample=%d,atempo=%.4f," % (int(sr * rate), sr, tempo / rate)
    swell = "volume='0.8+0.35*t/%.2f':eval=frame," % max(len(y) / sr / tempo, 0.5) if steps_up >= 1.5 else ""
    out = subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-f", "wav", "-i", "pipe:0", "-af", "%s%s%s%s,aresample=44100,apad=pad_dur=0.25" % (lift, swell, edge, CAST),
                          "-ac", "1", "-c:a", "libvorbis", "-q:a", "5", "-f", "ogg", path], input=buf.getvalue(), capture_output=True)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.decode("utf-8", "replace"))
    with open(path, "rb") as f:
        return f.read()


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
                self._send(200, speak(text, (q.get("mood") or ["calm"])[0]), "audio/ogg")
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
    # The calls the game makes as a ball goes (MatchSound.CALLS), ready before they are asked.
    def warm():
        for text, mood in [("큽니다, 큽니다, 넘어갑니다!", "hot"), ("넘어갔습니다!", "hot"), ("맞는 순간 홈런!", "hot"), ("빠졌습니다! 장타!", "hot"),
                           ("외야를 가릅니다!", "hot"), ("펜스까지 굴러갑니다!", "hot"), ("안타!", "warm"), ("빠져나갑니다!", "warm")]:
            speak(text, mood)
    threading.Thread(target=warm, daemon=True).start()
    print("voice_server: %s on 127.0.0.1:%d" % (VOICE, port), flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


main()
