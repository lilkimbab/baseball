# 진행 상황

> 이 파일만 보면 **지금 어디까지 됐고 다음에 무엇을 하는지** 알 수 있게 유지한다.
> 단계의 정의는 [docs/08 구현 파이프라인](docs/08-roadmap.md), 작업 단위와 수치는 [docs/13 구현 명세](docs/13-implementation-spec.md), 지난 작업의 시간순 기록은 [docs/14 작업 기록](docs/14-work-log.md), 아이디어 목록은 [IDEAS.md](IDEAS.md).

## 1. 한눈에

| | |
|---|---|
| 브랜치 | `overnight-2026-11-21` (main과 같은 커밋까지 푸시됨. 그 뒤 작업은 아래 5절, 아직 커밋 전) |
| 테스트 | 467개 전부 통과 (`./dev test`, 2026-11-22 새벽) |
| 성능 | 경기 장면 1080p 평균 72fps·하위 1% 64fps (Arc 140V, 관중 만원, 업스케일 품질 88%). 77%로 그리면 85fps, 원본 해상도는 62fps |
| 실행 | `./dev play` → 제목 → 홈(친선 경기·리그·커리어·연습·상점) |
| 커밋 | 사용자가 직접 한다(7절의 명령) |

## 2. 지금까지 만든 것

| 영역 | 들어 있는 것 | 단계 |
|---|---|---|
| **공 물리** | 구종 8종 + 진화 구종 4종, 실밥 효과(심 시프트 웨이크), 배트-공 충돌, 구장 충돌, 날씨·고도 공기 밀도 식. C++ 확장(없으면 GDScript)으로 경기 시뮬레이션 1.7배 | S2, 제안 1·5 |
| **경기 엔진** | KBO 2026 규칙, 기록(자책점·세이브·홀드), 통계 해석기(1경기 10ms)와 물리 해석기(투구마다 물리), 수비·주루·감독 AI, Statcast식 포구 확률. 리그 지표가 KBO 2025와 맞음(타율 .259, 득점 4.6) | S4, S5 |
| **조작** | 타격(배트 커서 조준, 컨택·강타·번트), 투구(구종·목표·게이지, 예상 궤적), 송구(방향 키 + 게이지), 주루(E/Q), 도루(Shift 타이밍) | S3, S5, S12 |
| **경기 화면** | 점수 표시, 하단 바, 투구 기록 패널, 화면 속 화면, 낙하 지점·베이스 표식, 한 줄 중계, 투구 시간, 일시정지·교체, 경기 뒤 화면 | S6 |
| **감독 리그** | 30구단 3부 리그, 일정·순위·포스트시즌·승강·시상, 1군/2군 엔트리와 외국인 규정, 감독 지휘 경기(상황판·작전·예약·개입), 구단 운영(코스트·컨디션·스카우트·훈련·특성·팀 컬러) | S7 |
| **커리어** | 선수 생성, 2군 → 1군, 내 장면만 하는 경기(약 6분), 성장, 구종 진화, 평점·보상, 올스타전·홈런 더비 | S8 |
| **메뉴** | 새 디자인(그래파이트 + 모드별 색, Paperlogy·Barlow Condensed, 실시간 야구장 배경): 제목, 홈, 친선 경기, 리그·커리어 내부 화면, 연습 모드, 상점, 설정, 불러오기, 선수 카드, 로딩 화면. 저장·자동 저장 | S9 + 재작업 |
| **동작** | 모션캡처 투구 폼 20·타격 폼 20(선수별 배정), 수비·주루 동작(포구 IK, 송구 4종, 슬라이딩, 태그, 포수·심판), 달리기 모션 매칭(CMU 40클립), 도루·견제·폭투 장면 | S10, S12, 제안 3·4 |
| **선수 모델** | 체형 4종(인체 계측표 기준, 80~106kg), 옷감 주름을 구운 유니폼, 전용 피부 셰이더, 6쪽 모자·헬멧·포수 장비·심판 마스크·스파이크, 구단별 홈·원정 유니폼(실제 서체·규격), 선수마다 다른 얼굴·피부톤·핏줄 | S11 (5절) |
| **구장** | 구장 모형 17종 × 배경 13종 × 구단 색(구단마다 홈구장), 사진 하늘, 스캔 재질, 전광판, 광고판, 낮·해 질 녘·밤·돔 | S13 |
| **관중** | 좌석마다 사람(만원 약 2만 1천 명, 인물 13명 × 자세 8장), 응원석, 흥분도 연동 | S14 |
| **도구** | `./dev`(test, check, play, model, materials, native, mocap, sim, tool-win …), 캡처 도구(경기·메뉴·구장·배경·전신), 시뮬레이션·분포 검사, 모델 치수 측정 | |

쓴 외부 자료와 라이선스: MakeHuman/MPFB(CC0), ambientCG·Poly Haven(CC0), Rocketbox(MIT), Phosphor 아이콘(MIT), Paperlogy·Barlow Condensed·Black Han Sans·Do Hyeon·Lobster·Rye(OFL), College Block(MIT), AMD FSR 2(MIT). 비상업·개인 사용 자료(OBP·CMU 모션캡처, 유니폼 서체 복각본)는 git에 올리지 않는 `content-local/`에만 있다(출처는 그 안의 SOURCES.md).

## 3. 앞으로 할 것 (순서대로)

자세한 표(완료 기준 포함)는 [docs/08의 12절](docs/08-roadmap.md#12-남은-단계-2026-11-21-밤에-다시-정리).

| 순서 | 단계 | 요약 |
|---|---|---|
| 1 | **R1 선수 외형 마무리** | 이번 3차 결과를 경기 화면(투구·타격·수비 자세)에서 확인하고 다듬기, 타자 보호대, 하이삭스·긴팔 언더셔츠 |
| 2 | **R2 구장 사실감 2차** | 배경 건물 디테일(옥상·도로·차·가로수), 지붕, 광고판 로고화, 17종 × 낮·밤·돔 점검 |
| 3 | **R3 날씨와 바람** | 경기별 날씨·바람이 공 비행·깃발·하늘·전광판·감독 AI에 반영 |
| 4 | **R4 불펜 몸풀기** | 구원 투수 준비도, 몸풀기 지시, 불펜에서 실제로 던지는 투수 |
| 5 | **R5 경기 화면과 구단 관리 UI 완성** | 경기 화면(HUD)을 새 디자인으로, 라인업·로테이션 편집 |
| 6 | **R6 2군(퓨처스)과 육성** | 2군 리그, 콜업·말소, 유망주 성장 (UI 완성 뒤) |
| 7 | **R7 역사적 시즌 재현** | 과거 시즌 시나리오 모드 (UI 완성 뒤) |
| 8 | **S15 소리와 음악** | 관중 음향, 응원, 효과음, 장내 방송, 음악 |
| 9 | **S16 중계 연출** | 경기 전 연출, 리플레이, 득점·교체 연출 |
| 10 | **S17 실제 로스터** | 기록 수집, 능력치 변환, 로스터 팩(로컬) |
| 11 | **S18 실제 구장·유니폼·폼·얼굴** | 실제 구장, 실제 유니폼, 사진 기반 얼굴(로컬) |
| 12 | **S19 대조 점검 → S20 마감** | 참고 영상과 나란히 점검, 밸런스·성능, Windows 빌드 |

## 4. 알려진 문제

| 문제 | 계획 |
|---|---|
| 얼굴이 MakeHuman 기본 얼굴(창백하고 인형 같음) | 사진 기반 얼굴은 S18. 그 전에는 피부톤·수염·골격 변형까지 |
| 포수 장비·미트가 뭉툭하고 질감이 없음(누빔·끈·로고) | R1 |
| 해가 타자 뒤에 있을 때(투수 시점) 선수 앞면의 명암이 밋밋함 | R1·R2에서 조명과 함께 |
| 홈 화면 모드 카드의 그림이 예전 모델로 찍은 것 | `tools/ui/make_art.sh`로 다시 찍기(R1 끝에) |
| 경기 화면(HUD)이 아직 예전 디자인 | R5 |
| 배경 건물이 상자에 사진을 입힌 수준, 광고판이 글자뿐 | R2 |
| 새 구장 모형 13종은 높은 시점 한 장면으로만 확인 | R2 |
| 물리 해석기의 2루타 5.7%(목표 4.13%는 가정값) | 실제 기록을 받는 S17에서 |
| 홈런 때 타자가 베이스를 다 돌 때까지 못 넘김 | S16(건너뛰기) |
| 테스트 종료 때 Godot의 "ObjectDB 누수" 경고 | 테스트 도구의 정리 순서 문제, 결과에 영향 없음 |

## 5. 이번 작업 (2026-11-21 밤 ~ 22 새벽): 선수 비율·유니폼·핏줄, 투구 조작, 서체, 심판, 정리

사용자 요청: 지금까지 한 것과 앞으로 할 것 정리(불필요한 파일 정리), 머리·몸 비율, 짧은 목, 몸에 붙지 않는 유니폼, 인위적인 팔 핏줄, 실제 선수들이 쓰는 유니폼·등번호 서체. 이어서: 공 궤적 표시, 원형 구종 선택, 상황별 서체, 심판 디자인, 타석에 선 선수들의 모습.

| 요청 | 재 보니 | 고친 것 |
|---|---|---|
| 머리·몸 비율 | 6.9등신(목표 7.5~8), 머리둘레 63cm. 허리 70cm·팔뚝 26cm·종아리 37cm로 몸은 가늘었다 | 7.7등신·58cm. 허리 86·팔뚝 31·손목 18·종아리 41cm. 체형 4종의 체중 80·89·96·106kg |
| 목이 짧다 | 턱 끝~어깨 4.5cm(표준 약 8cm) | 8.3cm, 목둘레 41cm |
| 옷이 뜨고 뒤가 튀어나옴 | 등 5.8cm, 가슴 5.1cm(1차 시도) | 옷이 걸리는 모양을 계산하는 재단으로 가슴·등 1.5cm. 소매는 팔 위에 얹힘, 바지는 곧게 |
| 팔 핏줄 | 굵은 줄 한 가닥 + 오돌토돌한 피부. 팔 텍스처가 1텍셀 1.4mm | 셰이더가 화면 해상도로 그리는 정맥 7개 + 손등 정맥궁 + 힘줄. 선수마다 무늬·세기 다름 |
| 유니폼·등번호 서체 | 시스템 고딕, 한글 구단명 | 풀 블록·터스칸·스크립트(꼬리) 서체, 영문 별칭/연고지, 번호 20.3·10.2cm, 테두리, 파이핑·소매 띠·패치·스폰서 |
| (함께) | 수영모 같은 모자, 광대 신발, 삐죽한 머리카락, 붉은 눈, 톱니 모양 목둘레, 떠 있는 모자 글자 | 6쪽 모자, 스파이크, 두피에 그린 짧은 머리, 어두운 갈색 눈, 정확히 자른 목둘레와 옷깃 띠, 앞판 표면에 붙인 글자 |
| 얼굴의 흰 점(눈물 자국처럼) | 피부의 코팅 반사층(클리어코트)이 한 픽셀짜리 반짝임으로 깨짐 | 피부에서 그 층을 뺌. 속눈썹·눈썹 무광 |
| 공 궤적이 선수 목에서 나옴 | 예상 궤적을 손에서부터 그려서 투수 몸을 가림 | 포심은 존의 도착점만, 변화구는 마지막 약 6m가 휘어 들어가는 것만 |
| 구종 선택을 2K14처럼 원형 6방향으로 | 숫자 키 목록뿐이었다 | 도넛 고리 6칸: 오른쪽 버튼을 누른 채 마우스를 구종 쪽으로 보내고 뗀다(숫자 키도 유지) |
| 모든 곳의 폰트가 같다 | 메뉴 서체 하나로 HUD·전광판·광고판까지 그림 | 역할별 서체: 중계 그래픽 S-Core Dream, 콜·판정 Black Han Sans, 전광판 Galmuri(도트), 펜스 숫자 College Block, 광고판은 브랜드마다, 숫자는 Barlow Condensed |
| 심판 디자인이 대충 | 선수 유니폼에 색만 바꾼 것 | 폴로 셔츠(깃·주머니·리그 배지·소매 번호), 차콜 바지, 검은 구두, 주심 마스크·짧은 챙 모자·공 주머니, 심판 체격 |
| 타석의 선수가 울퉁불퉁·뚱뚱·흐릿 | 헐렁한 옷용 주름이 덩어리로 보임, 넓은 바지 통, 77% 해상도로 그려 키움 | 주름 얕게 다시 굽기, 옷을 몸에 더 붙임, 기본 해상도 배율 77 → 88%, 역광일 때 앞면을 비추는 반사광 추가. 옷과 화면은 나아졌지만 얼굴과 포수 장비는 아직 부족(4절) |

- 측정 도구: `tools/blender/anthropometry.py`(빌드마다 표 출력, `player_<체형>_measure.json`), `tools/blender/try_shapes.py`(설정 시험 3초), 전신 캡처 `./dev tool-win figure_shots`
- 정리: 진행 기록을 이 파일(현황)과 docs/14(기록 보관)로 나눔, 로드맵 12절 다시 작성, 안 쓰는 도구 2개(`career_shots`, `league_shots` → `menu_shots`가 대신함)와 Pretendard 서체 삭제, 오래된 캡처 폴더 정리(build 519MB → 240MB), 예전 얼굴 주름·핏줄 굽기 코드 삭제
- 캡처: `build/figure/`(`before_after.png` 위가 고치기 전·아래가 지금, `final_away.png` 원정·헬멧·건장 체형, `final_arm.png` 팔, `umpire_top.png` 심판, `plate_before_after.png` 투수 시점 타석 전·후), `build/aim3/`(구종 고리·도착점 표시), `build/match2/`(경기 화면)

## 6. 확인하는 법

```bash
./dev test                     # 전체 테스트
./dev play                     # 게임 실행 (Windows GPU)
./dev tool-win figure_shots build/figure/a --team 22              # 선수 전신 네 방향
./dev tool-win figure_shots build/figure/b --zoom arm --veins 0.8 # 팔 근접
./dev tool-win menu_shots build/menus/m --only hub,quick,league --league
./dev tool-win backdrop_shots build/backdrops/b                    # 배경 13종
./dev sim --physical --games 800 --jobs 8                          # 리그 분포 검사
```

## 7. 커밋 (사용자가 직접)

```bash
cd /home/parkjune/baseball
git add -A .gitignore README.md PROGRESS.md IDEAS.md dev docs/ game/ tools/
git commit -m "Player figure to the tables (7.7 heads, neck, girths), fitted uniforms, cap, spikes, drawn veins; real uniform lettering; umpires' kit; pitch wheel; faces by role; tidy-up

- Body re-measured against ANSUR II (tools/blender/anthropometry.py) and reshaped; four builds by weight
- Uniforms cut to hang (jersey, sleeves, trousers), exact neckline, collar trim, side piping, buckle
- Six-panel cap, spikes, cropped hair on the scalp, umpire's mask, polo collar, ball bags, short-billed cap
- Arm veins and tendons drawn by the skin shader from arm coordinates in the model; no clear coat on skin
- Uniform lettering: block, Tuscan and script faces, English nicknames and towns, regulation number sizes, patches
- Pitch preview shows the arrival only (the last bend for breaking balls); six-way pitch wheel on the right button
- UiTheme.face: broadcast, impact, scoreboard, wall and sponsors' faces; sponsors' boards with marks
- PROGRESS rewritten as a status page, work log moved to docs/14, roadmap section 12 re-planned

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>"
git push origin overnight-2026-11-21
git fetch . overnight-2026-11-21:main
git push origin main
```
