# 무기 시스템 가이드

> **무기 17종의 기본 공격·특수 공격이 구현되어 있습니다.**
> 이 문서는 무기를 추가·수정할 때 어디를 고쳐야 하는지와, 지켜야 할 계약을 설명합니다.

관련 이슈: [#32](https://github.com/KADSA-OFFICIAL/Group-3/issues/32) (온라인 전환 로드맵),
[#46](https://github.com/KADSA-OFFICIAL/Group-3/issues/46) (무기·전투 레이어 이식)

수치의 근거와 미확정 항목은 [무기_수치_초안.md](%EB%AC%B4%EA%B8%B0_%EC%88%98%EC%B9%98_%EC%B4%88%EC%95%88.md)에 있습니다.

## 값이 흐르는 경로

```
선택 UI (player_panel.gd)
  → Lobby.submit_config()          클라이언트가 자기 선택만 전송
  → 서버: _sanitize()              목록에 있는 값인지 검증
  → 서버: _resolve_weapon()        "랜덤"을 실제 무기로 확정 (Weapons.resolve)
  → main.gd: spawn(data)           스폰 데이터에 weapon_id 포함
  → Player.weapon_id               무기 이름 보관
  → main.gd 서버 전투 틱            이 이름으로 Weapons.get_weapon()을 조회해 판정
```

## 파일 구성

| 파일 | 역할 |
| --- | --- |
| `scripts/weapons.gd` | **무기 표(17종)**. 이름·데미지·쿨타임·넉백 등 모든 수치의 출처 |
| `scripts/combat.gd` | 전투 공통 수치. 최대 체력·무적 시간·넉백 세기·투사체 속도 |
| `scripts/game_state.gd` | `WEAPONS` — "랜덤" + `Weapons.names()`. 선택 UI가 쓰는 목록 |
| `scripts/lobby.gd` | `_resolve_weapon()` — "랜덤" 확정 (서버 전용) |
| `scripts/main.gd` | **공격 판정 전부**. 기본 공격 틱, 특수 공격, 투사체 발사, 출혈·연사 |
| `scripts/player.gd` | 체력·무적·기절·게이지·버프·강제 이동. `server_*` 함수가 판정 결과를 받는 창구 |
| `scripts/projectile.gd` | 허공을 나는 것 — 화살·총알·표창·던진 단검·폭탄 |

## 무기를 추가·수정하려면

1. `scripts/weapons.gd`의 `LIST`에 항목을 넣거나 고칩니다. **목록의 유일한 출처입니다** —
   선택 UI·검증·전송이 전부 이 배열을 따라가므로 다른 곳을 손댈 필요가 없습니다.
2. 특수 공격에 새 동작이 필요하면 `main.gd`의 `_execute_special()`에 `match` 가지를 추가합니다.
3. 기본 공격은 `basic_kind`가 `"melee"` / `"melee_dot"` / `"ranged"`면 자동으로 동작합니다.

`LIST` 항목의 필드는 `weapons.gd` 맨 위 주석에 설명이 있습니다.

## 지켜야 할 계약

### 1. 공격 판정은 **서버에서만** 실행한다

이 프로젝트는 서버 권위 구조입니다. 위치·피해·사망을 서버가 결정하고 클라이언트는 입력만 보냅니다.

```gdscript
if not multiplayer.is_server():
    return
# 여기서부터 판정
```

`main.gd`의 `_physics_process()`가 이 분기 하나로 전투 틱 전체를 감싸고 있고,
`player.gd`의 `server_*` 함수들도 각각 같은 검사를 합니다.
판정 결과는 `@rpc("authority", "call_local", "reliable")`로 양쪽에 복제됩니다.

### 2. 클라이언트 입력은 송신자를 검증한다

클라이언트가 보낸 RPC는 **송신자가 그 플레이어의 주인인지** 확인해야 합니다.
없으면 상대 캐릭터를 조작하거나 임의로 피해를 입힐 수 있습니다.

```gdscript
if multiplayer.get_remote_sender_id() != owner_peer_id:
    return
```

`player.gd`의 `_is_owner_input()`이 이동·점프·Shift RPC 세 곳에서 이 검사를 합니다.
`lobby.gd`의 `_receive_config()`·`_receive_ready()`도 같은 방식입니다.

### 3. 판정에 쓰는 시간은 서버가 잰다

방패의 짧게/길게 구분은 클라이언트가 "길게 눌렀다"고 알려주는 것이 아니라,
서버가 Shift 누름·뗌 시각을 재서 판단합니다 (`player.gd`의 `_check_long_press()`).
클라이언트가 보내는 것은 눌렀다/뗐다는 사실뿐입니다.

### 4. "랜덤"은 서버가 뽑는다

`Weapons.resolve()`는 서버에서만 호출합니다. 클라이언트가 각자 뽑으면
양쪽이 서로 다른 무기를 갖게 됩니다.

## 하지 말 것

- 클라이언트에서 피해·사망을 결정하지 마세요 (서버 권위가 무너집니다)
- `Weapons.LIST`를 우회해 무기 목록을 따로 두지 마세요 (선택 UI와 어긋납니다)
- 무기 이름 문자열을 여러 곳에 하드코딩하지 마세요 — 판정은 `main.gd`의 `_execute_special()` 한 곳에 모읍니다
- 지연 보상(prediction·rollback)을 넣지 마세요 — 로드맵 Non-goal입니다

## 아직 안 된 것

무기 관련:

- **표창의 파란 표창** (15% 확률, 1P·2P 위치 교환) — 미구현
- **삼지창의 자동 회수 연출** — 지금은 맞으면 사라집니다
- **방패의 짧게/길게 경계 시간** — 임시로 0.3초(`Player.LONG_PRESS_TIME`)를 씁니다
- **샷건의 감소 기준 거리** — 임시로 400px입니다
- 무기 그래픽 — 전부 임시 도형(막대)입니다. 길이가 사거리, 색이 특수 쿨타임 상태입니다

전투 전반 (로드맵 5단계):

- 점수·3점 선취 승리, 라운드 진행·재시작 — 죽으면 반투명해질 뿐 다음 라운드가 없습니다
  (`main.gd`의 `_on_player_died()`가 그 자리입니다)
- 낙사 판정 — `Combat.is_out_of_bounds()`는 있지만 플레이어에는 아직 안 쓰입니다
  (현재 유일한 맵인 평지는 좌우 벽이 있어 낙사가 없습니다)

## 이전 구현 (참고용)

2026-07-17에 만든 첫 무기 구현이 **`backup/main-before-reset` 브랜치**에 남아 있습니다.
한 기기 2인 로컬 전제라 클라이언트가 스스로 판정하는 구조여서 지금 코드와는 맞지 않습니다.

```bash
git show origin/backup/main-before-reset:scripts/weapons/weapon.gd
```

현재 수치는 이 구현이 아니라 계획서(`무기 리스트(정리본).docx`)와
[무기_수치_초안.md](%EB%AC%B4%EA%B8%B0_%EC%88%98%EC%B9%98_%EC%B4%88%EC%95%88.md)에서 왔습니다.

## 작업 전 체크리스트

- [ ] `CLAUDE.md`의 게임 정보 섹션을 읽어 현재 구조 파악
- [ ] 이 저장소는 issue-first 하네스를 씁니다 — 구현 전에 이슈를 만드세요 (`docs/github-workflow.md`)
- [ ] `scripts/start-task.sh <이슈번호> feat <주제>`로 브랜치 생성
- [ ] 판정 코드가 서버 분기 안에 있는지 확인
- [ ] 에디터 `Debug → Customize Run Instances` 3개(1번 인자 `--server`)로 실제 대전 확인
