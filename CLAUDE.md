# Group-3 Claude Harness

이 저장소는 issue-first workflow를 사용합니다. Claude Code는 새 기능, 버그 수정, 개선, 리팩터링, 동작 변경을 시작하기 전에 이 하네스를 따라야 합니다.

## 게임 정보 (젤리 워즈)

2기기 **1 VS 1 온라인 대전** 액션, **Godot 4.6 (GL Compatibility)**. 3조(스틱매너) 개발기획서 기반. `project.godot`의 `config/name`은 "Jelly Wars", 메인 씬은 `scenes/title.tscn`.
기획 핵심 루프(무기 선택 → 맵 → 전투 → 3점 선취 승리)가 **전부 돈다.**

2026-07-28에 한 기기 2인 로컬에서 온라인 구조로 전환 중이다(로드맵 이슈 #32). 전용 헤드리스 서버가 권위를 갖고, 클라이언트 2대가 Tailscale로 접속한다. 서버 주소는 **저장소가 공개이므로 코드에 적지 않는다** — 접속 화면에서 입력받고 커밋되는 기본값은 `127.0.0.1`이다.

**접속에는 역할이 있다 — 플레이어와 관전**(이슈 #167). 방 하나에 플레이어 2명(`Network.MAX_PLAYERS`)과 관전자 4명(`MAX_OBSERVERS`)이 들어가고, ENet 정원은 둘을 합한 `MAX_CLIENTS`(6)다. 관전자는 플레이어 자리를 차지하지 않고 스폰도 받지 않으며 입력도 보내지 않는다 — 대기실과 전투 화면을 **읽기 전용**으로 본다. 역할은 접속 화면에서 고르고, 접속만으로는 자리가 생기지 않는다(`Lobby.submit_role()`).

**방 하나 = 포트 하나 = 서버 프로세스 하나**다(이슈 #89). 방 2개를 쓰려면 `--port=`를 달리해 서버를 두 번 띄운다. 방끼리 완전히 독립적이고 한 방이 죽어도 다른 방은 멀쩡하다. 실행 명령·방화벽·문제 해결은 `docs/server.md`에 있다.

`main` 브랜치는 2026-07-26에 새 구현(커밋 `e2a7dcb`)으로 교체되었다. 이전 구현(`autoload/game_manager.gd`, `scripts/weapons/`, `scenes/maps/` 등)은 `backup/main-before-reset` 브랜치에만 있고 현재 코드베이스에는 없다 — 그 경로를 참조하지 말 것.

### 씬 흐름

title(방과 역할을 고르고 서버 주소를 입력해 `StartButton`으로 접속) → select(대기실 겸 무기 선택, 둘 다 준비하면 서버가 시작 지시) → main(평지 전투, 서버가 플레이어 스폰) → **3점 선취 시 서버가 select로 되돌린다**(`Lobby.match_ended`). 전투 중 ESC(`ui_cancel`)로 접속 종료 후 title 복귀

**관전자도 같은 씬을 지나간다** — select에서 양쪽 선택을 보기만 하다가 같은 `match_starting` 지시로 main에 함께 들어가고, 경기가 끝나면 함께 select로 돌아온다. 다른 점은 자기 젤리가 없다는 것뿐이다. **경기 도중에 들어온 관전자는 그 경기를 못 보고** select에서 `Lobby.in_match`를 보고 다음 경기를 기다린다 — `MultiplayerSpawner`가 이미 스폰된 플레이어를 나중에 로드한 피어에게 전달하지 않기 때문이다(이슈 #167의 non-goal).

헤드리스로 실행되면 `Network`가 서버를 시작하고 title이 UI 없이 곧바로 main으로 넘어간다. **전용 서버는 select를 거치지 않고 계속 main에 머문다** — 대기실 상태는 씬이 아니라 `Lobby` 오토로드가 들고 있기 때문이다.

### 구조 요약

- `scripts/network.gd` = 오토로드 싱글턴 `Network`: 연결 수립과 피어 알림만 담당(게임 로직 없음). `ROOMS`(1번 방 7777·2번 방 7778 — 서버컴 방화벽 UDP 규칙과 일치), **방 하나당** `MAX_PLAYERS = 2` + `MAX_OBSERVERS = 4`이고 ENet에 넘기는 정원은 그 합인 `MAX_CLIENTS`(6)다, `DEFAULT_ADDRESS = "127.0.0.1"`. `should_run_as_server()`가 헤드리스 또는 `--server` 인자를 감지해 `_ready()`에서 자동으로 서버를 열고, 포트는 `port_from_cmdline()`이 `--port=7778` 인자에서 읽는다(없으면 첫 방). 시그널 `server_started`·`join_succeeded`·`join_failed`·`peer_joined`·`peer_left`.
  - **방 구성은 `ROOMS`가 유일한 출처다** — 포트도 방 이름도 여기 말고 다른 곳에 적지 않는다. 줄을 추가하면 접속 화면 버튼도 따라 늘어나므로 씬은 손대지 않아도 된다(이슈 #90).
  - **정원 상수를 늘리는 것만으로는 관전이 되지 않는다** — `MAX_CLIENTS`는 ENet에 넘기는 숫자일 뿐이고, 누구를 플레이어로 앉히고 누구를 관전으로 둘지는 `Lobby`가 정한다.
  - **포트를 못 열면 `get_tree().quit(1)`로 프로세스를 끝낸다**(이슈 #90). 안 끝내면 `is_server`가 false인 채로 살아남아 클라이언트 취급을 받는데, 헤드리스라 화면도 없어서 "서버 떠 있음"으로 착각하게 된다. 같은 방을 두 번 띄우거나 2번 방을 `--port=` 없이 띄웠을 때 실제로 걸린다.
- `scripts/lobby.gd` = 오토로드 싱글턴 `Lobby`: 대기실 상태를 **서버가 권위로** 보관한다. `order`(플레이어 접속 순서, 먼저 들어온 쪽이 1P), `observers`(관전자 peer 목록), `configs`(peer_id → weapon·character·map), `ready_flags`, `map_name`(시작할 때 확정되는 실제 맵), `in_match`(경기 진행 중인가). 클라이언트는 `submit_config()`·`submit_ready()`·`submit_map()`으로 자기 값만 보내고, 서버가 `_receive_lobby`로 전체를 복제한다. **무기 "랜덤" 확정과 맵 뽑기, 시작 판정은 서버에서만** 실행되어 양쪽이 같은 값을 갖는다. **맵은 플레이어마다 하나씩 고르고** 시작할 때 `_pick_map()`이 둘 중 하나를 뽑는다 — 각자의 "랜덤"을 먼저 실제 맵으로 확정한 뒤 뽑아야 뽑기가 두 번 일어나지 않는다. 클라이언트가 보낸 값은 `_sanitize()`로 목록에 있는 값인지 검사한다. 경기가 끝나면 서버가 `server_end_match()`로 준비를 풀고 양쪽을 대기실로 돌려보낸다(안 풀면 도착하자마자 다시 시작한다). 시그널 `lobby_changed`·`match_starting`·`match_ended`.
  - **자리 배정은 접속이 아니라 역할 신고로 일어난다**(이슈 #167). 클라이언트가 `submit_role()`을 보내면 서버가 `_receive_role`에서 `order`(플레이어) 또는 `observers`(관전)에 넣고 **그 피어에게만** 지금 상태를 돌려준다. 정원이 차면 넣지 않고 `role_rejected` 시그널로 사유를 보낸다 — 조용히 잠긴 화면을 만들지 않기 위해서다. 관전으로 들어온 피어는 `ready_flags`에 없으므로 시작 판정을 막지도 않는다.
  - **상태를 받는 것은 밀어주기만 믿지 않는다**(이슈 #93). `submit_role()`은 자리 배정과 상태 요청을 한 RPC로 합친 것이고, 이미 등록된 피어가 다시 보내도 상태만 다시 내려온다 — 몇 번을 청해도 안전하다. 접속 순간의 브로드캐스트 한 번만 믿으면 그것을 놓쳤을 때 `order`에 내 peer id가 없는 채로 굳는데, 그러면 대기실 화면이 통째로 잠기고 되돌릴 방법이 없다. 그래서 대기실 화면이 자리를 받을 때까지 1초마다 다시 보낸다.
  - **`viewers`는 복제하지 않는 서버 전용 목록이다**(이슈 #167) — 전투 화면에 실제로 들어와 있는 피어다(`main.gd`의 `_notify_ready`가 등록). 관전이 생기면서 "접속해 있지만 전투 화면 밖에 있는 피어"가 정상 상태가 되었고, 그 피어에게 Player 노드의 RPC를 보내면 그쪽에 노드가 없어 `Node not found`가 **초당 60번** 쌓인다. 그래서 위치 복제(`Player._send_state`)와 투사체 동기화는 이 목록으로만 보낸다. 경기가 끝나면 `server_clear_viewers()`로 비운다.
  - `reset()`은 클라이언트가 들고 있던 상태를 버린다. 옛 접속의 `order`가 남으면 새 접속에서 **"2명이 있는데 그중에 나는 없는"** 상태가 되고, 이건 화면상 정상과 구별되지 않는다.
  - 이 둘의 서버 판정은 `multiplayer.is_server()`가 아니라 **`Network.is_server`로 한다** — 접속이 끊기면 peer가 없어 내 id가 1이 되므로 클라이언트가 자기를 서버로 착각한다.
- `scripts/game_state.gd` = 오토로드 싱글턴 `GameState`: 화면 간 선택 정보 전달. `CHARACTERS`(`Characters.names()` 5종 — 사본을 두지 않고 캐릭터 표에서 만든다), `WEAPONS`("랜덤" + `Weapons.names()` 17종 — 마찬가지), `MAPS`("랜덤" + `Maps.names()` 4종 — 마찬가지), `p1_config`/`p2_config`(weapon·character), `map_name`, `get_config(prefix)`.
- `scenes/title.tscn` + `scripts/title.gd` = 타이틀 겸 접속 화면. `AddressEdit`(기본 `127.0.0.1`)·`RoomBox`(방 선택)·`RoleBox`(역할 선택 — `PlayerButton`·`ObserverButton`, 고른 값은 `Lobby.my_role`에 담긴다)·`StartButton`("접속")·`StatusLabel`(접속 중/실패 표시). 접속 성공 시 select로 전환한다. 좌우 `JellyLeft`/`JellyRight`는 미리보기 장식.
  - **방 버튼은 씬에 박아 두지 않고 `Network.ROOMS` 개수만큼 만든다**(이슈 #90). `RoomBox`(HBoxContainer) 아래 `RoomButton` 하나가 첫 방이자 나머지의 원본이고, `_setup_room_buttons()`가 `duplicate()`로 복제한다 — 스타일과 `ButtonGroup`이 그대로 딸려 오므로 라디오 동작과 모양이 자동으로 맞는다. 버튼은 `size_flags_horizontal = 3`이라 방이 몇 개든 같은 폭에 균등하게 나뉜다.
  - **역할 버튼은 방 버튼과 색으로 구분한다**(이슈 #167) — 방은 진한 핑크, 역할은 진한 라벤더가 선택 색이다. 두 줄이 똑같이 생기면 방을 고른 것과 역할을 고른 것이 헷갈린다. 고른 역할은 오토로드에 남아 다음 접속에도 유지된다.
  - `AddressEdit`에 `주소:포트`로 적으면 고른 방보다 그쪽을 우선한다.
  - **방이 꽉 차면 ENet이 거절 신호를 보내지 않고 조용히 무시한다** — `connection_failed`조차 오지 않아 "접속 중..."에서 영원히 멈춘다. 그래서 `JOIN_TIMEOUT_SEC`(8초) 타이머로 직접 실패 처리한다. 이 타이머를 지우면 증상이 되살아난다.
- `scenes/select.tscn` + `scripts/select.gd` = 대기실 겸 무기 선택. `P1Panel`/`P2Panel`은 흰 카드(`Card`) 위에 얹히며 `Lobby.order` 슬롯에 대응하고 **자기 슬롯만 조작 가능**하고 상대 패널은 서버가 보낸 값을 표시만 한다. `StatusLabel`에 "상대 대기 중" 또는 양쪽 준비 상태, `GoButton`은 준비 토글. **씬 전환은 클라이언트가 스스로 하지 않고 `Lobby.match_starting`(서버 지시)을 받아서 한다.** 좌우 화살표는 **자기 맵 선택만** 바꾼다(`Lobby.submit_map()`) — `MapBox`에 양쪽 선택이 나란히 보이고, 실제로 쓸 맵은 시작할 때 서버가 둘 중 하나를 뽑는다. 그 아래 `WeaponBox`에 양쪽이 고른 무기 그림과 이름이 나란히 보인다.
  - **화면에 들어오면 역할을 신고하고 대기실 상태를 새로 받는다**(`_start_sync()`, 이슈 #93·#167) — 들고 있던 것을 `Lobby.reset()`으로 버리고 `Lobby.submit_role(Lobby.my_role)`을 보낸다. 답도 유실될 수 있어 자리를 받을 때까지(`Lobby.knows_me()`) `SYNC_RETRY_SEC`(1초)마다 다시 보낸다.
  - **관전자에게는 이 화면이 통째로 읽기 전용이다** — 양쪽 패널·맵 화살표·`GoButton`이 다 잠기고 `StatusLabel`이 관전 상태를 적는다(플레이어 대기 중 / 준비 대기 중 / 경기 진행 중). 플레이어 쪽 문구 뒤에는 `관전 N명`이 붙는다.
  - **자리를 거절당하면(`Lobby.role_rejected`) 되풀이 요청을 멈추고 사유와 나갈 길을 띄운다** — 자리가 없는데 계속 청하면 "눌러도 아무 일 없는 화면"이 된다. **여기서 역할을 바꾸는 조작은 두지 않는다**(이슈 #170) — 역할을 고르는 자리는 접속 화면 하나뿐이다. 다만 플레이어 자리가 비면 `_refresh`가 알아서 다시 신청하므로 기다리는 것만으로도 들어갈 수 있다.
  - **트리를 벗어난 뒤에는 신호를 무시한다**(`is_inside_tree()` 확인). 씬 전환은 프레임 끝에 일어나므로 그 사이에 도착한 서버 방송이 이미 떼어진 노드로 들어오고, 그때 `multiplayer`는 null이다. 관전자가 경기 중에 들어오고 나가면서 방송이 늘어 잘 드러난다.
  - **내 자리가 아직 없으면(`slot_of(me) < 0`) `GoButton`을 잠그고 "대기실 정보를 받는 중..."을 띄운다.** 그 상태에서는 준비를 보내도 서버가 버리므로, 버튼을 켜 두면 "눌리는데 아무 일도 안 일어난다"로만 보인다. 이때는 양쪽 패널도 잠겨 있다 — 화면 전체가 죽은 것처럼 보이는 유일한 경우다.
- `scenes/player_panel.tscn` + `scripts/player_panel.gd` = 플레이어 1인 패널(양쪽 재사용). `mirrored`가 true면 아이콘 열을 오른쪽으로 옮긴다. 무기/캐릭터 버튼은 각각 목록을 순환하고, `RandomButton`은 전부 랜덤. 사용자 조작으로 값이 바뀌면 `config_changed`를 내보낸다. `set_interactive(false)`로 상대 패널을 잠그고, `apply_config()`로 서버가 보낸 값을 표시한다(이때는 시그널을 내보내지 않는다).
- `scripts/weapon_preview.gd` = 대기실 가운데 `WeaponBox`의 무기 그림 미리보기. `jelly_preview.gd`와 같은 형태이고 `Art.content_rect()`로 여백을 뺀다. 그림이 있는 무기가 10종뿐이라 **없으면 아무것도 그리지 않고** 옆의 이름 라벨이 대신한다. 무기 원화는 세로로 긴 것(검 1:4.7)과 가로로 긴 것(전기톱·대포 총)과 뭉툭한 것(글러브 1.18:1)이 섞여 있어 칸은 세로로 잡았다.
- `scripts/jelly_preview.gd` = 젤리곰 미리보기. `character_id` setter가 `Characters.texture()`로 그림을 받아 `queue_redraw()`를 호출하고, `_draw()`가 비율을 지켜 가운데에 그린다.
- `scripts/characters.gd`(`class_name Characters`) = **캐릭터 표 5종**(분홍·파랑·초록·노랑·빨강). 이름과 그림 경로의 유일한 출처이며 대기실 선택지·서버 검증·전투 화면 그림이 모두 여기서 나온다. 그림은 `assets/characters/`에 있고, 파일이 없으면 표의 몸통 색 단색으로 대신 그린다. 여백 측정은 `Art.content_rect()`가 한다.
- `scenes/main.tscn` + `scripts/main.gd` = 전투 화면이자 **공격 판정의 주인**. 지형은 씬에 없고 `_ready()`가 `Lobby.map_name`으로 맵 씬을 `MapRoot` 아래에 붙인다(모든 피어에서, 스폰보다 먼저). 화면 글자는 전부 `UI/HUD` 아래 흰 카드 안에 있다 — `HintCard`(조작 안내 2줄)·`MapCard`(맵 이름)·`P1Card`/`P2Card`(`Name`·`Hp`·`Bar`·`Score`, 1P 핑크·2P 라벤더). ESC로 접속 종료.
  - **UI는 `UI`(CanvasLayer) 아래에 둔다**(이슈 #82). 씬 루트가 `Node2D`라 Control을 거기에 바로 붙이면 앵커가 기준으로 삼을 부모 사각형이 0×0이 되어 `HUD`의 크기도 0이 된다 — 그러면 `anchor_left = 0.5`로 가운데를 잡은 것들이 전부 화면 왼쪽 끝(x=0)에 그려지고 화면을 덮는 판도 안 보인다. CanvasLayer 아래에서는 뷰포트 크기가 기준이 된다. 앵커를 쓰는 UI를 새로 넣을 때는 반드시 이 아래에 붙인다.
  - **글자는 맵 배경 위에 그냥 얹지 않고 흰 카드 안에 넣는다**(이슈 #112). 맵마다 배경 밝기가 정반대라서(평지 하늘 `(0.82, 0.93, 0.99)` ↔ 용암 `(0.42, 0.26, 0.38)`) 한 맵에 맞춘 글자색은 다른 맵에서 사라진다 — 진한 글자를 용암 배경에 얹으면 대비가 1.3:1이다. 카드를 깔면 배경이 무엇이든 10:1이 나오므로, 맵 위에 글자를 새로 얹을 일이 생기면 카드부터 만든다. 카드는 하늘 영역(y ≲ 190)에 둔다 — 점프 정점이 y≈340이라 지형·젤리와 겹치지 않는다.
  - 체력 숫자는 막대 **안**(`show_percentage`)이 아니라 카드 위 별도 라벨에 적는다. 막대 안에 그리면 채운 쪽과 빈 쪽의 밝기가 반대라 어느 색을 골라도 한쪽에서 묻힌다.
  - **플레이어는 씬에 배치되어 있지 않고 서버가 런타임에 스폰한다** — `PlayerSpawner`(MultiplayerSpawner, `spawn_path = ../Players`)와 `Players` 노드가 담당. 클라이언트는 씬 준비 후 `_notify_ready()`를 서버로 RPC하고, 서버가 그때 `spawn()`한다(접속 직후 스폰하면 클라이언트가 씬 로드 전이라 놓칠 수 있다). 노드 이름은 `Player_<peer_id>`.
  - **관전자에게는 스폰하지 않는다**(이슈 #167) — `_notify_ready()`가 `Lobby.is_observer()`를 보고 걸러낸다. 대신 그 피어를 `Lobby.server_add_viewer()`로 등록해 **전투 노드 RPC의 대상**에 넣는다. 관전자는 조작 안내 대신 `관전 중` 문구를 보고(`_setup_observer_view()`), 결과 화면에서는 이긴 쪽의 젤리와 `1P 승리!`를 본다(`_play_result`의 `title_override`).
  - 투사체도 같은 방식이다 — `ProjectileSpawner`(`spawn_path = ../Projectiles`). 서버에서 `queue_free()`하면 클라이언트에서도 같이 사라진다.
  - **연출(이펙트)은 스포너를 쓰지 않는다**(이슈 #99). 서버가 결과를 정한 뒤 `@rpc("authority", "call_local", "reliable")`로 알리면 각 피어가 `Effects`(z_index 50) 아래에 노드를 붙이고, 그 노드가 다 재생한 뒤 스스로 `queue_free()`한다 — 아무것도 맞히지 않고 잠깐 떴다 사라져서 위치를 계속 맞출 것도 나중에 지워 줄 것도 없다. 검 특수의 빛기둥(`scenes/light_burst.tscn`)이 첫 사례다.
  - `_physics_process()`가 `multiplayer.is_server()` 하나로 전투 틱 전체를 감싼다: `_check_basic_attacks()`(근접 접촉·원거리 자동 발사) → `_check_pending_specials()`(강제 이동 중 명중) → `_tick_bleeds()`(출혈) → `_tick_bursts()`(연발 — 소총은 **시간**으로, 글러브 로켓 펀치는 **발 수**로 끝난다, 이슈 #164. `_start_burst()`가 둘 다 예약하고 `first_knockback`으로 첫 발만 세게 민다) → `_check_falls()`(낙사) → `_tick_round()`(예약된 라운드 재시작·대기실 복귀). 특수 공격은 `Player.special_requested` 신호를 받아 `_execute_special()`에서 무기별로 분기한다.
  - **근접은 기본·특수 모두 `_faces()`를 통과해야 들어간다**(이슈 #107) — 등 뒤의 상대는 못 때리고, 뒤를 잡으면 일방적으로 때릴 수 있다. 좌우가 정확히 같은 순간(위아래로 겹침)은 빗나간 것으로 본다. **원거리**(`_server_fire()`가 이미 `facing` 쪽으로만 쏜다)와 **강제 이동 중의 특수**(`_check_pending_specials` — 도끼 낙하는 바로 아래를 때려서 좌우를 따지면 영영 안 맞는다)는 일부러 거치지 않는다.
  - **포인트 진행도 여기가 주인이다.** `_on_player_died()`가 상대에게 1포인트를 주고, `Combat.POINTS_TO_WIN`(3포인트)에 닿으면 승리를 표시한 뒤 `Lobby.server_end_match()`로 양쪽을 대기실로 돌려보낸다. 아니면 `ROUND_RESTART_DELAY`(2초) 뒤 `_start_round()`가 투사체·서버 타이머를 비우고 `Player.server_reset()`으로 양쪽을 되살린다. 점수(`scores`)와 안내 문구(`banner`)는 서버가 정해 `_receive_round`로 복제하며 **클라이언트는 점수를 세지 않는다.**
  - **화면 문구는 "라운드 승패"가 아니라 "포인트 획득"으로 쓴다**(이슈 #76) — 배너는 `1P +1 포인트`, 마지막에 `1P 승리!  3포인트 달성`, HUD 점수는 `_score_text()`가 `●○○  1 / 3`처럼 동그라미와 숫자를 같이 낸다. 규칙은 그대로이고 표현만 통일한 것이다.
  - **경기가 끝나면 피어마다 자기 기준으로 결과 화면을 띄운다**(이슈 #79) — 서버는 `_receive_match_result`로 **승자 peer만** 보내고, 각 클라이언트가 `HUD/ResultOverlay`(어둡게 덮는 `Dim` + `Jelly` 미리보기 + `ResultLabel` + `ScoreLabel`)에 트윈으로 승리(통통 튐 + 글자 팝업·맥동)와 패배(색 빠지며 주저앉음 + 글자가 위에서 내려옴) 연출을 만든다. 젤리는 `jelly_preview.gd`를 그대로 재사용하고 **그 화면 주인의 캐릭터**를 보여준다. `get_player(내 peer)`가 없는 피어(전용 서버)는 아무것도 띄우지 않는다. 결과 화면이 떠 있는 동안 `Banner`는 접힌다. 연출 트윈은 `_result_tweens`에 모아 두고 `_hide_result()`가 전부 끊는다.
  - 전용 서버는 씬을 벗어나지 않으므로 경기가 끝나면 `_server_reset_match()`가 직접 판을 비운다 — 안 하면 다음 경기에 점수가 이어지고 플레이어가 다시 스폰되지 않는다.
- `scenes/player.tscn` + `scripts/player.gd`(CharacterBody2D, `class_name Player`): **서버 권위 이동 + 서버 권위 전투**. `owner_peer_id`·`player_name`·`character_id`·`weapon_id` export. SPEED 320, JUMP_VELOCITY -560, FAST_FALL_MULTIPLIER 2.0, INTERPOLATION_SPEED 20.
  - 클라이언트: `read_input()`(**`Input`을 읽는 유일한 지점**) → `_receive_move_input`(unreliable_ordered)·`_receive_jump`·`_receive_skill`(reliable, 엣지 입력이라 유실되면 안 됨)로 서버 전송. 물리를 계산하지 않고 `_receive_state`로 받은 위치로 lerp 보간만 한다.
  - 서버: `apply_movement(input, delta)`로 위치를 정하고(`move_and_slide()`는 여기서만 호출) `_receive_state`(authority, unreliable_ordered)로 위치·속도·접지·`facing`을 복제한다.
  - **위치 복제는 브로드캐스트가 아니라 `Lobby.viewers`에게만 보낸다**(`_send_state()`, 이슈 #167). 대기실에 앉아 있는 피어(경기 중에 들어온 관전자 등)에게는 이 노드가 없어서 `Node not found`가 **초당 60번** 쌓인다. 새로 매 프레임 복제하는 것을 만들 때도 같은 목록을 쓴다.
  - **권한 검증**: 입력 RPC 세 개가 모두 `_is_owner_input()`을 거친다 — `multiplayer.get_remote_sender_id() != owner_peer_id`이면 무시한다. 없으면 남의 플레이어를 조작할 수 있다.
  - 전투 상태(`hp`·`alive`·`facing`·무적·기절·게이지·버프·강제 이동)는 **서버가 정하고** `server_*` 함수가 결과를 `@rpc("authority", "call_local", "reliable")`로 양쪽에 복제한다. 판정 자체는 여기가 아니라 `main.gd`에 있다.
  - 방패의 짧게/길게는 **서버가 누른 시간을 잰다**(`_check_long_press()`) — 클라이언트는 눌렀다/뗐다만 보낸다.
  - 몸은 `Body`(Sprite2D)에 캐릭터 그림을 붙인다. 원화가 정사각 캔버스에 여백을 두고 그려져 있어 `Characters.content_rect()`로 **투명 여백을 뺀 실제 그림 영역**을 재고, 그 높이를 `BODY_HEIGHT`(72px)에 맞춰 배율과 위치를 정해 발을 충돌 상자 바닥에 붙인다. 찌그러짐은 그 기본 배율에 곱하고, 좌우 반전은 복제된 `facing`으로 `flip_h`를 켠다. **배율이나 반전이 바뀌면 반드시 `_place_body()`를 부른다**(이슈 #85) — Sprite2D는 자기 위치를 *중심으로* 확대·축소하므로 세로로 늘어나면 발이 바닥을 뚫고 납작해지면 발이 뜬다. 그래서 여백 보정은 배율을 곱하기 전 값(`_body_offset_unit`)으로 들고 있다가 `_place_body()`가 그때의 배율로 환산해 **발밑을 항상 `BODY_BOTTOM`에 고정**하고, `flip_h`를 보고 좌우 보정의 부호도 맞춘다.
  - 젤리 찌그러짐은 복제된 속도·접지값으로 각 피어가 계산한다.
  - **관통(광선검 특수) 중에는 Player 자신의 `_draw()`가 몸 뒤에 민트빛 빛무리를 그린다**(이슈 #101). 자식(`Body`)보다 먼저 그려지므로 뒤에 깔려서 별도 노드가 필요 없고, 씬 루트에 건 가산 혼합은 **이 그리기에만** 적용되고 자식 스프라이트에는 영향이 없다. `_pierce_until`이 복제되므로 양쪽 화면에 같이 뜬다. 관통은 "막기가 사라지는" 판정이라 표시가 없으면 켜졌는지 막힌 건지 사거리가 모자란 건지 구분할 수 없다 — 무기 색도 `PIERCE_TINT`(1을 넘겨 밝게)로 함께 바뀐다.
  - 무기는 그림이 있으면 `WeaponSprite`에 세워서 바라보는 쪽에 놓고(세로 `WEAPON_HEIGHT` 56px, 다만 가로가 `WEAPON_MAX_WIDTH` 80px를 넘으면 그쪽에 먼저 맞춘다 — 가로로 긴 원화(전기톱 2.69:1)가 몸통 3배 폭으로 터지는 것을 막는다, 이슈 #105), 쿨타임 상태는 밝기로 나타낸다. **뭉툭한 원화는 두 제한을 다 통과하고도 몸통만 해지므로**(세로 규칙이 가늘고 긴 무기 기준이다) 무기 표의 `weapon_art_scale`로 더 줄인다 — 지금은 글러브만 0.6이다(이슈 #158). 그림이 없는 7종은 여전히 `WeaponShape` 임시 막대이며 길이가 사거리·색이 쿨타임 상태다. 어느 쪽을 쓸지는 `_apply_weapon()`이 정한다.
- `scenes/light_burst.tscn` + `scripts/light_burst.gd` = **검 특수의 빛기둥 연출**(이슈 #99). 그림 파일 없이 `_draw()`로만 그려서 배경 없이 빛만 남고, 노드에 가산 혼합(`CanvasItemMaterial`, `blend_mode = 1`)이 걸려 있어 겹칠수록 하얘진다. 원점은 맞은 젤리의 발밑이고 0.9초 뒤 스스로 사라진다. 부챗살 모양·떨림은 `global_position`으로 씨앗을 잡은 난수라 **양쪽 화면에 같은 모양이 뜬다.**
- `scripts/weapons.gd`(`class_name Weapons`) = **무기 표 17종**. 이름·기본/특수 데미지·쿨타임·넉백 등 모든 무기 수치의 유일한 출처. `RANDOM` 상수와 `resolve()`(서버 전용 랜덤 확정)도 여기 있다. 그림이 있는 10종은 `file` 필드를 갖고 `texture()`가 `assets/weapons/`에서 꺼내 온다 — 없으면 null이고 부르는 쪽이 막대로 대신한다.
- `scripts/maps.gd`(`class_name Maps`) = **맵 표 4종**(평지·바다·용암·벽돌). 이름과 씬 경로의 유일한 출처. `RANDOM` 상수와 `resolve()`(서버 전용 랜덤 확정)가 무기 표와 같은 형태다. **맵 씬 계약**: 루트 `Node2D`, `Spawns/Spawn1`·`Spawn2`(Marker2D, 순서가 1P·2P), 지형은 `StaticBody2D` + `CollisionShape2D`, 즉사 구역은 `Hazard`(Area2D), 배경도 맵이 그린다. 좌우 벽이 없는 맵은 화면 밖으로 나가면 낙사한다.
  - 바다·용암에는 `Hazard`가 있어 닿으면 즉사한다. 평지·벽돌은 좌우 벽이 있고 `Hazard`도 없어 낙사가 일어나지 않는다.
- `scripts/art.gd`(`class_name Art`) = 그림 공통 처리. `content_rect()`가 **투명 여백을 뺀 실제 그림 영역**을 잰다. 캐릭터·무기 원화가 모두 정사각 캔버스에 여백을 두고 그려져 있어 크기와 위치를 잡을 때 항상 이 값을 기준으로 한다. `draw_glow()`는 **가운데가 밝은 빛무리**를 그린다 — 원 하나로 그리면 테두리가 딱 끊겨 어두운 판때기로 보여서, 같은 옅기의 원을 크기만 줄여 가며 겹쳐 쌓는다. 빛기둥과 관통 표시가 같이 쓴다.
- `scripts/combat.gd`(`class_name Combat`) = 전투 공통 수치. MAX_HP 100, INVULNERABLE_TIME 0.1, MELEE_HIT_INTERVAL 0.6(**지속 데미지 무기의 데미지 간격에는 안 걸리고 넉백 간격으로만 쓰인다** — 이슈 #103), ROUND_START_GRACE 2.0, POINTS_TO_WIN 3, ROUND_RESTART_DELAY 2.0, MATCH_END_DELAY 4.0, 넉백 3단계(200/400/700), PROJECTILE_SPEED 1120, 낙사 경계 `is_out_of_bounds()`.
- `scenes/projectile.tscn` + `scripts/projectile.gd`(Area2D, `class_name Projectile`) = 허공을 나는 것(화살·총알·표창·던진 단검·폭탄). 이동·판정은 서버만 하고 위치는 `MultiplayerSynchronizer`(`Sync`)로 복제된다. 상대 무기에 막히지 않고 공유 무적도 타지 않는다.
  - **`Sync`에 가시성 필터를 걸지 말 것**(이슈 #167에서 시도했다가 되돌렸다). `public_visibility = false` + `add_visibility_filter()`를 `_ready()`에서 걸면 **모든 클라이언트에서 투사체가 사라진다** — 서버에는 2개가 있는데 양쪽 화면에 0개였다. 자식 `Sync`의 `_ready()`가 부모보다 먼저 돌아 이미 등록된 뒤에 가시성을 끄는 순서 문제로 보이고, 필터가 다시 평가되지 않는다. 대기실에 앉아 있는 피어에게 날아가는 것을 막으려면 이 경로가 아니라 다른 방법을 찾아야 한다.
  - **폭발 반경은 `BlastRadius` 자식 노드가 그린다**(`scripts/blast_radius.gd`, 이슈 #140) — `explosion_radius`(폭탄 200px)만큼의 반투명 원과 그 경계선이다. 폭탄은 닿지 않아도 맞는 유일한 무기라 범위가 안 보이면 피할 거리인지 판단할 근거가 없다. **루트가 아니라 자식에서 그리는 이유**는 루트에 미사일 불꽃용 가산 혼합이 걸려 있어서다 — 가산은 밝게만 만들 수 있어 평지 하늘처럼 흰 배경 위에서는 아무것도 안 보인다(#112). 자식은 그 재질을 물려받지 않아 보통의 알파 혼합으로 그려진다. 폭탄 그림 뒤에 깔리는 것은 **형제 순서**로 한다(`Visual`·`ArtSprite`보다 앞에 있다) — **`z_index`를 내리면 안 된다**(이슈 #146). z를 내리면 z 0에 있는 것 **전부보다** 먼저 그려지는데 맵이 자기 배경을 z 0의 불투명 `ColorRect`로 깔기 때문에 그 아래로 사라진다. `Effects`처럼 **올리는** 것은 안전하고 내리는 것만 위험하다. 원점 기준으로 한 번만 그려 두면 폭탄이 움직여도 따라간다. 반경이 0인 나머지 투사체는 아무것도 그리지 않는다.
  - 그리기는 기본이 노란 막대(`Visual`)지만, 스폰 데이터에 `art`(무기 이름)가 있으면 `ArtSprite`에 그 무기 그림을 붙이고 진행 방향으로 회전시킨다 — 단검·삼지창·로켓 글러브가 쓴다(이슈 #96·#152·#161). **원화의 앞이 오른쪽이면 `art_points_right`를 넘긴다** — 기본은 "날 끝이 위"라 90도를 더해 돌리는데, 가로로 그린 로켓 글러브는 그러면 주먹이 위를 본다. `max_distance`를 주면 그만큼 날아간 뒤 사라진다(글러브 300px — 기획서의 "단거리"를 지키는 선이다). `speed`를 주면 그 속도로 나간다(글러브 700px/s, 없으면 공통 1120px/s). 클라이언트는 속도를 복제받지 않으므로 방향은 **위치 변화**로 잡는다(`_process`). 멈추면 마지막 방향을 유지해 바닥에 꽂힌 모양이 된다. 회전하는 그림이라 여백 보정은 `position`이 아니라 `Sprite2D.offset`으로 넣어야 한다.
- `docs/weapon-system.md` = 무기 추가·수정 방법과 지켜야 할 계약. `docs/무기_수치_초안.md` = 수치가 정해진 근거와 미확정 항목.
- `resources/korean_font.tres` = 한글 폰트 리소스 (SystemFont).
- `resources/ui_theme.tres` = **UI 공통 테마**. `project.godot`의 `gui/theme/custom`으로 프로젝트 전체에 걸려 있어 버튼·라벨·패널·입력칸·진행바의 기본 모양이 여기서 나온다. **색을 바꾸려면 여기를 고친다** — 씬마다 `theme_override`를 넣지 말 것. 젤리 톤 팔레트: 크림 배경 `(0.99, 0.95, 0.92)`, 진한 글자 `(0.29, 0.23, 0.32)`, 보조 글자 `(0.44, 0.39, 0.48)`, 젤리 핑크 `(0.96, 0.55, 0.78)`, 라벤더 `(0.56, 0.59, 0.91)`. 흰 카드 + 큰 둥근 모서리(버튼 18·패널 28) + 부드러운 그림자가 기본형이다.
  - **파스텔 핑크·라벤더는 장식용이고, 흰 글자를 얹는 면에는 진한 쪽을 쓴다**(이슈 #112). 파스텔 위의 흰 글자는 대비가 2.2~2.7:1밖에 안 나와 글자가 배경에 뜬다. 주 동작 버튼·선택된 방 버튼·체력 막대 채움은 **진한 핑크 `(0.8, 0.29, 0.56)`**(hover `(0.86, 0.36, 0.63)`·pressed `(0.68, 0.22, 0.46)`·테두리 `(0.62, 0.17, 0.4)`)와 **진한 라벤더 `(0.42, 0.45, 0.82)`**(hover `(0.48, 0.51, 0.86)`·pressed `(0.34, 0.37, 0.74)`·테두리 `(0.3, 0.33, 0.68)`)를 쓴다 — 이 조합은 4.2:1이다. 파스텔 두 색은 젤리 미리보기·결과 글자처럼 **외곽선이 대비를 대신 받쳐 주는 곳에만** 남겼다.
  - 글자는 **18px이 바닥**이다. 크림·흰 배경 위 본문은 4.5:1, 색 버튼의 큰 글자는 3:1을 넘긴다. 보조 글자를 옅게 하고 싶어도 `(0.44, 0.39, 0.48)`보다 밝히지 않는다.
  - 체력 막대는 트랙 `(0.9, 0.86, 0.9)`에 2px 테두리 `(0.76, 0.7, 0.78)`가 있다. 흰 카드 위에 트랙만 얹으면 막대가 **어디서 끝나는지** 안 보여서 남은 비율을 읽을 수 없다.
  - 예외적으로 씬에 남긴 `theme_override`는 **화면마다 하나뿐인 주 동작 버튼**(타이틀 `StartButton`·대기실 `GoButton`은 핑크, `RandomButton`은 라벤더)과 글자 크기·색 같은 개별 값이다. 새 버튼은 기본 흰 카드 모양을 그대로 쓰는 것이 원칙이다.

### 조작 (project.godot `[input]`)

기기당 1명이므로 **액션은 `move_left`·`move_right`·`jump`·`fast_fall`·`skill` 5개뿐**이며, 각 액션에 두 벌이 함께 바인딩되어 있어 어느 쪽을 눌러도 동작한다(이동·점프·낙하는 WASD와 방향키, `skill`은 Shift와 Space). 전투 중 ESC(`ui_cancel`)로 접속 종료.
**기본 공격에는 입력이 없다** — 근접은 닿으면, 원거리는 간격마다 서버가 자동으로 판정한다. `skill`은 특수 공격 전용이다. 옛 `p1_/p2_` 8개 액션은 온라인 전환(#33)으로 제거되었다.

### 미구현 (로드맵 #32 기준)

기획서의 냉장고·봉지 속·위 속 맵 — 이슈 #62에서 바다·용암·벽돌로 교체했다. 필요하면 `Maps.LIST`에 되살린다.
맵 고유 기믹(움직이는 발판 등)과 배경 애니메이션(물결·용암 흐름)은 없다.
라운드마다 무기를 다시 고르는 방식(기획서)은 아직 없다 — 한 번 고른 무기로 경기가 끝날 때까지 싸운다.
**경기 도중 난입 관전은 없다**(이슈 #167 non-goal) — 경기 중에 들어온 관전자는 대기실에서 다음 경기를 기다린다. 하려면 `player.tscn`에 가시성용 `MultiplayerSynchronizer`를 붙여 늦게 들어온 피어에게도 스폰이 전달되게 해야 한다(투사체는 이미 그 방식이다). 관전자 전용 카메라·자유 시점·리플레이·채팅도 없다.
무기별로 남은 것(표창의 파란 표창, 삼지창 회수 연출, 미확정 수치)은 `docs/weapon-system.md`의 "아직 안 된 것"에 정리되어 있다.
지연 보상(prediction·rollback)은 로드맵 Non-goal이라 입력 지연이 왕복 시간만큼 발생한다.

무기·전투(4단계)는 #46에서 공동작업자(@Kadsa-MXZI)의 `feat/online-multiplayer-and-weapons` 브랜치에서 이식했다. 그 브랜치에는 독자적인 네트워크·대기실 구현(`net.gd`, 자체 `lobby.gd`, `server/` 도커)도 들어 있지만 **가져오지 않았다** — 이쪽 `main`의 서버 권위 구조를 유지한다.

### 개발 시 주의

- **Godot 바이너리가 있다** — `~/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe`. **커밋 전에 반드시 돌린다:**

  ```
  timeout 20s "<godot>" --headless --path . 2>&1 | grep -E "SCRIPT ERROR|\.gd:|Parse Error|Compile Error"
  ```

  헤드리스로 뜨면 서버가 시작되어 계속 떠 있으므로 `timeout`으로 끊는다. 끊을 때 나오는
  `BUG: Unreferenced static string ...`은 엔진 종료 잡음이니 무시하고, 위 필터에 걸리는 것만 본다.
  경로·상수 대조 같은 정적 확인만으로는 **타입 추론 실패·타입 불일치가 잡히지 않는다**(이슈 #66·#69에서 두 번 놓쳤다).
  `--check-only --script`는 오토로드를 안 올려서 `Lobby` 같은 식별자를 못 찾는다고 헛짚으니 쓰지 말 것.
- 그래도 **화면으로 봐야 아는 것**(색·배치·발판 높이·조작감)은 사용자 F5 확인이 필요하다. 헤드리스 실행은 오류 유무만 알려준다.
- `_ready()`에서 `change_scene_to_file()`을 바로 부르면 "Parent node is busy" 오류가 난다 — `call_deferred`로 미룬다.
- 배포본(export)이 아직 없고 `export_presets.cfg`도 없다. 유저 실행용 빌드는 별도 이슈로 진행 예정.
- `README.md`는 프로젝트와 무관한 외부 유저가 보는 문서다 — 폴더 구조, 확장 가이드, 엔진 실행·검증 방법을 넣지 않는다(이슈 #4·#8·#11). 개발자용 정보는 이 파일과 `docs/`에 둔다. 현재 README에는 리셋과 함께 폴더 구조·실행 방법이 다시 들어가 있어 정리가 필요하다.
- **표(`Weapons.LIST`·`Characters.LIST`·`Maps.LIST`)에서 꺼낸 값은 `Variant`다.** `var path := DIR + dict.get("file", "")`처럼 `:=`로 받으면 타입 추론이 실패해 **스크립트가 파싱되지 않고 게임이 아예 뜨지 않는다**(이슈 #66). 반드시 `var file: String = ...`처럼 명시 타입으로 받는다. 정적 검증이 잡아내지 못하는 종류라 표를 다루는 코드를 쓸 때마다 확인한다.
- .gd 스크립트를 새로 만들면 사용자 에디터가 .uid 파일을 생성한다 — 발견 시 해당 이슈 브랜치에 커밋한다.
- .tscn의 `load_steps`는 Godot 4.6이 더 이상 기록하지 않는다 — 이미 있는 파일에서는 값을 유지하고(= ext_resource 수 + sub_resource 수 + 1), 없는 파일에 손으로 추가하지 않는다.
- **사용자가 에디터에서 씬을 만지면 파일이 정규화된다** — `load_steps`가 빠지고, 노드에 `layout_mode`·`anchors_preset`·`unique_id`가 붙고, 손으로 적어 둔 자리표시 UID(`uid://jellyselect01` 같은 것)가 진짜 UID로 교체된다. 실제 변경은 몇 줄인데 diff가 크게 보이니 놀라지 말 것. 이때 **참조 쪽만 새 UID로 바뀌고 선언 쪽은 옛 UID로 남아 어긋날 수 있다**(#72에서 `player_panel.tscn`이 그랬다) — 씬을 커밋하기 전에 선언과 참조를 대조한다. 아직 자리표시 UID인 씬(`main`·`player`·`title`·`projectile`)도 열어 저장하는 순간 같은 일이 일어난다.
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
- **`main` 대상 PR도 같은 조건이면 자동으로 머지합니다**(이슈 #115). mergeable/CLEAN이고 변경 파일이 이슈 범위와 일치하고 아래 중단 조건에 걸리지 않으면 `dev` 머지 후 이어서 머지합니다. 사람 리뷰를 기다리며 멈추지 않습니다 — 팀원 대부분이 코드를 읽지 못해 리뷰가 검증 역할을 하지 못하고, 리뷰 요청만 쌓인 채 `main` 반영이 막혔습니다.
- 브랜치 보호 설정을 admin 권한으로 우회하지 않습니다(`gh pr merge --admin` 금지). 지금은 `main`·`dev` 모두 보호가 걸려 있지 않지만, 나중에 켜면 이 금지가 그대로 적용됩니다.
- `main` 머지가 끝난 뒤 원격 이슈 브랜치를 삭제합니다.
- 정리 후 로컬 저장소는 삭제된 이슈 브랜치가 아니라 `main` 또는 `dev`에 둡니다.
- 팀 협업 규칙과 브랜치 보호 설정은 `docs/collaboration.md`를 따릅니다.

자동 머지를 멈추고 사용자에게 보고하는 예외. **`dev`와 `main` 양쪽에 적용됩니다:**

- 코드 충돌이 있거나 mergeable/CLEAN이 아닌 경우
- 이슈 범위 밖의 파일 변경이 섞인 경우
- 검증이 누락되었거나 미완인 경우(예: 자격증명·바이너리 부족으로 실행 확인 불가)
- 사용자가 "머지하지 말라"고 지시한 경우
- 되돌리기 어려운 부수효과가 있는 경우(데이터 마이그레이션, 배포 트리거 등)

`main`에만 걸리던 예외("화면으로만 판단되는 변경은 `dev`까지만 머지하고 멈춘다", 이슈 #115)는 **없앴습니다**(이슈 #142). UI 색·배치·글자 크기, 맵 지형 높이, 조작감처럼 눈으로 봐야 아는 변경도 위 조건만 맞으면 `main`까지 이어서 머지합니다. **공동작업자 리뷰를 기다리지 않는 것과 같은 이유입니다** — 화면 확인은 사용자가 하는 것이고, 그것 때문에 머지를 붙들고 있을 이유가 없습니다.

- 그 예외에 걸리는 것이 UI·연출·맵 작업 **대부분**이라, 자동 머지를 열어 둔 것이 실질적으로는 열리지 않은 것과 같았습니다. 확인을 기다리는 동안 `main` 반영이 계속 밀렸습니다.
- **F5로 무엇을 봐 달라는 보고는 그대로 합니다.** 머지를 멈추지 않을 뿐 확인 요청을 없애는 것이 아닙니다. 헤드리스 실행은 여전히 **오류 유무만** 알려주므로, PR 본문과 사용자 보고에 무엇을 눈으로 봐야 하는지 구체적으로 적습니다.
- 화면이 잘못 나온 것을 나중에 알게 되면 되돌리지 말고 **새 이슈로 고칩니다.** 그리기만 바뀐 변경은 고치는 쪽이 되돌리는 쪽보다 싸고 이력도 깔끔합니다.
