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
   - `"melee"` — `basic_interval`에 **0.6초 바닥**(`Combat.MELEE_HIT_INTERVAL`)이 걸립니다.
   - `"melee_dot"` — 바닥 없이 `basic_interval` 그대로 들어갑니다. 데미지는 **한 틱당** 값이므로
     초당 데미지는 `basic_damage / basic_interval`입니다 (광선검 = 4 / 0.2 = 초당 20).
     넉백만 0.6초마다 한 번 주고 나머지 틱은 넉백 없이 들어갑니다 — 매 틱 밀어내면
     상대 조작이 잠기고 지속 무기가 자기 사거리 밖으로 상대를 내보냅니다 (이슈 #103).
4. 그림이 있으면 `assets/weapons/`에 넣고 항목에 `"file": "이름.png"` 한 줄을 더합니다.
   `file`이 없는 무기는 전투 화면에서 임시 막대로 그려집니다 (`assets/weapons/README.md` 참고).
5. 날아가는 것까지 그 그림으로 그리려면 발사할 때 스폰 데이터에 `"art": weapon["name"]`을 넣습니다.
   투사체가 `Weapons.texture()`로 그림을 붙이고 진행 방향으로 회전시킵니다 — 없으면 노란 막대입니다.
   지금은 단검만 씁니다. 던진 단검을 바닥에서 다시 주워야 해서 눈에 띄어야 하기 때문입니다.
6. 특수를 일정 거리 안에서만 쓰게 하려면 항목에 `"special_range": 150.0`을 넣고
   `_execute_special()`의 그 무기 가지에서 거리를 재 **밖이면 `false`를 돌려줍니다.**
   `false`면 쿨타임이 돌지 않아 바로 다시 누를 수 있습니다. 지금은 검만 씁니다.
7. 특수에 연출을 붙이려면 `main.gd`의 "연출" 절을 따릅니다 — 검의 빛기둥
   (`scenes/light_burst.tscn`)이 본보기입니다.

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

### 5. 연출은 판정에 관여하지 않는다

이펙트는 **결과가 정해진 뒤에** 띄웁니다. 서버가 명중을 확정하고
`@rpc("authority", "call_local", "reliable")`로 알리면 각 피어가 자기 화면에 그립니다
(`main.gd`의 "연출" 절, `scenes/light_burst.tscn`).

연출 노드는 `Effects` 아래에 붙고 스스로 `queue_free()`합니다. 투사체와 달리
`MultiplayerSpawner`를 쓰지 않습니다 — 아무것도 맞히지 않고 잠깐 떴다 사라져서
위치를 계속 맞출 것도 나중에 지워 줄 것도 없기 때문입니다.

이펙트가 없어도 게임은 똑같이 돌아가야 합니다. 연출 쪽에서 체력을 깎거나
상태를 바꾸면 안 됩니다.

**"없어지는 판정"은 반드시 보이게 만드세요** (이슈 #101). 광선검의 관통처럼 *막기가
사라지는* 종류의 능력은 성공해도 화면에 변화가 없어서, 켜진 것인지 상대에게 막힌 것인지
사거리가 모자란 것인지 구분할 수 없습니다. 이런 버프는 `player.gd`의 관통 빛무리처럼
켜져 있는 동안 눈에 보이는 표시를 함께 넣습니다. 버프 상태가 이미 양쪽 피어에
복제되어 있으므로(`_receive_buff`) 그리기는 각 피어가 알아서 하면 됩니다.

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
- 무기 그래픽 — 8종(검·단검·광선검·전기톱·망치·대포 총·폭탄·활)만 그림이 있습니다.
  나머지 9종은 임시 막대이고 길이가 사거리, 색이 특수 쿨타임 상태입니다
- 강화 상태 그림(`sword_charged.png`·`bomb_charged.png`)은 어떤 상태를 뜻하는지 정해지지 않아
  아직 쓰이지 않습니다

전투 전반 (로드맵 5단계):

- 라운드마다 무기를 다시 고르는 방식 — 기획서에는 있지만 아직 없습니다.
  한 번 고른 무기로 경기가 끝날 때까지 싸웁니다
- 추가 맵 — 맵 시스템 자체가 없습니다 (이슈 #62)

점수·3점 선취·라운드 재시작·낙사 판정은 이슈 #61에서 들어갔습니다.
평지는 좌우 벽이 있어 낙사가 일어나지 않고, 뚫린 맵이 생기면 그때부터 작동합니다.

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
