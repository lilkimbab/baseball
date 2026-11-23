"""Numbers in a commentary line written out the way a KBO broadcast says them (the user,
2026-11-23: "the 4th batter is 사번 타자, not 네번 타자 — numbers will have this problem"),
before the line goes to the voice.

  Sino-Korean (일 이 삼): the batting order (4번 → 사번), innings (2회말 → 이회말), bases
  (1루 → 일루, 2루타 → 이루타), counts of a season (21홈런 → 이십일 홈런, 88타점), at-bats and
  hits (3타수 2안타 → 삼타수 이안타), uniform numbers, speeds (145km/h → 백사십오 킬로미터),
  a fielding play read digit by digit (6-4-3 → 육사삼), a score (3:2 → 삼 대 이).
  Native (한 두 세): runs (1점 → 한 점, 2점 → 두 점), people and things (명, 개).
  Broadcast English: outs (2아웃 → 투아웃), a home run's men (2점 홈런 → 투런 홈런, 4점 → 만루
  홈런), the count (3볼 2스트라이크 → 쓰리볼 투스트라이크).
  An average .312 → 삼할 일푼 이리.
"""
import re

DIGITS = ["영", "일", "이", "삼", "사", "오", "육", "칠", "팔", "구"]
NATIVE = {1: "한", 2: "두", 3: "세", 4: "네", 5: "다섯", 6: "여섯", 7: "일곱", 8: "여덟", 9: "아홉", 10: "열",
          11: "열한", 12: "열두", 13: "열세", 14: "열네", 15: "열다섯", 16: "열여섯", 17: "열일곱", 18: "열여덟", 19: "열아홉", 20: "스무"}
ENGLISH = {0: "노", 1: "원", 2: "투", 3: "쓰리", 4: "포"}
HOMER = {1: "솔로", 2: "투런", 3: "쓰리런", 4: "만루"}


def sino(n):
    """1234 -> 천이백삼십사 (as Korean reads a number)."""
    n = int(n)
    if n == 0:
        return "영"
    out = ""
    for value, word in ((10000, "만"), (1000, "천"), (100, "백"), (10, "십")):
        q = n // value
        if q:
            out += ("" if q == 1 and value != 10000 else sino(q)) + word
            n %= value
    if n:
        out += DIGITS[n]
    return out


def native(n):
    n = int(n)
    return NATIVE.get(n, sino(n))


def average(m):
    """.312 -> 삼할 일푼 이리."""
    d = m.group(1).ljust(3, "0")
    parts = []
    for digit, unit in zip(d, ("할", "푼", "리")):
        if digit != "0":
            parts.append(DIGITS[int(digit)] + unit)
    return " ".join(parts) if parts else "영할"


RULES = [
    (r"(\d)점 홈런", lambda m: HOMER.get(int(m.group(1)), sino(m.group(1)) + "점") + " 홈런"),
    (r"(\d)-(\d)-(\d)", lambda m: "".join(DIGITS[int(m.group(i))] for i in (1, 2, 3))),
    (r"(\d)-(\d)(?!\d)", lambda m: "".join(DIGITS[int(m.group(i))] for i in (1, 2))),
    (r"(\d+)\s*:\s*(\d+)", lambda m: "%s 대 %s" % (sino(m.group(1)), sino(m.group(2)))),
    (r"\.(\d{1,3})\b", average),
    (r"(\d)아웃", lambda m: ENGLISH.get(int(m.group(1)), sino(m.group(1))) + "아웃"),
    (r"(\d)볼", lambda m: ENGLISH.get(int(m.group(1)), sino(m.group(1))) + "볼"),
    (r"(\d)스트라이크", lambda m: ENGLISH.get(int(m.group(1)), sino(m.group(1))) + "스트라이크"),
    (r"(\d+)\s*km/h", lambda m: sino(m.group(1)) + " 킬로미터"),
    (r"(\d+)\s*(점|명|개|번째|타석|경기째)", lambda m: native(m.group(1)) + " " + m.group(2) if m.group(2) in ("점", "명", "개") else native(m.group(1)) + " " + m.group(2)),
    (r"(\d+)", lambda m: sino(m.group(1))),
]


def say(text):
    """The line with its numbers in words."""
    for pattern, fix in RULES:
        text = re.sub(pattern, fix, text)
    return text


if __name__ == "__main__":
    for line in ["타석에는 4번 타자 김윤민", "2회말 공격", "좌중간을 가르는 2루타", "1루 주자", "3루타!", "2점 홈런", "4점 홈런", "6-4-3 병살",
                 "3타수 2안타", "시즌 21홈런 88타점", "타율 .312", "2아웃 만루", "3볼 2스트라이크", "145km/h 직구", "3:2로 앞섭니다", "1점", "2점을 냅니다", "등번호 32번"]:
        print(line, "->", say(line))
