extends Node2D
## 전투 화면. 서버가 접속한 클라이언트마다 플레이어를 하나씩 스폰하고,
## 공격 판정을 **서버에서만** 실행해 결과를 양쪽에 복제한다.
##
## 무기 수치는 scripts/weapons.gd, 공통 수치는 scripts/combat.gd에 있다.
## 플레이어의 체력·상태이상은 Player의 server_* 함수로 전달한다.
## 통합 가이드: docs/weapon-system.md
##
## 포인트 진행(쓰러뜨리면 1포인트·3포인트 선취)도 여기가 주인이다. 판정은 전부 서버에서 하고
## 결과만 `_receive_round`로 복제한다 — 클라이언트는 점수를 세지 않는다.
##
## **관전자도 이 씬을 본다**(이슈 #167). 스폰을 받지 않아 자기 젤리가 없고 입력도 보내지 않지만,
## 지형·플레이어·투사체·HUD는 복제로 그대로 보인다.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const LIGHT_BURST_SCENE := preload("res://scenes/light_burst.tscn")
const SWAP_BURST_SCENE := preload("res://scenes/swap_burst.tscn")
const LIGHTNING_STRIKE_SCENE := preload("res://scenes/lightning_strike.tscn")
const SHOTGUN_BLAST_SCENE := preload("res://scenes/shotgun_blast.tscn")
const SHOCKWAVE_SCENE := preload("res://scenes/shockwave.tscn")
## 위치 교환 연출을 띄울 높이 보정. 젤리의 `global_position`은 충돌 상자(48x56)의
## 가운데이고 몸(72px)은 발밑이 +`Player.BODY_BOTTOM`(28)이라, 몸 한가운데가 -8이다.
## 검 특수의 빛기둥은 반대로 발밑(+28)에 띄운다 — 거기서 위로 솟는 연출이라서다.
const SWAP_BURST_CENTER := Vector2(0.0, -8.0)
## 맵에 Spawns가 없을 때만 쓰는 대비값. 정상 경로에서는 맵 씬이 위치를 들고 있다.
const SPAWN_POSITIONS := [Vector2(300, 500), Vector2(852, 500)]

## 근접 "닿으면" 판정 거리. 젤리 몸통이 48px이므로 두 몸통이 맞닿는 거리다.
## 무기별 사거리는 player.current_reach()로 더한다.
const MELEE_REACH := 48.0

## 라운드마다 제시할 무기 후보 수 (#205). `weapon_pick.tscn`의 카드 수와 같아야 한다 —
## 카드가 모자라면 뽑아 놓고 못 보여주고, 남으면 빈 카드가 나온다.
const WEAPON_CHOICES := 3
## 무기 선택 제한 시간(초). 다 되면 서버가 후보 중 하나를 대신 뽑는다 —
## 한 사람이 자리를 비웠다고 경기가 그 자리에서 영영 멈추면 안 된다.
const WEAPON_PICK_TIME := 20.0

## 싸울 사람이 부족한 채로 이만큼 지나면 판을 접는다.
##
## **경기가 시작된 직후에는 아무도 스폰되어 있지 않다** — 클라이언트가 전투 화면을
## 불러온 뒤에야 `_notify_ready()`로 알리고 그때 서버가 스폰한다. 그 시간을 기다려
## 주지 않으면 시작하자마자 판을 접어 버린다. 씬 로드보다 넉넉하게 잡는다.
const ABANDON_GRACE_SEC := 15.0

## 아래 상태는 전부 **서버에서만** 쓴다. 클라이언트에서는 비어 있다.
## "공격자peer>피격자peer" -> 다음 기본 공격이 들어갈 수 있는 시각
var _next_hit_at := {}
## peer -> 특수 공격 쿨타임이 끝나는 시각
var _special_ready_at := {}
## 강제 이동 중에 한 번만 터지는 특수 공격 (전기톱 돌진, 양날 도끼 낙하).
var _special_pending := {}
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
## 경기가 끝났으면 더 이상 라운드를 시작하지 않는다.
var _match_over := false

## 무기 선택이 진행 중인가 (#205). 켜져 있는 동안 두 젤리는 얼어 있다.
var _picking := false
## peer -> 그 사람에게 제시한 무기 이름 배열 (서버 전용).
var _pick_options := {}
## peer -> 고른 무기 이름 (서버 전용). 후보를 받은 사람이 전부 여기 들어오면 라운드가 열린다.
var _pick_choices := {}
## 안 고른 사람 몫을 서버가 대신 뽑을 시각. 0이면 선택 중이 아니다.
var _pick_deadline := 0.0
## 이번 선택에서 내가 고르는 쪽인가 · 이미 보냈는가 (**클라이언트 전용, 안내 문구용**).
## 판정에는 안 쓴다 — 서버가 자기 표(`_pick_choices`)로 다시 확인한다.
var _pick_is_mine := false
var _pick_sent := false
## 대기실로 돌려보낼 시각. 0이면 예약 없음.
var _return_at := 0.0
## 싸울 사람이 부족해진 시각. 0이면 부족하지 않다 (`ABANDON_GRACE_SEC` 참고).
var _short_handed_since := 0.0

## 아래 둘은 서버가 정하고 모든 피어에 복제된다 — HUD가 읽는다.
## peer_id -> 점수
var scores := {}
## 화면 가운데 안내. ""이면 아무것도 표시하지 않는다.
var banner := ""

## 현재 깔린 맵 지형과 그 즉사 구역 (물·용암). 없는 맵이면 _hazard가 null이다.
var _map: Node2D = null
var _hazard: Area2D = null

## 결과 화면(승리·패배 연출)에서 도는 트윈. 화면을 접을 때 전부 끊는다.
var _result_tweens: Array[Tween] = []
## 연출로 옮기기 전의 제자리. 첫 재생 때 한 번만 재고 그 뒤로는 여기로 되돌린다.
var _jelly_home := Vector2.ZERO
var _label_home := Vector2.ZERO
var _homes_measured := false

## 승리·패배 글자 색 (ui_theme.tres 팔레트).
const WIN_COLOR := Color(0.96, 0.55, 0.78)
const LOSE_COLOR := Color(0.72, 0.70, 0.80)

@onready var map_root: Node2D = $MapRoot
@onready var players_root: Node2D = $Players
@onready var projectiles_root: Node2D = $Projectiles
@onready var effects_root: Node2D = $Effects
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var projectile_spawner: MultiplayerSpawner = $ProjectileSpawner
@onready var result_overlay: Control = $UI/HUD/ResultOverlay
## weapon_pick.gd는 class_name이 없어 타입을 붙이지 않는다 (jelly_preview.gd와 같은 방식).
@onready var weapon_pick = $UI/HUD/WeaponPick
## jelly_preview.gd는 class_name이 없어 타입을 붙이지 않는다 (player_panel.gd와 같은 방식).
@onready var result_jelly = $UI/HUD/ResultOverlay/Jelly
@onready var result_label: Label = $UI/HUD/ResultOverlay/ResultLabel
@onready var result_score: Label = $UI/HUD/ResultOverlay/ScoreLabel


func _ready() -> void:
	$UI/HUD/MapCard/MapLabel.text = "맵: " + Lobby.map_name
	# 지형은 모든 피어에서 똑같이 깔려야 한다 — 스폰보다 먼저 붙인다.
	# 서버가 대기실에서 "랜덤"을 확정해 두므로 양쪽이 같은 맵을 받는다.
	_load_map(Lobby.map_name)
	# 스폰 함수는 모든 피어에서 등록되어야 한다 — 서버 판정보다 먼저 설정한다.
	player_spawner.spawn_function = _spawn_player
	projectile_spawner.spawn_function = _spawn_projectile

	# 경기가 끝나면 서버 지시로 대기실에 돌아간다 (서버 자신은 이 씬에 머문다).
	Lobby.match_ended.connect(_on_match_ended)
	# 접속이 끊기면 멈춘 화면에 남지 않고 타이틀로 나간다 (이슈 #184).
	# 관전자가 방을 옮기면서 접속 종료가 평상시 일어나는 일이 되었다.
	Network.join_failed.connect(_on_disconnected)
	# 라운드마다 뜨는 무기 선택 카드 (#205). 전용 서버는 화면이 없어 열 일이 없지만
	# 연결은 양쪽에서 해 둔다 — 서버도 이 씬을 그대로 쓴다.
	weapon_pick.weapon_chosen.connect(_on_weapon_chosen)

	if multiplayer.is_server():
		Network.peer_left.connect(_on_peer_left)
	else:
		# 씬이 준비된 뒤에 서버에 알린다. 접속 직후 바로 스폰하면
		# 클라이언트가 아직 이 씬을 로드하기 전이라 스폰을 놓칠 수 있다.
		_notify_ready.rpc_id(1)
		_setup_observer_view()


## 관전자 화면. 조작할 것이 없으니 조작 안내를 나가는 방법으로 바꿔 준다 (이슈 #167).
## 자기 젤리가 없다는 것 말고는 플레이어 화면과 같다 — HUD·배너·투사체가 다 보인다.
func _setup_observer_view() -> void:
	if not Lobby.is_observer(multiplayer.get_unique_id()):
		return
	$UI/HUD/HintCard/ControlsHint.text = "관전 중 — 이 기기는 경기를 보기만 합니다
접속 종료: ESC"


## 클라이언트가 전투 화면 준비를 마쳤음을 서버에 알린다.
@rpc("any_peer", "call_remote", "reliable")
func _notify_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# 이 씬에 들어온 피어만 전투 노드의 RPC·스폰 대상이 된다 — 관전자도 여기에 들어간다.
	# 등록되는 순간 `Sync` 가시성 필터가 통과로 바뀌어 **이미 스폰된 젤리가 그 피어에게 간다**.
	Lobby.server_add_viewer(sender)
	# 진행 중인 점수와 배너를 그 피어에게만 보낸다 (이슈 #182) — 경기 도중에 들어온 관전자는
	# 지난 방송을 못 받았으므로, 안 보내면 다음 득점까지 0 : 0 을 보게 된다.
	_receive_round.rpc_id(sender, scores, banner)
	# 무기 선택 중에 들어온 피어에게도 지금 단계를 알린다 (#205). 안 보내면 두 젤리가
	# 멈춰 있는 화면만 보다가 다음 라운드에야 무슨 일이었는지 알게 된다.
	if _picking:
		_receive_pick_start.rpc_id(sender, _pick_options, maxf(_pick_deadline - _now(), 0.0))
	# 관전자에게는 젤리를 주지 않는다. 스폰하면 셋째 플레이어가 판에 끼어든다.
	if Lobby.is_observer(sender):
		return
	_add_player(sender)


func _add_player(peer_id: int) -> void:
	if players_root.has_node("Player_%d" % peer_id):
		return
	# 슬롯과 선택값은 대기실에서 서버가 확정한 것을 그대로 쓴다
	var index: int = Lobby.slot_of(peer_id)
	if index < 0:
		index = players_root.get_child_count()
	var config: Dictionary = Lobby.config_for(peer_id)
	# **빈손으로 스폰한다** (#205). 무기는 대기실이 아니라 라운드 시작의 선택이 정하므로
	# 이 시점에는 아직 아무것도 안 들었다 — `Weapons.get_weapon("")`이 빈 표를 돌려주어
	# 판정도 그림도 없는 상태가 된다. 곧바로 선택이 열리므로 오래 가는 상태는 아니다.
	# 강화 뽑기(#134)도 무기가 정해진 뒤라야 뜻이 있어서 `_finish_pick_phase()`로 옮겼다.
	var player := player_spawner.spawn({
		"peer_id": peer_id,
		"index": index,
		"weapon_id": "",
		"character": config["character"],
		"empowered": false,
	}) as Player
	if player == null:
		return
	# 특수 공격 요청과 사망은 서버에서만 발생한다.
	player.special_requested.connect(_on_special_requested)
	player.died.connect(_on_player_died)
	# 강제 낙하(양날 도끼)가 땅에 닿는 순간도 서버에서만 온다 (#167).
	player.landed_forced.connect(_on_forced_landed)
	_dagger_held[peer_id] = true
	if not scores.has(peer_id):
		scores[peer_id] = 0
	_broadcast_round(banner)

	# 두 사람이 다 들어왔으면 첫 라운드를 연다 (#205). 라운드가 무기 선택으로 시작하게
	# 되면서 "첫 판"에도 여는 순간이 필요해졌다 — 전에는 스폰이 곧 시작이었다.
	if not _match_over and not _picking and players_root.get_child_count() >= Network.MAX_PLAYERS:
		_start_round()


## 모든 피어에서 호출되어 플레이어 노드를 만든다. 반환한 노드는 spawn_path 아래에 붙는다.
func _spawn_player(data: Dictionary) -> Node:
	var peer_id: int = data["peer_id"]
	var index: int = data["index"]
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = "Player_%d" % peer_id
	player.owner_peer_id = peer_id
	player.player_name = "%dP" % (index + 1)
	player.weapon_id = data["weapon_id"]
	player.character_id = data["character"]
	player.empowered_ready = data.get("empowered", false)
	player.position = _spawn_position(index)
	player.facing = _spawn_facing(index)
	return player


func _on_peer_left(peer_id: int) -> void:
	# 전투 화면 목록에서 빼는 것은 Lobby 가 접속 종료를 받아 직접 한다 — 여기는 판만 정리한다.
	var player := players_root.get_node_or_null("Player_%d" % peer_id)
	# 관전자가 나간 것이라면 판에 손댈 것이 없다 — 아래 정리를 그냥 돌리면
	# 남은 두 사람의 공격 간격(_next_hit_at)까지 날려서 경기가 영향을 받는다.
	if player == null:
		return
	player.queue_free()
	_special_ready_at.erase(peer_id)
	_special_pending.erase(peer_id)
	_bleeds.erase(peer_id)
	_bursts.erase(peer_id)
	_dagger_held.erase(peer_id)
	# 키가 "공격자>피격자" 조합이라 한쪽이 빠지면 전부 의미가 없어진다.
	_next_hit_at.clear()

	# 고르던 사람이 나갔다 (#205). 그 사람 몫을 지우고, 남은 사람이 이미 골랐으면
	# 기다릴 이유가 없으니 바로 라운드를 연다 — 안 그러면 제한 시간까지 멈춰 있는다.
	_pick_options.erase(peer_id)
	_pick_choices.erase(peer_id)

	# 싸우던 사람이 빠졌다 — 1 VS 1 이 성립하지 않으면 판을 접는다.
	# 여기서 안 접으면 `Lobby.in_match` 가 켜진 채로 남아 다음 경기를 시작할 수 없다.
	# 선택 중이었어도 여는 것이 아니라 접는 쪽이 먼저다 — 혼자 남은 판을 열 이유가 없다.
	if Lobby.in_match and not _match_over and _fighter_count() < Network.MAX_PLAYERS:
		_abandon_match()
		return

	if _picking and _all_picked():
		_finish_pick_phase()


# ─────────────────────────── 라운드 진행 (서버 판정) ───────────────────────────

## 죽은 쪽의 상대가 1포인트를 얻는다. 3포인트면 경기가 끝나고, 아니면 다음 판을 예약한다.
## 화면에는 "누가 이겼다"가 아니라 "누가 1포인트를 얻었다"로 보여준다.
func _on_player_died(peer_id: int) -> void:
	if not multiplayer.is_server() or _match_over:
		return
	# 이미 이번 판의 포인트가 나갔다 — 대기 중에 남은 쪽이 또 떨어져도 점수를 주지 않는다.
	if _round_restart_at > 0.0:
		return
	var scorer := _opponent_of(peer_id)
	if scorer == null:
		_round_restart_at = _now() + Combat.ROUND_RESTART_DELAY
		_broadcast_round("")
		return

	# 이긴 쪽만 여기서 포즈를 갈아 준다 (#176) — 죽은 쪽은 _check_death()가 이미
	# 모든 피어에서 패배 포즈를 걸었다. 다음 라운드가 시작되면 둘 다 평소로 돌아온다.
	scorer.server_set_pose(Characters.POSE_WIN)

	var id := scorer.owner_peer_id
	scores[id] = int(scores.get(id, 0)) + 1

	if int(scores[id]) >= Combat.POINTS_TO_WIN:
		_match_over = true
		_return_at = _now() + Combat.MATCH_END_DELAY
		_broadcast_round("%s 승리!  %d포인트 달성" % [scorer.player_name, Combat.POINTS_TO_WIN])
		# 점수를 먼저 보내고 결과를 알린다 — 결과 화면이 최종 점수를 읽는다.
		_receive_match_result.rpc(id)
		return

	_round_restart_at = _now() + Combat.ROUND_RESTART_DELAY
	_broadcast_round("%s +1 포인트" % scorer.player_name)


## 양쪽을 되살리고 판을 깨끗이 만든다. 여기서 안 지운 값은 다음 라운드로 새어 나간다.
func _start_round() -> void:
	_round_restart_at = 0.0
	_hide_result()

	for projectile in projectiles_root.get_children():
		projectile.queue_free()

	_next_hit_at.clear()
	_special_ready_at.clear()
	_special_pending.clear()
	_bleeds.clear()
	_bursts.clear()
	_ruptures.clear()

	for player: Player in players_root.get_children():
		var index := maxi(Lobby.slot_of(player.owner_peer_id), 0)
		player.server_reset(_spawn_position(index), _spawn_facing(index))
		_dagger_held[player.owner_peer_id] = true

	_broadcast_round("")
	# 판을 치웠으면 곧바로 싸우는 것이 아니라 **무기부터 고른다** (#205).
	# 강화 뽑기(#134)가 여기서 빠진 것은 그래서다 — 무기가 정해진 뒤에 뽑아야
	# 이번 라운드에 들 무기로 뽑는다.
	_begin_pick_phase()


# ──────────────────────── 무기 선택 (서버 판정, #205) ────────────────────────
## 라운드는 **무기 선택으로 열린다.** 두 사람이 각자 후보 3개 중 하나를 고르고,
## 둘 다 고르면(또는 제한 시간이 지나면) 그때부터 판이 돈다.
##
## **후보는 서버가 뽑는다.** 클라이언트가 각자 뽑으면 화면에 보이는 카드와 서버가 아는
## 후보가 어긋나서, 고른 것이 엉뚱한 무기로 확정된다 — 대기실의 "랜덤"을 서버가
## 확정했던 것과 같은 이유다.


## 고를 동안 젤리를 얼리고 후보를 뽑아 각자에게 보낸다.
func _begin_pick_phase() -> void:
	if not multiplayer.is_server() or _match_over:
		return
	_pick_options.clear()
	_pick_choices.clear()
	for player: Player in players_root.get_children():
		# 카드를 읽는 사람이 그 자리에서 맞지 않도록 조작과 판정을 함께 잠근다.
		player.server_set_frozen(true)
		_pick_options[player.owner_peer_id] = Weapons.random_choices(WEAPON_CHOICES)

	# 아직 아무도 없다 (전용 서버가 혼자 도는 사이). 열어 둘 판이 없으므로 시작하지 않는다 —
	# 사람이 들어오면 `_add_player()`가 다시 연다.
	if _pick_options.is_empty():
		_picking = false
		_pick_deadline = 0.0
		return

	_picking = true
	_pick_deadline = _now() + WEAPON_PICK_TIME
	for peer in Lobby.viewers:
		_receive_pick_start.rpc_id(peer, _pick_options, WEAPON_PICK_TIME)


## 클라이언트가 고른 카드를 알려 온다. 넘어오는 값은 **후보 배열에서의 자리**다 —
## 무기 이름을 받으면 후보에 없는 무기를 적어 보낼 수 있다.
@rpc("any_peer", "call_remote", "reliable")
func _receive_pick(index: int) -> void:
	if not multiplayer.is_server() or not _picking:
		return
	var sender := multiplayer.get_remote_sender_id()
	var choices: Array = _pick_options.get(sender, [])
	# 후보를 못 받은 피어(관전자)와 이미 고른 피어는 버린다 — 두 번째 요청을 받아 주면
	# 상대가 기다리는 동안 무기를 바꿔 가며 고를 수 있다.
	if choices.is_empty() or _pick_choices.has(sender):
		return
	if index < 0 or index >= choices.size():
		return
	_pick_choices[sender] = choices[index]
	for peer in Lobby.viewers:
		_receive_pick_made.rpc_id(peer, sender)
	if _all_picked():
		_finish_pick_phase()


## 후보를 받은 사람이 전부 골랐는가.
func _all_picked() -> bool:
	for peer_id in _pick_options:
		if not _pick_choices.has(peer_id):
			return false
	return true


## 고른 무기를 손에 쥐여 주고 라운드를 시작한다.
## 안 고른 사람 몫은 서버가 후보 중에서 뽑는다 — 기다리기만 해도 판은 열려야 한다.
func _finish_pick_phase() -> void:
	if not multiplayer.is_server() or not _picking:
		return
	_picking = false
	_pick_deadline = 0.0

	for peer_id in _pick_options:
		var player := get_player(peer_id)
		if player == null:
			continue
		var choices: Array = _pick_options[peer_id]
		var chosen: String = _pick_choices.get(peer_id, choices.pick_random())
		player.server_set_weapon(chosen)
		# 뽑기는 무기를 바꾼 **뒤에** 한다 (#134) — 지난 무기로 뽑으면 폭탄·표창이
		# 아닌 무기에서는 늘 false가 되어 강화가 영영 안 나온다.
		player.server_set_empowered(_roll_empowered(chosen))
		player.server_set_frozen(false)
		# 자리와 무적을 여기서 한 번 더 준다. 고르는 데 쓴 시간만큼
		# `Combat.ROUND_START_GRACE`가 이미 흘렀으므로, 판이 실제로 열리는 지금부터 새로 잰다.
		var index := maxi(Lobby.slot_of(peer_id), 0)
		player.server_reset(_spawn_position(index), _spawn_facing(index))
		_dagger_held[peer_id] = true

	_pick_options.clear()
	_pick_choices.clear()
	for peer in Lobby.viewers:
		_receive_pick_end.rpc_id(peer)


# ─────────────────────── 무기 선택 (클라이언트 화면, #205) ───────────────────────

## 무기 선택이 시작됐다. 후보 표에는 두 사람 몫이 다 들어 있고 화면은 **자기 몫만** 연다 —
## 상대 카드까지 보여주면 무엇을 들지 알고 고르는 다른 게임이 된다.
@rpc("authority", "call_remote", "reliable")
func _receive_pick_start(options: Dictionary, seconds: float) -> void:
	var mine: Array = options.get(multiplayer.get_unique_id(), [])
	_pick_is_mine = not mine.is_empty()
	_pick_sent = false
	if _pick_is_mine:
		weapon_pick.open(mine, seconds)
	else:
		weapon_pick.open_watching(seconds)


## 누가 골랐다. 관전자 화면은 그대로 두고, 고르는 사람에게만 상황을 알려 준다.
@rpc("authority", "call_remote", "reliable")
func _receive_pick_made(peer_id: int) -> void:
	if not _pick_is_mine or peer_id == multiplayer.get_unique_id():
		return
	if _pick_sent:
		weapon_pick.set_status("둘 다 골랐습니다 — 곧 시작합니다.")
	else:
		weapon_pick.set_status("상대가 먼저 골랐습니다. 고를 차례입니다.")


@rpc("authority", "call_remote", "reliable")
func _receive_pick_end() -> void:
	weapon_pick.close()


## 카드를 눌렀다 (클라이언트). 확정은 서버가 하므로 여기서는 보내기만 한다.
func _on_weapon_chosen(index: int) -> void:
	if multiplayer.is_server():
		return
	_pick_sent = true
	_receive_pick.rpc_id(1, index)


## 낙사 — 화면 밖으로 나가거나 즉사 구역(물·용암)에 닿으면 죽는다.
## 좌우 벽이 있고 즉사 구역이 없는 맵(평지·벽돌)에서는 일어나지 않는다.
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
			player.server_kill()


## 예약된 라운드 재시작·대기실 복귀를 처리한다.
func _tick_round() -> void:
	var now := _now()
	if _round_restart_at > 0.0 and now >= _round_restart_at:
		_start_round()
	# 제한 시간이 다 됐다 — 안 고른 사람 몫은 서버가 뽑고 라운드를 연다 (#205).
	if _picking and _pick_deadline > 0.0 and now >= _pick_deadline:
		_finish_pick_phase()
	if _return_at > 0.0 and now >= _return_at:
		_return_at = 0.0
		Lobby.server_end_match()
		_server_reset_match()
	_tick_abandon(now)


## 싸울 사람이 없는 판이 영원히 남지 않게 하는 마지막 안전망.
##
## 사람이 빠지는 것은 대개 `_on_peer_left()`가 먼저 잡는다. 하지만 **아직 스폰되지 않은
## 피어가 끊기면** 거기서는 잡을 수 없다 — 전투 화면에 그 피어의 노드가 없어서 나간 것이
## 싸울 사람인지 관전자인지 구별이 안 되기 때문이다. 경기 시작 직후(클라이언트가 씬을
## 불러오는 동안)에 끊기면 그 상태가 된다.
##
## 그렇게 남은 판은 화면상 "맵만 깔려 있고 아무도 없는" 모습이고, `Lobby.in_match`가
## 켜진 채라 **다음 경기를 시작할 수 없다**(`Lobby._check_start()`가 일찍 돌아간다).
## 서버는 씬을 벗어나지 않으므로 스스로 알아차리는 곳이 여기밖에 없다.
func _tick_abandon(now: float) -> void:
	# 경기 중이 아니면 셀 것이 없다 — 전용 서버는 경기 사이에도 이 씬에 그냥 머문다.
	if not Lobby.in_match or _match_over or _fighter_count() >= Network.MAX_PLAYERS:
		_short_handed_since = 0.0
		return
	if _short_handed_since == 0.0:
		_short_handed_since = now
		return
	if now - _short_handed_since >= ABANDON_GRACE_SEC:
		_abandon_match()


## 지금 판에서 싸우고 있는 사람 수.
## `queue_free()`는 프레임 끝에야 노드를 떼므로 **지워질 예정인 것은 빼고 센다** —
## 안 그러면 방금 나간 사람이 아직 싸우는 중으로 잡힌다.
func _fighter_count() -> int:
	var count := 0
	for player: Player in players_root.get_children():
		if not player.is_queued_for_deletion():
			count += 1
	return count


## 싸울 사람이 부족해 판을 접는다. 점수는 주지 않는다 — 이긴 것이 아니라 못 끝낸 것이다.
## 남은 사람과 관전자는 `_return_at`이 되면 대기실로 돌아간다(정상 종료와 같은 길).
func _abandon_match() -> void:
	_match_over = true
	_round_restart_at = 0.0
	_short_handed_since = 0.0
	# 선택을 열어 둔 채로 두면 제한 시간이 되어 `_finish_pick_phase()`가 판을 다시 연다 (#205).
	# 남은 사람의 카드도 닫아 준다 — 접힌 경기 위에 카드가 떠 있으면 고르라는 화면이 된다.
	if _picking:
		_picking = false
		_pick_deadline = 0.0
		for peer in Lobby.viewers:
			_receive_pick_end.rpc_id(peer)
	_pick_options.clear()
	_pick_choices.clear()
	# 고르는 동안 잠겼던 조작을 풀어 준다. 얼어 있는 채로 남으면 멈춘 화면으로 보인다.
	for player: Player in players_root.get_children():
		player.server_set_frozen(false)
	_return_at = _now() + Combat.MATCH_END_DELAY
	_broadcast_round("상대가 나가서 경기를 끝냅니다")


## 전용 서버는 씬을 벗어나지 않으므로 다음 경기를 위해 직접 판을 비운다.
## 이걸 안 하면 다음 경기에서 점수가 이어지고 플레이어가 다시 스폰되지 않는다.
func _server_reset_match() -> void:
	# 모두 대기실로 돌아갔다 — 전투 화면 목록을 비운다. 남겨 두면 대기실에 있는 피어에게
	# 위치가 계속 날아가고, 그쪽에는 노드가 없어 오류만 쌓인다.
	Lobby.server_clear_viewers()
	for player in players_root.get_children():
		player.queue_free()
	for projectile in projectiles_root.get_children():
		projectile.queue_free()
	scores.clear()
	banner = ""
	_hide_result()
	_match_over = false
	_round_restart_at = 0.0
	_short_handed_since = 0.0
	# 선택 도중에 경기가 끝나는 일은 없지만, 다음 경기는 깨끗한 표로 시작해야 한다 (#205).
	_picking = false
	_pick_deadline = 0.0
	_pick_options.clear()
	_pick_choices.clear()
	_next_hit_at.clear()
	_special_ready_at.clear()
	_special_pending.clear()
	_bleeds.clear()
	_bursts.clear()
	_ruptures.clear()
	_dagger_held.clear()


## 점수와 안내 문구를 양쪽에 복제한다.
func _broadcast_round(new_banner: String) -> void:
	_receive_round.rpc(scores, new_banner)


@rpc("authority", "call_local", "reliable")
func _receive_round(new_scores: Dictionary, new_banner: String) -> void:
	scores = new_scores
	banner = new_banner
	_update_hud()


# ─────────────────────────── 결과 화면 (승리·패배 연출) ───────────────────────────
## 연출은 피어마다 **자기 기준**으로 만든다 — 같은 신호를 받고도 이긴 쪽은 승리,
## 진 쪽은 패배 화면을 본다. 판정은 서버가 하고 여기서는 보여주기만 한다.

## 경기 결과를 모든 피어에 알린다. 승자 peer만 넘기면 각자 자기 화면을 만들 수 있다.
@rpc("authority", "call_local", "reliable")
func _receive_match_result(winner_peer: int) -> void:
	var me := multiplayer.get_unique_id()
	var my_player := get_player(me)
	if my_player != null:
		_play_result(winner_peer == me, my_player.character_id)
		return
	# 관전자는 이길 쪽도 질 쪽도 아니다 — 이긴 사람 기준으로 승리 연출만 보여준다.
	# 전용 서버는 화면이 없으니 여기서도 아무것도 띄우지 않는다.
	var winner := get_player(winner_peer)
	if winner != null and Lobby.is_observer(me):
		_play_result(true, winner.character_id, "%s 승리!" % winner.player_name)


## title_override 를 주면 승리 연출을 그대로 쓰면서 글자만 바꾼다 — 관전자 화면이 쓴다.
func _play_result(is_winner: bool, character_id: String, title_override := "") -> void:
	_kill_result_tweens()
	result_jelly.character_id = character_id
	# 전투 화면에 누워 있던/서 있던 포즈를 결과 화면도 그대로 이어받는다 (#178).
	# 관전자는 이긴 쪽 기준(is_winner = true)이므로 승리 포즈를 본다.
	result_jelly.pose = Characters.POSE_WIN if is_winner else Characters.POSE_LOSE
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

	if is_winner:
		_play_win()
	else:
		_play_lose()

	# 연출이 정한 글자를 덮어쓴다. 크기·색·트윈은 그대로 두고 문구만 바꾼다.
	if title_override != "":
		result_label.text = title_override


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


## 패배 — 젤리가 색이 빠지며 기울어 주저앉고 글자가 위에서 천천히 내려온다.
func _play_lose() -> void:
	result_label.text = "패배..."
	result_label.add_theme_color_override("font_color", LOSE_COLOR)
	result_label.modulate.a = 0.0
	result_label.position.y = _label_home.y - 60.0

	var droop := create_tween()
	droop.tween_property(result_jelly, "modulate", Color(0.62, 0.58, 0.66), 0.8)
	droop.parallel().tween_property(result_jelly, "rotation", deg_to_rad(14.0), 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	droop.parallel().tween_property(result_jelly, "scale", Vector2(1.08, 0.86), 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	droop.parallel().tween_property(result_jelly, "position:y", _jelly_home.y + 26.0, 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	droop.tween_callback(_start_lose_sway)
	_result_tweens.append(droop)

	var drop := create_tween()
	drop.tween_interval(0.25)
	drop.tween_property(result_label, "modulate:a", 1.0, 0.5)
	drop.parallel().tween_property(result_label, "position:y", _label_home.y, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_result_tweens.append(drop)


func _start_lose_sway() -> void:
	var sway := create_tween().set_loops()
	sway.tween_property(result_jelly, "rotation", deg_to_rad(17.0), 1.1).set_trans(Tween.TRANS_SINE)
	sway.tween_property(result_jelly, "rotation", deg_to_rad(11.0), 1.1).set_trans(Tween.TRANS_SINE)
	_result_tweens.append(sway)


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


## 결과 화면 아래에 적는 최종 점수. 대기실 순서대로 1P : 2P.
func _final_score_text() -> String:
	var out: Array[String] = []
	for slot in 2:
		var peer_id := 0
		if slot < Lobby.order.size():
			peer_id = Lobby.order[slot]
		out.append(str(int(scores.get(peer_id, 0))))
	return "%s  :  %s" % out


# ─────────────────────────── 맵 ───────────────────────────

## 맵 지형을 MapRoot 아래에 붙인다. 모든 피어에서 호출된다.
func _load_map(map_name: String) -> void:
	for child in map_root.get_children():
		child.queue_free()
	_map = null
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


func _on_match_ended() -> void:
	get_tree().change_scene_to_file("res://scenes/select.tscn")


## 서버가 죽거나 방을 옮기다 실패했다. 방 전환은 스스로 화면을 옮기므로(room_switcher.gd)
## 그쪽이 처리 중이면 손대지 않는다 — 두 곳에서 씬을 갈아치우면 어느 쪽이 이길지 알 수 없다.
func _on_disconnected(_reason: String) -> void:
	if not is_inside_tree() or $UI/HUD/RoomSwitcher.is_switching():
		return
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func get_player(peer_id: int) -> Player:
	return players_root.get_node_or_null("Player_%d" % peer_id) as Player


## 기기당 1명, 최대 2명이므로 상대는 자기 자신이 아닌 나머지 하나다.
func _opponent_of(peer_id: int) -> Player:
	for player: Player in players_root.get_children():
		if player.owner_peer_id != peer_id:
			return player
	return null


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ─────────────────────────── 서버 전투 틱 ───────────────────────────

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	_sync_special_ready()
	_check_basic_attacks()
	_check_pending_specials()
	_tick_bleeds()
	_tick_bursts()
	_tick_ruptures()
	_check_falls()
	_tick_round()


## 쿨타임 상태를 무기 도형 색에 쓰도록 내려준다.
func _sync_special_ready() -> void:
	var now := _now()
	for player: Player in players_root.get_children():
		player.server_set_special_ready(now >= _special_ready_at.get(player.owner_peer_id, 0.0))


## 기본 공격은 조작 없이 자동으로 들어간다 — 근접은 닿으면, 원거리는 간격마다.
func _check_basic_attacks() -> void:
	for attacker: Player in players_root.get_children():
		var target := _opponent_of(attacker.owner_peer_id)
		if target == null or not attacker.alive or not target.alive:
			continue
		_try_melee_basic(attacker, target)
		_try_ranged_basic(attacker)


func _try_melee_basic(attacker: Player, target: Player) -> void:
	var weapon := Weapons.get_weapon(attacker.weapon_id)
	if weapon.is_empty() or weapon["basic_damage"] <= 0.0:
		return
	if not weapon["basic_kind"].begins_with("melee"):
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

	var key := "%d>%d" % [attacker.owner_peer_id, target.owner_peer_id]
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
		target.server_apply_dot(weapon["basic_damage"])
		return
	_next_hit_at[knock_key] = now + Combat.MELEE_HIT_INTERVAL
	target.server_apply_hit(weapon["basic_damage"], weapon["knockback"],
		attacker.global_position.x, 0.0, "basic")


## 원거리 무기의 기본 공격도 자동이다. basic_interval 마다 알아서 발사한다.
func _try_ranged_basic(attacker: Player) -> void:
	var weapon := Weapons.get_weapon(attacker.weapon_id)
	if weapon.is_empty() or weapon["basic_damage"] <= 0.0:
		return
	if weapon["basic_kind"] != "ranged":
		return
	if not attacker.can_act():
		return

	var peer_id: int = attacker.owner_peer_id
	var key := "ranged>%d" % peer_id
	var now := _now()
	if now < _next_hit_at.get(key, 0.0):
		return

	# 단검: 들고 있을 때만 나가고, 상대를 자동으로 따라간다. 쏘면 손에서 없어진다.
	if weapon["name"] == "단검":
		if not _dagger_held.get(peer_id, true):
			return
		var target := _opponent_of(peer_id)
		if target == null:
			return
		_next_hit_at[key] = now + weapon["basic_interval"]
		_dagger_held[peer_id] = false
		_server_fire(attacker, {
			"damage": weapon["basic_damage"],
			"knockback": weapon["knockback"],
			"homing_peer": target.owner_peer_id,
			"use_gravity": true,
			"on_solid": "stay",
			"pickup_owner": peer_id,
			# 던진 뒤에도 바닥에서 주워야 해서 손에 들었을 때와 같은 그림으로 그린다.
			"art": weapon["name"],
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
	for peer_id: int in _special_pending.keys():
		var attacker := get_player(peer_id)
		var target := _opponent_of(peer_id)
		if attacker == null or target == null:
			_special_pending.erase(peer_id)
			continue
		if not attacker.is_forced():
			_special_pending.erase(peer_id)   # 동작이 끝났으면 기회는 사라진다
			continue
		var info: Dictionary = _special_pending[peer_id]
		if not attacker.forced_mode in info["modes"]:
			continue
		var reach: float = MELEE_REACH + attacker.current_reach()
		if attacker.global_position.distance_to(target.global_position) > reach:
			continue
		if is_blocked(attacker, target):
			continue
		target.server_apply_hit(info["damage"], info["knockback"],
			attacker.global_position.x, 0.0, "special")
		if info.get("bleed_dps", 0.0) > 0.0:
			# 첫 타는 즉시 들어간다. 3초 출혈이면 0·1·2초에 세 번 = 문서상 총 12.
			_bleeds[target.owner_peer_id] = {
				"dps": info["bleed_dps"],
				"until": _now() + info["bleed_duration"],
				"next_at": _now(),
			}
		_special_pending.erase(peer_id)


## 출혈은 무적 시간을 무시하고 1초마다 들어간다.
func _tick_bleeds() -> void:
	var now := _now()
	for peer_id: int in _bleeds.keys():
		var info: Dictionary = _bleeds[peer_id]
		var target := get_player(peer_id)
		if now >= info["until"] or target == null or not target.alive:
			_bleeds.erase(peer_id)
			continue
		if now < info["next_at"]:
			continue
		info["next_at"] = now + 1.0
		target.server_apply_dot(info["dps"])


## 소총 연사 — 한 번 누르면 지속시간 동안 자동으로 나간다.
func _tick_bursts() -> void:
	var now := _now()
	for peer_id: int in _bursts.keys():
		var info: Dictionary = _bursts[peer_id]
		var shooter := get_player(peer_id)
		if shooter == null or not shooter.can_act():
			_bursts.erase(peer_id)
			continue
		# 끝나는 조건이 둘이다 — 시간(소총: 누르는 동안 2초)과 발 수(글러브: 6발, #164).
		if info["remaining"] == 0 or (info["until"] > 0.0 and now >= info["until"]):
			_bursts.erase(peer_id)
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
func _start_burst(peer_id: int, damage: float, knockback: int, interval: float,
		duration := 0.0, shots := 0, first_knockback := -1, base := {}) -> void:
	var now := _now()
	_bursts[peer_id] = {
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

## 서버에서만 호출한다. offsets로 여러 발을 한 번에 낼 수 있다 (활 특수의 평행 3발).
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
		data["id"] = _next_projectile_id
		_next_projectile_id += 1
		data["shooter_peer"] = attacker.owner_peer_id
		data["velocity"] = _launch_velocity(dir, launch_angle, speed)
		# 무기 끝에서 나가게 한다.
		data["position"] = attacker.global_position + Vector2(
			dir * (MELEE_REACH * 0.5 + attacker.current_reach()), offset)
		projectile_spawner.spawn(data)


## 부채꼴 발사 (샷건). **서버에서만 부른다.**
##
## 탄을 쓰지 않는 이유: 산탄은 코앞에서 퍼지는 것이라 "날아가는 무엇"이 없다.
## 투사체로 흉내내면 회피가 "옆으로 비키기"가 되는데, 부채꼴은 **거리를 벌리거나
## 부채 밖으로 나가는 것**이 회피여야 한다.
##
## **막기(`is_blocked`)를 거치지 않는다.** 막기는 무기 끝과 무기 끝이 부딪히는 판정인데
## 이건 흩뿌리는 것이다 — 폭탄 반경·양날 도끼 착지 충격파와 같은 취급이다.
## 다만 `_faces()`는 뜻이 있다: 부채꼴 자체가 바라보는 쪽으로만 열린다.
##
## 데미지는 가까울수록 세다(34 → 14). 감소 기준 거리는 부채꼴 사거리와 같은 값이라
## 부채 끝에 겨우 닿으면 최소값이 들어간다.
func _cone_blast(attacker: Player, weapon: Dictionary) -> void:
	var reach: float = weapon["special_cone_range"]
	var spread: float = weapon["special_cone_angle"]
	# **맞았는지와 무관하게 먼저 띄운다.** 빗나간 것도 "여기까지였다"로 보여야 한다
	# (착지 충격파를 띄우는 이유 #167과 같다).
	_play_shotgun_blast.rpc(
		attacker.global_position + Vector2(0.0, Player.WEAPON_CENTER_Y),
		signf(float(attacker.facing)), reach, spread)
	var target := _opponent_of(attacker.owner_peer_id)
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
	# 표에서 꺼낸 값은 Variant라 명시 타입으로 받는다 (#66).
	var near: float = weapon["special_damage"]
	var far: float = weapon["falloff_min_damage"]
	var damage := lerpf(near, far, clampf(distance / reach, 0.0, 1.0))
	target.server_apply_hit(damage, weapon["knockback"], attacker.global_position.x,
		0.0, "special")


## 다음에 던질 것이 강화인지 뽑는다 (#134). **서버에서만 부른다** —
## 클라이언트가 각자 뽑으면 손에 든 그림이 양쪽에서 달라진다.
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


## 모든 피어에서 호출되어 투사체 노드를 만든다.
func _spawn_projectile(data: Dictionary) -> Node:
	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	projectile.name = "Projectile_%d" % int(data["id"])
	projectile.setup(data)
	if multiplayer.is_server():
		projectile.finished.connect(_on_projectile_finished)
		projectile.picked_up.connect(_on_dagger_picked_up)
		projectile.swapped.connect(_on_positions_swapped)
		projectile.struck.connect(_on_lightning_struck)
	return projectile


## 서버에서 지우면 스포너가 클라이언트에서도 같이 지운다.
func _on_projectile_finished(projectile: Projectile) -> void:
	projectile.queue_free()


## 단검을 주우면 다시 들고 있는 상태가 된다.
func _on_dagger_picked_up(peer_id: int, projectile: Projectile) -> void:
	_dagger_held[peer_id] = true
	projectile.queue_free()


# ─────────────────────────── 특수 공격 (Shift) ───────────────────────────
## 방향은 바라보는 방향(좌우)으로만 나간다.
## Player가 서버에서 입력을 받아 신호를 내므로, 여기서는 판정만 한다.

func _on_special_requested(peer_id: int, long_press: bool) -> void:
	if not multiplayer.is_server():
		return
	var attacker := get_player(peer_id)
	var target := _opponent_of(peer_id)
	if attacker == null or target == null or not attacker.can_act():
		return

	var weapon := Weapons.get_weapon(attacker.weapon_id)
	if weapon.is_empty():
		return

	var now := _now()
	if now < _special_ready_at.get(peer_id, 0.0):
		return
	if not _execute_special(attacker, target, weapon, long_press):
		return
	_special_ready_at[peer_id] = now + weapon["special_cooldown"]


## 무기별 특수 공격. 발동했으면 true (쿨타임이 돌아간다).
func _execute_special(attacker: Player, target: Player, weapon: Dictionary, long_press: bool) -> bool:
	var peer_id: int = attacker.owner_peer_id
	match weapon["name"]:
		"검":
			# 일정 거리 안에 상대가 있을 때만 쓸 수 있다. 밖이면 발동 자체를 안 해서
			# 쿨타임도 돌지 않는다 — 허공에 대고 쿨타임만 날리는 일이 없게 한다.
			var sword_range: float = weapon["special_range"]
			if attacker.global_position.distance_to(target.global_position) > sword_range:
				return false
			# 거리만 맞으면 들어간다. 빛기둥이 상대에게 꽂히는 연출이라 휘두르는 방향이나
			# 상대 무기의 막기(is_blocked)는 따지지 않는다.
			var hp_ratio: float = weapon["special_hp_ratio"]
			target.server_apply_hit(target.hp * hp_ratio, weapon["knockback"],
				attacker.global_position.x, 0.0, "special")
			_play_light_burst.rpc(target.global_position + Vector2(0.0, Player.BODY_BOTTOM))
			return true
		"망치":
			return _melee_special(attacker, target, weapon["special_damage"],
				weapon["knockback"], weapon["stun_duration"])
		"글러브":
			# "단거리 주먹 발사" — 글러브가 손에서 분리되어 연달아 날아간다 (#161·#164).
			# 옛 구현은 사거리만 1.5배 늘린 즉시 판정이라 화면에 아무것도 안 나타났다.
			# **발 수**로 끝나고(6발), **첫 발만 세게 민다**. 정해진 거리를 날아가면
			# 사라지는 것은 기획서의 "단거리"를 지키기 위한 것이다.
			_start_burst(peer_id, weapon["special_damage"], Combat.Knockback.WEAK,
				weapon["burst_interval"], 0.0, weapon["burst_shots"], weapon["knockback"], {
					"art_file": weapon["projectile_file"],
					# 원화의 앞이 위가 아니라 오른쪽이다.
					"art_points_right": weapon["projectile_points_right"],
					"max_distance": weapon["special_distance"],
					"speed": weapon["projectile_speed"],
				})
			return true
		"너클":
			# 게이지 비례 데미지 → 쓰면 게이지는 전부 소모된다.
			var ratio: float = attacker.gauge / weapon["gauge_max"]
			var punch: float = lerpf(weapon["gauge_min_damage"], weapon["gauge_max_damage"], ratio)
			var landed := _melee_special(attacker, target, punch, weapon["knockback"])
			attacker.server_set_gauge(0.0)
			return landed
		"광선검":
			# 관통 — 일정 시간 상대 무기의 막기를 무시한다.
			attacker.server_apply_buff("pierce", 1.0, weapon["special_duration"])
			return true
		"장대":
			# 상시 사거리(`reach_multiplier`)가 아니라 **특수 전용 배율**을 쓴다.
			# 상시로 걸면 특수를 쓰지 않아도 근접 공격을 전부 막는다 (막기 판정 참고).
			attacker.server_apply_buff("reach", weapon["special_reach_multiplier"],
				weapon["special_duration"])
			return true
		"전기톱":
			# 관통 돌진. 속도는 일반 점프의 두 배, 벽에 부딪히면 끝난다.
			attacker.server_start_forced("dash", _dash_safety_time())
			_special_pending[peer_id] = {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"modes": ["dash"],
				"bleed_dps": weapon["bleed_damage"],
				"bleed_duration": weapon["bleed_duration"],
			}
			return true
		"양날 도끼":
			# 고속 상승 후 고속 낙하. 데미지는 낙하 중에만 들어간다.
			# 낙하 중 직격을 놓치면 **착지할 때 주변을 때린다** (#167) — 그 수치를
			# 여기 같이 실어 둔다. `_on_forced_landed()`가 꺼내 쓴다.
			attacker.server_start_forced("rise", _rise_time())
			_special_pending[peer_id] = {
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
			# 특수만 불꽃 꼬리 미사일이다 — 기본 공격 탄은 노란 막대 그대로 (#121).
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
			attacker.server_set_empowered(_roll_empowered(attacker.weapon_id))
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
			attacker.server_set_empowered(_roll_empowered(attacker.weapon_id))
			return true
		"소총":
			# 한 번 누르면 지속시간 동안 자동 연사. **시간**으로 끝난다.
			_start_burst(peer_id, weapon["special_damage"], weapon["knockback"],
				weapon["burst_interval"], weapon["burst_duration"])
			return true
		"단검":
			# 특수 = 자동 재수집. 주우러 가지 않아도 손으로 돌아온다.
			if _dagger_held.get(peer_id, true):
				return false   # 이미 들고 있으면 쓸 것이 없다
			_dagger_held[peer_id] = true
			for projectile: Projectile in projectiles_root.get_children():
				if projectile.pickup_owner == peer_id:
					projectile.queue_free()
			return true
		"방패":
			# **하나뿐인 길게/짧게로 갈리는 특수다.** 길게(0.3초 이상, `Player.LONG_PRESS_TIME`)는
			# 크기 증가, 짧게는 던지기다. `long_press`는 **서버가 잰 것**이라 클라이언트가
			# 속일 수 없고, 길게가 확정되는 순간 뗄 때를 기다리지 않고 바로 발동한 뒤
			# 눌린 기록을 지운다 — 그래서 손을 뗄 때 던지기가 겹쳐 나가지 않고 쿨타임도
			# 한 번만 돈다 (`Player._check_long_press`·`_receive_skill` 참고).
			if long_press:
				attacker.server_apply_buff("size", weapon["size_multiplier"], weapon["special_duration"])
			else:
				_server_fire(attacker, {
					"damage": weapon["special_damage"],
					"knockback": weapon["knockback"],
					# 손에 든 것과 **같은 그림으로** 날아간다 (표창과 같은 이유다) —
					# 노란 막대로 날아가면 16 데미지짜리가 오는데 무엇이 오는지가
					# 화면에 없고, 크기 증가 쪽과 구별도 안 된다.
					"art_file": weapon["file"],
					# 진행 방향으로 돌리면 방패가 옆으로 눕는다 — 원화가 세로(위가 위)라
					# `_face()`의 기본 +90도가 걸리면 넘어진 것처럼 보인다. 폭탄이
					# 도화선 때문에 세워 두는 것과 같은 처리다 (#131).
					"art_upright": true,
				})
			return true
		_:
			return false


## 바라보는 방향으로 사거리 안에 있으면 맞는다.
## 빗나가도 발동은 한 것이므로 true — 쿨타임은 돌아간다.
func _melee_special(attacker: Player, target: Player, damage: float, knockback: int,
		stun := 0.0, reach_bonus := 1.0) -> bool:
	if not _faces(attacker, target):
		return true  # 방향이 안 맞아 빗나감
	var reach: float = (MELEE_REACH + attacker.current_reach()) * reach_bonus
	if attacker.global_position.distance_to(target.global_position) > reach:
		return true  # 사거리 밖
	if is_blocked(attacker, target):
		return true  # 상대 무기에 막힘
	target.server_apply_hit(damage, knockback, attacker.global_position.x, stun, "special")
	return true


# ─────────────────────────── 연출 ───────────────────────────
## 판정에 관여하지 않는 그림만. 서버가 결과를 정한 뒤 각 피어가 자기 화면에 띄운다.
## 투사체와 달리 MultiplayerSpawner를 쓰지 않는다 — 잠깐 떴다 스스로 사라지고
## 아무것도 맞히지 않아서, 위치를 계속 맞출 것도 나중에 지워 줄 것도 없다.

## 검 특수의 빛기둥. `at`은 맞은 젤리의 발밑이다.
@rpc("authority", "call_local", "reliable")
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
@rpc("authority", "call_local", "reliable")
func _play_shotgun_blast(at: Vector2, aim: float, reach: float, spread: float) -> void:
	var blast := SHOTGUN_BLAST_SCENE.instantiate()
	blast.position = at
	blast.aim = aim
	blast.reach = reach
	blast.spread = spread
	effects_root.add_child(blast)


## 삼지창 특수가 맞혔다 (서버 전용 — 투사체가 알려 온다).
func _on_lightning_struck(at: Vector2) -> void:
	_play_lightning_strike.rpc(at)


## 삼지창 특수의 번개. `at`은 맞은 젤리의 발밑이고, 줄기는 화면 위에서 거기까지 내려온다.
@rpc("authority", "call_local", "reliable")
func _play_lightning_strike(at: Vector2) -> void:
	var bolt := LIGHTNING_STRIKE_SCENE.instantiate()
	# 위치를 붙이기 전에 넣는다 — `_ready()`가 이 값으로 줄기 모양의 씨앗을 잡는다.
	bolt.position = at
	effects_root.add_child(bolt)


## 빨간 표창이 자리를 바꿨다 (서버 전용 — 투사체가 알려 온다).
func _on_positions_swapped(from_position: Vector2, to_position: Vector2) -> void:
	_play_swap_burst.rpc(from_position, to_position)


## 위치 교환 연출. **두 자리에 하나씩** 띄운다 — 하나만 띄우면 어디로 갔는지 알 수 없다.
##
## 받는 값은 **바꾸기 전의** 두 위치다. 각각이 "여기 있던 것이 떠났다"와
## "여기 있던 것이 저기로 갔다"를 동시에 뜻한다 — 서로 자리를 맞바꾼 것이므로 같은 두 점이다.
##
## 원점을 젤리 몸 한가운데로 올린다. 넘어오는 위치는 발밑 기준(`global_position`)이고,
## 몸 전체가 사라졌다 나타나는 연출이라 발밑에서 터지면 아래로 쏠려 보인다.
@rpc("authority", "call_local", "reliable")
func _play_swap_burst(from_position: Vector2, to_position: Vector2) -> void:
	for at: Vector2 in [from_position, to_position]:
		var burst := SWAP_BURST_SCENE.instantiate()
		# **위치를 붙이기 전에 넣는다.** `_ready()`가 붙는 순간 돌면서 위치로 난수 씨앗을
		# 잡으므로, 나중에 넣으면 두 자리 모두 (0, 0)으로 같은 씨앗을 받아 같은 모양이 된다.
		burst.position = at + SWAP_BURST_CENTER
		effects_root.add_child(burst)


## 강제 낙하(양날 도끼)가 땅에 닿았다 — **좌우로 땅을 갈라 보낸다** (#167). 서버 전용.
##
## 여기서는 시작만 한다. 실제로 때리는 것은 `_tick_ruptures()`가 앞선을 밀면서 하고,
## 그래서 멀리 선 상대는 가까이 선 상대보다 조금 늦게 맞는다 — 착지 순간 반경을
## 한꺼번에 때리면 "갈라져 나간다"가 아니라 "닿으면 맞는다"가 된다.
##
## **낙하 중 직격을 놓쳤을 때만 들어간다.** 직격이 성공하면 `_check_pending_specials()`가
## 예약을 지우므로 여기 올 것이 없다 — 한 번의 특수로 두 번 맞는 일은 생기지 않는다.
func _on_forced_landed(peer_id: int, at: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var info: Dictionary = _special_pending.get(peer_id, {})
	var radius: float = info.get("landing_radius", 0.0)
	if radius <= 0.0:
		return
	_special_pending.erase(peer_id)   # 착지로 기회를 다 썼다
	var speed: float = info.get("landing_rupture_speed", 0.0)
	if speed <= 0.0:
		return

	# 연출은 맞았는지와 무관하게 띄운다 — 빗나간 것도 "여기까지였다"로 보여야 한다.
	# 속도까지 넘겨서 **화면에 보이는 앞선이 곧 맞는 경계**가 되게 한다.
	_play_shockwave.rpc(at, radius, speed)

	var damage: float = info.get("landing_damage", 0.0)
	if damage <= 0.0:
		return
	# 착지 순간 반경을 한꺼번에 때리지 않는다. 앞선이 거기까지 가는 데 걸리는 시간이
	# 있어야 "갈라져 나간다"로 읽히고, 멀리 선 상대는 조금 늦게 맞는다.
	_ruptures.append({
		"peer": peer_id,
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


## 땅 격파의 앞선을 좌우로 밀고, 닿는 상대를 한 번씩 때린다 (서버 전용).
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
			var target_peer: int = target.owner_peer_id
			if target_peer == rupture["peer"] or not target.alive:
				continue
			if rupture["hit"].has(target_peer):
				continue
			if absf(target.global_position.y - origin.y) > Player.BODY_HEIGHT:
				continue
			var span := absf(target.global_position.x - origin.x)
			if span > minf(front, reach):
				continue
			rupture["hit"][target_peer] = true
			target.server_apply_hit(rupture["damage"], rupture["knockback"],
				origin.x, 0.0, "special")
		if front >= reach:
			_ruptures.remove_at(i)


## 착지 땅 격파. `at`은 떨어진 자리, `radius`는 **좌우 각각 실제로 맞는 거리**,
## `speed`는 앞선이 뻗어 나가는 속도다 — 셋 다 판정에 쓰는 값 그대로다.
## 보이는 것과 맞는 범위가 어긋나면 이 연출이 거짓말이 된다.
@rpc("authority", "call_local", "reliable")
func _play_shockwave(at: Vector2, radius: float, speed: float) -> void:
	var wave := SHOCKWAVE_SCENE.instantiate()
	wave.radius = radius
	wave.speed = speed
	effects_root.add_child(wave)
	wave.global_position = at + Vector2(0.0, Player.BODY_BOTTOM)


## 돌진이 벽 없는 맵에서 무한히 이어지지 않게 하는 안전장치.
## 화면 폭을 돌진 속도로 지나가는 시간이면 충분하다.
func _dash_safety_time() -> float:
	return get_viewport_rect().size.x / Player.FORCED_SPEED


## 상승에서 낙하로 넘어가는 시점. 일반 점프가 정점에 닿는 시간의 두 배 속도이므로 절반이다.
func _rise_time() -> float:
	return absf(Player.JUMP_VELOCITY) / Player.FORCED_SPEED * 0.5


# ─────────────────────────── 표시 ───────────────────────────

func _process(_delta: float) -> void:
	_update_hud()


## 체력·점수 표시. 대기실 접속 순서(Lobby.order)가 1P·2P를 정한다.
##
## 라벨은 전부 흰 카드(`P1Card`·`P2Card`) **안**에 들어 있다 — 카드 밖에 두면 맵 배경 위에
## 그대로 그려져서 어두운 맵(용암)에서 진한 글자가 묻힌다(이슈 #112).
## 체력은 막대와 숫자를 함께 낸다. 막대 길이만으로는 남은 값을 정확히 읽을 수 없고,
## 막대 안에 숫자를 그리면(`show_percentage`) 채운 쪽과 빈 쪽 중 한쪽에서 반드시 묻힌다.
func _update_hud() -> void:
	for slot in 2:
		var card := $UI/HUD.get_node("P%dCard" % (slot + 1))
		var bar := card.get_node("Bar") as ProgressBar
		var label := card.get_node("Name") as Label
		var hp_label := card.get_node("Hp") as Label
		var score_label := card.get_node("Score") as Label
		var player: Player = null
		var peer_id := 0
		if slot < Lobby.order.size():
			peer_id = Lobby.order[slot]
			player = get_player(peer_id)
		score_label.text = _score_text(int(scores.get(peer_id, 0)))
		if player == null:
			bar.value = 0.0
			label.text = "%dP —" % (slot + 1)
			hp_label.text = "—"
			continue
		bar.max_value = Combat.MAX_HP
		bar.value = player.hp
		# 무기 선택이 끝나기 전에는 아직 아무것도 안 들었다 (#205) — 빈칸 대신 줄표를 둔다.
		var weapon_text := player.weapon_id if player.weapon_id != "" else "—"
		label.text = "%dP  %s" % [slot + 1, weapon_text]
		# 올림으로 낸다 — 0.4처럼 남은 체력을 "0"으로 적으면 살아 있는데 죽은 것으로 읽힌다.
		hp_label.text = "%d" % ceili(player.hp)

	var banner_label := $UI/HUD.get_node("Banner") as Label
	banner_label.text = banner
	# 결과 화면이 떠 있으면 그쪽 글자와 겹치므로 배너는 접는다.
	banner_label.visible = banner != "" and not result_overlay.visible


## 딴 포인트는 채운 동그라미, 남은 포인트는 빈 동그라미로 보여주고 숫자를 함께 적는다.
## 동그라미만 있으면 몇 포인트 중 몇 포인트인지 한눈에 안 읽힌다 (3포인트 선취).
func _score_text(score: int) -> String:
	var filled := clampi(score, 0, Combat.POINTS_TO_WIN)
	var dots := "●".repeat(filled) + "○".repeat(Combat.POINTS_TO_WIN - filled)
	return "%s  %d / %d" % [dots, filled, Combat.POINTS_TO_WIN]


func _unhandled_input(event: InputEvent) -> void:
	# ESC로 접속을 끊고 타이틀로 돌아간다
	if event.is_action_pressed("ui_cancel"):
		Network.leave()
		get_tree().change_scene_to_file("res://scenes/title.tscn")
