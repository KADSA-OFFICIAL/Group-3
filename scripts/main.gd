extends Node2D
## 전투 화면. **한 화면에서 1P와 2P가 같이 싸운다** (#320).
##
## 씬이 열리면 젤리 둘을 바로 세우고(`_spawn_players`), 공격 판정을 여기 한 곳에서
## 실행한다 — 예전에는 전용 서버가 판정하고 결과를 두 기기에 나눠 주었는데, 한 화면에서는
## 판정하는 곳과 그리는 곳이 같다.
##
## 무기 수치는 scripts/weapons.gd, 공통 수치는 scripts/combat.gd에 있다.
## 플레이어의 체력·상태이상은 Player의 공개 함수(`apply_hit`·`set_frozen` …)로 전달한다.
## 통합 가이드: docs/weapon-system.md
##
## 포인트 진행(쓰러뜨리면 1포인트·3포인트 선취)도 여기가 주인이다.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const LIGHT_BURST_SCENE := preload("res://scenes/light_burst.tscn")
const SWAP_BURST_SCENE := preload("res://scenes/swap_burst.tscn")
const LIGHTNING_STRIKE_SCENE := preload("res://scenes/lightning_strike.tscn")
const SHOTGUN_BLAST_SCENE := preload("res://scenes/shotgun_blast.tscn")
const SHOCKWAVE_SCENE := preload("res://scenes/shockwave.tscn")
const HIT_SPARKS_SCENE := preload("res://scenes/hit_sparks.tscn")
const HEAVY_PUNCH_SCENE := preload("res://scenes/heavy_punch.tscn")
const CANNON_BURST_SCENE := preload("res://scenes/cannon_burst.tscn")
const BOMB_BLAST_SCENE := preload("res://scenes/bomb_blast.tscn")

## 위치 교환 연출을 띄울 높이 보정. 젤리의 `global_position`은 충돌 상자(48x56)의
## 가운데이고 몸(72px)은 발밑이 +`Player.BODY_BOTTOM`(28)이라, 몸 한가운데가 -8이다.
## 검 특수의 빛기둥은 반대로 발밑(+28)에 띄운다 — 거기서 위로 솟는 연출이라서다.
const SWAP_BURST_CENTER := Vector2(0.0, -8.0)
## 맵에 Spawns가 없을 때만 쓰는 대비값. 정상 경로에서는 맵 씬이 위치를 들고 있다.
const SPAWN_POSITIONS := [Vector2(300, 500), Vector2(852, 500)]

## 강펀치 부채꼴이 시작되는 자리 — 몸 중심에서 바라보는 쪽으로 이만큼 (#225).
## 젤리가 무기를 드는 자리(`Player.WEAPON_OFFSET_X` 26)와 같은 쪽이라 주먹에서 터진다.
const PUNCH_ORIGIN_X := 24.0

## 근접 "닿으면" 판정 거리. 젤리 몸통이 48px이므로 두 몸통이 맞닿는 거리다.
## 무기별 사거리는 player.current_reach()로 더한다.
const MELEE_REACH := 48.0

## 라운드마다 제시할 무기 후보 수 (#205). `weapon_pick.tscn`의 카드 수와 같아야 한다 —
## 카드가 모자라면 뽑아 놓고 못 보여주고, 남으면 빈 카드가 나온다.
const WEAPON_CHOICES := 3
## 무기 선택 제한 시간(초). 다 되면 후보 중 하나를 대신 뽑는다 (`_auto_pick`) —
## 한 사람이 자리를 비웠다고 경기가 그 자리에서 영영 멈추면 안 된다.
const WEAPON_PICK_TIME := 20.0

## 경기 표지 그림이 떠 있는 시간(초). **`match_intro.gd`의 `TOTAL`과 같아야 한다** —
## 그쪽은 이 시간에 맞춰 커졌다 사라지고, 여기서는 이만큼 무기 선택을 미룬다.
## 어긋나면 그림이 덜 사라진 채로 카드가 뜨거나(이 값이 짧을 때) 빈 화면을 본다(길 때).
const MATCH_INTRO_TIME := 2.0

## 아래 상태는 전부 전투 판정이 쓴다.
## "공격자>피격자" -> 다음 기본 공격이 들어갈 수 있는 시각
var _next_hit_at := {}
## 플레이어 번호 -> 특수 공격 쿨타임이 끝나는 시각
var _special_ready_at := {}
## 강제 이동 중에 한 번만 터지는 특수 공격 (전기톱 돌진, 양날 도끼 낙하).
var _special_pending := {}
## 범위를 보여 주고 기다리는 중인 강펀치 (#231). 플레이어 번호 -> 누른 순간에 굳힌 값.
## **자리·방향·데미지가 다 여기 들어 있다** — 기다리는 동안 쓰는 쪽이 움직여도
## 주먹은 보여 준 자리에 들어간다. 예고한 범위와 맞는 범위가 달라지면 예고가 거짓말이 된다.
var _punch_pending := {}
## 내려베는 중인 검 특수 (#247). 플레이어 번호 -> 굳힌 값과 검이 다 내려오는 시각.
## **강펀치와 달리 자리를 굳히지 않는다** — 빛기둥은 맞는 순간의 상대 발밑에 서고
## 체력 비례 데미지도 그때의 체력에 걸리므로, 미리 재 둘 것이 없다.
var _sword_swings := {}
## 출혈. 무적 시간을 무시하고 1초마다 들어간다.
var _bleeds := {}
## 소총 연사. 한 번 누르면 지속시간 동안 자동으로 나간다.
var _bursts := {}
## 진행 중인 땅 격파 (양날 도끼 착지). 착지 자리에서 좌우로 뻗는 앞선이고,
## 앞선이 닿는 순간에 데미지가 들어간다 — 착지 순간 반경을 한꺼번에 때리지 않는다.
var _ruptures: Array[Dictionary] = []
## 단검을 손에 들고 있는가. 발사하면 false, 주우면 다시 true.
var _dagger_held := {}
var _next_projectile_id := 1
## 다음 라운드를 시작할 시각. 0이면 예약 없음 (진행 중이거나 경기가 끝났다).
var _round_restart_at := 0.0
## 표지 그림이 끝나 무기 선택을 열 시각. 0이면 기다리는 중이 아니다.
var _pick_opens_at := 0.0
## 이번 경기에서 표지 그림을 이미 띄웠는가. **경기마다 한 번**이라 라운드가 아니라
## 경기 단위로 기억한다 — 경기가 끝나면 씬이 통째로 닫히므로 되돌릴 곳이 따로 없다.
var _intro_shown := false
## 경기가 끝났으면 더 이상 라운드를 시작하지 않는다.
var _match_over := false

## **지금 판이 돌고 있는가.** 포인트가 나갈 수 있는 유일한 구간이다.
##
## `_open_round()`(카운트다운이 끝나 얼음을 푸는 자리)에서 켜지고 **포인트가 나가는 순간
## 꺼진다** — 그래서 한 판에서 포인트는 많아도 한 번 나간다.
##
## 전에는 이 자리에 `_round_restart_at > 0.0`(다음 판 예약이 걸렸는가)을 대신 썼는데,
## 그 값은 `_start_round()`가 맨 위에서 0으로 지운다. 즉 **판을 치운 순간 막이 걷혀서**
## 무기 선택과 `3 · 2 · 1` 을 세는 동안(둘 다 젤리가 얼어 있는 구간이다)이 통째로
## 뚫렸다 — 그 사이에 어느 쪽이든 한 번 더 죽으면 방금 끝난 판의 포인트가 한 번 더
## 나갔다. 지난 판이 남긴 것에 죽는 길이 여럿이라(#276의 출혈·연사, 낙사 판정은 무적을
## 보지 않는다) 이 창을 하나씩 막는 대신 "포인트는 판이 도는 동안 한 번" 이라는 규칙을
## 여기 한 곳에 둔다.
var _round_live := false

## 무기 선택이 진행 중인가 (#205). 켜져 있는 동안 두 젤리는 얼어 있다.
var _picking := false
## 플레이어 번호 -> 그 사람에게 제시한 무기 이름 배열.
var _pick_options := {}
## 플레이어 번호 -> 고른 무기 이름. 둘 다 여기 들어오면 라운드가 열린다.
var _pick_choices := {}
## 이번 차례를 대신 뽑아 줄 시각. 0이면 선택 중이 아니다.
var _pick_deadline := 0.0
## 지금 고르는 차례인 사람 (#320). 0이면 고르는 중이 아니다 — 카드가 한 벌뿐이라
## 1P가 고르고 나면 2P로 차례가 넘어간다.
var _pick_turn := 0
## 선택 창으로 돌아갈 시각. 0이면 예약 없음.
var _return_at := 0.0
## 카운트다운이 끝나 판이 실제로 열릴 시각. 0이면 예약 없음 (요청).
##
## 무기 선택이 끝나는 순간부터 `Combat.COUNTDOWN_TIME` 동안 두 젤리는 얼어 있고,
## 이 시각이 되면 얼음을 풀면서 무적을 새로 준다.
var _round_opens_at := 0.0
## 결과 화면을 띄울 시각. 0이면 예약 없음 (이슈 #273).
##
## 마지막 포인트에서는 획득 장면과 결과 화면이 이어서 떠야 한다 — 예전처럼 점수가 나는
## 자리에서 바로 결과를 알리면 두 화면이 겹쳐서, 축하 장면 위에 승패 글자가 덮인다.
var _result_at := 0.0
## 그때 알려 줄 승자 번호. `_result_at` 이 0이면 뜻이 없다.
var _result_winner := 0

## 아래 둘은 HUD가 읽는다.
## 플레이어 번호 -> 점수
var scores := {}
## 화면 가운데 안내. ""이면 아무것도 표시하지 않는다.
var banner := ""

## 현재 깔린 맵 지형과 그 즉사 구역 (물·용암). 없는 맵이면 _hazard가 null이다.
var _map: Node2D = null
var _hazard: Area2D = null
## 아직 안 나온 맵들. 판마다 하나씩 꺼내 쓰고, 비면 다시 섞어 채운다 —
## `_pick_round_map()` 참고.
var _map_pool: Array[String] = []
## 직전 판에 깔린 맵. 가방을 새로 채울 때 첫 장이 이것과 겹치지 않게 하는 데만 쓴다.
var _last_map := ""

## 결과 화면에서 도는 트윈. 화면을 접을 때 전부 끊는다.
var _result_tweens: Array[Tween] = []
## 연출로 옮기기 전의 제자리. 첫 재생 때 한 번만 재고 그 뒤로는 여기로 되돌린다.
var _jelly_home := Vector2.ZERO
var _label_home := Vector2.ZERO
var _homes_measured := false

## 승리 글자 색 (ui_theme.tres 팔레트).
const WIN_COLOR := Color(0.96, 0.55, 0.78)

@onready var map_root: Node2D = $MapRoot
@onready var players_root: Node2D = $Players
@onready var projectiles_root: Node2D = $Projectiles
@onready var effects_root: Node2D = $Effects
@onready var result_overlay: Control = $UI/HUD/ResultOverlay
## weapon_pick.gd는 class_name이 없어 타입을 붙이지 않는다 (jelly_preview.gd와 같은 방식).
@onready var weapon_pick = $UI/HUD/WeaponPick
## match_intro.gd도 class_name이 없어 타입을 붙이지 않는다 (위와 같은 방식).
@onready var match_intro = $UI/HUD/MatchIntro
## point_gain.gd도 class_name이 없어 타입을 붙이지 않는다 (위와 같은 방식).
@onready var point_gain = $UI/HUD/PointGain
## countdown.gd도 class_name이 없어 타입을 붙이지 않는다 (위와 같은 방식).
@onready var countdown = $UI/HUD/Countdown
## jelly_preview.gd는 class_name이 없어 타입을 붙이지 않는다 (player_panel.gd와 같은 방식).
@onready var result_jelly = $UI/HUD/ResultOverlay/Jelly
@onready var result_label: Label = $UI/HUD/ResultOverlay/ResultLabel
@onready var result_score: Label = $UI/HUD/ResultOverlay/ScoreLabel


func _ready() -> void:
	# **여기서 까는 것은 임시 지형이다.** 진짜 맵은 라운드가 열릴 때 뽑는다
	# (`_start_round`) — 선택 창에서 고르던 것을 없애면서 이 시점에는 아직 무엇이
	# 깔릴지 정해져 있지 않다.
	#
	# 그래도 하나는 깔아 둔다. 씬이 열리고 첫 라운드가 열리기까지의 몇 프레임 동안
	# 빈 화면을 보이지 않기 위해서다.
	_load_map(Maps.default_name())
	# 라운드마다 뜨는 무기 선택 카드 (#205). 한 화면에서 1P·2P가 차례로 고른다.
	weapon_pick.weapon_chosen.connect(_on_weapon_chosen)
	_spawn_players()


## 젤리 둘을 세운다 (#320). 씬이 열리자마자 부른다 — 기다릴 접속이 없다.
func _spawn_players() -> void:
	for player_id: int in GameState.PLAYER_IDS:
		_add_player(player_id)
	_update_round(banner)
	# 둘이 다 섰으니 첫 라운드를 연다 (#205). 라운드가 무기 선택으로 시작하게 되면서
	# "첫 판"에도 여는 순간이 필요해졌다 — 전에는 스폰이 곧 시작이었다.
	_start_round()


## 젤리 하나를 세운다. 자리와 캐릭터는 선택 창이 `GameState`에 적어 둔 것을 그대로 쓴다.
func _add_player(player_id: int) -> void:
	if players_root.has_node("Player_%d" % player_id):
		return
	var index := GameState.slot_of(player_id)
	var config := GameState.config_for(player_id)
	# **빈손으로 세운다** (#205). 무기는 선택 창이 아니라 라운드 시작의 선택이 정하므로
	# 이 시점에는 아직 아무것도 안 들었다 — `Weapons.get_weapon("")`이 빈 표를 돌려주어
	# 판정도 그림도 없는 상태가 된다. 곧바로 선택이 열리므로 오래 가는 상태는 아니다.
	# 강화 뽑기(#134)도 무기가 정해진 뒤라야 뜻이 있어서 `_finish_pick_phase()`로 옮겼다.
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = "Player_%d" % player_id
	player.player_id = player_id
	player.player_name = "%dP" % player_id
	player.weapon_id = ""
	player.character_id = config["character"]
	player.empowered_ready = false
	player.position = _spawn_position(index)
	player.facing = _spawn_facing(index)
	players_root.add_child(player)
	# 특수 공격 요청과 사망은 이 화면이 받아 판정한다.
	player.special_requested.connect(_on_special_requested)
	player.died.connect(_on_player_died)
	# 강제 낙하(양날 도끼)가 땅에 닿는 순간도 여기서 받는다 (#167).
	player.landed_forced.connect(_on_forced_landed)
	_dagger_held[player_id] = true
	scores[player_id] = 0


# ─────────────────────────── 라운드 진행 ───────────────────────────

## 죽은 쪽의 상대가 1포인트를 얻는다. 3포인트면 경기가 끝나고, 아니면 다음 판을 예약한다.
## 화면에는 "누가 이겼다"가 아니라 "누가 1포인트를 얻었다"로 보여준다.
func _on_player_died(player_id: int) -> void:
	if _match_over:
		return
	# **판이 도는 동안이 아니면 점수를 주지 않는다.** 이번 판의 포인트가 이미 나갔거나
	# (대기 중에 남은 쪽이 또 떨어지는 경우) 아직 판이 열리지 않았거나(무기 선택·카운트다운
	# 중에 지난 판이 남긴 출혈·연사·낙사로 죽는 경우) 둘 다 여기서 걸린다.
	if not _round_live:
		return
	# 여기를 지난 뒤에는 무슨 일이 있어도 이번 판의 포인트는 끝났다 — 아래에서 돌아가는
	# 갈래가 여럿이므로 맨 먼저 내린다.
	_round_live = false
	var scorer := _opponent_of(player_id)
	if scorer == null:
		_round_restart_at = _now() + Combat.ROUND_RESTART_DELAY
		_update_round("")
		return

	# 이긴 쪽만 여기서 포즈를 갈아 준다 (#176) — 죽은 쪽은 _check_death()가 이미
	# 패배 포즈를 걸었다. 다음 라운드가 시작되면 둘 다 평소로 돌아온다.
	scorer.set_pose(Characters.POSE_WIN)

	var id := scorer.player_id
	scores[id] = int(scores.get(id, 0)) + 1
	var total := int(scores[id])
	var final_point := total >= Combat.POINTS_TO_WIN

	if final_point:
		_match_over = true
		# 결과 화면은 획득 장면이 끝난 뒤에 뜬다 (#273) — 그래서 선택 창 복귀도 그만큼
		# 뒤로 밀린다. `MATCH_END_DELAY` 는 결과 화면이 떠 있는 시간이라야 한다.
		_return_at = _now() + Combat.POINT_GAIN_TIME + Combat.MATCH_END_DELAY
		_result_at = _now() + Combat.POINT_GAIN_TIME
		_result_winner = id
		_update_round("%s 승리!  %d포인트 달성" % [scorer.player_name, Combat.POINTS_TO_WIN])
	else:
		_round_restart_at = _now() + Combat.ROUND_RESTART_DELAY
		_update_round("%s +1 포인트" % scorer.player_name)

	# 장면은 점수를 적은 뒤에 띄운다 — 장면이 걷힌 뒤에 드러나는 HUD 카드의 동그라미가
	# 이미 새 점수여야 한다. 반대 순서면 장면이 3점을 축하한 직후에 카드가 2점을 적고 있다.
	_play_point_gain(id, total, final_point)


## 양쪽을 되살리고 판을 깨끗이 만든다. 여기서 안 지운 값은 다음 라운드로 새어 나간다.
func _start_round() -> void:
	_round_restart_at = 0.0
	# 판을 치우는 것과 판이 도는 것은 다르다 — 여기서 켜면 무기 선택과 카운트다운이
	# 포인트가 나갈 수 있는 구간이 된다. 켜는 곳은 `_open_round()` 하나뿐이다.
	_round_live = false
	_hide_result()

	# 맵은 **라운드마다 새로 뽑는다** (요청). 선택 창에서 고르던 것을 없애면서 맵을 정하는
	# 자리가 여기 하나만 남았다 — 경기 내내 한 지형이 아니라 판마다 지형이 갈린다.
	#
	# **스폰보다 먼저다.** 바로 아래 `reset_round`이 쓰는 `_spawn_position()`은 지금
	# 깔린 맵의 `Spawns` 마커를 읽는다. 순서를 바꾸면 지난 라운드 맵의 자리에 세워 놓고
	# 지형만 갈아 버려, 젤리가 허공이나 벽 속에서 판을 시작한다.
	#
	# 뽑는 방식은 `_pick_round_map()` 이 정한다 — **판마다 반드시 다른 맵**이다 (#310).
	_load_map(_pick_round_map())

	for projectile in projectiles_root.get_children():
		projectile.queue_free()

	_next_hit_at.clear()
	_special_ready_at.clear()
	_special_pending.clear()
	_punch_pending.clear()
	_sword_swings.clear()
	_bleeds.clear()
	_bursts.clear()
	_ruptures.clear()

	for player: Player in players_root.get_children():
		var index := GameState.slot_of(player.player_id)
		player.reset_round(_spawn_position(index), _spawn_facing(index))
		_dagger_held[player.player_id] = true

	_update_round("")
	# 판을 치웠으면 곧바로 싸우는 것이 아니라 **무기부터 고른다** (#205).
	# 강화 뽑기(#134)가 여기서 빠진 것은 그래서다 — 무기가 정해진 뒤에 뽑아야
	# 이번 라운드에 들 무기로 뽑는다.
	#
	# **경기의 첫 판에서는 그 앞에 표지 그림이 한 번 낀다** (요청). 시작을 누르고
	# 카드가 뜨기까지 2초를 이 그림에 준다. 라운드마다가 아니라 경기마다 한 번이다 —
	# 매 판 끼면 3점 경기에서 열 번 넘게 보게 된다.
	if not _intro_shown:
		_intro_shown = true
		_play_match_intro()
		# **그동안 움직이지 못하게 얼린다.** 젤리는 바로 위에서 이미 스폰됐고, 카드를
		# 여는 `_begin_pick_phase()`가 얼리는 일까지 하는데 그것이 2초 뒤로 밀렸다 —
		# 안 얼리면 그림 뒤에서 빈손으로 2초 동안 서로 밀치고 있게 된다.
		for player: Player in players_root.get_children():
			player.set_frozen(true)
		_pick_opens_at = _now() + MATCH_INTRO_TIME
		return
	_begin_pick_phase()


# ──────────────────────────── 무기 선택 (#205) ────────────────────────────
## 라운드는 **무기 선택으로 열린다.** 두 사람이 각자 후보 3개 중 하나를 고르고,
## 둘 다 고르면(또는 제한 시간이 지나면) 그때부터 판이 돈다.
##
## **한 화면이므로 차례로 고른다** (#320). 1P가 고르고 나면 2P의 카드가 열린다 —
## 카드가 한 벌이라 동시에 고를 수 없고, 두 벌을 나란히 깔면 서로의 패가 다 보인다.
## 고르는 동안 두 젤리는 얼어 있다.

## 고를 동안 젤리를 얼리고 후보를 뽑아 첫 차례를 연다.
func _begin_pick_phase() -> void:
	if _match_over:
		return
	_pick_options.clear()
	_pick_choices.clear()
	for player: Player in players_root.get_children():
		# 카드를 읽는 사람이 그 자리에서 맞지 않도록 조작과 판정을 함께 잠근다.
		player.set_frozen(true)
		_pick_options[player.player_id] = Weapons.random_choices(WEAPON_CHOICES)

	# 세울 젤리가 아직 없다 — 열어 둘 판이 없으므로 시작하지 않는다.
	if _pick_options.is_empty():
		_picking = false
		_pick_turn = 0
		_pick_deadline = 0.0
		return

	_picking = true
	_open_pick_turn(_next_picker())


## 아직 안 고른 사람 중 앞자리 (1P 먼저). 다 골랐으면 0.
func _next_picker() -> int:
	for player_id: int in GameState.PLAYER_IDS:
		if _pick_options.has(player_id) and not _pick_choices.has(player_id):
			return player_id
	return 0


## 이 사람의 카드를 연다.
##
## **제한 시간은 차례마다 새로 잰다** — 앞사람이 오래 골랐다고 뒷사람 몫이 줄어들면
## 고를 새도 없이 대신 뽑히게 된다.
func _open_pick_turn(player_id: int) -> void:
	_pick_turn = player_id
	_pick_deadline = _now() + WEAPON_PICK_TIME
	weapon_pick.open(_pick_options[player_id], WEAPON_PICK_TIME, player_id)


## 지금 차례인 사람이 골랐다. 넘어오는 값은 **후보 배열에서의 자리**다 —
## 무기 이름으로 주고받으면 후보에 없는 무기가 확정될 수 있다.
func _take_pick(index: int) -> void:
	if not _picking or _pick_turn == 0:
		return
	var choices: Array = _pick_options.get(_pick_turn, [])
	# 이미 고른 차례의 두 번째 누름은 버린다 — 카드가 닫히기 전의 한 프레임이 있다.
	if choices.is_empty() or _pick_choices.has(_pick_turn):
		return
	if index < 0 or index >= choices.size():
		return
	_pick_choices[_pick_turn] = choices[index]
	var next_picker := _next_picker()
	if next_picker == 0:
		_finish_pick_phase()
		return
	_open_pick_turn(next_picker)


## 카드를 눌렀다 (`weapon_pick.gd`의 신호). 확정은 여기서 한다.
func _on_weapon_chosen(index: int) -> void:
	_take_pick(index)


## 제한 시간이 다 됐다 — 그 사람 몫은 후보 중에서 대신 뽑는다 (#205).
## 한 사람이 자리를 비웠다고 판이 그 자리에서 영영 멈추면 안 된다.
func _auto_pick() -> void:
	var choices: Array = _pick_options.get(_pick_turn, [])
	if choices.is_empty():
		_finish_pick_phase()
		return
	_take_pick(randi() % choices.size())


## 고른 무기를 손에 쥐여 주고 라운드를 시작한다.
func _finish_pick_phase() -> void:
	if not _picking:
		return
	_picking = false
	_pick_turn = 0
	_pick_deadline = 0.0

	for player_id: int in _pick_options:
		var player := get_player(player_id)
		if player == null:
			continue
		var choices: Array = _pick_options[player_id]
		var chosen: String = _pick_choices.get(player_id, choices.pick_random())
		player.set_weapon(chosen)
		# 뽑기는 무기를 바꾼 **뒤에** 한다 (#134) — 지난 무기로 뽑으면 폭탄·표창이
		# 아닌 무기에서는 늘 false가 되어 강화가 영영 안 나온다.
		player.set_empowered(_roll_empowered(chosen))
		# **여기서 풀지 않는다** (요청) — 고른 뒤에 `3 · 2 · 1 · START!` 를 세는 동안
		# 두 젤리는 자기 자리에 선 채로 얼어 있고, 다 세면 `_tick_round()` 가 풀어 준다.
		# 자리는 지금 잡아 둔다: 세는 동안 서로가 어디에 섰는지 보고 첫 움직임을 정한다.
		var index := GameState.slot_of(player_id)
		player.reset_round(_spawn_position(index), _spawn_facing(index))
		_dagger_held[player_id] = true

	_pick_options.clear()
	_pick_choices.clear()
	weapon_pick.close()

	_round_opens_at = _now() + Combat.COUNTDOWN_TIME
	countdown.play()


## 다 세었다 — 얼음을 풀어 판을 연다 (요청).
##
## **무적을 여기서 새로 준다.** `reset_round()` 는 `Combat.ROUND_START_GRACE` 를 그 순간
## 부터 재는데, 무기 선택이 끝날 때 한 번 주고 그대로 두면 세는 데 쓴 1.7초가 그 안에서
## 흘러가 버려 실제로 싸움이 시작될 때 남는 무적이 0.3초뿐이다. 젤리는 얼어 있어 자리가
## 그대로이므로 다시 불러도 순간이동으로 보이지 않는다 — 값만 새로 잡힌다.
func _open_round() -> void:
	for player: Player in players_root.get_children():
		var index := GameState.slot_of(player.player_id)
		player.reset_round(_spawn_position(index), _spawn_facing(index))
		player.set_frozen(false)
	# **여기서부터가 판이다.** 포인트는 이 뒤의 첫 사망 하나에만 나간다 (`_round_live`).
	# 얼음을 푼 **뒤에** 켠다 — 위 반복이 무적을 새로 주므로, 순서를 바꾸면 아직 아무도
	# 움직이지 못하는 한 프레임이 점수가 날 수 있는 구간에 들어온다.
	_round_live = true


## 낙사 — 화면 밖으로 나가거나 즉사 구역(물·용암)에 닿으면 죽는다.
## 좌우 벽이 있고 즉사 구역이 없는 맵(오두막·투기장)에서는 일어나지 않는다.
func _check_falls() -> void:
	if _match_over:
		return
	var screen := Vector2(get_viewport_rect().size)
	# 삼항으로 받으면 안 된다 — get_overlapping_bodies()는 Array[Node2D]인데
	# 빈 배열 갈래는 타입 없는 Array라 대입에서 터진다.
	var drowning: Array[Node2D] = []
	if _hazard != null:
		drowning = _hazard.get_overlapping_bodies()
	for player: Player in players_root.get_children():
		if not player.alive:
			continue
		if Combat.is_out_of_bounds(player.global_position, screen) or drowning.has(player):
			player.kill()


## 예약된 라운드 재시작·선택 창 복귀를 처리한다.
func _tick_round() -> void:
	var now := _now()
	# **카드가 떠 있는 동안에는 판을 다시 열지 않는다** (#315) — 예약을 버리지 않고
	# 미룬다. 고르는 중에 지형이 갈리면 읽고 있던 카드가 남의 판 위에 뜬 것이 되고,
	# 젤리도 스폰으로 되돌아가 무엇이 일어났는지 알 수 없다. `_pick_deadline` 이 선택을
	# 반드시 끝내므로(`_finish_pick_phase`) 이 예약이 영원히 밀리는 일은 없다.
	if _round_restart_at > 0.0 and now >= _round_restart_at and not _picking:
		_start_round()
	# 표지 그림이 끝났다 — 미뤄 둔 무기 선택을 이제 연다 (요청).
	if _pick_opens_at > 0.0 and now >= _pick_opens_at:
		_pick_opens_at = 0.0
		_begin_pick_phase()
	# 제한 시간이 다 됐다 — 이번 차례 몫을 대신 뽑는다 (#205).
	if _picking and _pick_deadline > 0.0 and now >= _pick_deadline:
		_auto_pick()
	# 다 셌다 — 얼음을 풀어 판을 연다 (요청).
	if _round_opens_at > 0.0 and now >= _round_opens_at:
		_round_opens_at = 0.0
		_open_round()
	# 마지막 포인트 장면이 끝났다 — 미뤄 둔 결과 화면을 이제 띄운다 (#273).
	if _result_at > 0.0 and now >= _result_at:
		_result_at = 0.0
		_show_match_result(_result_winner)
	if _return_at > 0.0 and now >= _return_at:
		_return_at = 0.0
		_return_to_select()


## 점수와 안내 문구를 화면에 반영한다.
func _update_round(new_banner: String) -> void:
	banner = new_banner
	_update_hud()


# ─────────────────────────── 결과 화면 (승리 연출) ───────────────────────────
## 한 화면이므로 **이긴 쪽 기준으로 한 번만** 만든다 (#320). 두 기기 시절에는 같은
## 신호를 받고도 이긴 쪽은 승리를, 진 쪽은 패배 화면을 봤다 — 한 화면에서는 그렇게
## 갈라 놓을 곳이 없어서, 이긴 젤리를 세우고 누가 이겼는지를 글자로 적는다.

## 경기 결과를 띄운다.
##
## **점수가 난 자리에서 바로 부르지 않는다** (이슈 #273) — 마지막 포인트의 획득 장면이
## 끝난 뒤에 `_tick_round`가 부른다. 여기서 읽는 최종 점수는 그 전에 이미 적혀 있다.
func _show_match_result(winner_id: int) -> void:
	var winner := get_player(winner_id)
	if winner == null:
		return
	_play_result(winner.character_id, "%s 승리!" % winner.player_name)


func _play_result(character_id: String, title: String) -> void:
	_kill_result_tweens()
	result_jelly.character_id = character_id
	# 전투 화면에서 이긴 젤리가 짓던 포즈를 결과 화면도 그대로 이어받는다 (#178).
	result_jelly.pose = Characters.POSE_WIN
	result_score.text = _final_score_text()
	_reset_result_visuals()

	result_overlay.visible = true
	result_overlay.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(result_overlay, "modulate:a", 1.0, 0.25)
	_result_tweens.append(fade)

	# 점수는 결과 글자가 자리를 잡은 뒤에 뒤따라 나온다.
	var score_in := create_tween()
	score_in.tween_interval(0.5)
	score_in.tween_property(result_score, "modulate:a", 1.0, 0.3)
	_result_tweens.append(score_in)

	_play_win()

	# 연출이 정한 글자를 덮어쓴다. 크기·색·트윈은 그대로 두고 문구만 바꾼다.
	result_label.text = title


## 승리 — 젤리가 계속 통통 튀고 글자가 팝업으로 튀어나온다.
func _play_win() -> void:
	result_label.text = "승리!"
	result_label.add_theme_color_override("font_color", WIN_COLOR)
	result_label.scale = Vector2(0.2, 0.2)

	# 발밑(pivot)을 축으로 늘었다 눌렸다 하며 뛴다.
	var hop := create_tween().set_loops()
	hop.tween_property(result_jelly, "position:y", _jelly_home.y - 46.0, 0.34) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.parallel().tween_property(result_jelly, "scale", Vector2(0.92, 1.12), 0.34)
	hop.tween_property(result_jelly, "position:y", _jelly_home.y, 0.26) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hop.parallel().tween_property(result_jelly, "scale", Vector2(1.18, 0.82), 0.26)
	hop.tween_property(result_jelly, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_result_tweens.append(hop)

	var pop := create_tween()
	pop.tween_property(result_label, "scale", Vector2(1.15, 1.15), 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(result_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE)
	# 팝업이 끝난 뒤부터 숨 쉬듯 맥동한다. 팝업을 반복하면 계속 튀어 산만하다.
	pop.tween_callback(_start_win_pulse)
	_result_tweens.append(pop)


func _start_win_pulse() -> void:
	var pulse := create_tween().set_loops()
	pulse.tween_property(result_label, "scale", Vector2(1.06, 1.06), 0.5).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(result_label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
	_result_tweens.append(pulse)


## 연출로 건드리는 값을 전부 제자리로 돌린다. 제자리는 첫 재생 때 한 번만 잰다 —
## 그 뒤에 재면 이전 연출이 옮겨 놓은 위치를 제자리로 착각한다.
func _reset_result_visuals() -> void:
	if not _homes_measured:
		_jelly_home = result_jelly.position
		_label_home = result_label.position
		_homes_measured = true
	result_jelly.position = _jelly_home
	result_jelly.scale = Vector2.ONE
	result_jelly.rotation = 0.0
	result_jelly.modulate = Color.WHITE
	result_label.position = _label_home
	result_label.scale = Vector2.ONE
	result_label.modulate = Color.WHITE
	result_score.modulate.a = 0.0


func _hide_result() -> void:
	_kill_result_tweens()
	result_overlay.visible = false


func _kill_result_tweens() -> void:
	for tween in _result_tweens:
		if tween.is_valid():
			tween.kill()
	_result_tweens.clear()


## 결과 화면 아래에 적는 최종 점수. 왼쪽이 1P, 오른쪽이 2P다.
func _final_score_text() -> String:
	var out: Array[String] = []
	for player_id: int in GameState.PLAYER_IDS:
		out.append(str(int(scores.get(player_id, 0))))
	return "%s  :  %s" % out


# ─────────────────────────── 맵 ───────────────────────────

## 이번 판에 깔 맵을 고른다 (부르는 자리는 `_start_round()` 하나다).
##
## **가방에서 한 장씩 뽑는 방식이다** (#310). 맵 목록을 섞어 `_map_pool` 에 넣어 두고
## 판마다 앞에서 하나 꺼내며, 다 쓰면 다시 섞어 채운다. 그래서 두 가지가 보장된다 —
## **판마다 지형이 반드시 바뀌고**, 맵 종류만큼(지금 5판) 이어 하면 모든 맵을 한 번씩
## 지난다.
##
## **전에는 판마다 따로 `pick_random()` 했다.** 그쪽은 직전 맵을 기억하지 않아서 같은
## 맵이 연달아 나왔다 — 20판을 돌려 보니 19번의 넘어감 중 6번이 연속 중복이었고 한
## 지형이 네 판 이어진 구간도 있었다. 3점 선취는 보통 3~5판이라, 맵이 5종인데도 경기
## 하나가 통째로 한 지형에서 끝나는 일이 생겼다. 그것을 고치라는 요청이다.
##
## **가방이 넘어가는 자리도 막는다.** 새로 섞은 가방의 첫 장이 직전 맵과 같으면 마지막
## 자리와 맞바꾼다 — 안 하면 가방 경계에서만 같은 맵이 두 판 연달아 나온다. 맞바꿀
## 자리가 없는 경우(맵이 한 종뿐)는 그대로 둔다: 그때는 바꿀 지형 자체가 없다.
##
## **뽑는 자리는 `_start_round()` 하나다.** 뽑은 이름을 그 자리에서 `_load_map()` 에 넘긴다.
func _pick_round_map() -> String:
	if _map_pool.is_empty():
		_map_pool = Maps.names()
		_map_pool.shuffle()
		var last := _map_pool.size() - 1
		if last > 0 and _map_pool[0] == _last_map:
			_map_pool[0] = _map_pool[last]
			_map_pool[last] = _last_map
	_last_map = _map_pool.pop_front()
	return _last_map


## 맵 지형을 MapRoot 아래에 붙인다.
## **라운드마다 다시 불린다**(`_start_round`) — 두 번째 호출이 깨끗해야 한다.
func _load_map(map_name: String) -> void:
	for child in map_root.get_children():
		# queue_free()는 프레임 끝에야 노드를 뗀다. 그때까지 옛 지형의 충돌 몸체가
		# 물리 공간에 남아 **새 맵과 겹친 채로 한 프레임이 돈다** — 먼저 떼어 낸다.
		map_root.remove_child(child)
		child.queue_free()
	_map = null
	_hazard = null
	var scene := Maps.scene(map_name)
	if scene == null:
		push_error("맵 씬을 찾지 못했습니다: %s" % map_name)
		return
	_map = scene.instantiate() as Node2D
	map_root.add_child(_map)
	_hazard = _map.get_node_or_null("Hazard") as Area2D


## 맵이 들고 있는 스폰 지점. 맵에 없으면 대비값을 쓴다.
func _spawn_position(index: int) -> Vector2:
	if _map != null:
		var marker := _map.get_node_or_null("Spawns/Spawn%d" % (index + 1)) as Marker2D
		if marker != null:
			return marker.global_position
	return SPAWN_POSITIONS[index % SPAWN_POSITIONS.size()]


## 서로 마주 보게 둔다. 2P는 왼쪽을 본다.
func _spawn_facing(index: int) -> int:
	return -1 if index % 2 == 1 else 1


## 경기가 끝났다 — 선택 창으로 돌아간다. 씬이 통째로 새로 열리므로 다음 경기는
## 점수도 표도 깨끗한 자리에서 시작한다.
func _return_to_select() -> void:
	get_tree().change_scene_to_file("res://scenes/select.tscn")


func get_player(player_id: int) -> Player:
	return players_root.get_node_or_null("Player_%d" % player_id) as Player


## 기기당 1명, 최대 2명이므로 상대는 자기 자신이 아닌 나머지 하나다.
func _opponent_of(player_id: int) -> Player:
	for player: Player in players_root.get_children():
		if player.player_id != player_id:
			return player
	return null


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ─────────────────────────── 전투 틱 ───────────────────────────

func _physics_process(_delta: float) -> void:
	_sync_special_ready()
	_check_basic_attacks()
	_check_pending_specials()
	_tick_punches()
	_tick_sword_swings()
	_tick_bleeds()
	_tick_bursts()
	_tick_ruptures()
	_check_falls()
	_tick_round()


## 쿨타임 상태를 무기 도형 색에 쓰도록 내려준다.
func _sync_special_ready() -> void:
	var now := _now()
	for player: Player in players_root.get_children():
		player.set_special_ready(now >= _special_ready_at.get(player.player_id, 0.0))


## 기본 공격은 조작 없이 자동으로 들어간다 — 근접은 닿으면, 원거리는 간격마다.
func _check_basic_attacks() -> void:
	for attacker: Player in players_root.get_children():
		var target := _opponent_of(attacker.player_id)
		if target == null or not attacker.alive or not target.alive:
			continue
		_try_melee_basic(attacker, target)
		_try_ranged_basic(attacker)


func _try_melee_basic(attacker: Player, target: Player) -> void:
	var weapon := Weapons.get_weapon(attacker.weapon_id)
	if weapon.is_empty() or weapon["basic_damage"] <= 0.0:
		return
	if not _is_melee(weapon):
		return
	if not attacker.can_act():
		return
	# 방패를 크게 들어 올린 동안은 막기만 한다. 크게 든 방패로 몸을
	# 가리는 자세라 그 자세로 때릴 수는 없다 — 탄을 막는 것과 맞바꾸는 값이다.
	if attacker.is_guarding():
		return
	if target.is_invulnerable() or is_blocked(attacker, target):
		return
	# 등 뒤의 상대는 못 때린다. 뒤를 잡으면 일방적으로 때릴 수 있다는 뜻이기도 하다.
	if not _faces(attacker, target):
		return

	var reach: float = MELEE_REACH + attacker.current_reach()
	if attacker.global_position.distance_to(target.global_position) > reach:
		return

	# 지속 데미지 무기는 자기 basic_interval 대로 촘촘히 들어간다.
	# "닿으면" 무기는 0.6초 바닥을 지킨다 — 근거는 Combat.MELEE_HIT_INTERVAL 주석.
	var continuous: bool = weapon["basic_kind"] == "melee_dot"
	var interval: float = weapon["basic_interval"]
	if not continuous:
		interval = maxf(interval, Combat.MELEE_HIT_INTERVAL)

	var key := "%d>%d" % [attacker.player_id, target.player_id]
	var now := _now()
	if now < _next_hit_at.get(key, 0.0):
		return
	_next_hit_at[key] = now + interval

	# 넉백은 데미지보다 성기게 준다.
	#
	# 촘촘한 지속 데미지에 매번 넉백을 붙이면 두 가지가 망가진다. 상대는
	# KNOCKBACK_CONTROL_LOCK이 계속 새로 걸려 좌우 조작을 아예 못 하고, 지속 무기는
	# 자기가 상대를 제 사거리 밖으로 밀어내서 스스로 지속을 끊는다.
	# 그래서 넉백은 다른 근접 무기와 같은 박자(0.6초)로만 주고 나머지 틱은
	# 넉백 없는 지속 데미지로 넣는다.
	#
	# 간격이 0.6초보다 긴 무기(전기톱 1.0초)는 이 조건이 늘 참이라 지금까지와 똑같다.
	var knock_key := "knock>" + key
	if now < _next_hit_at.get(knock_key, 0.0):
		target.apply_dot(weapon["basic_damage"])
		return
	_next_hit_at[knock_key] = now + Combat.MELEE_HIT_INTERVAL
	# 기절은 무기 표에서 바로 읽지 않는다 — **켜져 있는 능력**에서 나온다
	# (망치 특수). 안 켜져 있으면 0 이라 지금까지와 똑같다.
	var stun := attacker.stun_bonus()
	target.apply_hit(weapon["basic_damage"], weapon["knockback"],
		attacker.global_position.x, stun, "basic")
	# 기절을 얹은 타격에는 **번개가 내려친다** — 삼지창이 맞혔을 때와 같은 연출이고
	# 같은 함수를 쓴다(`_play_lightning_strike`). 자리도 같은 기준인 **맞은 젤리의
	# 발밑**이다.
	#
	# **무기 이름이 아니라 기절이 얹혔는지로 가른다** — 위 `stun_bonus()` 와 같은 자리에서
	# 나온 값이라, 기절을 거는 능력이 다른 무기에 붙어도 번개와 기절이 어긋나지 않는다.
	# 지금 이 길로 오는 것은 망치 특수뿐이다.
	if stun > 0.0:
		_play_lightning_strike(target.global_position + Vector2(0.0, Player.BODY_BOTTOM))


## 이 무기가 근접인가. `basic_kind` 가 "melee" 로 시작하면 참이다 —
## 지속 데미지 무기("melee_dot", 전기톱·광선검)도 근접에 든다.
func _is_melee(weapon: Dictionary) -> bool:
	return weapon.get("basic_kind", "").begins_with("melee")


## 원거리 무기의 기본 공격도 자동이다. basic_interval 마다 알아서 발사한다.
func _try_ranged_basic(attacker: Player) -> void:
	var weapon := Weapons.get_weapon(attacker.weapon_id)
	if weapon.is_empty() or weapon["basic_damage"] <= 0.0:
		return
	if weapon["basic_kind"] != "ranged":
		return
	if not attacker.can_act():
		return

	var player_id: int = attacker.player_id
	var key := "ranged>%d" % player_id
	var now := _now()
	if now < _next_hit_at.get(key, 0.0):
		return

	# 단검: 들고 있을 때만 나가고, 상대를 자동으로 따라간다. 쏘면 손에서 없어진다.
	if weapon["name"] == "단검":
		if not _dagger_held.get(player_id, true):
			return
		var target := _opponent_of(player_id)
		if target == null:
			return
		_next_hit_at[key] = now + weapon["basic_interval"]
		_dagger_held[player_id] = false
		_server_fire(attacker, {
			"damage": weapon["basic_damage"],
			"knockback": weapon["knockback"],
			"homing_id": target.player_id,
			"use_gravity": true,
			"on_solid": "stay",
			"pickup_owner": player_id,
			# 던진 뒤에도 바닥에서 주워야 해서 손에 들었을 때와 같은 그림으로 그린다.
			"art": weapon["name"],
			# 맞은 자리에 빨간 알갱이가 튄다 (#250). 어떤 탄이 연출을 부르는지는
			# 무기 표가 정한다 — 삼지창의 `hit_lightning` 과 같은 방식이다.
			"hit_sparks": weapon.get("hit_sparks", false),
		})
		return

	_next_hit_at[key] = now + weapon["basic_interval"]
	var shot := {
		"damage": weapon["basic_damage"],
		"knockback": weapon["knockback"],
	}
	# 활 — 살짝 위로 쏴서 포물선을 그린다 (#125). 각도만 주면 비스듬한 직선이 되므로
	# 중력을 함께 켜야 한다. 특수(관통 3발)는 이 경로를 안 지나가서 직선 그대로다.
	var arc: float = weapon.get("basic_arc_angle", 0.0)
	if not is_zero_approx(arc):
		shot["launch_angle"] = arc
		shot["use_gravity"] = true
	_server_fire(attacker, shot)


## 강제 이동 중에 상대와 닿으면 특수 데미지가 한 번 들어간다.
func _check_pending_specials() -> void:
	for player_id: int in _special_pending.keys():
		var attacker := get_player(player_id)
		var target := _opponent_of(player_id)
		if attacker == null or target == null:
			_special_pending.erase(player_id)
			continue
		if not attacker.is_forced():
			_special_pending.erase(player_id)   # 동작이 끝났으면 기회는 사라진다
			continue
		var info: Dictionary = _special_pending[player_id]
		if not attacker.forced_mode in info["modes"]:
			continue
		var reach: float = MELEE_REACH + attacker.current_reach()
		if attacker.global_position.distance_to(target.global_position) > reach:
			continue
		if is_blocked(attacker, target):
			continue
		target.apply_hit(info["damage"], info["knockback"],
			attacker.global_position.x, 0.0, "special")
		if info.get("bleed_dps", 0.0) > 0.0:
			# 첫 타는 즉시 들어가고 그 뒤로 `interval`마다 이어진다.
			# 3초 출혈에 0.2초 간격이면 0·0.2·…·2.8초에 열다섯 번이다.
			_bleeds[target.player_id] = {
				"dps": info["bleed_dps"],
				"interval": info.get("bleed_interval", 1.0),
				"until": _now() + info["bleed_duration"],
				"next_at": _now(),
			}
		_special_pending.erase(player_id)


## 출혈은 무적 시간을 무시하고 무기 표가 정한 박자(`bleed_interval`)로 들어간다.
##
## **한 틱은 `dps * interval`이다** (#260). 그래서 박자를 촘촘하게 바꿔도 총량
## (`bleed_damage * bleed_duration`)은 그대로다 — 전기톱을 0.2초 간격으로 옮기면서
## 1초에 4씩이 0.2초에 0.8씩이 되었고, 3초 동안 들어가는 12는 변하지 않았다.
## 세기를 조절할 곳은 여기가 아니라 무기 표의 `bleed_damage`다.
##
## 촘촘하게 나눈 이유는 화면이다: 지속 피해인데 1초에 한 번 크게 들어오면 체력이
## "계속 깎인다"가 아니라 "가끔 뭉텅 준다"로 보인다 — 같은 무기의 기본 공격이 이미
## 0.2초 박자다(#105, 광선검과 같은 판단).
func _tick_bleeds() -> void:
	var now := _now()
	for player_id: int in _bleeds.keys():
		var info: Dictionary = _bleeds[player_id]
		var target := get_player(player_id)
		if now >= info["until"] or target == null or not target.alive:
			_bleeds.erase(player_id)
			continue
		if now < info["next_at"]:
			continue
		var interval: float = maxf(float(info.get("interval", 1.0)), 0.01)
		# **직전 예정 시각에 간격을 더한다** (`now + interval`이 아니다). 물리 프레임이
		# 0.0167초라 0.2초 간격은 늘 조금씩 늦게 걸리는데, 늦은 시각에서 다시 재면
		# 그 오차가 쌓여 3초 동안 들어가는 횟수가 열다섯에서 열넷으로 준다.
		info["next_at"] = float(info["next_at"]) + interval
		target.apply_dot(float(info["dps"]) * interval)


## 소총 연사 — 한 번 누르면 지속시간 동안 자동으로 나간다.
func _tick_bursts() -> void:
	var now := _now()
	for player_id: int in _bursts.keys():
		var info: Dictionary = _bursts[player_id]
		var shooter := get_player(player_id)
		if shooter == null or not shooter.can_act():
			_bursts.erase(player_id)
			continue
		# 끝나는 조건이 둘이다 — 시간(소총: 누르는 동안 2초)과 발 수(글러브: 6발, #164).
		if info["remaining"] == 0 or (info["until"] > 0.0 and now >= info["until"]):
			_bursts.erase(player_id)
			continue
		if now < info["next_at"]:
			continue
		info["next_at"] = now + info["interval"]
		var data: Dictionary = (info["base"] as Dictionary).duplicate()
		data["damage"] = info["damage"]
		# **첫 발만 세게 민다** (#164). 매 발 강하게 밀면 연발이 도는 동안 상대 조작이
		# 계속 잠긴다 — 지속 무기에서 같은 문제를 #103에서 이미 고쳤다.
		data["knockback"] = info["first_knockback"] if info["fired"] == 0 else info["knockback"]
		info["fired"] = int(info["fired"]) + 1
		if info["remaining"] > 0:
			info["remaining"] = int(info["remaining"]) - 1
		_server_fire(shooter, data)


## 연발 하나를 예약한다 (소총·글러브). **끝나는 조건은 둘 중 하나만 쓴다** —
## `duration`이 0보다 크면 시간으로, `shots`가 0보다 크면 발 수로 끝난다.
##
## `first_knockback`이 음수면 첫 발도 나머지와 같은 넉백이다(소총).
func _start_burst(player_id: int, damage: float, knockback: int, interval: float,
		duration := 0.0, shots := 0, first_knockback := -1, base := {}) -> void:
	var now := _now()
	_bursts[player_id] = {
		"until": now + duration if duration > 0.0 else 0.0,
		"remaining": shots if shots > 0 else -1,
		"next_at": now,
		"fired": 0,
		"interval": interval,
		"damage": damage,
		"knockback": knockback,
		"first_knockback": first_knockback if first_knockback >= 0 else knockback,
		"base": base,
	}


## 공격자가 상대 쪽을 보고 있는가. **근접 공격은 기본·특수 모두 이 방향으로만 들어간다** (이슈 #107).
##
## 좌우가 정확히 같은 순간(위아래로 겹쳤을 때)은 어느 쪽도 아니므로 빗나간 것으로 본다.
## 원거리는 `_server_fire()`가 애초에 바라보는 쪽으로만 쏘므로 여기를 거치지 않고,
## 강제 이동 중의 특수(돌진·낙하)도 거치지 않는다 — 도끼 낙하는 바로 아래를 때리는 기술이라
## 좌우를 따지면 영영 안 맞는다.
func _faces(attacker: Player, target: Player) -> bool:
	var offset: float = target.global_position.x - attacker.global_position.x
	return signf(offset) == signf(float(attacker.facing))


## 상대가 나를 보고 있고, 상대 무기가 내 무기보다 길면 막힌다.
## 같은 사거리면 둘 다 들어간다. 광선검의 관통은 이 판정을 무시한다.
func is_blocked(attacker: Player, target: Player) -> bool:
	if attacker.is_piercing():
		return false
	var toward_attacker := signf(attacker.global_position.x - target.global_position.x)
	if signf(float(target.facing)) != toward_attacker:
		return false   # 등을 보이고 있으면 못 막는다
	return target.current_reach() > attacker.current_reach()


# ─────────────────────────── 투사체 ───────────────────────────
## 속도는 무기와 무관하게 전부 같다.
##
## 근접 막기(`is_blocked()`, 사거리 비교)는 거치지 않는다. **단 하나 예외가 방패다** —
## 크게 들어 올린 방패는 앞에서 오는 탄을 막는다 (`Projectile._guarded_by`). 반경으로
## 흩뿌리는 것(폭탄)은 그것도 못 막는다.

## 전투 판정에서만 부른다. offsets로 여러 발을 한 번에 낼 수 있다 (활 특수의 평행 3발).
func _server_fire(attacker: Player, base: Dictionary, offsets: Array = [0.0]) -> void:
	var dir := signf(float(attacker.facing))
	# 탄 크기는 무기 표에서 읽는다 — 기본·특수·연사 어디서 쏘든 같은 크기로 나간다.
	# 표에서 꺼낸 값은 Variant라 명시 타입으로 받는다 (#66).
	var weapon := Weapons.get_weapon(attacker.weapon_id)
	var size_scale: float = weapon.get("projectile_scale", 1.0)
	# **그림만** 키우는 배율은 따로다 (#149). 판정을 건드리지 않고 눈에 띄게만 하고 싶을
	# 때 쓴다 — 위의 projectile_scale 은 충돌 상자까지 함께 키운다.
	var art_scale: float = weapon.get("projectile_art_scale", 1.0)
	# 결정질 화살로 그릴지는 무기가 정한다 — 기본이든 특수든 같은 모양으로 나간다 (#125).
	var draw_arrow: bool = weapon.get("projectile_arrow", false)
	# 파란 에너지 구슬로 그릴지도 같은 자리에서 읽는다 (대포 총). **미사일과 겹칠 수
	# 있다** — 대포 총은 특수만 불꽃 꼬리 미사일이라 특수 탄에는 두 값이 함께 실린다.
	# 어느 쪽이 이기는지는 `Projectile.setup()`이 한 곳에서 정한다.
	var draw_orb: bool = weapon.get("projectile_orb", false)
	# 맞은 자리에 푸른 충격을 터뜨릴지 (대포 총). 위와 같이 무기가 정하므로
	# 기본·특수·연사 어디서 쏘든 같이 터진다 — 한쪽만 터지면 같은 무기로 안 읽힌다.
	var hit_burst: bool = weapon.get("projectile_hit_burst", false)
	# 탄 그림도 무기 표에서 읽는다 (소총의 총알) — 크기와 같은 이유로, 기본에서 쏘든
	# 연사에서 쏘든 같은 탄이 나가야 한다. 여기서 읽지 않으면 기본 공격 경로와
	# 연사 경로 두 곳에 같은 줄을 적어야 하고, 한쪽만 고치면 어긋난다.
	var projectile_art: String = weapon.get("projectile_file", "")
	# 발사 각도는 쏘는 쪽(base)이 정한다. 활은 기본 공격만 위로 띄우고 특수는 직선이다.
	var launch_angle: float = base.get("launch_angle", 0.0)
	# 속도도 쏘는 쪽이 정할 수 있다 (#164). 없으면 지금까지의 공통 속도다 —
	# 로켓 글러브만 느리게 나간다.
	var speed: float = base.get("speed", Combat.PROJECTILE_SPEED)
	for offset: float in offsets:
		var data := base.duplicate()
		data["size_scale"] = size_scale
		data["art_scale"] = art_scale
		# **쏘는 쪽이 준 것이 우선이다.** 한 무기가 탄 그림을 둘 쓰는 경우(일반/강화
		# 폭탄·빨간 표창·로켓 글러브)에는 이미 `art_file` 을 넣어 두었고, 여기서
		# 덮으면 그쪽이 고른 것이 지워진다 (#131·#134와 같은 어긋남).
		if not projectile_art.is_empty() and not data.has("art_file"):
			data["art_file"] = projectile_art
		data["arrow"] = draw_arrow
		data["orb"] = draw_orb
		data["hit_burst"] = hit_burst
		data["id"] = _next_projectile_id
		_next_projectile_id += 1
		data["shooter_id"] = attacker.player_id
		data["velocity"] = _launch_velocity(dir, launch_angle, speed)
		# 무기 끝에서 나가게 한다.
		data["position"] = attacker.global_position + Vector2(
			dir * (MELEE_REACH * 0.5 + attacker.current_reach()), offset)
		_spawn_projectile(data)


## 부채꼴 발사 (샷건). **전투 판정에서만 부른다.**
##
## 탄을 쓰지 않는 이유: 산탄은 코앞에서 퍼지는 것이라 "날아가는 무엇"이 없다.
## 투사체로 흉내내면 회피가 "옆으로 비키기"가 되는데, 부채꼴은 **거리를 벌리거나
## 부채 밖으로 나가는 것**이 회피여야 한다.
##
## **사거리 비교 막기(`is_blocked`)는 거치지 않는다.** 그것은 무기 끝과 무기 끝이
## 부딪히는 판정인데 이건 흩뿌리는 것이다 — 폭탄 반경·양날 도끼 착지 충격파와 같은 취급이다.
## 다만 `_faces()`는 뜻이 있다: 부채꼴 자체가 바라보는 쪽으로만 열린다.
##
## **예외가 하나 있다 — 크게 들어 올린 방패는 이 산탄을 막는다** (#222).
## 부채꼴은 바라보는 쪽으로만 열리는 **정면 공격**이라, 정면을 가린 방패가 못 막을 이유가
## 없다. 방패의 사각이 샷건 하나로 남아 있었던 것을 메우는 것이다. 폭탄 반경과 착지
## 충격파는 그대로 못 막는다 — 그쪽은 정면이라는 것이 없다.
##
## 데미지는 가까울수록 세다(34 → 14). 감소 기준 거리는 부채꼴 사거리와 같은 값이라
## 부채 끝에 겨우 닿으면 최소값이 들어간다.
func _cone_blast(attacker: Player, weapon: Dictionary) -> void:
	var reach: float = weapon["special_cone_range"]
	var spread: float = weapon["special_cone_angle"]
	# **맞았는지와 무관하게 먼저 띄운다.** 빗나간 것도 "여기까지였다"로 보여야 한다
	# (착지 충격파를 띄우는 이유 #167과 같다).
	_play_shotgun_blast(
		attacker.global_position + Vector2(0.0, Player.WEAPON_CENTER_Y),
		signf(float(attacker.facing)), reach, spread)
	var target := _opponent_of(attacker.player_id)
	if target == null or not target.alive:
		return
	var offset := target.global_position - attacker.global_position
	var distance := offset.length()
	if distance > reach:
		return
	# 바라보는 쪽에서 벗어난 각도가 부채꼴 절반을 넘으면 빗나간다.
	# 두 젤리가 정확히 겹치면 방향을 못 재므로 그때는 맞은 것으로 둔다.
	var half := deg_to_rad(spread) * 0.5
	if distance > 0.001:
		var aim := Vector2(signf(float(attacker.facing)), 0.0)
		if absf(aim.angle_to(offset)) > half:
			return
	# 크게 들어 올린 방패에 막혔다 (#222). 데미지도 넉백도 없다 —
	# 탄이 막혔을 때(`Projectile._blocked`)와 같다. 부채꼴 연출은 위에서 이미 띄웠으므로
	# 쏜 쪽에는 "여기까지였는데 막혔다"가 보인다.
	if _guarded_cone(attacker, target):
		return
	# 표에서 꺼낸 값은 Variant라 명시 타입으로 받는다 (#66).
	var near: float = weapon["special_damage"]
	var far: float = weapon["falloff_min_damage"]
	var damage := lerpf(near, far, clampf(distance / reach, 0.0, 1.0))
	target.apply_hit(damage, weapon["knockback"], attacker.global_position.x,
		0.0, "special")


## 크게 들어 올린 방패가 정면에서 오는 산탄을 막는가 (#222).
##
## 자세만으로는 부족하고 **앞에서 와야** 막힌다 — 탄을 막는 `Projectile._guarded_by`,
## 근접 막기 `is_blocked()` 와 같은 기준이다. 방패를 들었다고 등 뒤까지 가려지면
## `special_duration`(4초) 동안 무적이 된다.
##
## 좌우가 정확히 겹치면(위아래로 포개졌을 때) 어느 쪽이 앞인지 못 재므로 막지 못한 것으로
## 둔다 — 부채꼴 쪽이 그때를 "맞은 것"으로 두는 것과 짝이 맞는다.
func _guarded_cone(attacker: Player, target: Player) -> bool:
	if not target.is_guarding():
		return false
	var toward_attacker := signf(attacker.global_position.x - target.global_position.x)
	return signf(float(target.facing)) == toward_attacker


## 너클 강펀치 (#225). 게이지를 전부 소모하고 **부채꼴**로 때린다.
##
## 부채꼴 안에서 **가운데가 가장 세다** — 바라보는 쪽에서 벗어난 각도만큼 약해지고
## 가장자리는 가운데의 `punch_edge_ratio`(45%)다. 샷건이 **거리**로 줄어드는 것과 다르다:
## 강펀치는 코앞에서 내지르는 것이라 거리보다 조준이 값이어야 한다.
##
## **게이지는 맞았는지와 무관하게 비워진다.** 헛치면 아무 일도 없이 게이지만 날아가는 것이
## 이 무기의 무게다 — 빗나갈 때마다 공짜로 다시 시도할 수 있으면 조준에 값이 없다.
## 그래서 쿨타임도 늘 돌도록 항상 true를 돌려준다.
##
## 크게 들어 올린 방패는 이 부채꼴도 막는다 (#222와 같은 판정). 근접 특수였을 때는
## `is_blocked()`(사거리 비교)에 막혔는데 부채꼴로 바뀌면서 그 길이 사라지므로,
## 막을 수단이 아예 없어지지 않게 같은 규칙을 잇는다.
func _punch_cone(attacker: Player, weapon: Dictionary) -> bool:
	var reach: float = weapon["punch_cone_range"]
	var spread: float = weapon["punch_cone_angle"]
	var aim := signf(float(attacker.facing))
	var windup: float = weapon.get("punch_windup", 0.0)
	var player_id: int = attacker.player_id

	# **누른 순간의 것으로 다 굳힌다** (#231) — 자리·방향·데미지·충전 여부.
	# 기다리는 동안 쓰는 쪽이 움직이거나(자리) 돌아서거나(방향) 다시 맞아도(게이지)
	# 이번 주먹은 안 바뀐다. 예고한 범위와 맞는 범위가 달라지면 예고가 거짓말이 된다.
	var shot := {
		# 판정을 재는 기준은 **몸 중심**이다 (즉발이었을 때와 같은 계산을 이어 쓴다).
		"body": attacker.global_position,
		# 그림이 시작되는 자리는 **주먹**이다. 둘이 `PUNCH_ORIGIN_X`만큼 어긋나 있다.
		"origin": attacker.global_position + Vector2(aim * PUNCH_ORIGIN_X, Player.WEAPON_CENTER_Y),
		"aim": aim,
		"reach": reach,
		"spread": spread,
		"charged": attacker.is_charged(),
		# 한가운데 데미지. 게이지 0%에서 10, 100%에서 40이다.
		"center": lerpf(weapon["gauge_min_damage"], weapon["gauge_max_damage"],
			attacker.gauge_ratio()),
		"edge_ratio": float(weapon["punch_edge_ratio"]),
		"knockback": int(weapon["knockback"]),
	}

	# 게이지는 **누른 순간** 비워진다. 기다리는 동안 다시 차는 것은 다음 주먹 몫이다.
	attacker.set_gauge(0.0)

	# 예고가 없는 값(0)이면 지금까지처럼 즉발이다 — 무기 표만 고쳐도 되돌릴 수 있게 남겨 둔다.
	if windup <= 0.0:
		_resolve_punch(attacker, shot)
		return true

	_play_punch_range(shot["origin"], aim, reach, spread, shot["charged"], windup)
	shot["at"] = _now() + windup
	_punch_pending[player_id] = shot
	return true


## 예고가 찬 강펀치를 터뜨린다 (#231). 예약은 한 사람당 하나뿐이다 —
## 쿨타임(5초)이 예고(0.2초)보다 훨씬 길어서 겹칠 수가 없다.
func _tick_punches() -> void:
	var now := _now()
	for player_id: int in _punch_pending.keys():
		var shot: Dictionary = _punch_pending[player_id]
		if now < shot["at"]:
			continue
		_punch_pending.erase(player_id)
		var attacker := get_player(player_id)
		# 예고 중에 죽었으면 주먹은 들어가지 않는다. 게이지는 이미 비워졌으니
		# 헛친 것과 같다 — 그것이 이 무기의 무게다.
		if attacker == null or not attacker.alive:
			continue
		_resolve_punch(attacker, shot)


## 검이 다 내려온 순간에 검 특수를 넣는다 (#247).
##
## **거리는 누를 때 이미 봤고 여기서 다시 보지 않는다.** 이 무기는 휘두르는 방향도
## 상대 무기의 막기도 따지지 않고 들어가던 무기고(빛기둥이 상대에게 꽂히는 연출이다),
## 이번에 바꾼 것은 **언제** 들어가는가뿐이다 — 여기서 거리를 다시 재면 회피할 수
## 있는 무기가 되어 수치를 건드리지 않고도 세기가 달라진다.
##
## 들어 올리는 도중에 쓰는 쪽이 죽으면 사라진다. 쿨타임은 이미 돌기 시작했으니 헛친
## 것과 같다 — 강펀치(`_tick_punches`)와 같은 규칙이다.
func _tick_sword_swings() -> void:
	var now := _now()
	for player_id: int in _sword_swings.keys():
		var swing: Dictionary = _sword_swings[player_id]
		if now < swing["at"]:
			continue
		_sword_swings.erase(player_id)
		var attacker := get_player(player_id)
		if attacker == null or not attacker.alive:
			continue
		var target := _opponent_of(player_id)
		if target == null or not target.alive:
			continue
		# 비율은 **맞는 순간의** 현재 체력에 걸린다 — 휘두르는 동안 깎였으면 그만큼 적다.
		target.apply_hit(target.hp * float(swing["hp_ratio"]),
			int(swing["knockback"]), attacker.global_position.x, 0.0, "special")
		_play_light_burst(target.global_position + Vector2(0.0, Player.BODY_BOTTOM))


## 굳혀 둔 부채꼴로 판정하고 주먹 연출을 띄운다 (#231).
##
## **맞았는지와 무관하게 연출을 먼저 띄운다** — 빗나간 것도 "여기까지였다"로 보여야 한다
## (샷건 부채꼴·도끼 착지 충격파와 같은 이유).
##
## 부채꼴 안에서 **가운데가 가장 세다.** 가장자리는 가운데의 `edge_ratio`(45%)다.
## 크게 들어 올린 방패는 이 부채꼴도 막는다 (#222와 같은 판정).
func _resolve_punch(attacker: Player, shot: Dictionary) -> void:
	var aim: float = shot["aim"]
	var reach: float = shot["reach"]
	_play_heavy_punch(shot["origin"], aim, reach, shot["spread"], shot["charged"])

	var target := _opponent_of(attacker.player_id)
	if target == null or not target.alive:
		return
	var body: Vector2 = shot["body"]
	var offset := target.global_position - body
	var distance := offset.length()
	if distance > reach:
		return
	# 바라보는 쪽에서 벗어난 각도가 부채꼴 절반을 넘으면 빗나간다.
	# 두 젤리가 정확히 겹치면 방향을 못 재므로 그때는 한가운데로 둔다.
	var half := deg_to_rad(float(shot["spread"])) * 0.5
	var edge := 0.0
	if distance > 0.001:
		var away := absf(Vector2(aim, 0.0).angle_to(offset))
		if away > half:
			return
		edge = away / maxf(half, 0.001)
	if _guarded_cone(attacker, target):
		return
	var center: float = shot["center"]
	var damage := lerpf(center, center * float(shot["edge_ratio"]), edge)
	target.apply_hit(damage, int(shot["knockback"]), body.x, 0.0, "special")


## 다음에 던질 것이 강화인지 뽑는다 (#134). **뽑는 자리는 여기 하나다** —
## 여러 곳에서 뽑으면 손에 든 그림과 실제로 나가는 것이 갈린다.
##
## 확률은 던질 때 뽑던 때와 같다. 언제 뽑느냐만 앞당긴 것이다.
## `empowered_chance`가 없는 무기는 항상 false다 —
## 지금 이 값을 가진 것은 폭탄(데미지·넉백 증가)과 표창(빨간 표창, 위치 교환)뿐이다.
func _roll_empowered(weapon_id: String) -> bool:
	var chance: float = Weapons.get_weapon(weapon_id).get("empowered_chance", 0.0)
	return chance > 0.0 and randf() < chance


## 평행 다발의 세로 offset 목록 (#128).
##
## **가운데를 0으로 두고 위아래 대칭으로 벌린다.** 홀수면 한 발이 정확히 가운데로,
## 짝수면 가운데를 비우고 양쪽으로 갈라진다 — 어느 쪽이든 조준점이 다발 한가운데다.
## 0부터 세면 다발이 위로만 쏠려서 조준한 곳보다 높게 나간다.
func _parallel_offsets(count: int, spacing: float) -> Array[float]:
	if count <= 1:
		return [0.0]
	var offsets: Array[float] = []
	var middle := (float(count) - 1.0) * 0.5
	for i in count:
		offsets.append((float(i) - middle) * spacing)
	return offsets


## 발사 속도. 각도가 0이면 지금까지처럼 정확히 수평이다.
##
## **좌우 어느 쪽으로 쏘든 "위로" 나가야 한다** — 각도를 그대로 더하면 한쪽은 위로,
## 반대쪽은 아래로 나간다. 그래서 회전량에 방향(`dir`)을 곱한다.
## 화면 좌표는 y가 아래로 커지므로 위가 음수다.
func _launch_velocity(dir: float, angle_degrees: float,
		speed := Combat.PROJECTILE_SPEED) -> Vector2:
	var flat := Vector2(dir * speed, 0.0)
	if is_zero_approx(angle_degrees):
		return flat
	return flat.rotated(-deg_to_rad(angle_degrees) * dir)


## 투사체 노드를 만들어 화면에 붙인다.
func _spawn_projectile(data: Dictionary) -> void:
	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	projectile.name = "Projectile_%d" % int(data["id"])
	projectile.setup(data)
	projectile.finished.connect(_on_projectile_finished)
	projectile.picked_up.connect(_on_dagger_picked_up)
	projectile.swapped.connect(_on_positions_swapped)
	projectile.struck.connect(_on_lightning_struck)
	projectile.sparked.connect(_on_dagger_sparked)
	projectile.burst.connect(_on_cannon_burst)
	projectile.exploded.connect(_on_bomb_exploded)
	projectiles_root.add_child(projectile)


## 다 쓴 투사체를 치운다.
func _on_projectile_finished(projectile: Projectile) -> void:
	projectile.queue_free()


## 단검을 주우면 다시 들고 있는 상태가 된다.
func _on_dagger_picked_up(player_id: int, projectile: Projectile) -> void:
	_dagger_held[player_id] = true
	projectile.queue_free()


# ─────────────────────────── 특수 공격 (Shift) ───────────────────────────
## 방향은 바라보는 방향(좌우)으로만 나간다.
## Player가 자기 키를 읽어 신호를 내므로, 여기서는 판정만 한다.

func _on_special_requested(player_id: int, long_press: bool) -> void:
	var attacker := get_player(player_id)
	var target := _opponent_of(player_id)
	if attacker == null or target == null or not attacker.can_act():
		return

	var weapon := Weapons.get_weapon(attacker.weapon_id)
	if weapon.is_empty():
		return

	var now := _now()
	if now < _special_ready_at.get(player_id, 0.0):
		return
	if not _execute_special(attacker, target, weapon, long_press):
		return
	_special_ready_at[player_id] = now + weapon["special_cooldown"]


## 무기별 특수 공격. 발동했으면 true (쿨타임이 돌아간다).
func _execute_special(attacker: Player, target: Player, weapon: Dictionary, long_press: bool) -> bool:
	var player_id: int = attacker.player_id
	match weapon["name"]:
		"검":
			# 일정 거리 안에 상대가 있을 때만 쓸 수 있다. 밖이면 발동 자체를 안 해서
			# 쿨타임도 돌지 않는다 — 허공에 대고 쿨타임만 날리는 일이 없게 한다.
			var sword_range: float = weapon["special_range"]
			if attacker.global_position.distance_to(target.global_position) > sword_range:
				return false
			# 거리만 맞으면 들어간다. 빛기둥이 상대에게 꽂히는 연출이라 휘두르는 방향이나
			# 상대 무기의 막기(is_blocked)는 따지지 않는다.
			#
			# **누른 프레임에 때리지 않는다** (#247). 검을 머리 위로 들어 올렸다
			# 내려베고, 다 내려온 순간에 들어간다 — 손에 든 검이 가만히 있는데
			# 상대가 맞으면 무엇이 때렸는지 화면에서 읽히지 않는다(강펀치 #231과 같은 이유).
			# 그림은 `Player` 가 시작 시각 하나로 그리고, 판정 시각은
			# `_tick_sword_swings()`가 잰다. 쿨타임은 지금까지처럼 누른 순간부터 돈다.
			attacker.start_swing(weapon["special_windup"], weapon["special_swing"])
			_sword_swings[player_id] = {
				"at": _now() + float(weapon["special_windup"]) + float(weapon["special_swing"]),
				"hp_ratio": weapon["special_hp_ratio"],
				"knockback": weapon["knockback"],
			}
			return true
		"망치":
			# 때리지 않고 **능력을 건다** — `special_duration` 동안 기본 공격에
			# `stun_duration` 짜리 기절이 얹힌다 (`_try_melee_basic` 의 `stun_bonus()`).
			# 전에는 즉시 한 번 때리고 끝이었는데(`_melee_special()`), 그것은 이 무기의
			# 기획("공격마다 적에게 기절 효과를 부여")과 다른 동작이었다.
			# **망치가 그 함수의 마지막 사용자였으므로 함수도 함께 지웠다** —
			# 남겨 두면 아무도 부르지 않는 판정 코드가 되어, 다음에 읽는 사람이
			# 근접 특수가 저기로도 들어간다고 믿게 된다.
			#
			# `target` 을 보지 않으므로 **상대가 사거리 밖이어도 켜진다** — 광선검의
			# 관통과 같다. 능력을 켜는 특수는 지금 상대가 어디 있는지와 상관이 없다.
			attacker.apply_buff("stun", weapon["stun_duration"],
				weapon["special_duration"])
			return true
		"글러브":
			# "단거리 주먹 발사" — 글러브가 손에서 분리되어 연달아 날아간다 (#161·#164).
			# 옛 구현은 사거리만 1.5배 늘린 즉시 판정이라 화면에 아무것도 안 나타났다.
			# **발 수**로 끝나고(6발), **첫 발만 세게 민다**. 정해진 거리를 날아가면
			# 사라지는 것은 기획서의 "단거리"를 지키기 위한 것이다.
			_start_burst(player_id, weapon["special_damage"], Combat.Knockback.WEAK,
				weapon["burst_interval"], 0.0, weapon["burst_shots"], weapon["knockback"], {
					"art_file": weapon["projectile_file"],
					# 원화의 앞이 위가 아니라 오른쪽이다.
					"art_points_right": weapon["projectile_points_right"],
					"max_distance": weapon["special_distance"],
					"speed": weapon["projectile_speed"],
				})
			return true
		"너클":
			return _punch_cone(attacker, weapon)
		"광선검":
			# 관통 — 일정 시간 상대 무기의 막기를 무시한다.
			attacker.apply_buff("pierce", 1.0, weapon["special_duration"])
			return true
		"장대":
			# 상시 사거리(`reach_multiplier`)가 아니라 **특수 전용 배율**을 쓴다.
			# 상시로 걸면 특수를 쓰지 않아도 근접 공격을 전부 막는다 (막기 판정 참고).
			attacker.apply_buff("reach", weapon["special_reach_multiplier"],
				weapon["special_duration"])
			return true
		"전기톱":
			# **제자리 회전 후 관통 돌진** (#260). 누른 프레임에 튀어 나가지 않고
			# `spin_time` 동안 제자리에서 톱을 돌린 뒤 돌진한다 — 넘어가는 것은
			# `Player._apply_forced()`가 하고, 돌진 자체는 지금까지와 같다(속도는 일반
			# 점프의 두 배, 벽에 부딪히면 끝난다).
			#
			# 예약(`_special_pending`)은 **누른 순간 걸어 둔다.** `modes`가 `dash`뿐이라
			# 도는 동안에는 닿아도 안 맞고, 돌진으로 넘어가는 순간부터 판정이 열린다 —
			# 도끼가 `rise` 중에 예약을 들고 `fall`에서만 때리는 것과 같은 짜임이다.
			var spin: float = weapon.get("spin_time", 0.0)
			if spin > 0.0:
				attacker.start_forced("spin", spin)
			else:
				attacker.start_forced("dash", attacker.dash_time())
			_special_pending[player_id] = {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"modes": ["dash"],
				"bleed_dps": weapon["bleed_damage"],
				"bleed_duration": weapon["bleed_duration"],
				# 출혈 박자. 없으면 지금까지처럼 1초에 한 번이다.
				"bleed_interval": weapon.get("bleed_interval", 1.0),
			}
			return true
		"양날 도끼":
			# 고속 상승 후 고속 낙하. 데미지는 낙하 중에만 들어간다.
			# 낙하 중 직격을 놓치면 **착지할 때 주변을 때린다** (#167) — 그 수치를
			# 여기 같이 실어 둔다. `_on_forced_landed()`가 꺼내 쓴다.
			attacker.start_forced("rise", _rise_time())
			_special_pending[player_id] = {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"modes": ["fall"],
				"landing_damage": weapon["landing_damage"],
				"landing_radius": weapon["landing_radius"],
				"landing_rupture_speed": weapon["landing_rupture_speed"],
			}
			return true
		"활":
			# 관통 화살 여러 발 — 벌어진 평행. **발 수는 무기 표가 정한다** (#128).
			# 전에는 여기서 3발을 하드코딩해 표의 special_projectiles 가 죽은 값이었다.
			var count: int = weapon.get("special_projectiles", 1)
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"pierce_targets": true,
			}, _parallel_offsets(count, Combat.PARALLEL_SPACING))
			return true
		"대포 총":
			# 특수만 불꽃 꼬리 미사일이다 — 기본 공격 탄은 파란 구슬로 나간다
			# (무기 표의 `projectile_orb`; 전에는 공용 노란 막대였다).
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"missile": weapon.get("special_missile", false),
				"knockback_speed": weapon.get("special_knockback_speed", 0.0),
			})
			return true
		"삼지창":
			# 던지고 맞으면 기절. "자동 회수"는 지금은 사라지는 것으로 처리하고,
			# 돌아오는 연출은 그래픽 작업 때 붙인다.
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"stun": weapon["stun_duration"],
				# 날아가는 것이 삼지창 자신이므로 같은 그림으로 그린다 (#152).
				# 그림이 생기기 전에는 노란 막대였다.
				"art": weapon["name"],
				# 맞은 자리에 번개가 내려친다. 표에서 읽으므로 여기에 true를 박지 않는다.
				"hit_lightning": weapon.get("hit_lightning", false),
			})
			return true
		"샷건":
			# **원거리가 아니다.** 탄을 쏘지 않고 앞으로 퍼지는 부채꼴 안을 한 번 때린다 —
			# 코앞에서 쏟아붓는 산탄이라 화면을 가로지르지 않는다.
			_cone_blast(attacker, weapon)
			return true
		"표창":
			# 중력 영향을 받는다. 빨간 표창은 아래 폭탄과 **같은 틀**이다 (#134) —
			# 여기서 새로 뽑지 않고 미리 뽑아 손에 들고 있던 그것을 쓴다.
			# 여기서 뽑으면 손에 든 그림과 날아가는 것이 어긋난다.
			var swap: bool = attacker.empowered_ready
			# 빨간 표창은 그림이 따로다 — 데미지가 없고 위치가 바뀌는 것이라
			# 겉모습이 같으면 피할지 말지를 정할 근거가 화면에 없다 (#131).
			# 표에서 꺼낸 값은 Variant라 명시 타입으로 받는다 (#66).
			var shuriken_art: String = weapon["empowered_file"] if swap else weapon["file"]
			_server_fire(attacker, {
				"damage": weapon["empowered_damage"] if swap else weapon["special_damage"],
				"knockback": weapon["empowered_knockback"] if swap else weapon["knockback"],
				"use_gravity": true,
				"art_file": shuriken_art,
				# 폭탄의 강화가 데미지를 올리는 자리에, 이쪽은 위치 교환이 들어간다.
				"swap_positions": swap and weapon.get("empowered_swap", false),
			})
			# 던졌으니 다음 것을 새로 뽑는다 — 쿨타임 동안 손에 들려 보인다.
			attacker.set_empowered(_roll_empowered(attacker.weapon_id))
			return true
		"폭탄":
			# 던진 폭탄은 바닥에서 조금 구르다 멈추고, 3초 뒤 또는 닿으면 반경 200px을 때린다.
			# 강화 여부는 **미리 뽑아 손에 들고 있던 그것**을 쓴다 (#134).
			# 여기서 새로 뽑으면 손에 든 그림과 날아가는 것이 어긋난다.
			var empowered: bool = attacker.empowered_ready
			# 강화 폭탄은 그림이 따로다 — 데미지가 32 → 48인데 겉모습이 같으면
			# 피할지 말지를 정할 근거가 화면에 없다 (#131).
			# 표에서 꺼낸 값은 Variant라 명시 타입으로 받는다 (#66).
			var bomb_art: String = weapon["empowered_file"] if empowered else weapon["file"]
			_server_fire(attacker, {
				"damage": weapon["empowered_damage"] if empowered else weapon["special_damage"],
				"knockback": weapon["empowered_knockback"] if empowered else weapon["knockback"],
				"use_gravity": true,
				"on_solid": "roll",
				"art_file": bomb_art,
				# 진행 방향으로 돌리면 도화선이 앞을 향한다.
				"art_upright": true,
				"fuse": 3.0,
				"explosion_radius": 200.0,
			})
			# 던졌으니 다음 것을 새로 뽑는다 — 쿨타임 동안 손에 들려 보인다.
			attacker.set_empowered(_roll_empowered(attacker.weapon_id))
			return true
		"소총":
			# 한 번 누르면 지속시간 동안 자동 연사. **시간**으로 끝난다.
			_start_burst(player_id, weapon["special_damage"], weapon["knockback"],
				weapon["burst_interval"], weapon["burst_duration"], 0, -1)
			return true
		"단검":
			# 특수 = 자동 재수집. 주우러 가지 않아도 손으로 돌아온다.
			if _dagger_held.get(player_id, true):
				return false   # 이미 들고 있으면 쓸 것이 없다
			_dagger_held[player_id] = true
			for projectile: Projectile in projectiles_root.get_children():
				if projectile.pickup_owner == player_id:
					projectile.queue_free()
			return true
		"방패":
			# **하나뿐인 길게/짧게로 갈리는 특수다.** 길게(0.3초 이상, `Player.LONG_PRESS_TIME`)는
			# 크기 증가, 짧게는 던지기다. `long_press`는 `Player` 가 잰 것이고,
			# 길게가 확정되는 순간 뗄 때를 기다리지 않고 바로 발동한 뒤
			# 눌린 기록을 지운다 — 그래서 손을 뗄 때 던지기가 겹쳐 나가지 않고 쿨타임도
			# 한 번만 돈다 (`Player._check_long_press`·`_read_input` 참고).
			if long_press:
				attacker.apply_buff("size", weapon["size_multiplier"], weapon["special_duration"])
			else:
				_server_fire(attacker, {
					"damage": weapon["special_damage"],
					"knockback": weapon["knockback"],
					# 손에 든 것과 **같은 그림으로** 날아간다 (표창과 같은 이유다) —
					# 노란 막대로 날아가면 16 데미지짜리가 오는데 무엇이 오는지가
					# 화면에 없고, 크기 증가 쪽과 구별도 안 된다.
					"art_file": weapon["file"],
					# **원반처럼 돌면서 날아간다.** 세워 둔 채(`art_upright`) 날리면
					# 손에 든 모습 그대로 미끄러져 가고, 진행 방향으로 한 번 돌려 굳히면
					# (`_face()`의 기본 +90도) 넘어진 채 굳은 것으로 보인다 — 둘 다
					# 던진 것으로 안 보였다. 도는 값 하나가 그 자리를 대신한다.
					"art_spin": weapon["throw_spin"],
				})
			return true
		_:
			return false


# ─────────────────────────── 연출 ───────────────────────────
## 판정에 관여하지 않는 그림만. 판정이 결과를 정한 뒤 화면에 띄운다.
## 잠깐 떴다 스스로 사라지고 아무것도 맞히지 않으므로 나중에 지워 줄 것이 없다.

## 검 특수의 빛기둥. `at`은 맞은 젤리의 발밑이다.
func _play_light_burst(at: Vector2) -> void:
	var burst := LIGHT_BURST_SCENE.instantiate()
	effects_root.add_child(burst)
	burst.global_position = at


## 샷건 특수의 부채꼴. `at`은 총구 높이의 몸 중심이고 `aim`이 바라보는 쪽이다.
##
## 사거리·각도를 **판정과 같은 값으로** 넘긴다 — 여기서 다른 값을 주면 플레이어가
## 눈으로 배운 범위가 실제로 맞는 범위와 어긋난다 (폭탄 반경을 그린 이유 #140).
##
## **위치와 값을 `add_child` 전에 넣는다.** `_ready()`가 붙는 순간 돌면서 위치로 난수
## 씨앗을 잡기 때문이다 — 나중에 넣으면 모든 발사가 (0, 0)으로 같은 씨앗을 받는다.
func _play_shotgun_blast(at: Vector2, aim: float, reach: float, spread: float) -> void:
	var blast := SHOTGUN_BLAST_SCENE.instantiate()
	blast.position = at
	blast.aim = aim
	blast.reach = reach
	blast.spread = spread
	effects_root.add_child(blast)


## 강펀치가 곧 들어올 범위 (#231). 안쪽이 `windup`에 걸쳐 차오르므로 **언제 들어오는지**도
## 같이 보인다. 그리는 부채꼴은 실제로 맞는 부채꼴과 같다.
func _play_punch_range(at: Vector2, aim: float, reach: float, spread: float,
		charged: bool, windup: float) -> void:
	var range_hint := HEAVY_PUNCH_SCENE.instantiate()
	range_hint.position = at
	range_hint.aim = aim
	range_hint.reach = reach
	range_hint.spread = spread
	range_hint.charged = charged
	range_hint.preview = true
	range_hint.preview_time = windup
	effects_root.add_child(range_hint)


## 너클 강펀치의 부채꼴 (#225). `charged`면 다른 디자인으로 뜬다.
func _play_heavy_punch(at: Vector2, aim: float, reach: float, spread: float,
		charged: bool) -> void:
	var punch := HEAVY_PUNCH_SCENE.instantiate()
	# **위치를 add_child 전에 넣는다** — 연출이 `_ready()`에서 위치로 씨앗을 잡으므로
	# 나중에 넣으면 모든 강펀치가 같은 모양이 된다 (`heavy_punch.gd` 참고).
	punch.position = at
	punch.aim = aim
	punch.reach = reach
	punch.spread = spread
	punch.charged = charged
	effects_root.add_child(punch)


## 삼지창 특수가 맞혔다 (투사체가 알려 온다).
func _on_lightning_struck(at: Vector2) -> void:
	_play_lightning_strike(at)


## 단검이 맞혔다 (#250). 번개와 같은 짜임이다 — 탄은 신호만 내고 연출은 여기가 띄운다.
func _on_dagger_sparked(at: Vector2) -> void:
	_play_hit_sparks(at)


## 대포 총 포탄이 맞혔다 (투사체가 알려 온다). 위 둘과 같은 짜임이다.
func _on_cannon_burst(at: Vector2) -> void:
	_play_cannon_burst(at)


## 폭탄이 터졌다 (투사체가 알려 온다).
##
## **공용 피격음을 막지 않는다.** 틱 소리(위)와 달리 이건 0.2초마다 되풀이되는 것이
## 아니라 한 번뿐이고, 터진 것과 그 안에 누가 있었는지는 서로 다른 소식이다 —
## 빗나간 폭탄도 터지는 소리는 나야 하고, 맞았으면 맞은 소리가 겹쳐 나는 편이 맞다.
## 연출도 같은 자리에서 띄운다 (#262) — 터진 순간이 곧 이 신호다. 소리와 짝이라
## 빗나간 폭탄에도 함께 뜬다.
func _on_bomb_exploded(at: Vector2, blast_radius: float) -> void:
	_play_bomb_blast(at, blast_radius)


## 삼지창 특수의 번개. `at`은 맞은 젤리의 발밑이고, 줄기는 화면 위에서 거기까지 내려온다.
func _play_lightning_strike(at: Vector2) -> void:
	var bolt := LIGHTNING_STRIKE_SCENE.instantiate()
	# 위치를 붙이기 전에 넣는다 — `_ready()`가 이 값으로 줄기 모양의 씨앗을 잡는다.
	bolt.position = at
	effects_root.add_child(bolt)


## 단검에 맞은 자리에 튀는 빨간 알갱이 (#250). `at`은 날이 닿은 자리다.
##
## 위치를 붙이기 전에 넣는 것은 번개와 같은 이유다 — `_ready()`가 이 값으로 알갱이가
## 튀는 방향의 씨앗을 잡아서, 나중에 넣으면 모든 피격이 (0, 0)으로 같은 모양이 된다.
func _play_hit_sparks(at: Vector2) -> void:
	var sparks := HIT_SPARKS_SCENE.instantiate()
	sparks.position = at
	effects_root.add_child(sparks)


## 폭탄이 터지는 자리의 폭발 (#262). `at`은 터진 자리, `blast_radius`는 **판정에 쓰는
## 반경 그대로**다 — 연출의 고리가 닿는 자리가 곧 맞는 경계다. 둘이 따로 놀면 이 연출은
## 오히려 거짓말이 된다(착지 충격파 `_play_shockwave`와 같은 규칙).
##
## 위치를 붙이기 전에 넣는 것은 알갱이·번개와 같은 이유다 — `_ready()`가 이 값으로
## 살과 불티가 뻗는 방향의 씨앗을 잡아서, 나중에 넣으면 모든 폭발이 (0, 0)으로
## 같은 모양이 된다.
func _play_bomb_blast(at: Vector2, blast_radius: float) -> void:
	var blast := BOMB_BLAST_SCENE.instantiate()
	blast.position = at
	blast.radius = blast_radius
	effects_root.add_child(blast)


## 대포 총 포탄이 맞은 자리에서 터지는 푸른 충격. `at`은 탄이 닿은 자리다.
##
## 위치를 붙이기 전에 넣는 것은 알갱이·번개와 같은 이유다 — `_ready()`가 이 값으로
## 살과 알갱이가 뻗는 방향의 씨앗을 잡아서, 나중에 넣으면 모든 피격이 (0, 0)으로
## 같은 모양이 된다.
func _play_cannon_burst(at: Vector2) -> void:
	var burst := CANNON_BURST_SCENE.instantiate()
	burst.position = at
	effects_root.add_child(burst)


## 경기 표지 그림을 띄운다 (요청). 띄울 조건은 `_start_round()` 가 정한다 —
## **경기의 첫 판, 무기 선택이 열리기 전** 딱 한 번이다.
##
## 이 그림을 띄운 뒤 `MATCH_INTRO_TIME` 만큼 무기 선택을 미룬다 — 그동안
## 두 젤리는 얼려 둔다. 미루는 것도 얼리는 것도 부르는 쪽(`_start_round`)의 몫이다.
func _play_match_intro() -> void:
	match_intro.play()


## 포인트를 딴 순간의 장면 (이슈 #273). 점수를 적은 뒤에 띄운다.
##
## **한 화면이므로 딴 사람 기준으로만 보여준다** (#320). 두 기기 시절에는 서버가
## "누가 몇 점이 되었다" 하나만 보내고 그것을 자기 편으로 읽는지 남의 편으로 읽는지는
## 받는 쪽이 정했다 — 그래서 같은 순간에 한 기기에는 파란 띠가, 다른 기기에는 빨간
## 띠가 떴다. 지금은 화면이 하나뿐이라 가를 것이 없다.
func _play_point_gain(scorer_id: int, score_after: int, is_final: bool) -> void:
	var scorer := get_player(scorer_id)
	if scorer == null:
		return
	point_gain.play(scorer.player_name, scorer.character_id, score_after, true, is_final)


## 빨간 표창이 자리를 바꿨다 (투사체가 알려 온다).
func _on_positions_swapped(from_position: Vector2, to_position: Vector2) -> void:
	_play_swap_burst(from_position, to_position)


## 위치 교환 연출. **두 자리에 하나씩** 띄운다 — 하나만 띄우면 어디로 갔는지 알 수 없다.
##
## 받는 값은 **바꾸기 전의** 두 위치다. 각각이 "여기 있던 것이 떠났다"와
## "여기 있던 것이 저기로 갔다"를 동시에 뜻한다 — 서로 자리를 맞바꾼 것이므로 같은 두 점이다.
##
## 원점을 젤리 몸 한가운데로 올린다. 넘어오는 위치는 발밑 기준(`global_position`)이고,
## 몸 전체가 사라졌다 나타나는 연출이라 발밑에서 터지면 아래로 쏠려 보인다.
func _play_swap_burst(from_position: Vector2, to_position: Vector2) -> void:
	for at: Vector2 in [from_position, to_position]:
		var burst := SWAP_BURST_SCENE.instantiate()
		# **위치를 붙이기 전에 넣는다.** `_ready()`가 붙는 순간 돌면서 위치로 난수 씨앗을
		# 잡으므로, 나중에 넣으면 두 자리 모두 (0, 0)으로 같은 씨앗을 받아 같은 모양이 된다.
		burst.position = at + SWAP_BURST_CENTER
		effects_root.add_child(burst)


## 강제 낙하(양날 도끼)가 땅에 닿았다 — **좌우로 땅을 갈라 보낸다** (#167).
##
## 여기서는 시작만 한다. 실제로 때리는 것은 `_tick_ruptures()`가 앞선을 밀면서 하고,
## 그래서 멀리 선 상대는 가까이 선 상대보다 조금 늦게 맞는다 — 착지 순간 반경을
## 한꺼번에 때리면 "갈라져 나간다"가 아니라 "닿으면 맞는다"가 된다.
##
## **낙하 중 직격을 놓쳤을 때만 들어간다.** 직격이 성공하면 `_check_pending_specials()`가
## 예약을 지우므로 여기 올 것이 없다 — 한 번의 특수로 두 번 맞는 일은 생기지 않는다.
func _on_forced_landed(player_id: int, at: Vector2) -> void:
	var info: Dictionary = _special_pending.get(player_id, {})
	var radius: float = info.get("landing_radius", 0.0)
	if radius <= 0.0:
		return
	_special_pending.erase(player_id)   # 착지로 기회를 다 썼다
	var speed: float = info.get("landing_rupture_speed", 0.0)
	if speed <= 0.0:
		return

	# 연출은 맞았는지와 무관하게 띄운다 — 빗나간 것도 "여기까지였다"로 보여야 한다.
	# 속도까지 넘겨서 **화면에 보이는 앞선이 곧 맞는 경계**가 되게 한다.
	_play_shockwave(at, radius, speed)

	var damage: float = info.get("landing_damage", 0.0)
	if damage <= 0.0:
		return
	# 착지 순간 반경을 한꺼번에 때리지 않는다. 앞선이 거기까지 가는 데 걸리는 시간이
	# 있어야 "갈라져 나간다"로 읽히고, 멀리 선 상대는 조금 늦게 맞는다.
	_ruptures.append({
		"owner": player_id,
		"at": at,
		"damage": damage,
		"knockback": info["knockback"],
		"reach": radius,
		"speed": speed,
		"started": _now(),
		# 앞선은 지나가면서 한 번만 때린다 — 매 프레임 판정이라 이게 없으면
		# 앞선 안에 서 있는 동안 계속 맞는다.
		"hit": {},
	})


## 땅 격파의 앞선을 좌우로 밀고, 닿는 상대를 한 번씩 때린다.
##
## **가로 거리로만 잰다.** 땅을 타고 갈라져 나가는 것이라 위아래로 퍼지는 것이 아니다.
## 대신 다른 높이의 발판에 선 상대는 맞지 않아야 해서 세로로 한 몸통(BODY_HEIGHT)까지만
## 같은 땅으로 본다 — 그게 없으면 머리 위 발판에 있는 상대도 같이 맞는다.
##
## 좌우(`_faces()`)도 상대 무기 막기(`is_blocked()`)도 보지 않는다. 바로 아래를 때리는
## 기술이라 좌우를 따지면 영영 안 맞고, 땅을 타고 오는 것이라 앞으로 든 무기와 무관하다.
func _tick_ruptures() -> void:
	var now := _now()
	for i in range(_ruptures.size() - 1, -1, -1):
		var rupture: Dictionary = _ruptures[i]
		var origin: Vector2 = rupture["at"]
		var front: float = (now - float(rupture["started"])) * float(rupture["speed"])
		var reach: float = rupture["reach"]
		for target: Player in players_root.get_children():
			var target_id: int = target.player_id
			if target_id == rupture["owner"] or not target.alive:
				continue
			if rupture["hit"].has(target_id):
				continue
			if absf(target.global_position.y - origin.y) > Player.BODY_HEIGHT:
				continue
			var span := absf(target.global_position.x - origin.x)
			if span > minf(front, reach):
				continue
			rupture["hit"][target_id] = true
			target.apply_hit(rupture["damage"], rupture["knockback"],
				origin.x, 0.0, "special")
		if front >= reach:
			_ruptures.remove_at(i)


## 착지 땅 격파. `at`은 떨어진 자리, `radius`는 **좌우 각각 실제로 맞는 거리**,
## `speed`는 앞선이 뻗어 나가는 속도다 — 셋 다 판정에 쓰는 값 그대로다.
## 보이는 것과 맞는 범위가 어긋나면 이 연출이 거짓말이 된다.
func _play_shockwave(at: Vector2, radius: float, speed: float) -> void:
	var wave := SHOCKWAVE_SCENE.instantiate()
	wave.radius = radius
	wave.speed = speed
	effects_root.add_child(wave)
	wave.global_position = at + Vector2(0.0, Player.BODY_BOTTOM)


## 상승에서 낙하로 넘어가는 시점. 일반 점프가 정점에 닿는 시간의 두 배 속도이므로 절반이다.
func _rise_time() -> float:
	return absf(Player.JUMP_VELOCITY) / Player.FORCED_SPEED * 0.5


# ─────────────────────────── 표시 ───────────────────────────

func _process(_delta: float) -> void:
	_update_hud()


## 라운드 포인트 표시. 왼쪽 칸이 1P, 오른쪽 칸이 2P다.
##
## 라벨은 흰 카드(`ScoreCard`) **안**에 들어 있다 — 카드 밖에 두면 맵 배경 위에 그대로
## 그려져서 어두운 맵(용암)에서 진한 글자가 묻힌다(이슈 #112).
##
## **화면 좌우 맨 위에는 이제 아무것도 없다** (이슈 #317, 요청). 늘 떠 있던 체력 바와
## 숫자는 맞은 순간 젤리 머리 위에 2초만 뜨는 바(`health_bar.gd`)로 옮겼고, 남아 있던
## 이름·무기 카드(`P1Card`·`P2Card`)도 걷어냈다 — 이름은 젤리 머리 위 `NameLabel` 이
## 이미 달고 있고 무기는 손에 든 그림으로 읽힌다. 싸우는 동안 눈이 가지 않는 자리에
## 같은 것을 한 번 더 적고 있던 셈이다.
##
## 남은 것은 승패를 가르는 유일한 조건인 라운드 포인트뿐이고, 그것을 맨 위 가운데로 올렸다.
func _update_hud() -> void:
	var score_card := $UI/HUD.get_node("ScoreCard")
	for slot in GameState.PLAYER_COUNT:
		var score_label := score_card.get_node("P%dScore" % (slot + 1)) as Label
		var player_id := GameState.id_at(slot)
		score_label.text = _score_text(int(scores.get(player_id, 0)), slot == 1)

	var banner_label := $UI/HUD.get_node("Banner") as Label
	banner_label.text = banner
	# 결과 화면이 떠 있으면 그쪽 글자와 겹치므로 배너는 접는다.
	banner_label.visible = banner != "" and not result_overlay.visible


## 딴 포인트는 채운 동그라미, 남은 포인트는 빈 동그라미로 보여주고 숫자를 함께 적는다.
## 동그라미만 있으면 몇 포인트 중 몇 포인트인지 한눈에 안 읽힌다 (3포인트 선취).
##
## `mirrored` 는 가운데 카드의 **오른쪽 칸(2P)**이다 (이슈 #317). 한 카드 안에 두 편이
## 마주 보고 앉으므로 오른쪽은 숫자와 동그라미의 순서를 뒤집어 좌우 대칭으로 만든다 —
## 딴 만큼이 양쪽에서 가운데를 향해 차오르는 모양이 된다.
## 선취 점수(`/ 3`)는 더 이상 적지 않는다. 동그라미 개수 자체가 그 수이고, 좁은 가운데
## 카드에 두 번 적으면 정작 몇 대 몇인지가 글자에 묻힌다.
func _score_text(score: int, mirrored: bool) -> String:
	var filled := clampi(score, 0, Combat.POINTS_TO_WIN)
	var empty := Combat.POINTS_TO_WIN - filled
	if mirrored:
		return "%d  %s" % [filled, "●".repeat(filled) + "○".repeat(empty)]
	return "%s  %d" % ["○".repeat(empty) + "●".repeat(filled), filled]


func _unhandled_input(event: InputEvent) -> void:
	# ESC로 경기를 그만두고 타이틀로 돌아간다
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/title.tscn")
