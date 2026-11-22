"""Real-like names for real players (the user, 2026-11-22: keep the records, the ratings and the
colours, but change the names so that only a baseball fan would know who is meant). Used by
kaggle_to_tables.py when it writes a season, and by rename_packs.py on packs already built.

A Korean name keeps its shape: the family name becomes a near one (김 → 권, 이 → 임, 박 → 백 ...)
and the last syllable of the given name a near sound (영 → 연, 후 → 호, 지 → 진 ...). A
foreign player's name (in Hangul) changes its first consonant to its neighbour (ㄴ → ㄹ,
ㅍ → ㅂ ...) and the consonant of its last syllable (ㅌ → ㄷ, ㅅ → ㅈ ...). Always the same
answer for the same name.
"""

SURNAMES = {
    "김": "권", "이": "임", "박": "백", "최": "채", "정": "전", "강": "장", "조": "주", "윤": "원",
    "장": "강", "임": "이", "한": "함", "오": "우", "서": "성", "신": "진", "권": "김", "황": "홍",
    "안": "한", "송": "손", "전": "천", "홍": "황", "고": "구", "문": "민", "양": "방", "손": "송",
    "배": "백", "백": "배", "허": "하", "유": "류", "남": "남궁", "노": "나", "하": "허", "곽": "곡",
    "성": "서", "차": "채", "주": "추", "우": "오", "구": "고", "민": "문", "류": "유", "나": "라",
    "진": "신", "지": "기", "엄": "염", "채": "최", "원": "윤", "천": "전", "방": "팽", "공": "곽",
    "현": "형", "함": "한", "변": "편", "염": "엄", "여": "려", "추": "주", "도": "두", "소": "서",
    "석": "설", "선": "신", "설": "석", "마": "매", "길": "김", "연": "윤", "위": "우", "표": "포",
    "명": "맹", "기": "지", "반": "박", "왕": "황", "금": "김", "옥": "육", "육": "옥", "인": "임",
    "맹": "명", "제": "재", "모": "목", "탁": "택", "국": "구", "어": "여", "은": "윤", "편": "변",
    "용": "웅", "예": "여", "경": "강", "봉": "방", "사": "서", "가": "하", "복": "박", "태": "채",
    "목": "모", "형": "현", "피": "표", "두": "도", "감": "강", "호": "허", "빈": "민", "동": "돈",
    "온": "원", "황보": "황", "남궁": "남", "선우": "서", "제갈": "제", "독고": "독",
}
TWO_SYLLABLE_SURNAMES = ("황보", "남궁", "선우", "제갈", "독고", "사공", "서문")

# The last syllable of a given name: a near sound, natural in a name.
LAST = {
    "영": "연", "연": "영", "후": "호", "호": "후", "지": "진", "진": "신", "신": "진", "완": "환",
    "환": "한", "한": "환", "현": "헌", "헌": "현", "민": "빈", "빈": "민", "수": "주", "주": "수",
    "준": "윤", "윤": "준", "우": "유", "유": "우", "석": "섭", "섭": "석", "혁": "학", "학": "혁",
    "훈": "운", "운": "훈", "원": "언", "언": "원", "성": "선", "선": "성", "재": "제", "제": "재",
    "규": "균", "균": "규", "용": "웅", "웅": "용", "태": "택", "택": "태", "기": "길", "길": "기",
    "희": "휘", "휘": "희", "범": "봄", "근": "건", "건": "근", "욱": "옥", "옥": "욱", "찬": "천",
    "천": "찬", "형": "협", "협": "형", "경": "겸", "겸": "경", "일": "율", "율": "일", "상": "생",
    "생": "상", "철": "청", "청": "철", "식": "직", "직": "식", "모": "무", "무": "모", "도": "두",
    "두": "도", "구": "규", "광": "강", "강": "광", "남": "람", "람": "남", "동": "둥", "명": "맹",
    "배": "베", "병": "평", "평": "병", "복": "북", "봉": "붕", "산": "선", "삼": "섬", "세": "새",
    "새": "세", "소": "수", "송": "승", "승": "송", "시": "실", "실": "시", "안": "언", "양": "영",
    "엽": "업", "업": "엽", "열": "율", "오": "우", "외": "위", "요": "유", "익": "욱", "인": "윤",
    "임": "인", "장": "정", "정": "전", "전": "정", "조": "주", "종": "중", "중": "종", "창": "찬",
    "춘": "준", "충": "중", "치": "지", "탁": "택", "표": "효", "효": "표", "필": "빌", "하": "허",
    "허": "하", "해": "혜", "혜": "해", "홍": "황", "화": "하", "황": "홍", "흠": "흥", "흥": "흠",
    "서": "소", "혼": "훈", "준호": "준후",
}

# Neighbouring consonants (initial jamo indices 0..18): ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ
CHO_NEXT = {0: 15, 15: 0, 2: 5, 5: 2, 3: 16, 16: 3, 6: 7, 7: 17, 17: 7, 9: 12, 12: 9, 14: 12, 18: 11, 11: 18, 1: 0, 4: 3, 8: 7, 10: 9, 13: 12}


def _split(ch):
    code = ord(ch) - 0xAC00
    if code < 0 or code > 11171:
        return None
    return code // 588, (code % 588) // 28, code % 28


def _join(cho, jung, jong):
    return chr(0xAC00 + cho * 588 + jung * 28 + jong)


def _hangul(s):
    return all(_split(c) is not None for c in s)


def _near_syllable(ch, start):
    """The syllable with its first consonant moved to its neighbour; for a syllable without one
    (ㅇ) at the start of a word, its vowel moved instead."""
    parts = _split(ch)
    if parts is None:
        return ch
    cho, jung, jong = parts
    if cho == 5 and not start:
        # A last syllable on ㄹ keeps it and changes its vowel (블럼 → 블롬, not 블넘).
        vowels = {4: 8, 0: 4, 8: 13, 13: 8, 18: 13, 20: 5, 5: 20, 1: 5, 6: 4}
        return _join(cho, vowels.get(jung, jung), jong)
    if cho == 11 and start:
        vowels = {0: 4, 4: 0, 8: 13, 13: 8, 20: 19, 19: 20, 2: 6, 6: 2}
        return _join(cho, vowels.get(jung, jung), jong)
    return _join(CHO_NEXT.get(cho, cho), jung, jong)


def _near_last(ch):
    if ch in LAST:
        return LAST[ch]
    parts = _split(ch)
    if parts is None:
        return ch
    cho, jung, jong = parts
    # A final ㅇ and ㄴ trade places; a syllable without a final takes ㄴ; else the final goes.
    if jong == 21:
        return _join(cho, jung, 4)
    if jong == 4:
        return _join(cho, jung, 21)
    if jong == 0:
        return _join(cho, jung, 4)
    return _join(cho, jung, 0)


def korean(name):
    for two in TWO_SYLLABLE_SURNAMES:
        if name.startswith(two) and len(name) >= 3:
            return SURNAMES.get(two, two) + _given(name[2:])
    if len(name) < 2:
        return name
    return SURNAMES.get(name[0], name[0]) + _given(name[1:])


def _given(given):
    if len(given) == 1:
        return _near_last(given)
    return given[:-1] + _near_last(given[-1])


def foreign(name):
    if not name:
        return name
    if len(name) == 1:
        return _near_syllable(name, True)
    first = _near_syllable(name[0], True)
    last = _near_syllable(name[-1], False)
    if len(name) == 2:
        return first + last
    return first + name[1:-1] + last


def person(name, is_foreign=False):
    """The real-like name for a player's real one."""
    name = (name or "").strip()
    if not name or not _hangul(name.replace(" ", "")):
        return name
    if " " in name:
        return " ".join(person(part, is_foreign) for part in name.split(" "))
    return foreign(name) if is_foreign else korean(name)


if __name__ == "__main__":
    for n, f in [("김민수", False), ("이준호", False), ("박지훈", False), ("최영", False), ("남궁민", False),
                 ("스미스", True), ("존슨", True), ("가르시아", True), ("브라운", True)]:
        print(n, "->", person(n, f))
