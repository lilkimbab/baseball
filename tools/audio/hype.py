"""Raises a spoken line's tension like a caster's voice at a big moment: a little faster, pitched
up (more on an excited line), louder toward its end. Used on the announcer's lines
(announcer_voice.py) before the broadcast sound.

    <supertonic venv python> tools/audio/hype.py <in.wav> <out.wav> <semitones> <tempo>
"""
import sys

import librosa
import numpy as np
import soundfile as sf


def main():
    src, dst = sys.argv[1], sys.argv[2]
    steps = float(sys.argv[3])
    tempo = float(sys.argv[4])
    y, sr = librosa.load(src, sr=None, mono=True)
    if tempo != 1.0:
        y = librosa.effects.time_stretch(y, rate=tempo)
    if steps != 0.0:
        y = librosa.effects.pitch_shift(y, sr=sr, n_steps=steps)
    # Louder toward the end: the voice rises with the ball.
    ramp = np.linspace(0.8, 1.15, len(y)) if steps >= 1.5 else np.ones(len(y))
    y = y * ramp
    peak = np.max(np.abs(y)) or 1.0
    sf.write(dst, y * (0.95 / peak), sr)


main()
