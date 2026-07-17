# Group-3

KADSA Group-3 게임 프로젝트 저장소입니다.

## 젤리 워즈 (Jelly Wars)

3조(스틱매너) 게임 개발기획서 기반 2인 로컬 대전 액션 게임. Godot 4.6으로 개발합니다.

핵심 루프: 무기 선택 → 맵 배정(랜덤) → 전투 → 승자 1점 / 패자 0점 → **3점 선취한 유저 승리**

### 조작

| 동작 | 1P | 2P |
| --- | --- | --- |
| 이동 | A / D | 숫자패드 4 / 6 |
| 점프 | W | 숫자패드 8 |
| 아래 (예약) | S | 숫자패드 5 |
| 공격 | Ctrl | 숫자패드 0 |

> 기획서에서 2P 공격 키가 미정("?")이라 임시로 숫자패드 0을 사용합니다. `project.godot`의 `[input]` 섹션에서 변경할 수 있습니다.

### 프로젝트 구조

```
autoload/
  game_manager.gd     # 전역 상태: 무기 레지스트리, 맵 목록, 점수, 3점 선취 판정
scenes/
  main_menu.tscn      # 시작 화면
  weapon_select.tscn  # 무기 선택 (각자 이동 키로 변경, 공격 키로 확정)
  match.tscn          # 매치 진행 + HUD (체력바, 점수, 라운드 배너)
  player/player.tscn  # 플레이어 (CharacterBody2D)
  maps/               # 맵 씬들
scripts/
  main_menu.gd / weapon_select.gd / match.gd / player.gd
  weapons/
    weapon.gd         # 무기 베이스 클래스 (쿨타임, 근접 판정 헬퍼)
    sword.gd          # 검: 근접 기본
    hammer.gd         # 망치: 강타 + 기절
    gun.gd            # 총: 투사체 발사
    projectile.gd     # 투사체
```

### 무기 추가 방법

1. `scripts/weapons/`에 `weapon.gd`(`Weapon`)를 상속하는 스크립트를 만들고 `_perform_attack()`을 구현합니다.
2. `autoload/game_manager.gd`의 `WEAPONS` 딕셔너리에 등록합니다.
3. 무기 선택 화면과 장착은 자동으로 반영됩니다.

### 맵 추가 방법

1. `scenes/maps/`에 새 씬을 만듭니다. 필수 노드: `SpawnP1`, `SpawnP2` (Marker2D).
2. `autoload/game_manager.gd`의 `MAPS` 배열에 등록합니다.

맵 기믹(냉장고 미끄러움, 위 속 위산 낙사 등)은 맵 씬 안에 스크립트를 붙여 구현합니다. 화면 밖으로 떨어지면 낙사 처리됩니다(`match.gd`의 `KILL_Y`).

### 실행 / 검증

- Godot 4.6 에디터로 프로젝트를 열고 F5 (메인 씬: `scenes/main_menu.tscn`)
- 헤드리스 스모크 테스트: `godot --headless --path . --quit`

## GitHub 작업 흐름

이 프로젝트는 `issue -> branch -> commit -> PR to dev -> PR to main` 흐름으로 작업합니다.

- 안정 버전은 `main` 브랜치에 둡니다.
- 새 기능, 개선, 버그 수정은 `dev`에서 작업 브랜치를 만들어 진행합니다.
- 작업 브랜치 이름은 `feat-12-player-jump`, `fix-18-camera-bug`, `issue-20-folder-cleanup`처럼 이슈 번호를 포함합니다.
- 작업 PR은 먼저 `dev`로 올립니다.
- `dev`에서 문제가 없으면 같은 작업 브랜치에서 `main`으로 PR을 올립니다.

자세한 규칙과 로컬 명령은 [docs/github-workflow.md](docs/github-workflow.md)를 확인하세요.
