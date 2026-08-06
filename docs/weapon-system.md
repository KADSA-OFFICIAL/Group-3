# 무기 시스템 통합 가이드

> **이 문서를 보고 있다면, 무기 시스템을 여기에 이어 만들면 됩니다.**
> 무기 선택값이 플레이어까지 도달하는 연결부는 이미 완성되어 있고, **무기 동작만 비어 있습니다.**

관련 이슈: [#32](https://github.com/KADSA-OFFICIAL/Group-3/issues/32) (온라인 전환 로드맵)

## 지금 보장되는 것

선택 화면에서 고른 무기가 아래 경로로 **양쪽 피어의 `Player` 노드까지 이미 전달됩니다.**

```
선택 UI (player_panel.gd)
  → Lobby.submit_config()          클라이언트가 자기 선택만 전송
  → 서버: _sanitize()              목록에 있는 값인지 검증
  → 서버: _resolve_weapon()        "랜덤"을 실제 무기로 확정
  → main.gd: spawner.spawn(data)   스폰 데이터에 weapon_id 포함
  → Player.weapon_id               ← 여기서부터가 비어 있음
```

`Player.weapon_id`는 값을 **보관만** 하고 아무 동작도 하지 않습니다. 이 값을 읽어 무기 동작을 붙이는 것이 남은 작업입니다.

## 연결 지점

| 파일 | 심볼 | 역할 |
| --- | --- | --- |
| `scripts/game_state.gd` | `WEAPONS` | 선택 가능한 무기 목록의 **유일한 출처** |
| `scripts/lobby.gd` | `_resolve_weapon()` | "랜덤"을 실제 무기로 확정 (서버 전용) |
| `scripts/main.gd` | `_spawn_player()` | 스폰 시 `weapon_id` 주입 |
| `scripts/player.gd` | `weapon_id` | **무기 동작을 붙일 지점** |

## 지켜야 할 계약

### 1. 무기는 문자열 id 하나로 식별한다

목록의 유일한 출처는 `GameState.WEAPONS`입니다.

```gdscript
const WEAPONS := ["랜덤", "광선검", "망치", "총", "활", "의자", "우산", "방패"]
```

무기를 추가·변경하려면 이 배열을 고치세요. 선택 UI·검증·전송이 전부 이 배열을 따라가므로 다른 곳을 손댈 필요가 없습니다. 0번 `"랜덤"`은 실제 무기가 아니라 특수값입니다.

### 2. 공격 판정은 **서버에서만** 실행한다

이 프로젝트는 서버 권위 구조입니다. 위치·피해·사망을 서버가 결정하고 클라이언트는 입력만 보냅니다.

```gdscript
if not multiplayer.is_server():
    return
# 여기서부터 판정
```

`scripts/player.gd`의 이동 처리가 같은 패턴이니 참고하세요. `apply_movement()`는 서버 분기에서만 호출되고, `move_and_slide()`도 그 안에만 있습니다.

### 3. 클라이언트 입력은 검증한다

클라이언트가 보낸 RPC는 **송신자가 그 플레이어의 주인인지** 확인해야 합니다. 없으면 상대 캐릭터를 조작하거나 임의로 피해를 입힐 수 있습니다.

```gdscript
if multiplayer.get_remote_sender_id() != owner_peer_id:
    return
```

`player.gd`의 `_receive_move_input()`·`_receive_jump()`, `lobby.gd`의 `_receive_config()`·`_receive_ready()`가 모두 이 검사를 합니다.

### 4. 무기 동작은 `Player.weapon_id`를 읽어 스스로 붙는다

연결부 코드는 무기 종류를 알지 못합니다. 무기 쪽에서 id를 보고 자기 자신을 구성하세요. 그래야 무기를 추가할 때 `lobby.gd`·`main.gd`를 건드리지 않아도 됩니다.

## 이전 구현 참조 (재사용 권장)

2026-07-17에 만들어진 무기 구현이 **`backup/main-before-reset` 브랜치**에 남아 있습니다. 7월 26일 `main` 리셋 때 현재 코드베이스에서 빠졌습니다.

```bash
git show origin/backup/main-before-reset:scripts/weapons/weapon.gd
git show origin/backup/main-before-reset:scripts/weapons/sword.gd
```

경로: `scripts/weapons/{weapon,sword,hammer,gun,projectile}.gd`

### 이미 조정된 밸런스 값

수치는 한 번 다듬어진 자산이라 그대로 쓰면 밸런싱을 처음부터 하지 않아도 됩니다.

| 무기 | 피해 | 쿨타임 | 사거리 | 넉백 | 비고 |
| --- | --- | --- | --- | --- | --- |
| 검 | 15.0 | 0.4s | 56.0 | 220 | 기본 근접 |
| 망치 | 25.0 | 1.2s | 60.0 | 300 | 명중 시 1.0s 기절 |
| 총 | 8.0 | 0.3s | — | — | 투사체 발사 |
| (베이스 기본값) | 10.0 | 0.5s | — | — | |

- 플레이어 최대 체력: `100.0`
- 근접 판정 조건: **바라보는 방향** + y 차이 **50 이내** + 사거리 이내
- 넉백은 수평 `knockback_power`, 수직 `-knockback_power * 0.5`

### 그대로 가져오면 안 되는 부분

이전 구현은 **한 기기 2인 로컬** 전제라 클라이언트가 스스로 판정합니다. 지금 구조에 그대로 붙이면 두 클라이언트가 서로 다른 결과를 내서 화면이 어긋납니다.

| 이전 구현 | 지금 필요한 것 |
| --- | --- |
| 클라이언트가 `melee_hit()` 직접 호출 | 서버에서만 판정 |
| `GameManager.WEAPONS` (스크립트 경로 딕셔너리) | `GameState.WEAPONS` (이름 문자열) |
| `Player.health`·`take_damage()`·`apply_stun()`·`facing` | **아직 없음** — 4단계에서 추가 예정 |
| `players` 그룹 | 등록하지 않음 |
| 공격 입력 액션 | **아직 없음** — 4단계에서 추가 예정 |

즉 **로직 구조가 아니라 수치와 판정 규칙을 가져오는 것**이 맞습니다.

## 현재 없는 것 (4단계에서 추가 예정)

무기 동작에 필요하지만 아직 없는 것들입니다. 로드맵 4단계에서 이쪽이 만들 예정이니, 그 전에 필요하면 알려주세요.

- 공격 입력 액션 (`project.godot`의 `[input]`에 현재 `move_left`·`move_right`·`jump`·`fast_fall` 4개뿐)
- `Player`의 체력·피해·사망 처리
- 플레이어 그룹 등록, 바라보는 방향(`facing`)

## 하지 말 것

- 클라이언트에서 피해·사망을 결정하지 마세요 (서버 권위가 무너집니다)
- `GameState.WEAPONS`를 우회해 무기 목록을 따로 두지 마세요 (선택 UI와 어긋납니다)
- `weapon_id` 문자열을 여러 곳에 하드코딩하지 마세요
- "랜덤"을 클라이언트에서 뽑지 마세요 (양쪽이 다른 무기를 갖게 됩니다 — 서버의 `_resolve_weapon()`이 담당)

## 작업 전 체크리스트

- [ ] `CLAUDE.md`의 게임 정보 섹션을 읽어 현재 구조 파악
- [ ] 이 저장소는 issue-first 하네스를 씁니다 — 구현 전에 이슈를 만드세요 (`docs/github-workflow.md`)
- [ ] `scripts/start-task.sh <이슈번호> feat <주제>`로 브랜치 생성
- [ ] 판정 코드가 서버 분기 안에 있는지 확인
- [ ] 에디터 `Debug → Customize Run Instances` 3개(1번 인자 `--server`)로 실제 대전 확인
