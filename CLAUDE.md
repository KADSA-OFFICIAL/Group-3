# Group-3 Claude Harness

이 저장소는 issue-first workflow를 사용합니다. Claude Code는 새 기능, 버그 수정, 개선, 리팩터링, 동작 변경을 시작하기 전에 이 하네스를 따라야 합니다.

## 게임 정보 (젤리 워즈)

2인 로컬 대전 액션, Godot 4.6 (Forward Plus), 뷰포트 1280×720. 3조(스틱매너) 개발기획서 기반.
핵심 루프: 무기 선택 → 맵 배정(랜덤) → 전투 → 승자 1점 → 3점 선취한 쪽이 최종 승리.

### 씬 흐름

main_menu → weapon_select(각자 이동 키로 무기 변경, 공격 키로 확정) → match(라운드 반복) → 3점 선취 시 main_menu 복귀

### 구조 요약

- `autoload/game_manager.gd` = 전역 싱글턴 `GameManager`: `WEAPONS` 레지스트리, `MAPS` 배열, `scores`, `WIN_SCORE = 3`, `random_map()`, `is_match_over()`, `weapon_for()`. 씬이 바뀌어도 점수·무기 선택이 유지된다.
- `scenes/match.tscn` + `scripts/match.gd` = 라운드 진행: `MapHolder`에 랜덤 맵 인스턴스 → 플레이어 2명을 `SpawnP1`/`SpawnP2`에 배치 → 사망 시 승자 1점 → `ROUND_DELAY`(2초) 후 다음 라운드, 매치 종료 시 `MATCH_END_DELAY`(3초) 후 메뉴 복귀. HUD(`Banner`·`ScoreLabel`·`P1Health`·`P2Health`)는 match.tscn 안에 있다.
- 낙사: `match.gd`의 `KILL_Y = 800.0` — y가 이 값을 넘으면 `MAX_HEALTH` 데미지로 즉사 처리.
- `scripts/player.gd`(`class_name Player`, CharacterBody2D): `player_id`로 `p1_*`/`p2_*` 입력 액션을 분기. SPEED 260, JUMP_VELOCITY -430, MAX_HEALTH 100. `facing`에 따라 `WeaponMount`의 x를 ±24로 옮긴다. `take_damage()`/`apply_stun()` 제공, `died`·`health_changed` 시그널로 match.gd와 통신.
- 무기: `scripts/weapons/weapon.gd`(`class_name Weapon`)가 베이스 — 쿨타임 관리 + `melee_hit(range, knockback)` 헬퍼(y 차이 50 이내, 바라보는 방향만 판정). 상속: 검(15dmg/0.4s), 망치(25dmg/1.2s + 1초 기절), 총(8dmg/0.3s, `projectile.gd` 발사). 무기는 씬이 아니라 코드로 `new()` 인스턴스화해 `WeaponMount`에 붙인다. `projectile.gd`도 노드 구성을 코드로 만든다.
- 맵: `scenes/maps/flat_map.tscn`, `scenes/maps/obstacle_map.tscn`. 필수 노드는 `SpawnP1`/`SpawnP2`(Marker2D). 지형은 StaticBody2D + CollisionShape2D + `Visual`(ColorRect) 조합.
- 그룹: 플레이어는 `players`, 투사체는 `projectiles` — 라운드 시작 시 `projectiles` 그룹을 일괄 `queue_free()` 한다.

### 조작 (project.godot `[input]`)

1P: A/D 이동, W 점프, S 아래, Ctrl 공격 / 2P: 숫자패드 4·6 이동, 8 점프, 5 아래, 0 공격.
`p1_down`/`p2_down` 액션은 정의만 되어 있고 player.gd에서 아직 쓰지 않는다(예약). 2P 공격 키는 기획서 미정이라 임시값이다.

### 개발 시 주의

- 이 환경에는 Godot 바이너리가 없음 — 실행 검증(F5)은 사용자가 수동으로 한다. 정적 검증(경로·상수 대조 등)을 기록하고 PR을 연 뒤 사용자 확인을 기다린다.
- 배포본(export)이 아직 없고 `export_presets.cfg`도 없다. 유저 실행용 빌드는 별도 이슈로 진행 예정.
- `README.md`는 프로젝트와 무관한 외부 유저가 보는 문서다 — 폴더 구조, 확장 가이드, 엔진 실행·검증 방법을 넣지 않는다(이슈 #4·#8·#11). 개발자용 정보는 이 파일과 `docs/`에 둔다.
- .gd 스크립트를 새로 만들면 사용자 에디터가 .uid 파일을 생성한다 — 발견 시 해당 이슈 브랜치에 커밋한다.
- .tscn 수정 시 `load_steps` = ext_resource 수 + sub_resource 수 + 1 을 유지한다.

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
- PR이 mergeable/CLEAN이고 변경 파일이 이슈 범위와 일치하면 자동으로 머지합니다.
- 같은 원격 이슈 브랜치에서 `main`으로 두 번째 PR을 열고, 같은 기준을 확인한 뒤 자동으로 머지합니다.
- `main` 머지가 끝나면 원격 이슈 브랜치를 삭제합니다.
- 정리 후 로컬 저장소는 삭제된 이슈 브랜치가 아니라 `main` 또는 `dev`에 둡니다.

자동 머지를 멈추고 사용자에게 보고하는 예외:

- 코드 충돌이 있거나 mergeable/CLEAN이 아닌 경우
- 이슈 범위 밖의 파일 변경이 섞인 경우
- 검증이 누락되었거나 미완인 경우(예: 자격증명·바이너리 부족으로 실행 확인 불가)
- 사용자가 "머지하지 말라"고 지시한 경우
- 되돌리기 어려운 부수효과가 있는 경우(데이터 마이그레이션, 배포 트리거 등)
