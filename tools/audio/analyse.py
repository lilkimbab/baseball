"""Looks at a recorded game (tools/sound_record.gd): its loudness second by second, its peak
(clipping?), and a spectrogram written as a PNG (through Blender's image writer, since the
Python here has numpy but no imaging library)..

    blender --background --python tools/audio/analyse.py -- build/sound/game.wav build/sound/game.png
"""
import sys
import wave

import numpy as np

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
src, out = args[0], args[1]
with wave.open(src, "rb") as w:
    sr = w.getframerate()
    ch = w.getnchannels()
    width = w.getsampwidth()
    raw = w.readframes(w.getnframes())
data = np.frombuffer(raw, dtype="<i2" if width == 2 else "<i4").astype(np.float64)
data = data.reshape(-1, ch).mean(axis=1) / (32768.0 if width == 2 else 2147483648.0)
seconds = len(data) / sr
print("length %.1f s, %d Hz, %d ch" % (seconds, sr, ch))
peak = np.max(np.abs(data))
print("peak %.3f (%.1f dBFS)%s" % (peak, 20 * np.log10(max(peak, 1e-9)), "  CLIPPING" if peak >= 0.999 else ""))
rms = [np.sqrt(np.mean(data[i * sr:(i + 1) * sr] ** 2)) for i in range(int(seconds))]
print("rms dBFS by second:", " ".join("%d" % round(20 * np.log10(max(r, 1e-9))) for r in rms))
print("mean rms %.1f dBFS" % (20 * np.log10(max(np.sqrt(np.mean(data ** 2)), 1e-9))))

# Spectrogram: 2048-sample frames, a hop of 1024, log frequency 50 Hz to 12 kHz, 100 rows.
frame, hop = 2048, 1024
win = np.hanning(frame)
cols = (len(data) - frame) // hop
spec = np.zeros((100, cols))
freqs = np.fft.rfftfreq(frame, 1.0 / sr)
edges = np.geomspace(50, 12000, 101)
for c in range(cols):
    seg = data[c * hop:c * hop + frame] * win
    mag = np.abs(np.fft.rfft(seg))
    for r in range(100):
        sel = (freqs >= edges[r]) & (freqs < edges[r + 1])
        spec[99 - r, c] = mag[sel].mean() if sel.any() else 0
db = 20 * np.log10(spec + 1e-6)
db = np.clip((db - db.max() + 70) / 70, 0, 1)
try:
    import bpy
    h, wd = db.shape
    img = bpy.data.images.new("spec", width=wd, height=h)
    rgba = np.zeros((h, wd, 4))
    rgba[..., 0] = db ** 0.6
    rgba[..., 1] = db ** 1.5
    rgba[..., 2] = 0.3 + 0.7 * db ** 3
    rgba[..., 3] = 1
    img.pixels = rgba[::-1].ravel()
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    print("spectrogram", out, "%dx%d" % (wd, h))
except ImportError:
    print("(no bpy: spectrogram skipped)")
