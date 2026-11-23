"""The umpire's calls as recorded lines (the user, 2026-11-23: "why are strike and ball the system's
TTS? use a generated voice"): Supertonic 3 (the caster's model, another voice than his M3), each
call shouted once, with the ring of a ballpark after it. The game plays them (MatchSound) instead
of the system's speech; generated output of an Open RAIL-M model, ours to ship.

    .tools/supertonic-src/py/.venv/bin/python tools/audio/umpire_calls.py [--voice M1] [--out game/audio/voice]
    .tools/supertonic-src/py/.venv/bin/python tools/audio/umpire_calls.py --samples build/umpire_samples
"""
import argparse
import io
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ST = os.path.join(ROOT, ".tools", "supertonic-src")
sys.path.insert(0, os.path.join(ST, "py"))
FFMPEG = os.path.join(ROOT, ".tools", "ffmpeg", "node_modules", "ffmpeg-static", "ffmpeg")

CALLS = {
    "umpire_strike": "스트라이크!",
    "umpire_strikeout": "스트라이크 아웃!",
    "umpire_out": "아웃!",
    "umpire_safe": "세이프!",
}
STEPS = 10
SPEED = 1.1
# A voice in the open air of a ballpark, picked up by the field microphones.
PARK = "highpass=f=110,acompressor=threshold=-20dB:ratio=3:attack=3:release=80:makeup=4,aecho=0.8:0.55:70|130:0.22|0.12,aresample=44100,apad=pad_dur=0.3"


def make(tts, style, text, path):
    import numpy as np
    import soundfile as sf
    np.random.seed(7)
    wav, _ = tts(text, "ko", style, STEPS, SPEED)
    y = np.asarray(wav[0] if getattr(wav, "ndim", 1) > 1 else wav, dtype=np.float32)
    buf = io.BytesIO()
    sf.write(buf, y, tts.sample_rate, format="WAV")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "wav", "-i", "pipe:0", "-af", PARK,
                          "-ac", "1", "-c:a", "libvorbis", "-q:a", "5", path], input=buf.getvalue(), capture_output=True)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.decode("utf-8", "replace"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--voice", default="M1")
    ap.add_argument("--out", default=os.path.join(ROOT, "game", "audio", "voice"))
    ap.add_argument("--samples", default="")
    a = ap.parse_args()
    from helper import load_text_to_speech, load_voice_style
    tts = load_text_to_speech(os.path.join(ST, "assets", "onnx"), False)
    voices = ["M1", "M2", "M4", "M5"] if a.samples else [a.voice]
    for voice in voices:
        style = load_voice_style([os.path.join(ST, "assets", "voice_styles", voice + ".json")])
        for name, text in CALLS.items():
            folder = os.path.join(a.samples, voice) if a.samples else a.out
            make(tts, style, text, os.path.join(folder, name + ".ogg"))
        print("umpire_calls: %s done" % voice)


if __name__ == "__main__":
    main()
