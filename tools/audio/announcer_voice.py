"""The announcer's voice by Supertonic 3 (Supertone's offline text-to-speech, ONNX on the CPU,
model under OpenRAIL-M; Korean among its 31 languages), with its male voices (the user,
2026-11-23: "a man's voice with the high tension of a real broadcast team").

    .tools/supertonic-src/py/.venv/bin/python tools/audio/announcer_voice.py <out dir> [--voices M1,M2] [--speed 1.2] [--steps 10]

Each line in each voice, raw and as a broadcast (the band of a broadcast microphone, compressed,
a little room, the crowd under it). Lines of a play that excites ("!") are spoken faster and
pushed up a touch in pitch and loudness, as a caster's voice rises with the ball.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ST = os.path.join(ROOT, ".tools", "supertonic-src")
sys.path.insert(0, os.path.join(ST, "py"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
FFMPEG = os.path.join(ROOT, ".tools", "ffmpeg", "node_modules", "ffmpeg-static", "ffmpeg")
BED = os.path.join(ROOT, "game", "audio", "crowd", "bed_normal.ogg")
LOCAL_BED = os.path.join(ROOT, "content-local", "audio", "crowd", "bed_normal.ogg")

SAMPLES = [
    "2회말 다솜 팰컨스의 공격, 타석에는 4번 타자 김윤민 선수입니다. 오늘 3타수 2안타.",
    "초구 145km/h 직구, 스트라이크!",
    "김윤민, 좌중간을 가르는 2루타! 주자 들어옵니다, 한 점!",
    "큽니다, 큽니다, 넘어갑니다! 역전 2점 홈런! 시즌 21호!",
    "3볼 2스트라이크 풀카운트에서, 헛스윙 삼진! 2아웃 만루 위기를 넘깁니다!",
    "유격수 땅볼, 6-4-3으로 이어지는 병살! 이닝 끝납니다.",
    "펜스 앞까지 굴러가는 3루타! 3루까지 들어갑니다!",
    "만루 홈런! 그랜드슬램! 4점 홈런으로 경기를 뒤집습니다!",
    "끝내기! 경기 끝납니다! 늘봄 트레일즈가 3:2로 승리합니다!",
    "타율 .312, 21홈런 88타점을 기록 중인 김윤민 선수.",
]

# How excited a line is: a home run, a long hit, a walk-off, a lead taken are shouted; a
# strikeout or a double play to end a jam lifted; the rest said.
HOT = ("홈런!", "넘어갑니다", "끝내기", "그랜드슬램", "2루타!", "3루타!", "역전")
WARM = ("삼진", "병살", "위기", "도루", "스트라이크!")


def mood(text):
    if any(w in text for w in HOT):
        return "hot"
    if any(w in text for w in WARM):
        return "warm"
    return "calm"


# Semitones up, tempo, and the voice's edge (a shout's presence and a little grit) by mood.
MOODS = {"hot": (3.0, 1.12, "equalizer=f=3200:t=q:w=1.2:g=5,asoftclip=type=tanh:threshold=0.7,"),
         "warm": (1.5, 1.07, "equalizer=f=3000:t=q:w=1.2:g=3,"),
         "calm": (0.5, 1.03, "")}

CAST = "highpass=f=120,lowpass=f=7500,acompressor=threshold=-22dB:ratio=4:attack=4:release=90:makeup=5,aecho=0.7:0.5:22|41:0.12|0.07"


def main():
    args = sys.argv[1:]
    out = args[0] if args and not args[0].startswith("--") else os.path.join(ROOT, "build", "tts_male")
    voices = ["M3"]
    speed = 1.18
    steps = 10
    if "--voices" in args:
        voices = args[args.index("--voices") + 1].split(",")
    if "--speed" in args:
        speed = float(args[args.index("--speed") + 1])
    if "--steps" in args:
        steps = int(args[args.index("--steps") + 1])
    os.makedirs(out, exist_ok=True)
    import soundfile as sf
    from helper import load_text_to_speech, load_voice_style
    tts = load_text_to_speech(os.path.join(ST, "assets", "onnx"), False)
    bed = LOCAL_BED if os.path.exists(LOCAL_BED) else BED
    from korean_numbers import say
    hype = os.path.join(ROOT, "tools", "audio", "hype.py")
    for voice in voices:
        style = load_voice_style([os.path.join(ST, "assets", "voice_styles", voice + ".json")])
        for i, text in enumerate(SAMPLES):
            m = mood(text)
            steps_up, tempo, edge = MOODS[m]
            spoken = say(text)
            wav, _ = tts(spoken, "ko", style, steps, speed)
            raw = os.path.join(out, "%s_%02d_raw.wav" % (voice, i + 1))
            sf.write(raw, wav[0] if getattr(wav, "ndim", 1) > 1 else wav, tts.sample_rate)
            lifted = os.path.join(out, "%s_%02d_lift.wav" % (voice, i + 1))
            subprocess.run([sys.executable, hype, raw, lifted, str(steps_up), str(tempo)], check=True, capture_output=True)
            cast = os.path.join(out, "%s_%02d_cast.wav" % (voice, i + 1))
            subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", lifted, "-stream_loop", "-1", "-i", bed,
                            "-filter_complex", "[0]%s%s,aresample=44100,apad=pad_dur=0.7[v];[1]aresample=44100,volume=%.2f[c];[v][c]amix=inputs=2:duration=first:normalize=0" % (edge, CAST, 0.3 if m == "hot" else 0.22),
                            "-ac", "2", cast], check=True)
            print("announcer_voice: %s %02d %s  %s" % (voice, i + 1, m, spoken))
        print("announcer_voice: %s done" % voice)


main()
