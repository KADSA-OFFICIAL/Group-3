# Group-3 Codex Harness

이 저장소는 issue-first workflow를 사용합니다. Codex는 새 기능, 버그 수정, 개선, 리팩터링, 동작 변경을 시작하기 전에 이 하네스를 따라야 합니다.

## 게임 정보 (젤리 워즈)

한 기기 한 화면 **1 VS 1 로컬 대전** 액션, **Godot 4.6 (GL Compatibility)**. 3조(스틱매너) 개발기획서 기반. `project.godot`의 `config/name`은 "Jelly Wars", 메인 씬은 `scenes/title.tscn`.
기획 핵심 루프(무기 선택 → 맵 → 전투 → 3점 선취 승리)가 **전부 돈다.**

**2026-09-10에 온라인 구조를 걷어내고 오프라인 한 화면 2인으로 되돌렸다**(이슈 #320). 없어진 것: `Network`·`Lobby` 오토로드, 접속 화면·방·포트, 관전 역할과 관전 빌드, `@rpc`·`MultiplayerSpawner`·`MultiplayerSynchronizer`, `run-server.bat`·`docs/server.md`. 한 프로세스가 젤리 둘을 다 굴리고, 판정 코드(`main.gd`)는 그대로 남았으며 복제만 사라졌다. **되살리지 말 것** — 필요해지면 이 이슈 이전 이력에서 꺼낸다.

**젤리마다 키가 따로 있다** — 1P는 `WASD`+왼쪽 `Shift`, 2P는 방향키+`Space`(액션 이름은 `p1_left`·`p2_left` …). 플레이어 번호는 1과 2이고 자리는 0·1이며 변환은 `GameState.id_at()`·`slot_of()`가 한다.

`main` 브랜치는 2026-07-26에 새 구현(커밋 `e2a7dcb`)으로 교체되었다. 이전 구현(`autoload/game_manager.gd`, `scripts/weapons/`, `scenes/maps/` 등)은 `backup/main-before-reset` 브랜치에만 있고 현재 코드베이스에는 없다 — 그 경로를 참조하지 말 것.


title(`StartButton`으로 시작) → select(1P·2P가 각자 캐릭터를 고르고 `시작!`) → main(전투, 라운드마다 무기 카드가 1P → 2P 차례로 뜬다) → 3점 선취 시 select로 복귀. 전투 중 ESC로 title 복귀.

### 구조 요약

- `scripts/game_state.gd` = 오토로드 싱글턴 `GameState`: 화면 간 선택 정보 전달. `CHARACTERS`(`Characters.names()` 5종 — 사본을 두지 않고 캐릭터 표에서 만든다), `WEAPONS`("랜덤" + `Weapons.names()` 17종 — 마찬가지), `MAPS`("랜덤" + `Maps.names()` 4종 — 마찬가지), `p1_config`/`p2_config`(weapon·character), `map_name`, `get_config(prefix)`.
- `scenes/title.tscn` + `scripts/title.gd` = 타이틀 화면. **화면 전체가 표지 원화다**(요청) — `Cover`(TextureRect)가 `assets/ui/cover.png`를 바닥에 맞춰 덮고, 원화에 로고와 젤리가 이미 있으므로 `TitleLabel`·`JellyLeft`·`JellyRight`를 없앴다. 남은 조작은 로고를 피해 네 귀퉁이로 갔고(`StartButton`은 원화에 그려진 띠 자리), 글자는 흰색 + 진한 테두리다. `cover.png`는 경기 표지(`match_intro.tscn`)와 같이 쓴다.
- `scenes/select.tscn` + `scripts/select.gd` = 캐릭터 선택 창(두 패널 다 조작할 수 있다). `P1Panel`/`P2Panel`은 흰 카드(`Card`) 위에 얹히며 자리마다 하나씩이고 **둘 다 조작할 수 있다**(이슈 #320). `StatusLabel`에는 조작 안내를 적고, `GoButton`(`시작!`)을 누르면 곧바로 main 으로 넘어간다. **가운데 칸이 아예 없다**(요청) — 화면은 `1P 패널 | StatusLabel + GoButton | 2P 패널` 세 칸이다. 꾸밈은 `Decor`(`scripts/select_decor.gd`)가 통째로 `_draw()`로 그린다(왼쪽 분홍·오른쪽 남색 그라데이션, 가운데 번개, 별·젤리 조각, 꽃밭, `VS`, `캐릭터 선택` 리본 — 자리는 `SEED`로 고정). 카드는 편마다 색이 다르고(`player_panel.gd`의 `accent`) `_apply_accent()`가 카드·버튼·별 배지를 거기서 만든다 — **스타일박스는 반드시 `duplicate()`** 해야 한다(씬의 `SubResource`는 인스턴스끼리 같은 객체를 나눠 써서, 복제하지 않으면 1P를 칠할 때 2P까지 바뀐다). 맵도 무기도 라운드가 시작될 때 전투 화면에서 정해지므로 여기서 고를 것이 없어 안내판 둘(`MapBox`·`WeaponBox`)을 치우고 그 자리에 `StatusLabel`·`GoButton`을 올렸다. 되살리지 말 것.
- `scenes/player_panel.tscn` + `scripts/player_panel.gd` = 플레이어 1인 패널(양쪽 재사용). `mirrored`가 true면 아이콘 열을 오른쪽으로 옮긴다. 무기/캐릭터 버튼은 각각 목록을 순환하고, `RandomButton`은 전부 랜덤. 사용자 조작으로 값이 바뀌면 `config_changed`를 내보낸다. `apply_config()` 는 들고 있던 값을 표시만 한다(이때는 시그널을 내보내지 않는다).
- `scripts/weapon_preview.gd` = 라운드 시작 무기 선택 카드(`weapon_pick.tscn`)의 무기 그림 미리보기. 대기실에는 무기 칸이 없다. `jelly_preview.gd`와 같은 형태이고 `Art.content_rect()`로 여백을 뺀다. 그림이 있는 무기가 7종뿐이라 **없으면 아무것도 그리지 않고** 옆의 이름 라벨이 대신한다. 무기 원화는 세로로 긴 것(검 1:4.7)과 가로로 긴 것(전기톱·대포 총)이 섞여 있어 칸은 세로로 잡았다.
- `scripts/jelly_preview.gd` = 젤리곰 미리보기. `character_id` setter가 `Characters.texture()`로 그림을 받아 `queue_redraw()`를 호출하고, `_draw()`가 비율을 지켜 가운데에 그린다.
- `scripts/characters.gd`(`class_name Characters`) = **캐릭터 표 5종**(분홍·파랑·초록·노랑·빨강). 이름과 그림 경로의 유일한 출처이며 선택 창 선택지·선택값 정리·전투 화면 그림이 모두 여기서 나온다. 그림은 `assets/characters/`에 있고, 파일이 없으면 표의 몸통 색 단색으로 대신 그린다. 여백 측정은 `Art.content_rect()`가 한다.
- `scenes/main.tscn` + `scripts/main.gd` = 전투 화면이자 **공격 판정의 주인**. 지형은 씬에 없고 라운드가 열릴 때마다 `_pick_round_map()` 이 뽑아 `_load_map()` 이 `MapRoot` 아래에 붙인다(모든 피어에서, 스폰보다 먼저). 화면 글자는 전부 `UI/HUD` 아래 흰 카드 안에 있다 — 맨 위 가운데 `ScoreCard`(`P1Score`·`Divider`·`P2Score`, 라운드 포인트를 좌우 대칭으로, 1P 핑크·2P 라벤더)와 **화면 좌우 맨 위에는 아무것도 없다**(이슈 #317) — 체력은 맞은 순간 젤리 머리 위에 2초 뜨는 `scripts/health_bar.gd`가 내고, 이름·무기 카드(`P1Card`·`P2Card`)는 없앴다(이름은 젤리 머리 위 `NameLabel`, 무기는 손에 든 그림이 낸다). ESC로 접속 종료.
  - **UI는 `UI`(CanvasLayer) 아래에 둔다**(이슈 #82). 씬 루트가 `Node2D`라 Control을 거기에 바로 붙이면 앵커가 기준으로 삼을 부모 사각형이 0×0이 되어 `HUD`의 크기도 0이 된다 — 그러면 `anchor_left = 0.5`로 가운데를 잡은 것들이 전부 화면 왼쪽 끝(x=0)에 그려지고 화면을 덮는 판도 안 보인다. CanvasLayer 아래에서는 뷰포트 크기가 기준이 된다. 앵커를 쓰는 UI를 새로 넣을 때는 반드시 이 아래에 붙인다.
  - **글자는 맵 배경 위에 그냥 얹지 않고 흰 카드 안에 넣는다**(이슈 #112). 맵마다 배경 밝기가 정반대라서(평지 하늘 `(0.82, 0.93, 0.99)` ↔ 용암 `(0.42, 0.26, 0.38)`) 한 맵에 맞춘 글자색은 다른 맵에서 사라진다 — 진한 글자를 용암 배경에 얹으면 대비가 1.3:1이다. 카드를 깔면 배경이 무엇이든 10:1이 나오므로, 맵 위에 글자를 새로 얹을 일이 생기면 카드부터 만든다. 카드는 하늘 영역(y ≲ 190)에 둔다 — 점프 정점이 y≈340이라 지형·젤리와 겹치지 않는다.
  - 체력 숫자는 막대 **안**(`show_percentage`)이 아니라 카드 위 별도 라벨에 적는다. 막대 안에 그리면 채운 쪽과 빈 쪽의 밝기가 반대라 어느 색을 골라도 한쪽에서 묻힌다.
  - **플레이어는 씬에 배치되어 있지 않고 `_spawn_players()` 가 씬이 열릴 때 세운다**(이슈 #320) — `PlayerSpawner`(MultiplayerSpawner, `spawn_path = ../Players`)와 `Players` 노드가 담당. `PLAYER_SCENE.instantiate()` 로 만들어 `Players` 아래에 붙인다. 노드 이름은 `Player_1`·`Player_2` 다.
  - `_physics_process()`가 `multiplayer.is_server()` 하나로 전투 틱 전체를 감싼다: `_check_basic_attacks()`(근접 접촉·원거리 자동 발사) → `_check_pending_specials()`(강제 이동 중 명중) → `_tick_bleeds()`(출혈) → `_tick_bursts()`(소총 연사) → `_check_falls()`(낙사) → `_tick_round()`(예약된 라운드 재시작·대기실 복귀). 특수 공격은 `Player.special_requested` 신호를 받아 `_execute_special()`에서 무기별로 분기한다.
  - **포인트 진행도 여기가 주인이다.** `_on_player_died()`가 상대에게 1포인트를 주고, `Combat.POINTS_TO_WIN`(3포인트)에 닿으면 승리를 표시한 뒤 `_return_to_select()` 로 선택 창으로 돌아간다. 아니면 `ROUND_RESTART_DELAY`(2초) 뒤 `_start_round()`가 투사체·판정 타이머를 비우고 `Player.server_reset()`으로 양쪽을 되살린다. 점수(`scores`)와 안내 문구(`banner`)는 `main.gd` 가 정하고 `_update_round()` 가 HUD에 적는다.
  - **화면 문구는 "라운드 승패"가 아니라 "포인트 획득"으로 쓴다**(이슈 #76) — 배너는 `1P +1 포인트`, 마지막에 `1P 승리!  3포인트 달성`, HUD 점수는 `_score_text()`가 `●○○  1 / 3`처럼 동그라미와 숫자를 같이 낸다. 규칙은 그대로이고 표현만 통일한 것이다.
  - **판은 `3 · 2 · 1 · START!` 를 세고 열린다**(요청) — `scenes/countdown.tscn` + `scripts/countdown.gd`. 무기를 고른 직후에 뜨고 그 동안 두 젤리는 자기 자리에 선 채로 얼어 있다. 한 칸 `Combat.COUNTDOWN_STEP`(0.42초) × 4 = `COUNTDOWN_TIME`(1.68초)이고 판마다 끼므로 빠른 쪽으로 잡았다. **얼음을 푸는 것은 카운트다운 화면이 아니다** — `_round_opens_at` 예약을 `_tick_round()`가 처리하고 `_open_round()`가 `server_reset()`을 한 번 더 불러 무적(`ROUND_START_GRACE`)을 새로 준다(세는 데 쓴 1.68초가 무적에서 먼저 흘러가 버리기 때문이다). 판이 접히면 이 예약을 버린다. 뒤에 막은 깔지 않고 글자를 크게·테두리를 굵게 해서 읽히게 한다.
  - **포인트가 오를 때는 전용 장면이 뜬다**(이슈 #273) — `scenes/point_gain.tscn` + `scripts/point_gain.gd`. 띠가 왼쪽에서 쓸려 들어와 딴 사람의 젤리 얼굴·이름·포인트 칸 3개를 보여주고, 이번에 딴 칸에 흰 빛이 터지며 금색으로 채워진다. **띠 색은 보는 사람 기준이다** — 내가 땄으면 파랑, 상대가 땄으면 빨강. 띠 색은 한 화면이라 늘 딴 사람 기준(파랑)이다 (이슈 #320). 장면 길이는 `Combat.POINT_GAIN_TIME`(2.6초) 하나이고 `ROUND_RESTART_DELAY`(2.8초)는 그보다 길어야 한다. 마지막 포인트에서는 결과 화면을 `_result_at`으로 장면 뒤로 미룬다 — 겹치면 축하 장면 위에 승패 글자가 덮인다.
  - **경기가 끝나면 이긴 쪽 기준으로 결과 화면을 한 번 띄운다**(이슈 #79·#320) — `_show_match_result(winner_id)` 가 `HUD/ResultOverlay` 에 승리 연출을 만들고 글자를 `1P 승리!` 로 바꾼다. 진 쪽 화면이 따로 없으므로 패배 연출은 지웠다.
- `scenes/player.tscn` + `scripts/player.gd`(CharacterBody2D, `class_name Player`): 젤리 하나. `owner_peer_id`·`player_name`·`character_id`·`weapon_id` export. SPEED 320, JUMP_VELOCITY -560, FAST_FALL_MULTIPLIER 2.0, INTERPOLATION_SPEED 20.
  - 전투 상태(`hp`·`alive`·`facing`·무적·기절·게이지·버프·강제 이동)는 **`main.gd` 의 판정이 정하고** 공개 함수(`apply_hit`·`set_frozen`·`reset_round` …)가 그 결과를 적는다. 입력은 `read_input()` 이 `GameState.action(player_id, ...)` 이름으로 자기 자리 키만 읽는다.
  - 방패의 짧게/길게는 `_check_long_press()` 가 잰다(`_check_long_press()`) — 길게가 확정되는 순간 바로 발동한다.
  - 몸은 `Body`(Sprite2D)에 캐릭터 그림을 붙인다. 원화가 정사각 캔버스에 여백을 두고 그려져 있어 `Characters.content_rect()`로 **투명 여백을 뺀 실제 그림 영역**을 재고, 그 높이를 `BODY_HEIGHT`(72px)에 맞춰 배율과 위치를 정해 발을 충돌 상자 바닥에 붙인다. 찌그러짐은 그 기본 배율에 곱하고, 좌우 반전은 `facing`으로 `flip_h`를 켜며 이때 여백 보정(`_body_offset_x`)의 부호도 뒤집는다.
  - 젤리 찌그러짐은 속도·접지값에서 바로 나온다.
  - 무기는 그림이 있으면 `WeaponSprite`에 세워서 바라보는 쪽에 놓고(`WEAPON_HEIGHT` 56px), 쿨타임 상태는 밝기로 나타낸다. 그림이 없는 10종은 여전히 `WeaponShape` 임시 막대이며 길이가 사거리·색이 쿨타임 상태다. 어느 쪽을 쓸지는 `_apply_weapon()`이 정한다.
- `scripts/weapons.gd`(`class_name Weapons`) = **무기 표 17종**. 이름·기본/특수 데미지·쿨타임·넉백 등 모든 무기 수치의 유일한 출처. `RANDOM` 상수와 `resolve()`(랜덤 확정)도 여기 있다. 그림이 있는 7종은 `file` 필드를 갖고 `texture()`가 `assets/weapons/`에서 꺼내 온다 — 없으면 null이고 부르는 쪽이 막대로 대신한다.
- `scripts/maps.gd`(`class_name Maps`) = **맵 표 4종**(평지·바다·용암·벽돌). 이름과 씬 경로의 유일한 출처. `RANDOM` 상수와 `resolve()`(랜덤 확정)가 무기 표와 같은 형태다. **맵 씬 계약**: 루트 `Node2D`, `Spawns/Spawn1`·`Spawn2`(Marker2D, 순서가 1P·2P), 지형은 `StaticBody2D` + `CollisionShape2D`, 즉사 구역은 `Hazard`(Area2D), 배경도 맵이 그린다. 좌우 벽이 없는 맵은 화면 밖으로 나가면 낙사한다.
  - 바다·용암에는 `Hazard`가 있어 닿으면 즉사한다. 평지·벽돌은 좌우 벽이 있고 `Hazard`도 없어 낙사가 일어나지 않는다.
- `scripts/art.gd`(`class_name Art`) = 그림 공통 처리. `content_rect()`가 **투명 여백을 뺀 실제 그림 영역**을 잰다. 캐릭터·무기 원화가 모두 정사각 캔버스에 여백을 두고 그려져 있어 크기와 위치를 잡을 때 항상 이 값을 기준으로 한다.
- `scripts/combat.gd`(`class_name Combat`) = 전투 공통 수치. MAX_HP 100, INVULNERABLE_TIME 0.1, MELEE_HIT_INTERVAL 0.6, ROUND_START_GRACE 2.0, POINTS_TO_WIN 3, ROUND_RESTART_DELAY 2.0, MATCH_END_DELAY 4.0, 넉백 3단계(200/400/700), PROJECTILE_SPEED 1120, 낙사 경계 `is_out_of_bounds()`.
- `scenes/projectile.tscn` + `scripts/projectile.gd`(Area2D, `class_name Projectile`) = 허공을 나는 것(화살·총알·표창·던진 단검·폭탄). 이동도 판정도 스스로 하고, 만들고 없애는 것은 `main.gd` 다. 상대 무기에 막히지 않고 공유 무적도 타지 않는다.
- `docs/weapon-system.md` = 무기 추가·수정 방법과 지켜야 할 계약. `docs/무기_수치_초안.md` = 수치가 정해진 근거와 미확정 항목.
- `assets/fonts/BlackHanSans-Regular.ttf` = 화면 글꼴(요청, Google Fonts·SIL OFL 1.1). `resources/display_font.tres`(FontVariation)가 이것을 감싸고 테마가 그것을 가리킨다 — `fallbacks`에 `korean_font.tres`를 물려 둔 것이 핵심이다(이 글꼴에는 이모지가 없어서 폴백이 없으면 `랜덤 🎲`의 주사위가 네모로 나온다).
- `resources/korean_font.tres` = 한글 계통 폰트 리소스 (SystemFont). 이제 폴백으로만 쓰인다.
- `resources/ui_theme.tres` = **UI 공통 테마**. `project.godot`의 `gui/theme/custom`으로 프로젝트 전체에 걸려 있어 버튼·라벨·패널·입력칸·진행바의 기본 모양이 여기서 나온다. **색을 바꾸려면 여기를 고친다** — 씬마다 `theme_override`를 넣지 말 것. 젤리 톤 팔레트: 크림 배경 `(0.99, 0.95, 0.92)`, 진한 글자 `(0.29, 0.23, 0.32)`, 보조 글자 `(0.44, 0.39, 0.48)`, 젤리 핑크 `(0.96, 0.55, 0.78)`, 라벤더 `(0.56, 0.59, 0.91)`. 흰 카드 + 큰 둥근 모서리(버튼 18·패널 28) + 부드러운 그림자가 기본형이다.
  - **파스텔 핑크·라벤더는 장식용이고, 흰 글자를 얹는 면에는 진한 쪽을 쓴다**(이슈 #112). 파스텔 위의 흰 글자는 대비가 2.2~2.7:1밖에 안 나와 글자가 배경에 뜬다. 주 동작 버튼·선택된 방 버튼·체력 막대 채움은 **진한 핑크 `(0.8, 0.29, 0.56)`**(hover `(0.86, 0.36, 0.63)`·pressed `(0.68, 0.22, 0.46)`·테두리 `(0.62, 0.17, 0.4)`)와 **진한 라벤더 `(0.42, 0.45, 0.82)`**(hover `(0.48, 0.51, 0.86)`·pressed `(0.34, 0.37, 0.74)`·테두리 `(0.3, 0.33, 0.68)`)를 쓴다 — 이 조합은 4.2:1이다. 파스텔 두 색은 젤리 미리보기·결과 글자처럼 **외곽선이 대비를 대신 받쳐 주는 곳에만** 남겼다.
  - 글자는 **18px이 바닥**이다. 크림·흰 배경 위 본문은 4.5:1, 색 버튼의 큰 글자는 3:1을 넘긴다. 보조 글자를 옅게 하고 싶어도 `(0.44, 0.39, 0.48)`보다 밝히지 않는다.
  - 체력 막대는 트랙 `(0.9, 0.86, 0.9)`에 2px 테두리 `(0.76, 0.7, 0.78)`가 있다. 흰 카드 위에 트랙만 얹으면 막대가 **어디서 끝나는지** 안 보여서 남은 비율을 읽을 수 없다.
  - 예외적으로 씬에 남긴 `theme_override`는 **화면마다 하나뿐인 주 동작 버튼**(타이틀 `StartButton`·대기실 `GoButton`은 핑크, `RandomButton`은 라벤더)과 글자 크기·색 같은 개별 값이다. 새 버튼은 기본 흰 카드 모양을 그대로 쓰는 것이 원칙이다.


**자리마다 한 벌씩, 액션이 모두 10개다**(이슈 #320): `p1_left`·`p1_right`·`p1_jump`·`p1_fast_fall`·`p1_skill`, `p2_…`. 1P는 `A`/`D`·`W`·`S`·왼쪽 `Shift`, 2P는 `←`/`→`·`↑`·`↓`·`Space`다. 읽는 곳은 `Player.read_input()` 하나이고 이름은 `GameState.action(player_id, name)` 이 만든다. 전투 중 ESC(`ui_cancel`)로 title 복귀.
**기본 공격에는 입력이 없다** — 근접은 닿으면, 원거리는 간격마다 `main.gd` 가 자동으로 판정한다.

### 미구현 (로드맵 #32 기준)

기획서의 냉장고·봉지 속·위 속 맵 — 이슈 #62에서 바다·용암·벽돌로 교체했다. 필요하면 `Maps.LIST`에 되살린다.
맵 고유 기믹(움직이는 발판 등)과 배경 애니메이션(물결·용암 흐름)은 없다.
라운드마다 무기를 다시 고르는 방식(기획서)은 아직 없다 — 한 번 고른 무기로 경기가 끝날 때까지 싸운다.
무기별로 남은 것(표창의 파란 표창, 삼지창 회수 연출, 미확정 수치)은 `docs/weapon-system.md`의 "아직 안 된 것"에 정리되어 있다.
지연 보상(prediction·rollback)은 로드맵 Non-goal이라 입력 지연이 왕복 시간만큼 발생한다.

무기·전투(4단계)는 #46에서 공동작업자(@Kadsa-MXZI)의 `feat/online-multiplayer-and-weapons` 브랜치에서 이식했다. 그 브랜치에는 독자적인 네트워크·대기실 구현(`net.gd`, 자체 `lobby.gd`, `server/` 도커)도 들어 있지만 **가져오지 않았다.**

### 개발 시 주의

- **Godot 바이너리가 있다** — `~/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe`. **커밋 전에 반드시 돌린다:**

  ```
  timeout 20s "<godot>" --headless --path . 2>&1 | grep -E "SCRIPT ERROR|\.gd:|Parse Error|Compile Error"
  ```

  헤드리스로도 게임이 그대로 도므로 `timeout`으로 끊는다. 끊을 때 나오는
  `BUG: Unreferenced static string ...`은 엔진 종료 잡음이니 무시하고, 위 필터에 걸리는 것만 본다.
  경로·상수 대조 같은 정적 확인만으로는 **타입 추론 실패·타입 불일치가 잡히지 않는다**(이슈 #66·#69에서 두 번 놓쳤다).
  `--check-only --script`는 오토로드를 안 올려서 `GameState` 같은 식별자를 못 찾는다고 헛짚으니 쓰지 말 것.
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
