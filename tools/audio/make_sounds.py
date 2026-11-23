"""Makes the game's own sounds (docs/11, docs/13 S15): every effect, the crowd, the cheering
instruments and the short music, synthesised from noise and oscillators, written as OGG
Vorbis into game/audio/. Nothing is recorded or taken from anywhere; real chants, walk-up
songs and menu music can be dropped into content-local/audio/ and are played instead.

Run with a Python that has numpy (Blender's does), ffmpeg on the way to Vorbis:

    ./dev audio            # or: <python> tools/audio/make_sounds.py <ffmpeg> <out dir>

The physics picks among the effects: the exit speed picks the bat's tier (1 weak .. 4
crushed), the contact its kind (solid, jam, end), the pitch speed the mitt's tier.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
RNG = np.random.default_rng(20261122)


# --- Building blocks ---------------------------------------------------------------------

def t_axis(seconds, sr=SR):
    return np.arange(int(seconds * sr)) / sr


def noise(seconds, sr=SR):
    return RNG.standard_normal(int(seconds * sr))


def band(x, lo, hi, sr=SR, soft=0.15):
    """Band-pass by masking the spectrum (raised-cosine edges `soft` of an octave wide)."""
    n = len(x)
    if n == 0:
        return x
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / sr)
    mask = np.ones_like(f)
    if lo > 0:
        edge = lo * (2 ** soft - 1)
        mask *= np.clip((f - (lo - edge)) / max(edge * 2, 1e-6), 0, 1)
    if hi < sr / 2:
        edge = hi * (2 ** soft - 1)
        mask *= np.clip(((hi + edge) - f) / max(edge * 2, 1e-6), 0, 1)
    return np.fft.irfft(spec * mask, n)


def formants(x, peaks, sr=SR):
    """Shapes noise with vowel formants: peaks = [(freq, width, gain), ...]."""
    n = len(x)
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / sr)
    shape = np.full_like(f, 0.02)
    for freq, width, gain in peaks:
        shape += gain * np.exp(-0.5 * ((f - freq) / width) ** 2)
    return np.fft.irfft(spec * shape, n)


def lowpass_sweep(x, start, end, sr=SR, blocks=48):
    """A low-pass whose corner moves from start to end Hz over the sound (block-wise)."""
    out = np.zeros_like(x)
    edges = np.linspace(0, len(x), blocks + 1).astype(int)
    fade = 256
    for i in range(blocks):
        a, b = edges[i], edges[i + 1]
        a0, b0 = max(a - fade, 0), min(b + fade, len(x))
        corner = start + (end - start) * (i + 0.5) / blocks
        part = band(x[a0:b0], 0, corner, sr)
        w = np.ones(b0 - a0)
        ramp = np.linspace(0, 1, fade)
        if a0 < a:
            w[:a - a0 + 0] = 0
            w[a - a0:a - a0 + fade] = ramp[: min(fade, b0 - a)]
        out[a0:b0] += part * w[: b0 - a0]
    return out


def decay(seconds, tau, attack=0.0005, sr=SR):
    t = t_axis(seconds, sr)
    env = np.exp(-t / tau)
    if attack > 0:
        env *= np.clip(t / attack, 0, 1)
    return env


def mode(seconds, freq, tau, sr=SR, phase=None):
    t = t_axis(seconds, sr)
    p = RNG.uniform(0, 2 * np.pi) if phase is None else phase
    return np.sin(2 * np.pi * freq * t + p) * np.exp(-t / tau)


def pad(x, seconds, sr=SR):
    n = int(seconds * sr)
    return np.pad(x, (0, max(n - len(x), 0)))[:n]


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x, seconds, total, sr=SR):
    out = np.zeros(int(total * sr))
    i = int(seconds * sr)
    j = min(i + len(x), len(out))
    if i < len(out):
        out[i:j] += x[: j - i]
    return out


def normalise(x, peak=0.89):
    m = np.max(np.abs(x)) if len(x) else 0
    return x * (peak / m) if m > 0 else x


def loop_seam(x, seconds, sr=SR):
    """Makes a sound loop without a click: its last `seconds` crossfaded into its start."""
    n = int(seconds * sr)
    if x.ndim == 1:
        head, tail, body = x[:n], x[-n:], x[n:-n]
        fade = np.linspace(0, 1, n)
        return np.concatenate([tail * (1 - fade) + head * fade, body])
    return np.stack([loop_seam(x[:, c], seconds, sr) for c in range(x.shape[1])], axis=1)


# --- Writing ----------------------------------------------------------------------------

FFMPEG = "ffmpeg"
OUT = "game/audio"
WRITTEN = []


def write(name, x, sr=SR, peak=0.89, quality=4):
    """Writes x (mono, or frames x 2) as OUT/name.ogg."""
    x = np.asarray(x, dtype=np.float64)
    x = normalise(x, peak)
    path = os.path.join(OUT, name + ".ogg")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    channels = 1 if x.ndim == 1 else x.shape[1]
    pcm = np.clip(x * 32767, -32768, 32767).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = tmp.name
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
    os.remove(wav_path)
    WRITTEN.append(path)


# --- Bat, ball, gloves ------------------------------------------------------------------

def bat_solid(tier):
    """A wooden bat on the sweet spot: a bright crack, high and short; harder is louder,
    brighter and a little longer."""
    k = tier / 4.0
    click = band(noise(0.004), 2500, 12000) * decay(0.004, 0.0009)
    body = sum(mode(0.18, f * RNG.uniform(0.96, 1.04), tau * (0.8 + 0.4 * k)) * a
               for f, tau, a in [(560, 0.045, 0.7), (1240, 0.03, 1.0), (2050, 0.022, 0.8), (3100, 0.012, 0.5)])
    thock = mode(0.06, 190 * RNG.uniform(0.95, 1.05), 0.012) * 0.5
    snap = band(noise(0.03), 1500, 6000) * decay(0.03, 0.004) * 0.6
    return mix(click * (1.2 + k), body * (0.6 + 0.6 * k), thock, snap * (0.5 + k))


def bat_jam(tier):
    """Off the handle: a dull thud with a buzz, low and ringing."""
    thud = mode(0.3, 140 * RNG.uniform(0.9, 1.1), 0.09) + mode(0.3, 260, 0.06) * 0.5
    buzz = (1 + 0.6 * np.sin(2 * np.pi * 36 * t_axis(0.3))) * band(noise(0.3), 120, 900) * decay(0.3, 0.07) * 0.35
    click = band(noise(0.004), 900, 4000) * decay(0.004, 0.001) * 0.6
    return mix(thud * (0.7 + 0.1 * tier), buzz, click)


def bat_end(tier):
    """Off the end: a 'tink' with a beating vibration."""
    tink = mode(0.25, 720 * RNG.uniform(0.95, 1.05), 0.08) + mode(0.25, 748, 0.08) * 0.8
    hum = mode(0.25, 165, 0.1) * 0.5
    click = band(noise(0.004), 1500, 7000) * decay(0.004, 0.001)
    return mix(tink * 0.6, hum, click * (0.6 + 0.1 * tier))


def foul_tip():
    return mix(band(noise(0.02), 1800, 8000) * decay(0.02, 0.002), mode(0.05, 900, 0.01) * 0.3)


def mitt(tier):
    """The catcher's mitt: a leather pop that gets sharper with the pitch's speed."""
    k = tier / 3.0
    pop = band(noise(0.08), 700 + 300 * k, 5200) * decay(0.08, 0.012 + 0.004 * (1 - k))
    thump = mode(0.1, 110 * RNG.uniform(0.9, 1.1), 0.03)
    slap = band(noise(0.006), 3000, 10000) * decay(0.006, 0.001)
    return mix(pop * (0.7 + 0.6 * k), thump * 0.8, slap * (0.4 + 0.8 * k))


def glove():
    return mix(band(noise(0.06), 500, 3200) * decay(0.06, 0.01), mode(0.06, 150 * RNG.uniform(0.9, 1.1), 0.02) * 0.6)


def bare_hand():
    return band(noise(0.04), 900, 4500) * decay(0.04, 0.006)


def bounce(ground):
    thud = mode(0.1, (95 if ground == "grass" else 120) * RNG.uniform(0.9, 1.1), 0.025)
    if ground == "grass":
        rustle = band(noise(0.08), 1500, 7000) * decay(0.08, 0.012) * 0.25
    else:
        rustle = band(noise(0.12), 700, 6000) * decay(0.12, 0.03) * 0.45 * (1 + 0.5 * RNG.standard_normal(int(0.12 * SR)))
    return mix(thud, rustle)


def fence(kind):
    if kind == "pad":
        return mix(mode(0.25, 70, 0.06), band(noise(0.1), 150, 900) * decay(0.1, 0.02) * 0.5)
    if kind == "wall":
        return mix(mode(0.3, 310, 0.05), mode(0.3, 870, 0.03) * 0.6, band(noise(0.01), 800, 6000) * decay(0.01, 0.002))
    return band(noise(0.35), 1500, 9000) * decay(0.35, 0.08) * (1 - np.exp(-t_axis(0.35) / 0.01))


def step(ground):
    n = 0.07
    grit = band(noise(n), 600 if ground == "dirt" else 1200, 5000) * decay(n, 0.014)
    return mix(grit, mode(n, 90, 0.015) * 0.6)


def slide():
    n = 0.8
    t = t_axis(n)
    env = np.clip(t / 0.05, 0, 1) * np.exp(-np.maximum(t - 0.25, 0) / 0.18)
    return band(noise(n), 250, 4000) * env * (1 + 0.4 * RNG.standard_normal(len(t)))


def dive():
    return mix(mode(0.2, 80, 0.05), band(noise(0.35), 400, 4000) * decay(0.35, 0.09) * 0.6)


def swing(power):
    n = 0.32
    t = t_axis(n)
    env = np.exp(-((t - 0.13) / 0.05) ** 2)
    x = noise(n)
    whoosh = mix(band(x, 280, 1400) * 0.8, band(x, 1200, 3500) * 0.35) * env
    return whoosh * (0.7 + 0.3 * power)


def base_tag():
    return mix(mode(0.08, 140, 0.02), band(noise(0.03), 500, 2500) * decay(0.03, 0.006) * 0.4)


# --- The interface ----------------------------------------------------------------------

def blip(freqs, length=0.06, tau=0.03, shape="sine"):
    t = t_axis(length)
    out = np.zeros_like(t)
    for f in freqs:
        wave_ = np.sin(2 * np.pi * f * t) if shape == "sine" else np.sign(np.sin(2 * np.pi * f * t)) * 0.4
        out += wave_
    return out * np.exp(-t / tau) * np.clip(t / 0.002, 0, 1)


def ui_sounds():
    write("ui/move", blip([1320], 0.04, 0.012), peak=0.35)
    write("ui/select", mix(blip([880], 0.08, 0.03), at(blip([1320], 0.08, 0.03), 0.045, 0.13)), peak=0.45)
    write("ui/back", mix(blip([990], 0.07, 0.025), at(blip([660], 0.08, 0.03), 0.05, 0.13)), peak=0.4)
    write("ui/confirm", mix(blip([660, 990], 0.1, 0.04), at(blip([880, 1320], 0.14, 0.06), 0.07, 0.22)), peak=0.5)
    write("ui/tick", blip([2200], 0.02, 0.006), peak=0.25)
    write("ui/judge_perfect", mix(blip([1046, 1568], 0.18, 0.08), at(blip([2093], 0.2, 0.08), 0.06, 0.26)), peak=0.5)
    write("ui/judge_good", blip([988, 1480], 0.15, 0.06), peak=0.45)
    write("ui/judge_bad", blip([220, 233], 0.2, 0.1, "square"), peak=0.4)


# --- The crowd --------------------------------------------------------------------------

VOWELS = {
    "a": [(750, 90, 1.0), (1250, 120, 0.6), (2600, 200, 0.25)],
    "e": [(520, 80, 1.0), (1850, 150, 0.5), (2600, 200, 0.25)],
    "o": [(460, 70, 1.0), (820, 90, 0.55), (2500, 200, 0.15)],
    "u": [(340, 60, 1.0), (720, 90, 0.4), (2400, 200, 0.1)],
    "i": [(300, 60, 0.9), (2200, 180, 0.5), (3000, 220, 0.25)],
}


def babble(seconds, voices, sr=SR, busy=1.0):
    """Many people talking at once: each a stream of syllables through vowel formants, panned
    about; under them a far, dull wash. Returns frames x 2."""
    n = int(seconds * sr)
    out = np.zeros((n, 2))
    keys = list(VOWELS)
    for v in range(voices):
        env = np.zeros(n)
        pos = RNG.uniform(0, 0.4)
        while pos < seconds:
            length = RNG.uniform(0.09, 0.28)
            if RNG.uniform() < 0.8 * busy:
                a = int(pos * sr)
                b = min(int((pos + length) * sr), n)
                w = np.hanning(max(b - a, 2))[: b - a]
                env[a:b] += w * RNG.uniform(0.5, 1.0)
            pos += length + RNG.exponential(0.12 / busy)
        shift = RNG.uniform(0.85, 1.25)
        peaks = [(f * shift, w, g) for f, w, g in VOWELS[keys[v % len(keys)]]]
        voice = formants(RNG.standard_normal(n), peaks, sr) * env
        distance = RNG.uniform(0.25, 1.0)
        pan = RNG.uniform(0.1, 0.9)
        out[:, 0] += voice * distance * np.sqrt(1 - pan)
        out[:, 1] += voice * distance * np.sqrt(pan)
    wash = band(RNG.standard_normal(n), 120, 1600, sr)
    wash2 = band(RNG.standard_normal(n), 120, 1600, sr)
    level = np.std(out) if np.std(out) > 0 else 1.0
    out[:, 0] += wash * level * 0.9
    out[:, 1] += wash2 * level * 0.9
    return out


def claps(seconds, rate, sr=SR, swell=True):
    """Applause: claps at `rate` a second, each a short bright burst."""
    n = int(seconds * sr)
    out = np.zeros((n, 2))
    count = int(rate * seconds)
    times = np.sort(RNG.uniform(0, seconds, count))
    one = int(0.012 * sr)
    for tm in times:
        a = int(tm * sr)
        b = min(a + one, n)
        burst = RNG.standard_normal(b - a) * np.exp(-np.arange(b - a) / (0.0025 * sr))
        pan = RNG.uniform(0, 1)
        g = RNG.uniform(0.3, 1.0)
        out[a:b, 0] += burst * g * np.sqrt(1 - pan)
        out[a:b, 1] += burst * g * np.sqrt(pan)
    out[:, 0] = band(out[:, 0], 700, 5500, sr)
    out[:, 1] = band(out[:, 1], 700, 5500, sr)
    if swell:
        t = np.arange(n) / sr
        env = np.clip(t / 0.25, 0, 1) * np.clip((seconds - t) / (seconds * 0.45), 0, 1)
        out *= env[:, None]
    return out


def shout(seconds, vowel, voices, rise=0.15, fall=None, glide=1.0, sr=SR):
    """Many voices on one vowel (a cheer, a groan, an 'ooh'), swelling and fading;
    `glide` moves the formants by that factor over the sound."""
    n = int(seconds * sr)
    t = np.arange(n) / sr
    fall = fall if fall is not None else seconds * 0.5
    env = np.clip(t / rise, 0, 1) * np.clip((seconds - t) / fall, 0, 1)
    out = np.zeros((n, 2))
    half = n // 2
    for v in range(voices):
        shift = RNG.uniform(0.85, 1.2)
        start_peaks = [(f * shift, w * 1.3, g) for f, w, g in VOWELS[vowel]]
        end_peaks = [(f * shift * glide, w * 1.3, g) for f, w, g in VOWELS[vowel]]
        x = RNG.standard_normal(n)
        a = formants(x[:half + 2048], start_peaks, sr)[:half]
        b = formants(x[half - 2048:], end_peaks, sr)[2048:]
        voice = np.concatenate([a, b])
        voice *= 1 + 0.25 * np.sin(2 * np.pi * RNG.uniform(3, 6) * t + RNG.uniform(0, 6))
        pan = RNG.uniform(0.1, 0.9)
        g = RNG.uniform(0.4, 1.0)
        out[:, 0] += voice * g * np.sqrt(1 - pan)
        out[:, 1] += voice * g * np.sqrt(pan)
    return out * env[:, None]


def crowd_sounds():
    # The beds: quiet, normal and loud, of different lengths so their seams never line up.
    for name, length, voices, busy in [("bed_quiet", 23.0, 40, 0.6), ("bed_normal", 29.0, 90, 0.9), ("bed_loud", 31.0, 160, 1.3)]:
        bed = babble(length + 2.0, voices, busy=busy)
        write("crowd/" + name, loop_seam(bed, 2.0), peak=0.6)
    for name, length, rate in [("clap_light", 3.0, 45), ("clap", 3.5, 140), ("clap_big", 4.5, 420)]:
        write("crowd/" + name, claps(length, rate), peak=0.55)
    cheer_short = shout(2.2, "e", 60, 0.12, 1.4) + 0.4 * claps(2.2, 160)
    write("crowd/cheer", cheer_short, peak=0.75)
    cheer_long = shout(3.6, "a", 110, 0.15, 2.0) + shout(3.6, "e", 50, 0.3, 2.2) * 0.6 + 0.5 * claps(3.6, 260)
    write("crowd/cheer_long", cheer_long, peak=0.8)
    roar = shout(5.5, "a", 180, 0.12, 2.6) + shout(5.5, "o", 80, 0.4, 3.0) * 0.6 + 0.7 * claps(5.5, 520)
    write("crowd/roar", roar, peak=0.85)
    write("crowd/groan", shout(1.8, "o", 90, 0.08, 1.2, glide=0.82), peak=0.65)
    write("crowd/groan_big", shout(2.6, "o", 140, 0.06, 1.8, glide=0.78) + shout(2.6, "u", 60, 0.1, 1.8, glide=0.85) * 0.5, peak=0.7)
    write("crowd/boo", shout(2.4, "u", 90, 0.25, 1.0), peak=0.6)
    write("crowd/ooh", shout(1.4, "o", 100, 0.18, 0.7, glide=1.08), peak=0.65)
    # The rise as a big fly goes up: louder and brighter, in three lengths.
    for length in (2, 4, 6):
        n = int(length * SR)
        bed = babble(length, 140, busy=1.3)
        t = np.arange(n) / SR
        swell = (t / length) ** 1.6
        rise = np.stack([lowpass_sweep(bed[:, c], 700, 3500) for c in range(2)], axis=1) * (0.15 + 0.85 * swell)[:, None]
        rise += shout(length, "o", 90, length * 0.8, 0.05, glide=1.15) * 0.8
        write("crowd/rise_%d" % length, rise, peak=0.75)
    # Near voices for the batting and pitching cameras.
    for i, vowel in enumerate(["e", "a", "o", "i"]):
        one = shout(RNG.uniform(0.4, 0.8), vowel, 2, 0.05, 0.3)
        write("crowd/voice_%d" % (i + 1), one[:, 0], peak=0.5)
    t = t_axis(0.9)
    whistle = np.sin(2 * np.pi * (2400 + 600 * np.clip(t / 0.3, 0, 1) - 400 * np.clip((t - 0.5) / 0.4, 0, 1)) * t) * np.clip(t / 0.03, 0, 1) * np.clip((0.9 - t) / 0.2, 0, 1)
    write("crowd/whistle_fan", whistle, peak=0.35)


# --- Cheering instruments ---------------------------------------------------------------

def kick():
    t = t_axis(0.35)
    f = 48 + 60 * np.exp(-t / 0.03)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return mix(np.sin(phase) * np.exp(-t / 0.12), band(noise(0.01), 1500, 6000) * decay(0.01, 0.002) * 0.3)


def tom():
    t = t_axis(0.3)
    f = 140 + 40 * np.exp(-t / 0.04)
    return mix(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.1), band(noise(0.05), 300, 3000) * decay(0.05, 0.01) * 0.3)


def thunder_sticks():
    """Two inflated sticks struck together: a hollow plastic clack, many fans at once."""
    out = np.zeros(int(0.12 * SR))
    for k in range(40):
        clack = band(noise(0.03), 900, 4200) * decay(0.03, 0.006) + mode(0.03, RNG.uniform(380, 520), 0.008) * 0.6
        out += at(clack, RNG.normal(0.02, 0.006) % 0.08, 0.12) * RNG.uniform(0.4, 1.0)
    return out


def fan_whistle():
    t = t_axis(0.38)
    f = 2750 + 40 * np.sin(2 * np.pi * 26 * t)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.clip(t / 0.02, 0, 1) * np.clip((0.38 - t) / 0.05, 0, 1)
    return tone + band(noise(0.38), 2000, 6000) * 0.08 * np.clip((0.38 - t) / 0.05, 0, 1)


def chant_hey(voices=120):
    return shout(0.32, "e", voices, 0.03, 0.18)


def chant_oh(voices=120):
    return shout(0.5, "o", voices, 0.05, 0.25)


def cheer_sounds():
    write("cheer/drum_low", kick(), peak=0.8)
    write("cheer/drum_high", tom(), peak=0.7)
    write("cheer/sticks", thunder_sticks(), peak=0.6)
    write("cheer/whistle", fan_whistle(), peak=0.45)
    write("cheer/hey", chant_hey(), peak=0.7)
    write("cheer/oh", chant_oh(), peak=0.7)
    write("cheer/hey_small", chant_hey(30), peak=0.5)


# --- Music ------------------------------------------------------------------------------

NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def hz(name):
    """'C4', 'F#5' -> Hz."""
    pitch = name[:-1]
    octave = int(name[-1])
    return 440.0 * 2 ** ((NOTE[pitch] + 12 * (octave + 1) - 69) / 12)


def organ(freq, seconds, drawbars=(8, 8, 8, 0, 0, 0, 2, 0, 0)):
    """A tonewheel organ: the nine drawbars' partials, a little rotary-speaker wobble."""
    t = t_axis(seconds)
    ratios = [0.5, 1.5, 1, 2, 3, 4, 5, 6, 8]
    out = np.zeros_like(t)
    for r, level in zip(ratios, drawbars):
        if level:
            out += (level / 8.0) * np.sin(2 * np.pi * freq * r * t + RNG.uniform(0, 6))
    wobble = 1 + 0.12 * np.sin(2 * np.pi * 6.2 * t)
    env = np.clip(t / 0.006, 0, 1) * np.clip((seconds - t) / 0.03, 0, 1)
    return out * wobble * env


def brass(freq, seconds):
    t = t_axis(seconds)
    saw = sum(np.sin(2 * np.pi * freq * k * t) / k for k in range(1, 14))
    env = np.clip(t / 0.03, 0, 1) * np.clip((seconds - t) / 0.08, 0, 1)
    bright = lowpass_sweep(saw * env, 1200, 2600, blocks=8)
    return bright


def sequence(notes, bpm, voice, total=None):
    """notes = [(beat, length in beats, 'C5' or ['C4','E4'])]."""
    beat = 60.0 / bpm
    end = max(b + l for b, l, _ in notes) * beat + 0.3
    total = total or end
    out = np.zeros(int(total * SR))
    for b, l, pitch in notes:
        names = pitch if isinstance(pitch, list) else [pitch]
        for nm in names:
            out += at(voice(hz(nm), l * beat), b * beat, total)
    return out


def drums(pattern, bpm, bars, total=None):
    """pattern: dict beat (0..4 in a bar, eighths allowed) -> 'k', 's', 'h'."""
    beat = 60.0 / bpm
    total = total or bars * 4 * beat + 0.4
    out = np.zeros(int(total * SR))
    snare = band(noise(0.18), 900, 8000) * decay(0.18, 0.05) + mode(0.18, 190, 0.04) * 0.6
    hat = band(noise(0.05), 6000, 16000) * decay(0.05, 0.012) * 0.4
    sounds = {"k": kick() * 0.9, "s": snare * 0.7, "h": hat}
    for bar in range(bars):
        for pos, kinds in pattern.items():
            for kind in kinds:
                out += at(sounds[kind], (bar * 4 + pos) * beat, total)
    return out


def music_sounds():
    # Organ riffs between pitches: short, original, in major keys.
    riffs = [
        [(0, 0.5, "G4"), (0.5, 0.5, "C5"), (1, 0.5, "E5"), (1.5, 0.5, "G5"), (2.5, 0.5, "E5"), (3, 1.5, "G5")],
        [(0, 0.5, "C5"), (0.5, 0.5, "D5"), (1, 0.5, "E5"), (1.5, 0.5, "C5"), (2, 0.5, "F5"), (2.5, 0.5, "E5"), (3, 1, "D5")],
        [(0, 0.75, "E5"), (0.75, 0.25, "E5"), (1, 0.5, "D5"), (1.5, 0.5, "C5"), (2, 1, "G5"), (3, 1, ["C5", "E5", "G5"])],
        [(0, 0.5, "A4"), (0.5, 0.5, "C5"), (1, 0.5, "E5"), (1.5, 0.5, "A5"), (2, 0.5, "G5"), (2.5, 0.5, "E5"), (3, 1, ["A4", "C5", "E5"])],
        [(0, 0.25, "G4"), (0.25, 0.25, "G4"), (0.5, 0.5, "G4"), (1, 0.5, "C5"), (2, 0.25, "G4"), (2.25, 0.25, "G4"), (2.5, 0.5, "G4"), (3, 1, "D5")],
        [(0, 0.5, "F4"), (0.5, 0.5, "A4"), (1, 0.5, "C5"), (1.5, 0.5, "F5"), (2, 0.5, "E5"), (2.5, 0.5, "C5"), (3, 1.5, ["F4", "A4", "C5"])],
    ]
    for i, notes in enumerate(riffs):
        write("music/organ_%d" % (i + 1), sequence(notes, 132, organ), peak=0.55)
    # A short phrase between innings, a fanfare for a home run, the end of a game.
    jingles = [
        ([(0, 0.5, ["C4", "E4", "G4"]), (0.5, 0.5, ["C4", "E4", "G4"]), (1, 1, ["D4", "F4", "A4"]), (2, 2, ["E4", "G4", "C5"])], 150),
        ([(0, 0.5, ["G3", "D4", "G4"]), (0.75, 0.25, ["G3", "D4", "G4"]), (1, 0.5, ["A3", "E4", "A4"]), (1.5, 2.5, ["B3", "D4", "G4"])], 140),
        ([(0, 0.25, "C5"), (0.25, 0.25, "E5"), (0.5, 0.25, "G5"), (0.75, 1.25, ["C5", "E5", "G5", "C6"])], 160),
    ]
    for i, (notes, bpm) in enumerate(jingles):
        x = sequence(notes, bpm, brass)
        x = mix(x, drums({0: "k", 1: "s", 2: "k", 3: "s"}, bpm, 1, len(x) / SR) * 0.5)
        write("music/jingle_%d" % (i + 1), x, peak=0.65)
    fanfare = sequence([(0, 0.5, ["C4", "G4", "C5"]), (0.5, 0.5, ["C4", "G4", "C5"]), (1, 0.5, ["D4", "A4", "D5"]), (1.5, 0.5, ["E4", "B4", "E5"]),
                        (2, 1, ["F4", "C5", "F5"]), (3, 0.5, ["E4", "G4", "C5"]), (3.5, 2.5, ["G4", "C5", "E5", "G5"])], 138, brass)
    fanfare = mix(fanfare, drums({0: "k", 0.5: "k", 1: "s", 2: "k", 3: "s", 3.5: "s"}, 138, 2, len(fanfare) / SR) * 0.55)
    write("music/homerun", fanfare, peak=0.7)
    win = sequence([(0, 1, ["C4", "E4", "G4"]), (1, 1, ["F4", "A4", "C5"]), (2, 1, ["G4", "B4", "D5"]), (3, 3, ["C5", "E5", "G5", "C6"])], 120, brass)
    write("music/win", win, peak=0.65)
    lose = sequence([(0, 1.5, ["A3", "C4", "E4"]), (1.5, 1.5, ["F3", "A3", "C4"]), (3, 3, ["E3", "G#3", "B3"])], 90, lambda f, s: organ(f, s, (0, 8, 6, 4, 0, 0, 0, 0, 0)))
    write("music/lose", lose, peak=0.55)
    # The pressure of a big moment: a low drone and a heartbeat, looping.
    t = t_axis(8.0)
    drone = (np.sin(2 * np.pi * 55 * t) + 0.5 * np.sin(2 * np.pi * 82.4 * t)) * 0.25 * (1 + 0.2 * np.sin(2 * np.pi * 0.25 * t))
    beat = np.zeros_like(t)
    for k in range(10):
        for off, g in ((0.0, 1.0), (0.22, 0.7)):
            beat += at(mode(0.2, 52, 0.05) * g, k * 0.8 + off, 8.0)
    write("music/pressure", loop_seam(mix(drone, beat), 0.5), peak=0.6)
    # The menus: an upbeat loop, 16 bars at 120 (I-V-vi-IV in C), drums, bass, organ chords, a lead.
    bpm = 120
    bars = 16
    chords = [["C3", "E4", "G4", "C5"], ["G2", "D4", "G4", "B4"], ["A2", "C4", "E4", "A4"], ["F2", "C4", "F4", "A4"]]
    roots = ["C2", "G1", "A1", "F1"]
    notes = []
    bass = []
    for bar in range(bars):
        ch = chords[bar % 4]
        for b in (0, 1.5, 2.5):
            notes.append((bar * 4 + b, 1.0 if b else 1.5, ch[1:]))
        r = roots[bar % 4]
        for b in (0, 1, 2, 3, 3.5):
            bass.append((bar * 4 + b, 0.5, r if b != 3.5 else r[:-1] + str(int(r[-1]) + 1)))
    total = bars * 4 * 60.0 / bpm + 1.0
    lead_line = ["E5", "G5", "A5", "G5", "D5", "G5", "B5", "A5", "C5", "E5", "A5", "G5", "C5", "F5", "A5", "G5"]
    lead = []
    for bar in range(8, 16):
        for k in range(4):
            lead.append((bar * 4 + k * 0.5 + (1 if k > 1 else 0), 0.5, lead_line[(bar * 2 + k) % len(lead_line)]))
    music = mix(
        sequence(notes, bpm, lambda f, s: organ(f, s, (0, 0, 8, 6, 4, 0, 0, 2, 0)), total) * 0.35,
        sequence(bass, bpm, lambda f, s: organ(f, s, (8, 0, 8, 0, 0, 0, 0, 0, 0)), total) * 0.45,
        sequence(lead, bpm, brass, total) * 0.25,
        drums({0: "kh", 0.5: "h", 1: "sh", 1.5: "h", 2: "kh", 2.5: "kh", 3: "sh", 3.5: "h"}, bpm, bars, total) * 0.6,
    )
    music = music[: int((bars * 4 * 60.0 / bpm) * SR)]
    stereo = np.stack([music, np.roll(music, 300)], axis=1)
    write("music/menu", stereo, peak=0.6)


# --- Batter songs -----------------------------------------------------------------------
# A KBO park's cheering section plays each batter his own song: a trumpet's tune the crowd
# sings along to, a bass drum on every beat, thunder sticks, and the crowd's shout in the gaps.
# These are the game's own tunes (written here, like nothing in particular); a man's real song
# can be put in content-local/audio/chants/players/<id>.ogg and is played instead.

## The crowd's beat (Crowd.BEATS_PER_SECOND 2.1 a second): the songs keep to the stands' movement.
SONG_BPM = 126
SONG_BEATS = 32
## Each song: its four eight-beat phrases ("note:beats", "r" a rest) and the beats where the
## crowd shouts ("hey") or calls ("oh").
SONGS = [
    (["E5:1 E5:.5 G5:.5 C6:1 G5:1 A5:.5 G5:.5 E5:1 D5:2", "E5:1 E5:.5 G5:.5 C6:1 G5:1 A5:.5 B5:.5 C6:1 G5:2",
      "G5:.5 G5:.5 A5:1 r:2 G5:.5 G5:.5 E5:1 r:2", "C5:.5 E5:.5 G5:.5 C6:.5 D6:1 B5:1 C6:2 r:2"],
     {"hey": [18, 19, 22, 23], "oh": [30]}),
    (["D5:.5 G5:.5 G5:.5 A5:.5 B5:1 G5:1 D5:.5 E5:.5 G5:1 r:2", "D5:.5 G5:.5 G5:.5 A5:.5 B5:1 D6:1 C6:.5 B5:.5 A5:1 r:2",
      "B5:1 B5:1 C6:.5 B5:.5 A5:1 G5:1 A5:1 B5:2", "D6:1 B5:1 G5:1 A5:1 B5:.5 A5:.5 G5:1 r:2"],
     {"hey": [6, 7, 14, 15], "oh": [30]}),
    (["A4:.5 A4:.5 C5:.5 E5:.5 A5:1 G5:.5 E5:.5 F5:1 E5:1 r:2", "A4:.5 A4:.5 C5:.5 E5:.5 A5:1 G5:.5 E5:.5 D5:1 E5:1 r:2",
      "F5:1 F5:.5 E5:.5 D5:1 E5:1 F5:1 G5:1 A5:2", "A5:.5 G5:.5 E5:1 G5:.5 F5:.5 D5:1 E5:2 r:2"],
     {"hey": [6, 7, 14, 15, 31], "oh": [30]}),
    (["C5:1 F5:1.5 G5:.5 A5:1 C6:1 A5:1 G5:2", "C5:1 F5:1.5 G5:.5 A5:1 C6:1 D6:1 C6:2",
      "D6:1 C6:1 A5:1 F5:1 G5:1 A5:.5 G5:.5 F5:2", "r:1 C5:.5 C5:.5 F5:1 r:1 C5:.5 C5:.5 F5:1 r:2"],
     {"hey": [24, 28, 30, 31], "oh": []}),
    (["D5:.5 F#5:.5 A5:.5 F#5:.5 D5:.5 F#5:.5 A5:1 B5:.5 A5:.5 F#5:.5 E5:.5 D5:1 r:1",
      "D5:.5 F#5:.5 A5:.5 F#5:.5 D5:.5 F#5:.5 A5:1 D6:.5 C#6:.5 B5:.5 C#6:.5 D6:1 r:1",
      "E5:1 r:1 E5:1 r:1 F#5:.5 G5:.5 A5:.5 B5:.5 A5:2", "D6:.5 D6:.5 D6:1 A5:.5 A5:.5 A5:1 F#5:.5 E5:.5 D5:1 r:2"],
     {"hey": [7, 15, 17, 19, 31], "oh": [30]}),
    (["E5:1 E5:1 G5:1 E5:1 B5:1.5 A5:.5 G5:2", "E5:1 E5:1 G5:1 E5:1 D5:1.5 E5:.5 F#5:1 r:1",
      "G5:.5 G5:.5 G5:1 A5:.5 A5:.5 A5:1 B5:.5 B5:.5 B5:1 r:2", "E6:1 D6:1 B5:1 A5:1 G5:1 F#5:1 E5:2"],
     {"hey": [15, 22, 23], "oh": [30]}),
]


def song_notes(phrases):
    """The phrases' notes as [(beat, beats, note)]."""
    out = []
    b = 0.0
    for phrase in phrases:
        start = b
        for tok in phrase.split():
            name, length = tok.split(":")
            length = float(length)
            if name != "r":
                out.append((b, length, name))
            b += length
        assert abs(b - start - 8.0) < 1e-6, "a phrase is eight beats: " + phrase
    return out


def octave_down(name):
    return name[:-1] + str(int(name[-1]) - 1)


def crowd_sing(freq, seconds, vowel="o", voices=14):
    """A crowd singing one note: many voices a little out of tune and out of time, a buzz
    through the vowel's formants. Returns frames x 2."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    for v in range(voices):
        f = freq * 2 ** (RNG.normal(0.0, 0.22) / 12.0)
        vib = 1 + 0.006 * np.sin(2 * np.pi * RNG.uniform(4.5, 6.5) * t + RNG.uniform(0, 6))
        phase = 2 * np.pi * np.cumsum(f * vib) / SR
        buzz = sum(np.sin(k * phase) / k for k in range(1, 12))
        shift = RNG.uniform(0.9, 1.15)
        peaks = [(fq * shift, w * 1.5, g) for fq, w, g in VOWELS[vowel]]
        voice = formants(buzz + 0.2 * RNG.standard_normal(n), peaks)
        lag = RNG.uniform(0.0, 0.045)
        voice *= np.clip((t - lag) / 0.06, 0, 1) * np.clip((seconds - t) / 0.08, 0, 1)
        pan = RNG.uniform(0.1, 0.9)
        g = RNG.uniform(0.5, 1.0)
        out[:, 0] += voice * g * np.sqrt(1 - pan)
        out[:, 1] += voice * g * np.sqrt(pan)
    return out


def stereo(x):
    return np.stack([x, x], axis=1) if x.ndim == 1 else x


def place(x, seconds, total):
    """A sound (mono or stereo) at `seconds` into a stereo track `total` long."""
    x = stereo(x)
    out = np.zeros((int(total * SR), 2))
    i = int(seconds * SR)
    j = min(i + len(x), len(out))
    if i < len(out):
        out[i:j] += x[: j - i]
    return out


def batter_song(phrases, calls):
    """One song, exactly SONG_BEATS long so it loops on the beat (what rings past the end is
    folded back onto the start)."""
    beat = 60.0 / SONG_BPM
    loop = SONG_BEATS * beat
    total = loop + 1.6
    notes = song_notes(phrases)
    lead = sequence(notes, SONG_BPM, brass, total)
    low = sequence([(b, l, octave_down(nm)) for b, l, nm in notes], SONG_BPM, brass, total)
    # Every part set against the trumpet's peak: the crowd's singing nearly as loud, the drum
    # under it, the sticks and the shouts.
    ref = np.max(np.abs(lead))

    def level(x, share):
        return x * (share * ref / max(np.max(np.abs(x)), 1e-9))

    track = stereo(lead + level(low, 0.3))
    sing = np.zeros((int(total * SR), 2))
    for b, l, nm in notes:
        sing += place(crowd_sing(hz(octave_down(nm)), l * beat * 0.95), b * beat, total)
    track += level(sing, 0.8)
    bass_drum = level(kick(), 0.7)
    sticks = level(thunder_sticks(), 0.35)
    drum_hi = level(tom(), 0.45)
    for k in range(SONG_BEATS):
        track += place(bass_drum, k * beat, total)
        track += place(sticks, k * beat + 0.01, total)
        if k % 8 in (3, 7):
            track += place(drum_hi, (k + 0.5) * beat, total)
    for b in calls.get("hey", []):
        track += place(level(chant_hey(60), 0.9), b * beat, total)
    for b in calls.get("oh", []):
        track += place(level(chant_oh(60), 0.9), b * beat, total)
    n = int(loop * SR)
    out = track[:n].copy()
    tail = track[n:]
    out[: len(tail)] += tail
    return out


def song_sounds():
    for i, (phrases, calls) in enumerate(SONGS):
        write("cheer/song_%d" % (i + 1), batter_song(phrases, calls), peak=0.7, quality=3)


# --- All --------------------------------------------------------------------------------

def main():
    global FFMPEG, OUT
    if len(sys.argv) > 1:
        FFMPEG = sys.argv[1]
    if len(sys.argv) > 2:
        OUT = sys.argv[2]
    only = set(sys.argv[3].split(",")) if len(sys.argv) > 3 else None
    if only is None or "sfx" in only:
        for tier in range(1, 5):
            for v in range(3):
                write("sfx/bat_solid_%d_%d" % (tier, v + 1), bat_solid(tier), peak=0.6 + 0.08 * tier)
        for tier in range(1, 4):
            for v in range(2):
                write("sfx/bat_jam_%d_%d" % (tier, v + 1), bat_jam(tier), peak=0.55 + 0.08 * tier)
                write("sfx/bat_end_%d_%d" % (tier, v + 1), bat_end(tier), peak=0.5 + 0.08 * tier)
        for v in range(2):
            write("sfx/foul_tip_%d" % (v + 1), foul_tip(), peak=0.5)
        for tier in range(1, 4):
            for v in range(2):
                write("sfx/mitt_%d_%d" % (tier, v + 1), mitt(tier), peak=0.55 + 0.1 * tier)
        for v in range(3):
            write("sfx/glove_%d" % (v + 1), glove(), peak=0.55)
        write("sfx/bare_hand", bare_hand(), peak=0.4)
        for ground in ("grass", "dirt"):
            for v in range(2):
                write("sfx/bounce_%s_%d" % (ground, v + 1), bounce(ground), peak=0.5)
            for v in range(3):
                write("sfx/step_%s_%d" % (ground, v + 1), step(ground), peak=0.3)
        for kind in ("pad", "wall", "net"):
            write("sfx/fence_%s" % kind, fence(kind), peak=0.6)
        write("sfx/slide", slide(), peak=0.5)
        write("sfx/dive", dive(), peak=0.5)
        write("sfx/swing", swing(0.6), peak=0.4)
        write("sfx/swing_power", swing(1.0), peak=0.5)
        write("sfx/base_tag", base_tag(), peak=0.4)
        ui_sounds()
    if only is None or "crowd" in only:
        crowd_sounds()
    if only is None or "cheer" in only:
        cheer_sounds()
    if only is None or "music" in only:
        music_sounds()
    if only is None or "songs" in only:
        song_sounds()
    total = sum(os.path.getsize(p) for p in WRITTEN)
    print("make_sounds: %d files, %.1f MB in %s" % (len(WRITTEN), total / 1e6, OUT))


if __name__ == "__main__":
    main()
