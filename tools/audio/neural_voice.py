"""The announcer's voice by an offline neural text-to-speech model (MeloTTS-Korean, MIT licence,
runs on the CPU), instead of the system's voice (the user, 2026-11-23: "the voice sounds like a
TTS; change it and let me hear it").

    .tools/melotts/venv/bin/python tools/audio/neural_voice.py <out dir> [--speed 1.15] [--lines file]

Each line is spoken, then made to sound like a broadcast: the band of a broadcast microphone,
compressed, a little room, and the park's crowd under it. Writes <n>_raw.wav (the model as it
is) and <n>_cast.ogg (as it would sound in a game) for each line.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FFMPEG = os.path.join(ROOT, ".tools", "ffmpeg", "node_modules", "ffmpeg-static", "ffmpeg")
BED = os.path.join(ROOT, "game", "audio", "crowd", "bed_normal.ogg")
LOCAL_BED = os.path.join(ROOT, "content-local", "audio", "crowd", "bed_normal.ogg")

SAMPLES = [
    "2회말 다솜 팰컨스의 공격, 타석에는 4번 타자 김윤민 선수입니다.",
    "김윤민, 좌중간을 가르는 2루타! 주자 들어옵니다, 한 점!",
    "큽니다, 큽니다, 넘어갑니다! 역전 투런 홈런!",
    "헛스윙 삼진! 득점권 위기를 삼진으로 정리합니다.",
    "몸쪽 꽉 찬 공에 꼼짝 못 합니다. 루킹 삼진.",
    "유격수 땅볼, 6-4-3으로 이어지는 병살! 이닝 끝납니다.",
    "끝내기! 경기 끝납니다! 늘봄 트레일즈가 승리합니다!",
    "볼넷, 1루로 걸어 나갑니다. 투수의 제구가 흔들리네요.",
]

CAST = "highpass=f=140,lowpass=f=7200,acompressor=threshold=-22dB:ratio=4:attack=4:release=90:makeup=5,aecho=0.7:0.5:22|41:0.12|0.07"


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "tts")
    speed = 1.15
    lines = SAMPLES
    args = sys.argv[2:]
    if "--speed" in args:
        speed = float(args[args.index("--speed") + 1])
    if "--lines" in args:
        with open(args[args.index("--lines") + 1], encoding="utf-8") as f:
            lines = [l.strip() for l in f if l.strip()]
    os.makedirs(out, exist_ok=True)
    from melo.api import TTS
    model = TTS(language="KR", device="cpu")
    speaker = model.hps.data.spk2id["KR"]
    bed = LOCAL_BED if os.path.exists(LOCAL_BED) else BED
    for i, text in enumerate(lines):
        raw = os.path.join(out, "%02d_raw.wav" % (i + 1))
        model.tts_to_file(text, speaker, raw, speed=speed, quiet=True)
        cast = os.path.join(out, "%02d_cast.ogg" % (i + 1))
        subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", raw, "-stream_loop", "-1", "-i", bed,
                        "-filter_complex", "[0]%s,apad=pad_dur=0.6[v];[1]volume=0.22[c];[v][c]amix=inputs=2:duration=first:normalize=0" % CAST,
                        "-ac", "2", "-c:a", "libvorbis", "-q:a", "6", cast], check=True)
        print("neural_voice: %s  %s" % (os.path.basename(cast), text))


main()
