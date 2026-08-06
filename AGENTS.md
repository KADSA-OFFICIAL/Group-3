# Group-3 Codex Harness

이 저장소는 issue-first workflow를 사용합니다. Codex는 새 기능, 버그 수정, 개선, 리팩터링, 동작 변경을 시작하기 전에 이 하네스를 따라야 합니다.

## 게임 정보 (젤리 워즈)

2기기 **1 VS 1 온라인 대전** 액션, **Godot 4.6 (GL Compatibility)**. 3조(스틱매너) 개발기획서 기반. `project.godot`의 `config/name`은 "Jelly Wars", 메인 씬은 `scenes/title.tscn`.
기획 핵심 루프는 무기 선택 → 맵 → 전투 → 3점 선취 승리지만, **현재는 접속·스폰·평지 이동까지만 구현**되어 있다.

2026-07-28에 한 기기 2인 로컬에서 온라인 구조로 전환 중이다(로드맵 이슈 #32). 전용 헤드리스 서버가 권위를 갖고, 클라이언트 2대가 Tailscale로 접속한다. 서버 주소는 **저장소가 공개이므로 코드에 적지 않는다** — 접속 화면에서 입력받고 커밋되는 기본값은 `127.0.0.1`이다.

`main` 브랜치는 2026-07-26에 새 구현(커밋 `e2a7dcb`)으로 교체되었다. 이전 구현(`autoload/game_manager.gd`, `scripts/weapons/`, `scenes/maps/` 등)은 `backup/main-before-reset` 브랜치에만 있고 현재 코드베이스에는 없다 — 그 경로를 참조하지 말 것.

### 씬 흐름

title(서버 주소 입력 후 `StartButton`으로 접속) → select(대기실 겸 무기 선택, 둘 다 준비하면 서버가 시작 지시) → main(평지 전투, 서버가 플레이어 스폰) → ESC(`ui_cancel`)로 접속 종료 후 title 복귀

헤드리스로 실행되면 `Network`가 서버를 시작하고 title이 UI 없이 곧바로 main으로 넘어간다. **전용 서버는 select를 거치지 않고 계속 main에 머문다** — 대기실 상태는 씬이 아니라 `Lobby` 오토로드가 들고 있기 때문이다.

### 구조 요약

- `scripts/network.gd` = 오토로드 싱글턴 `Network`: 연결 수립과 피어 알림만 담당(게임 로직 없음). `PORT = 7777`(서버컴 방화벽 UDP 규칙과 일치), `MAX_CLIENTS = 2`, `DEFAULT_ADDRESS = "127.0.0.1"`. `should_run_as_server()`가 헤드리스 또는 `--server` 인자를 감지해 `_ready()`에서 자동으로 서버를 연다. 시그널 `server_started`·`join_succeeded`·`join_failed`·`peer_joined`·`peer_left`. **포트는 여기에만 정의한다.**
- `scripts/lobby.gd` = 오토로드 싱글턴 `Lobby`: 대기실 상태를 **서버가 권위로** 보관한다. `order`(접속 순서, 먼저 들어온 쪽이 1P), `configs`(peer_id → weapon·head·color1·color2), `ready_flags`, `map_name`. 클라이언트는 `submit_config()`·`submit_ready()`로 자기 값만 보내고, 서버가 `_receive_lobby`로 전체를 복제한다. **무기 "랜덤" 확정과 시작 판정은 서버에서만** 실행되어 양쪽이 같은 값을 갖는다. 클라이언트가 보낸 값은 `_sanitize()`로 목록에 있는 값인지 검사한다. 시그널 `lobby_changed`·`match_starting`.
- `scripts/game_state.gd` = 오토로드 싱글턴 `GameState`: 화면 간 선택 정보 전달. `COLORS`(10색), `WEAPONS`(랜덤·광선검·망치·총·활·의자·우산·방패), `HEADS`(없음·중절모·왕관·헬멧), `MAPS`(랜덤·평지·냉장고·봉지 속·위 속), `p1_config`/`p2_config`(weapon·head·color1·color2), `map_name`, `get_config(prefix)`.
- `scenes/title.tscn` + `scripts/title.gd` = 타이틀 겸 접속 화면. `AddressEdit`(기본 `127.0.0.1`)·`StartButton`("접속")·`StatusLabel`(접속 중/실패 표시). 접속 성공 시 main으로 전환한다. 좌우 `JellyLeft`/`JellyRight`는 미리보기 장식.
- `scenes/select.tscn` + `scripts/select.gd` = 대기실 겸 무기 선택. `P1Panel`/`P2Panel`은 `Lobby.order` 슬롯에 대응하며 **자기 슬롯만 조작 가능**하고 상대 패널은 서버가 보낸 값을 표시만 한다. `StatusLabel`에 "상대 대기 중" 또는 양쪽 준비 상태, `GoButton`은 준비 토글. **씬 전환은 클라이언트가 스스로 하지 않고 `Lobby.match_starting`(서버 지시)을 받아서 한다.** 맵은 서버가 정하며 평지만 구현되어 있어 좌우 화살표는 비활성이다.
- `scenes/player_panel.tscn` + `scripts/player_panel.gd` = 플레이어 1인 패널(양쪽 재사용). `mirrored`가 true면 아이콘 열을 오른쪽으로 옮긴다. 무기/머리/색1/색2 버튼은 각각 목록을 순환하고, `RandomButton`은 전부 랜덤. 사용자 조작으로 값이 바뀌면 `config_changed`를 내보낸다. `set_interactive(false)`로 상대 패널을 잠그고, `apply_config()`로 서버가 보낸 값을 표시한다(이때는 시그널을 내보내지 않는다).
- `scripts/jelly_preview.gd` = 젤리 미리보기를 `_draw()`로 직접 그린다(StyleBoxFlat 둥근 모서리 + 눈 2개). `body_color`/`eye_color` setter가 `queue_redraw()`를 호출한다.
- `scenes/main.tscn` + `scripts/main.gd` = 전투 화면. `Ground`/`WallLeft`/`WallRight`(StaticBody2D + CollisionShape2D + ColorRect) 지형, `MapLabel`에 `GameState.map_name` 표시, ESC로 접속 종료. **플레이어는 씬에 배치되어 있지 않고 서버가 런타임에 스폰한다** — `PlayerSpawner`(MultiplayerSpawner, `spawn_path = ../Players`)와 `Players` 노드가 담당. 클라이언트는 씬 준비 후 `_notify_ready()`를 서버로 RPC하고, 서버가 그때 `spawn()`한다(접속 직후 스폰하면 클라이언트가 씬 로드 전이라 놓칠 수 있다). 노드 이름은 `Player_<peer_id>`.
- `scenes/player.tscn` + `scripts/player.gd`(CharacterBody2D): **서버 권위 이동**. `owner_peer_id`·`player_name`·`jelly_color` export. SPEED 320, JUMP_VELOCITY -560, FAST_FALL_MULTIPLIER 2.0, INTERPOLATION_SPEED 20.
  - 클라이언트: `read_input()`(**`Input`을 읽는 유일한 지점**) → `_receive_move_input`(unreliable_ordered)·`_receive_jump`(reliable, 엣지 입력이라 유실되면 안 됨)로 서버 전송. 물리를 계산하지 않고 `_receive_state`로 받은 위치로 lerp 보간만 한다.
  - 서버: `apply_movement(input, delta)`로 위치를 정하고(`move_and_slide()`는 여기서만 호출) `_receive_state`(authority, unreliable_ordered)로 위치·속도·접지를 복제한다.
  - **권한 검증**: 입력 RPC에서 `multiplayer.get_remote_sender_id() != owner_peer_id`이면 무시한다 — 없으면 남의 플레이어를 조작할 수 있다.
  - 젤리 찌그러짐은 복제된 속도·접지값으로 각 피어가 계산한다.
  - `weapon_id`는 대기실에서 고른 무기 id를 **보관만** 한다. 동작은 없다.
- `resources/korean_font.tres` = 한글 폰트 리소스.

### 조작 (project.godot `[input]`)

기기당 1명이므로 **액션은 `move_left`·`move_right`·`jump`·`fast_fall` 4개뿐**이며, 각 액션에 WASD와 방향키가 함께 바인딩되어 있어 어느 쪽을 눌러도 동작한다. 전투 중 ESC(`ui_cancel`)로 접속 종료.
**공격 액션은 아직 없다.** 옛 `p1_/p2_` 8개 액션은 온라인 전환(#33)으로 제거되었다.

### 미구현 (로드맵 #32 기준)

공격·체력·사망(4단계), 점수·3점 선취 승리(5단계), 추가 맵(냉장고·봉지 속·위 속), 머리 장식의 전투 반영.
**무기 동작 구현(광선검·망치·총·활·의자·우산·방패)은 공동작업자 담당이다** — 이쪽은 연결부만 만든다. 무기는 문자열 id 하나로 식별하고 목록의 유일한 출처는 `GameState.WEAPONS`이며, 선택값은 스폰 시 `Player`에 주입된다. "랜덤"은 서버가 확정해 양쪽에 같은 값을 내려보낸다. **공격 판정도 서버에서만 실행한다** — `backup/main-before-reset`의 옛 무기 코드는 클라이언트 로컬 판정이라 그대로 쓰면 두 화면이 어긋난다(밸런스 값은 재사용 권장).
지연 보상(prediction·rollback)은 로드맵 Non-goal이라 입력 지연이 왕복 시간만큼 발생한다.

### 개발 시 주의

- 이 환경에는 Godot 바이너리가 없음 — 실행 검증(F5)은 사용자가 수동으로 한다. 정적 검증(경로·상수 대조 등)을 기록하고 PR을 연 뒤 사용자 확인을 기다린다.
- 배포본(export)이 아직 없고 `export_presets.cfg`도 없다. 유저 실행용 빌드는 별도 이슈로 진행 예정.
- `README.md`는 프로젝트와 무관한 외부 유저가 보는 문서다 — 폴더 구조, 확장 가이드, 엔진 실행·검증 방법을 넣지 않는다(이슈 #4·#8·#11). 개발자용 정보는 이 파일과 `docs/`에 둔다. 현재 README에는 리셋과 함께 폴더 구조·실행 방법이 다시 들어가 있어 정리가 필요하다.
- .gd 스크립트를 새로 만들면 사용자 에디터가 .uid 파일을 생성한다 — 발견 시 해당 이슈 브랜치에 커밋한다.
- .tscn의 `load_steps`는 Godot 4.6이 더 이상 기록하지 않는다 — 이미 있는 파일에서는 값을 유지하고(= ext_resource 수 + sub_resource 수 + 1), 없는 파일에 손으로 추가하지 않는다.
- .tscn의 `uid://`는 손으로 바꾸지 않는다. 씬의 자기 UID를 바꾸면 그 씬을 참조하는 `ext_resource`의 UID도 같이 고쳐야 한다. stale `.godot` 캐시 상태로 에디터가 UID를 재생성하면 참조가 끊길 수 있으니(이슈 #27), 그런 변경은 커밋하지 말고 `git restore`로 되돌린다.
- `main`이 리셋된 이력이 있다. `dev`는 2026-07-26에 `main`(`e2a7dcb`) 지점으로 재정렬했다. 옛 히스토리가 필요하면 `backup/main-before-reset`을 참조한다.

## Issue-First Rule

- 기능, 버그 수정, 개선, 리팩터링 작업은 GitHub 이슈 없이 구현을 시작하지 않습니다.
- 사용자가 이슈 없이 작업을 요청하면 GitHub 접근 권한이 있을 때 먼저 이슈를 만듭니다.
- GitHub 접근 권한이 없으면 사용자에게 이슈 없이 진행해도 되는지 확인하고, 최종 응답에 이슈 생성이 막혔다는 점을 남깁니다.
- 이슈 번호는 브랜치 이름, 커밋 메시지, PR 본문에 포함합니다.
- 관련 없는 정리 작업은 별도 이슈와 별도 브랜치로 분리합니다.

## Required Issue Detail

모든 기능, 개선, 버그 이슈에는 아래 항목이 있어야 합니다.

- Summary: 무엇이 바뀌어야 하는지.
- Motivation or Problem: 왜 필요한지.
- Current Behavior: 현재 어떻게 동작하는지.
- Expected Behavior: 완료 후 어떻게 동작해야 하는지.
- Scope: 영향을 받을 게임 시스템, 씬, 스크립트, 에셋, 문서.
- Acceptance Criteria: 완료를 증명할 구체적인 기준.
- Verification Plan: 실행할 명령이나 수동 확인 방법.

버그 수정 이슈에는 추가로 아래 항목이 필요합니다.

- Reproduction Steps.
- Actual Result.
- Expected Result.
- Environment, when relevant.

새 기능 이슈에는 추가로 아래 항목이 필요합니다.

- Player Flow.
- Non-goals.
- UX, input, balance, or settings expectations, when relevant.

## Branching

- 이슈 하나당 브랜치 하나를 만듭니다.
- 브랜치 이름은 짧고 이슈 번호를 포함합니다.
- 권장 형식:
  - `issue-<number>-short-topic`
  - `fix-<number>-short-topic`
  - `feat-<number>-short-topic`

## Implementation

- 파일을 수정하기 전에 이슈를 읽고 의도한 동작을 확인합니다.
- 변경 범위는 이슈에 적힌 내용으로 제한합니다.
- 기존 프로젝트 패턴을 우선합니다.
- 큰 구조 변경이나 폴더 정리는 해당 이슈가 직접 요구할 때만 합니다.

## Verification

변경한 파일과 게임 엔진 상태에 맞춰 가장 작은 의미 있는 검증부터 실행합니다.

- Godot 프로젝트 설정 확인
- 변경한 씬 또는 스크립트 수동 실행
- 플레이어 입력, UI, 충돌, 게임 흐름 확인
- 사용 가능한 테스트나 빌드 명령이 생기면 해당 명령 실행

PR 본문에는 실제로 확인한 내용을 기록합니다.

## Pull Requests

- PR 제목은 이슈에서 해결한 결과를 요약합니다.
- PR 본문에는 `Closes #<issue-number>`를 포함합니다.
- PR 본문에는 summary, verification, residual risks를 포함합니다.
- 검증 내용이 기록되기 전에는 머지하지 않습니다.

## Merge Flow

- 이슈를 해결하고 검증을 마친 뒤 이슈 브랜치에 커밋하고 원격 저장소에 푸시합니다.
- 이슈 브랜치에서 `dev`로 첫 번째 PR을 엽니다.
- `dev` 대상 PR이 mergeable/CLEAN이고 변경 파일이 이슈 범위와 일치하면 자동으로 머지합니다.
- 같은 원격 이슈 브랜치에서 `main`으로 두 번째 PR을 엽니다.
- **`main` 대상 PR은 자동으로 머지하지 않습니다.** PR을 열어 둔 채 CODEOWNERS 리뷰가 필요하다고 사용자에게 보고하고 멈춥니다. 이 저장소는 여러 명이 함께 쓰고 `main`은 발표·제출 기준이므로, 사람 리뷰를 건너뛰지 않습니다.
- 브랜치 보호 설정을 admin 권한으로 우회하지 않습니다(`gh pr merge --admin` 금지).
- 리뷰와 `main` 머지가 끝난 뒤 원격 이슈 브랜치를 삭제합니다.
- 정리 후 로컬 저장소는 삭제된 이슈 브랜치가 아니라 `main` 또는 `dev`에 둡니다.
- 팀 협업 규칙과 브랜치 보호 설정은 `docs/collaboration.md`를 따릅니다.

`dev` 자동 머지를 멈추고 사용자에게 보고하는 예외:

- 코드 충돌이 있거나 mergeable/CLEAN이 아닌 경우
- 이슈 범위 밖의 파일 변경이 섞인 경우
- 검증이 누락되었거나 미완인 경우(예: 자격증명·바이너리 부족으로 실행 확인 불가)
- 사용자가 "머지하지 말라"고 지시한 경우
- 되돌리기 어려운 부수효과가 있는 경우(데이터 마이그레이션, 배포 트리거 등)
