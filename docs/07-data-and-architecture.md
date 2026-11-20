# 07. 데이터·아키텍처

프로젝트 구조, 코드 규칙, 데이터 형식, 능력치 산식, 저장, 테스트, 작업 흐름.

## 1. 폴더 구조

```
baseball/
  README.md
  docs/                        # 설계 문서
  prototypes/                  # 검증 프로토타입
  game/                        # Godot 프로젝트 (project.godot)
    core/                      # 순수 로직. 노드·씬 의존 금지
      rng/                     # PCG32, 스트림 분리
      rules/                   # GameState, RuleSet, 상태기계, 기록 규칙
      resolve/                 # Resolver, StatResolver, PhysicalResolver
      physics/                 # BallSim, Aero, Collision, PitchModel, ContactModel, AnalyticField
      motion/                  # 선수 운동 모델 (이동, 포구, 송구 시간)
      ai/                      # 투수, 타자, 수비, 주자, 감독
      control/                 # Controller 인터페이스, 결정 객체, Tactic
      ratings/                 # 능력치, OVR, 등급, 변환 산식
      league/                  # 일정, 순위, 승강, 스카우트, 훈련, 경제
      career/                  # 성장, 목표, 구종 진화
      stats/                   # GameEvent, EventLog, StatBook
      io/                      # JSON 읽기·쓰기, 저장, 마이그레이션
    data/                      # JSON 데이터
    match/                     # 경기 씬
      match_session.gd         # 모드와 경기를 잇는다. 개입 횟수, 속도, 건너뛰기
      scene_space.gd           # CollisionProvider의 씬 구현
      actors/                  # 선수·심판·공 액터, ActorController, ActionPlayer, IK
      camera/                  # CameraDirector, 카메라 리그
      presentation/            # 리플레이, 연출, 관중 흥분도, 중계 문구
      input/                   # HumanController
    stadium/                   # 구장 생성기, 필드 셰이더, 관중
    ui/                        # 메뉴, HUD, 테마
    audio/                     # 버스 구성, 재생기
    assets/                    # 직접 만든 에셋과 CC0 에셋
    tests/                     # 헤드리스 테스트
    tools/                     # 헤드리스 명령 도구 (sim_batch, calibrate, screenshot)
    addons/gut/                # 테스트 프레임워크
  tools/                       # 엔진 밖 도구
    blender/                   # 선수 모델 생성 스크립트
    mocap/                     # 모션캡처 자료 → 관절 위치 클립 (Python)
    roster/                    # 기록 수집과 로스터 팩 생성 (Python)
  assets-src/                  # 에셋 원본 (.blend). git 제외
  content-local/               # 로컬 콘텐츠 팩. git 제외
  .tools/                      # Godot, Blender 실행 파일. git 제외
```

## 2. 코드 규칙

| 규칙 | 내용 |
|---|---|
| 정적 타입 | 모든 변수·인자·반환에 타입을 쓴다. 프로젝트 설정에서 타입 없는 선언을 오류로 처리 |
| `core/`의 의존 금지 | `Node`, `SceneTree`, `Input`, `Engine`, 렌더링·물리 서버를 참조하지 않는다. `RefCounted`와 값 타입만. 테스트가 금지 식별자를 검색해 강제한다 |
| 난수 | `core/rng`만 사용. `randf()`, `RandomNumberGenerator` 금지 |
| 시간 | `core/`는 실제 시간을 모른다. 고정 간격으로 진행한 횟수가 시간이다 |
| 좌표 | `core/`는 필드 좌표, 씬은 월드 좌표. 변환은 `Field.to_world()` / `to_field()` 한 곳 |
| 데이터 경계 | `Dictionary`는 JSON을 읽고 쓰는 `core/io`에서만. 안쪽은 타입 있는 클래스 |
| 씬 | 최소한으로. 구조는 코드와 데이터로 만든다. 사람이 에디터에서 조정할 값은 `@export` |
| 수치 | 조정 대상 수치는 코드가 아니라 `data/*.json`에 |
| 이름 | 파일과 변수는 `snake_case`, 클래스는 `PascalCase`, 상수는 `UPPER_CASE` |
| 주석 | 식별자와 주석은 영어, 문서와 화면 문구는 한국어. 화면 문구는 번역 파일(`ui/strings.ko.csv`)에 |

## 3. 주요 클래스

| 클래스 | 위치 | 책임 |
|---|---|---|
| `Rng` | core/rng | 시드 고정 난수. 스트림 분기 |
| `GameState`, `RuleSet` | core/rules | 경기 상태와 규칙 설정 |
| `GameFlow` | core/rules | 사건을 받아 상태를 바꾸고 이닝·경기 종료를 판정 |
| `Scorer` | core/rules | 타점, 자책점, 실책, 승패 투수 등 기록 규칙 |
| `Resolver` | core/resolve | 해석기 인터페이스 |
| `StatResolver` | core/resolve | 타석 단위 확률 해석 |
| `PhysicalResolver` | core/resolve | 투구 단위 물리 해석. 컨트롤러에 결정을 묻는다 |
| `BallSim` | core/physics | 공의 상태와 적분, 반발, 예측 |
| `PitchModel` | core/physics | 구종 정의 → 릴리스 상태. 조준 해법, 실행 오차 |
| `ContactModel` | core/physics | 접촉 파라미터 → 타구 속도·회전 |
| `CollisionProvider` | core/physics | 충돌 질의 인터페이스. `AnalyticField`가 기본 구현 |
| `FielderMotion`, `RunnerMotion` | core/motion | 이동·포구·송구의 시간 계산 |
| `Controller` | core/control | 투수·타자·수비·주자·감독의 결정 인터페이스 |
| `AiPitcher`, `AiBatter`, `AiFielding`, `AiRunning`, `AiManager` | core/ai | AI 구현 |
| `Player`, `Ratings`, `PitchArsenal` | core/ratings | 선수 데이터 |
| `Team`, `Roster`, `Lineup` | core/league | 구단과 편성 |
| `League`, `Season`, `Schedule`, `Standings` | core/league | 리그 진행 |
| `Scouting`, `Training`, `Economy` | core/league | 운영 시스템 |
| `CareerPlayer`, `Growth`, `Goals` | core/career | 커리어 진행 |
| `GameEvent`, `EventLog`, `StatBook` | core/stats | 이벤트와 기록 |
| `SaveStore` | core/io | 저장과 불러오기, 버전 마이그레이션 |
| `ContentPack` | core/io | 본체 데이터와 로컬 팩을 합쳐 읽는다 |
| `MatchSession` | match | 경기 한 판의 진행. 속도, 건너뛰기, 개입 |
| `SceneSpace` | match | Jolt 충돌 질의 |
| `HumanController` | match/input | 입력 → 결정 객체 |
| `ActorController`, `ActionPlayer` | match/actors | 이벤트 → 애니메이션. 이벤트 프레임 동기화 |
| `CameraDirector` | match/camera | 이벤트 → 카메라 전환 |
| `StadiumBuilder` | stadium | 구장 정의 → 메시·콜라이더 |

## 4. 능력치

### 4.1 항목

1~99, 리그 평균 50, 표준편차 15.

| 타자 | 설명 | 투수 | 설명 |
|---|---|---|---|
| 컨택 (좌·우 상대) | 타이밍 창, 상하 오차, 삼진 | 체력 | 투구 수 한도 |
| 파워 (좌·우 상대) | 배트 속도, 홈런 | 제구 | 실행 오차 |
| 선구안 | 구종·코스 인식, 볼넷 | 위기관리 | 득점권에서의 능력 유지 |
| 주력 | 최고 속도 | 견제 | 견제 속도, 퀵 모션 |
| 주루 | 스타트, 판단 | 수비 | 투수 앞 타구, 베이스 커버 |
| 번트 | 번트 정확도 | **구종별** | |
| 수비 범위 | 반응, 경로 | · 구속 (평균, 최고 km/h) | |
| 포구 | 포구 성공, 공 빼는 속도 | · 무브먼트 | 회전수·효율 배율 |
| 송구력 | 송구 속도 | · 구종 제구 | 그 구종의 오차 보정 |
| 송구 정확도 | 송구 오차 | · 구사율 | AI 볼배합 기본값 |
| 멘탈 | 승부처에서의 능력 유지 | | |
| 포지션 적성 | 포지션별 0~100% | | |

표시용 묶음: 구속(직구 평균 구속을 등급화), 구위(구종별 구속·무브먼트의 구사율 가중 평균), 변화(변화구의 무브먼트 평균).

### 4.2 종합 능력치와 등급

```
타자 OVR = Σ w[포지션][능력치] × 능력치
투수 OVR = 0.30 × 구위 + 0.25 × 제구 + 0.15 × 구속 + 0.10 × 변화 + 0.10 × 체력(선발) 또는 위기관리(구원) + 0.10 × 구종 수 보정
```

포지션별 가중치 예: 유격수는 수비 범위·포구·송구가 45%, 1루수는 15%. 등급과 코스트는 [02](02-game-design.md#52-등급과-코스트)의 표.

### 4.3 기록에서 능력치 계산

능력치를 임의로 매기지 않는다. 기록에서 계산하고, 그 능력치로 시뮬레이션하면 원래 기록에 가까운 성적이 나오도록 **경기 엔진의 변환식을 거꾸로** 쓴다.

```
1. 평균 회귀:   x_reg = (N × x + k × μ) / (N + k)
2. 역변환:      rating = 50 + 15 × ln(x_reg / μ) / K
3. 범위 제한:   20 ~ 99
```

- `x`는 선수의 비율 기록, `N`은 표본(타석, 상대 타자 수), `μ`는 그 시즌 리그 평균
- `k`는 그 기록이 안정되는 표본 크기. 적게 뛴 선수는 평균에 가깝게 나온다
- `K`는 [03](03-match-engine.md#63-능력치--비율)의 계수

| 능력치 | 기록 x | k (표본) |
|---|---|---|
| 컨택 | 삼진율 (낮을수록 높음) | 100 |
| 선구안 | 볼넷율 | 170 |
| 파워 | 타석당 홈런 60% + 순장타율 40% | 250 |
| 주력 | 도루 시도율, 3루타율, 내야 안타율의 표준 점수 합 | 300 |
| 주루 | 도루 성공률, 추가 진루율 | 300 |
| 수비 범위·포구 | 포지션별 수비 지표의 표준 점수. 지표가 없으면 포지션과 출장 이닝으로 추정 | 600이닝 |
| 투수 구위 | 탈삼진율 + 피홈런율 | 150 / 400 |
| 투수 제구 | 볼넷율 (낮을수록 높음) | 200 |
| 구종별 구속 | 문자중계의 평균·최고 구속 | 직접 사용 |
| 구종별 무브먼트 | 구종별 헛스윙률의 표준 점수 | 200구 |
| 체력 | 선발 경기당 평균 투구 수 | 직접 사용 |

좌투수·우투수 상대 기록은 표본이 절반 이하이므로 k를 두 배로 두고 전체 기록 쪽으로 회귀시킨다.

**검증**: 로스터 팩을 만든 뒤 그 시즌을 통계 해석기로 50회 시뮬레이션해 선수별 평균 성적과 실제 성적을 비교한다. 규정 타석 타자의 OPS 상관계수 0.85 이상, 팀 승률 상관계수 0.7 이상이 목표다.

## 5. 로스터 팩

```json
{
  "format": 1,
  "id": "fiction-2026",
  "name": "가상 리그 2026",
  "season": 2026,
  "league_env": "standard",
  "teams": [
    { "id": "t01", "name": "항구 시걸스", "short": "HBR", "stadium": "harbor_park",
      "colors": { "primary": "#12355b", "secondary": "#f2f2f2", "accent": "#e0a100" },
      "players": ["p0001", "p0002"] }
  ],
  "players": [
    { "id": "p0001", "name": "한도윤", "number": 27, "born": 1998,
      "bats": "R", "throws": "R", "height_cm": 183, "weight_kg": 88,
      "positions": { "SS": 100, "2B": 85, "3B": 80 },
      "batting": { "contact_r": 62, "contact_l": 58, "power_r": 55, "power_l": 51,
                   "eye": 60, "speed": 71, "baserunning": 66, "bunt": 48, "clutch": 52 },
      "fielding": { "range": 74, "hands": 70, "arm": 68, "accuracy": 65 },
      "potential": { "contact": 70, "power": 60 },
      "trait": null,
      "appearance": { "body": 0.4, "skin": 2, "hair": 5, "beard": 0, "gear": ["elbow_guard"] },
      "forms": { "batting": "bat_std_03", "pitching": null },
      "source": { "pa": 0, "note": "generated" } },
    { "id": "p0002", "name": "서강민", "number": 18, "born": 1996,
      "bats": "R", "throws": "R", "height_cm": 188, "weight_kg": 92,
      "positions": { "SP": 100 },
      "pitching": { "stamina": 68, "control": 61, "composure": 57, "hold": 50, "fielding": 45,
        "arsenal": [
          { "type": "four_seam", "velo_avg": 146.5, "velo_max": 152, "movement": 58, "command": 62, "usage": 0.48 },
          { "type": "slider", "velo_avg": 133.0, "velo_max": 138, "movement": 66, "command": 58, "usage": 0.27 },
          { "type": "changeup", "velo_avg": 131.5, "velo_max": 135, "movement": 54, "command": 55, "usage": 0.15 },
          { "type": "curve", "velo_avg": 120.0, "velo_max": 124, "movement": 50, "command": 48, "usage": 0.10 }
        ] },
      "forms": { "batting": null, "pitching": "pitch_ot_02" } }
  ]
}
```

| 팩 | 위치 | 만드는 법 |
|---|---|---|
| 가상 리그 (본체) | `game/data/rosters/` | `tools/gen_league.gd`가 시드로 생성. 이름은 음절 조합, 능력치는 포지션별 분포에서 추첨 |
| 실제 리그 (로컬) | `content-local/rosters/` | `tools/roster/`의 수집기와 변환기. [09](09-content-acquisition.md#5-선수-기록--능력치) |
| 직접 편집 | 어디든 | JSON 또는 CSV를 고쳐서 불러온다. 게임 안에 선수 편집 화면도 둔다 |

`ContentPack`이 본체와 로컬 팩을 합친다. 같은 ID가 양쪽에 있으면 로컬 팩이 우선한다.

## 6. 그 밖의 데이터 파일

| 파일 | 내용 |
|---|---|
| `data/league_env.json` | 환경별 리그 평균 비율, 진루 확률표, 능력치 계수 K |
| `data/pitch_types.json` | 구종 카탈로그([04](04-physics.md#53-구종-카탈로그-우완-초기값)), 진화 관계 |
| `data/physics.json` | 공기역학 상수, 면별 반발·마찰, 충돌 모델 상수 |
| `data/motion.json` | 선수 운동 모델의 보간 범위 |
| `data/difficulty.json` | 난이도별 타이밍 창, 조준 비율, AI 보정 |
| `data/win_expectancy.json` | 상황별 승리 확률표 (시뮬레이션으로 생성) |
| `data/traits.json`, `team_colors.json` | 특성, 팀 컬러 조건과 효과 |
| `data/forms/*.json` | 투구·타격 폼 정의 |
| `data/clips.json` | 애니메이션 클립 목록과 상태 기계 구성 |
| `data/stadiums/*.json` | 구장 정의 |
| `data/camera_rules.json` | 카메라 전환 규칙 |
| `data/commentary.ko.json` | 텍스트 중계 문구 템플릿 |
| `data/names.ko.json` | 가상 선수 이름 음절 표 |

## 7. 저장

| 항목 | 설계 |
|---|---|
| 위치 | `user://saves/<슬롯>/` (Windows는 `%APPDATA%\Godot\app_userdata\<프로젝트>\`) |
| 형식 | JSON을 압축해 저장. 파일은 `meta.json`(요약), `league.json`, `career.json`, `settings.json` |
| 버전 | 모든 파일에 `format` 번호. 불러올 때 낮은 버전은 마이그레이션 함수를 차례로 적용 |
| 시점 | 경기 종료, 날짜 진행, 설정 변경 시 자동 저장. 쓰기는 임시 파일에 쓴 뒤 이름을 바꾼다 |
| 경기 중 저장 | `GameState` + 시드 + 입력 기록. 이어 하기는 그 시점까지 다시 계산해 복원 |
| 리플레이 | 시드 + 입력 기록 + 로스터 요약. 수십 KB |
| 내보내기 | 슬롯을 압축 파일 하나로 |

## 8. 테스트

| 종류 | 대상 | 예 |
|---|---|---|
| 단위 | 규칙, 기록, 난수, 변환식 | 인필드 플라이, 병살타에 타점 없음, 끝내기 시 득점 처리, 자책점 책임 |
| 물리 회귀 | [04](04-physics.md#12-검증-결과)의 표 전체 | 포심 비행 시간, 타구 비거리, 조준 해법 잔차 |
| 불변식 | 무작위 시드 경기 | 아웃 합계, 득점 합계, 타순 순환, 이닝 수 |
| 결정론 | 고정 시드 경기 | 이벤트 해시가 저장된 값과 같다 |
| 보정 | 리그 분포 | [03](03-match-engine.md#13-보정과-검증)의 표. 느리므로 별도 실행 |
| 구조 | `core/`의 금지 식별자 | 소스 검색 |
| 화면 | 주요 화면의 캡처 | 경기 씬, 메뉴를 렌더링해 PNG로 저장하고 눈으로 확인. 깨짐·누락 검사 |

명령은 저장소 루트의 `./dev` 스크립트로 묶었다.

```bash
./dev import      # 임포트 캐시와 클래스 목록 재생성 (파일 추가 후)
./dev check       # 모든 스크립트 문법·타입 검사. 타입 없는 선언은 오류
./dev test        # 헤드리스 테스트 (GUT 9.7.1). 실패하면 종료 코드 1
./dev shot [파일] [씬]       # WSL에서 화면 캡처 (소프트웨어 렌더링)
./dev play        # Windows에서 게임 실행 (GPU)
./dev editor      # Windows에서 Godot 에디터 열기
./dev perf        # Windows에서 프레임 시간 측정
./dev shot-win [파일] [씬]   # Windows GPU로 화면 캡처
./dev model       # 선수 모델 재생성 (Blender 5.3 + MPFB, tools/blender/make_player.py)
./dev props       # 장비(글러브, 미트, 배트, 공 겉면)를 실제 규격으로 재생성 (tools/blender/make_props.py)
./dev mocap       # 모션캡처 자료(OBP)를 받아 투구·스윙 클립으로 변환 → content-local/animations/
./dev video       # 타격·투구 시연 영상 녹화 (Windows GPU) → build/demo/dugout-demo.mp4
                  # 동작 점검: res://tools/motion_shots.gd(시각별 촬영), motion_report.gd(튀는 뼈 찾기)
                  # 목표 장면 촬영: Godot으로 res://tools/closeup_shot.gd 실행 (Windows GPU 권장)
```

헤드리스 도구 스크립트는 `--` 뒤의 인자를 `OS.get_cmdline_user_args()`로 읽는다(`tools/cmd_args.gd`).

## 9. 작업 흐름

| 일 | 어디서 | 방법 |
|---|---|---|
| 코드·씬·데이터 작성 | VSCode (WSL) | 텍스트 편집 |
| 문법·타입 검사 | WSL | `--check-only`, 헤드리스 임포트의 오류 출력 |
| 테스트, 배치 시뮬레이션 | WSL 헤드리스 | 위 명령 |
| 화면 확인 | WSL | 화면 캡처 스크립트로 PNG 저장. 소프트웨어 렌더링이라 느리지만 결과는 같다 |
| 실제 플레이, 성능 측정 | Windows | Windows용 Godot으로 프로젝트를 열거나, WSL에서 Windows용으로 내보낸 실행 파일을 실행 |
| 눈으로 조정 | Windows의 Godot 에디터 | 카메라 위치, 재질, 조명 같은 값을 `@export`로 드러내 에디터에서 만지고 저장 |

- 프로젝트 폴더는 WSL 안에 둔다. Windows용 Godot(`.tools/godot-4.7.2-win/`)을 WSL에서 바로 실행하고, 프로젝트는 `\\wsl.localhost\Ubuntu\...` 경로로 연다. S1에서 임포트, 실행, 화면 캡처, 성능 측정이 이 경로로 되는 것을 확인했다
- Windows용 실행 파일로 내보내는 것(내보내기 템플릿 약 1GB)은 S20까지 미룬다. 플레이는 에디터 실행 파일로 프로젝트를 직접 돌리면 된다
- VSCode에는 Godot 확장(`geequlim.godot-tools`)을 권장 확장으로 등록했다. 설정은 `.vscode/settings.json`에 있고 헤드리스 언어 서버를 쓰도록 했다. 확장을 설치한 뒤의 동작은 아직 확인하지 않았다
- 에디터에서 저장한 변경도 텍스트 파일이므로 git에서 차이가 보인다

## 10. 성능 설계

| 영역 | 대책 |
|---|---|
| 배치 시뮬레이션 | 통계 해석기는 객체 생성을 줄이고 배열을 재사용. 1만 경기 1분 이내가 목표 |
| 물리 해석기 가속 | 헤드리스에서는 화면 없이 고정 간격을 연속 실행. 경기당 몇 초 |
| GDScript 병목 | 측정 후 해당 함수만 C# 또는 GDExtension으로 옮긴다. 후보는 `BallSim.integrate`와 통계 해석기의 안쪽 반복문 |
| 리그의 하루 진행 | 다른 팀 경기는 작업 스레드에서 계산 |
| 궤적 예측 | 타구당 한 번. 결과를 이벤트에 실어 수비 AI·카메라·HUD가 함께 쓴다 |
| 애니메이션 | 화면 밖과 먼 선수는 갱신 빈도를 낮춘다 |
