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
const HIT_SPARKS_SCENE := preload("res://scenes/hit_sparks.tscn")
const HEAVY_PUNCH_SCENE := preload("res://scenes/heavy_punch.tscn")
const CANNON_BURST_SCENE := preload("res://scenes/cannon_burst.tscn")
## 소리도 연출 씬들과 같은 자리에 둔다 — 짜임이 같다 (`scripts/sfx_oneshot.gd` 참고).
const CANNON_SHOT_SFX_SCENE := preload("res://scenes/cannon_shot_sfx.tscn")
const MELEE_CLASH_SFX_SCENE := preload("res://scenes/melee_clash_sfx.tscn")
const HIT_SFX_SCENE := preload("res://scenes/hit_sfx.tscn")
const LASER_SWORD_SKILL_SFX_SCENE := preload("res://scenes/laser_sword_skill_sfx.tscn")
const DAMAGE_TICK_SFX_SCENE := preload("res://scenes/damage_tick_sfx.tscn")
const DAGGER_RETURN_SFX_SCENE := preload("res://scenes/dagger_return_sfx.tscn")
const SHIELD_SIZE_SFX_SCENE := preload("res://scenes/shield_size_sfx.tscn")
const RIFLE_SHOT_SFX_SCENE := preload("res://scenes/rifle_shot_sfx.tscn")
const RIFLE_BURST_SFX_SCENE := preload("res://scenes/rifle_burst_sfx.tscn")
## 소총 기본 공격의 탄이 **맞은** 소리. 총성(`RIFLE_SHOT_SFX_SCENE`)과 짝이다 —
## 그쪽은 쏘는 순간, 이쪽은 닿는 순간이다.
const RIFLE_HIT_SFX_SCENE := preload("res://scenes/rifle_hit_sfx.tscn")
const SHURIKEN_SWAP_SFX_SCENE := preload("res://scenes/shuriken_swap_sfx.tscn")
const SHURIKEN_THROW_SFX_SCENE := preload("res://scenes/shuriken_throw_sfx.tscn")
const BOMB_THROW_SFX_SCENE := preload("res://scenes/bomb_throw_sfx.tscn")
const BOMB_EXPLODE_SFX_SCENE := preload("res://scenes/bomb_explode_sfx.tscn")
const BOMB_BLAST_SCENE := preload("res://scenes/bomb_blast.tscn")
const STUN_HIT_SFX_SCENE := preload("res://scenes/stun_hit_sfx.tscn")
## 너클 게이지가 75%를 넘어선 순간의 소리 (#225). 때리는 소리가 아니라 **상태가 바뀐**
## 소리라, 무기를 든 쪽이 아니라 **맞은 쪽**의 게이지가 찰 때 울린다.
const KNUCKLE_CHARGED_SFX_SCENE := preload("res://scenes/knuckle_charged_sfx.tscn")
## 너클 특수(강펀치)가 들어가는 소리 (#225).
const KNUCKLE_PUNCH_SFX_SCENE := preload("res://scenes/knuckle_punch_sfx.tscn")
const BOW_SHOT_SFX_SCENE := preload("res://scenes/bow_shot_sfx.tscn")
const BOW_SKILL_SFX_SCENE := preload("res://scenes/bow_skill_sfx.tscn")
const CHAINSAW_DASH_SFX_SCENE := preload("res://scenes/chainsaw_dash_sfx.tscn")
const CHAINSAW_WIND_SFX_SCENE := preload("res://scenes/chainsaw_wind_sfx.tscn")
const SWORD_SKILL_SFX_SCENE := preload("res://scenes/sword_skill_sfx.tscn")
const AXE_SKILL_SFX_SCENE := preload("res://scenes/axe_skill_sfx.tscn")
const AXE_LAND_GROUND_SFX_SCENE := preload("res://scenes/axe_land_ground_sfx.tscn")
const AXE_LAND_HIT_SFX_SCENE := preload("res://scenes/axe_land_hit_sfx.tscn")
## **소리 하나를 세 무기가 나눠 쓴다** — 망치·삼지창·장대의 특수다. 소리마다 씬 하나인
## 짜임(`sfx_oneshot.gd`)은 그대로이고, 그 씬을 부르는 자리가 셋인 것이다.
const SKILL_CAST_SFX_SCENE := preload("res://scenes/skill_cast_sfx.tscn")
## 샷건 특수(부채꼴 산탄)의 소리. **총성과 장전이 한 파일에 들어 있다** — 받은 소리가
## 그렇게 녹음되어 있고, 무기 설명("+장전 쿨타임")이 말하는 것도 그 둘이다.
const SHOTGUN_SKILL_SFX_SCENE := preload("res://scenes/shotgun_skill_sfx.tscn")
## 무기 선택 창이 뜨는 소리. **무기가 내는 소리가 아니라 화면이 내는 소리다** — 위의
## 무기 소리들과 달리 판정과 아무 상관이 없고, 라운드마다 창이 뜨는 그 한 번만 울린다.
const WEAPON_PICK_SFX_SCENE := preload("res://scenes/weapon_pick_sfx.tscn")

# ─────────────────────────── 피격음 박자 ───────────────────────────
## 피격음을 다시 울리기까지의 최소 간격(초).
##
## **같은 순간에 도착하는 여러 발을 한 소리로 뭉치려는 값이다.** 무적 시간은 다발성
## 무기가 먹히지 않도록 0.1초로 짧게 잡혀 있어서(`Combat.INVULNERABLE_TIME`), 활 특수
## 3발·소총 연사·샷건 부채꼴은 전부 따로 데미지가 들어간다. 그대로 울리면 같은 소리가
## 세 겹 겹쳐 세 배로 커진다 — 소리가 셋인 것이 아니라 한 번 크게 맞은 것이다.
##
## 0.09 는 무적 시간(0.1)보다 조금 짧다. 무적을 지나 들어오는 **다음** 타격은 늘 울리고,
## 한 순간에 몰린 것만 뭉친다.
const HIT_SFX_INTERVAL := 0.09
## 지속 데미지(전기톱·광선검)의 피격음 간격(초).
##
## 위와 따로 두는 이유: 지속 데미지는 0.2초마다 조금씩 들어오는 **하나의 지속**이라
## 타격이 여러 번인 것이 아니다. 0.09초 문틈으로 내보내면 초당 다섯 번 퍽퍽거려서
## 맞는 소리가 아니라 웅웅거림이 된다 — 근접 부딪힘 소리를 넉백 박자에 맞춘 것과 같은 판단.
## 넉백이 들어가는 박자(`Combat.MELEE_HIT_INTERVAL`, 0.6초)와 같이 두어 밀릴 때 같이 울린다.
const DOT_SFX_INTERVAL := Combat.MELEE_HIT_INTERVAL
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
## 범위를 보여 주고 기다리는 중인 강펀치 (#231). peer -> 누른 순간에 굳힌 값.
## **자리·방향·데미지가 다 여기 들어 있다** — 기다리는 동안 쓰는 쪽이 움직여도
## 주먹은 보여 준 자리에 들어간다. 예고한 범위와 맞는 범위가 달라지면 예고가 거짓말이 된다.
var _punch_pending := {}
## 내려베는 중인 검 특수 (#247). peer -> 누른 순간에 굳힌 값과 검이 다 내려오는 시각.
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
## 지금 깔린 맵의 이름. **전용 서버가 맵을 갈아야 하는지 판단하는 데 쓴다** —
## 클라이언트는 경기마다 씬을 새로 열어 `_ready()`에서 한 번만 깔므로 볼 일이 없다.
var _loaded_map := ""

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
		# 전용 서버는 이 씬을 벗어나지 않으므로 _ready()에서 깐 맵이 계속 남는다 —
		# 경기가 시작될 때 확정된 맵으로 갈아 주는 곳이 필요하다.
		Lobby.lobby_changed.connect(_on_lobby_changed)
	else:
		# 씬이 준비된 뒤에 서버에 알린다. 접속 직후 바로 스폰하면
		# 클라이언트가 아직 이 씬을 로드하기 전이라 스폰을 놓칠 수 있다.
		_notify_ready.rpc_id(1)
		_setup_observer_view()


## 대기실 상태가 바뀌었다 (**서버 전용**). 확정된 맵이 지금 깔린 것과 다르면 갈아 준다.
##
## **전용 서버는 전투 화면을 벗어나지 않는다.** `_ready()`는 서버가 켜질 때 딱 한 번 돌고,
## 그때 `Lobby.map_name`은 아직 대기실 기본값인 `"랜덤"`이다 — `Maps.scene()`은 목록에
## 없는 이름을 받으면 폴백으로 첫 맵(바다)을 주므로 **서버에는 바다가 깔린다.**
## 클라이언트는 경기마다 씬을 새로 열어 확정된 맵을 받지만 서버는 그러지 않으므로,
## 여기서 갈아 주지 않으면 어떤 맵을 골라도 **서버의 충돌 지형은 영원히 첫 맵**이다.
##
## 그게 곧 게임 지형이다 — 이동·접지·낙사 판정이 전부 서버에서 난다(`player.gd`의
## `apply_movement()`·`main.gd`의 `_check_falls()`). 클라이언트는 서버가 보낸 위치로
## 보간만 하므로, 바다의 발판도 화산의 `Hazard`도 서버에 없으면 없는 것이 된다.
##
## `map_name`은 서버의 `Lobby._check_start()`에서만 바뀌고 그 직후 `_broadcast()`가
## 이 신호를 낸다 — 경기 시작 때 한 번 갈리고 경기 중에는 갈리지 않는다.
func _on_lobby_changed() -> void:
	if not multiplayer.is_server() or Lobby.map_name == _loaded_map:
		return
	_load_map(Lobby.map_name)


## 관전자 화면. 이 기기가 보기만 한다는 것을 알려 준다 (이슈 #167).
## 자기 젤리가 없다는 것 말고는 플레이어 화면과 같다 — HUD·배너·투사체가 다 보인다.
##
## 문구는 씬에 적혀 있고 여기서는 켜기만 한다 — 플레이어에게는 접힌 채로 둔다.
## 카드가 화면 맨 위로 올라가면서(이슈 #267) 조작 안내가 없어졌고, 관전 안내는
## 젤리와 겹치지 않는 가운데 빈 자리(`ObserverCard`)로 옮겼다.
func _setup_observer_view() -> void:
	if not Lobby.is_observer(multiplayer.get_unique_id()):
		return
	$UI/HUD/ObserverCard.visible = true


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
	# 제자리 회전이 끝나 내지르기 시작하는 순간도 서버에서만 온다 (전기톱, #260).
	player.dash_launched.connect(_on_dash_launched)
	# 데미지가 들어간 순간도 서버에서만 온다 — 피격음을 울린다.
	player.damaged.connect(_on_player_damaged)
	# 기절하며 맞은 순간도 서버에서만 온다 — 기절음을 울린다 (망치·삼지창).
	player.stunned.connect(_on_player_stunned)
	# 너클 게이지가 75%를 넘어선 순간도 서버에서만 온다 — 충전음을 울린다 (#225).
	player.gauge_charged.connect(_on_player_gauge_charged)
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
	_punch_pending.erase(peer_id)
	_sword_swings.erase(peer_id)
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
	_punch_pending.clear()
	_sword_swings.clear()
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
	# 창이 뜨는 소리. **고르는 사람과 관전자 모두에게 울린다** — 아래 두 갈래가 갈리기
	# 전에 두는 것이 그 뜻이다. 관전자 화면에도 어둡기가 깔리며 판이 넘어간 것이 보이고
	# (`open_watching`), 그 순간을 알리는 소리는 카드가 있든 없든 같다.
	_play_weapon_pick_sfx()
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
	_punch_pending.clear()
	_sword_swings.clear()
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
## **서버에서는 경기마다 다시 불린다**(`_on_lobby_changed`) — 클라이언트는 씬을 새로 열어
## `_ready()`에서 한 번만 부른다. 그래서 두 번째 호출이 깨끗해야 한다.
func _load_map(map_name: String) -> void:
	# 갈아 줄 때 무엇이 깔렸는지 기억한다. 폴백으로 다른 맵이 깔려도 **요청한 이름**을
	# 적어 둔다 — 판단 기준이 `Lobby.map_name`과의 비교이므로 같은 값이어야 한다.
	_loaded_map = map_name
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
		# 틱 소리도 **데미지보다 먼저** 낸다 — 부딪힘 쇳소리와 같은 이유다
		# (`server_apply_dot()` 이 그 자리에서 `damaged` 를 내고 공용 피격음이 나간다).
		_try_damage_tick_sfx(weapon, "basic", now)
		target.server_apply_dot(weapon["basic_damage"])
		return
	_next_hit_at[knock_key] = now + Combat.MELEE_HIT_INTERVAL
	# **때리기보다 먼저 부른다.** `server_apply_hit()` 은 그 자리에서 `damaged` 를 내고,
	# 그 신호가 곧 피격음을 울린다 — 부딪힘 소리를 나중에 정하면 피격음이 이미 나가 버려
	# 둘이 같은 순간에 겹친다. 겹치면 두 소리가 한 음색으로 뭉쳐 **더 높은 소리 하나**로
	# 들린다. 무기끼리 부딪힌 것은 한 번의 사건이므로 소리도 하나여야 한다.
	_try_melee_clash_sfx(attacker, target, now)
	# **넉백이 들어가는 이 타이밍에도 틱은 빠지지 않는다.** 지속 데미지 무기는 0.6초마다
	# 한 번 이 길로 오는데(위 dot 길이 아니라), 여기서 안 내면 다섯 번의 따다다닥 중
	# 세 번째마다 하나가 빠져서 리듬에 구멍이 뚫린다.
	_try_damage_tick_sfx(weapon, "basic", now)
	# 기절은 무기 표에서 바로 읽지 않는다 — **켜져 있는 능력**에서 나온다
	# (망치 특수). 안 켜져 있으면 0 이라 지금까지와 똑같다.
	var stun := attacker.stun_bonus()
	target.server_apply_hit(weapon["basic_damage"], weapon["knockback"],
		attacker.global_position.x, stun, "basic")
	# 기절을 얹은 타격에는 **번개가 내려친다** — 삼지창이 맞혔을 때와 같은 연출이고
	# 같은 함수를 쓴다(`_play_lightning_strike`). 자리도 같은 기준인 **맞은 젤리의
	# 발밑**이다.
	#
	# **무기 이름이 아니라 기절이 얹혔는지로 가른다** — 위 `stun_bonus()` 와 같은 자리에서
	# 나온 값이라, 기절을 거는 능력이 다른 무기에 붙어도 번개와 기절이 어긋나지 않는다.
	# 지금 이 길로 오는 것은 망치 특수뿐이다.
	#
	# **기절음(`_on_player_stunned`)과 겹치지 않는다** — 그쪽은 소리고 이쪽은 그림이다.
	# 삼지창도 둘이 같이 난다.
	if stun > 0.0:
		_play_lightning_strike.rpc(target.global_position + Vector2(0.0, Player.BODY_BOTTOM))


## 이 무기가 근접인가. `basic_kind` 가 "melee" 로 시작하면 참이다 —
## 지속 데미지 무기("melee_dot", 전기톱·광선검)도 근접에 든다.
##
## **두 곳이 같은 판정을 쓴다** — 때리는 쪽을 가리는 `_try_melee_basic()` 과,
## 맞는 쪽도 근접인지 보는 `_try_melee_clash_sfx()`. 문자열 비교를 두 군데 적어 두면
## "melee_" 로 시작하는 갈래가 하나 더 늘 때 한쪽만 고쳐진다.
func _is_melee(weapon: Dictionary) -> bool:
	return weapon.get("basic_kind", "").begins_with("melee")


## 데미지가 들어갈 때마다 나는 짧은 틱 소리 (광선검·전기톱 기본, 소총 연사).
##
## `scope` 는 "basic" 또는 "special" — 무기 표의 `basic_tick_sfx`·`special_tick_sfx` 중
## 어느 쪽을 볼지다. 소총은 특수(연사)에만 붙고 기본 공격에는 안 붙어서, 무기 하나로
## 켜고 끌 수 없다 (`special_missile` 이 특수 전용인 것과 같은 사정).
##
## **박자를 재지 않는다.** 데미지가 들어가는 박자가 곧 소리의 박자다 — 요점이
## "따다다닥"이므로 여기서 문틈을 두면 그 리듬이 깎인다. 대신 공용 피격음을 그 리듬보다
## 길게 막아서(`DOT_SFX_INTERVAL`), 둘이 겹쳐 웅웅거리는 것을 막는다.
func _try_damage_tick_sfx(weapon: Dictionary, scope: String, now: float) -> void:
	if not weapon.get("%s_tick_sfx" % scope, false):
		return
	_mute_hit_sfx(now, DOT_SFX_INTERVAL)
	_play_damage_tick_sfx.rpc()


## 근접 무기끼리 맞부딪히는 소리.
##
## **양쪽이 다 근접일 때만 울린다.** 원거리·폭탄을 든 상대를 근접으로 때리는 것은
## 무기가 부딪히는 것이 아니라 한쪽이 일방적으로 맞는 것이다.
##
## **한 쌍에 한 번만 울린다.** 사거리가 같으면 두 젤리가 서로 들어가는데
## (`is_blocked()` — "같은 사거리면 둘 다 들어간다"), 각자 울리면 같은 한 번의
## 부딪힘에 소리가 둘 겹쳐 두 배로 커진다. 그래서 열쇠를 **순서 없는 쌍**으로 잡는다 —
## `a>b` 와 `b>a` 를 따로 세는 위쪽의 데미지·넉백 열쇠와 다른 점이다.
##
## 박자는 넉백과 같은 `Combat.MELEE_HIT_INTERVAL`(0.6초)이다. 지속 데미지 무기의
## 촘촘한 틱(위쪽에서 이미 돌아간다)에는 붙지 않는다 — 전기톱이 닿아 있는 동안
## 초당 네 번씩 쇳소리가 나면 부딪히는 소리가 아니라 웅웅거림이 된다.
func _try_melee_clash_sfx(attacker: Player, target: Player, now: float) -> void:
	if not _is_melee(Weapons.get_weapon(target.weapon_id)):
		return
	# **틱 소리를 내는 무기는 쇳소리를 내지 않는다** (광선검·전기톱). 0.2초마다 고르게
	# 나야 하는 "따다다닥" 사이에 0.6초마다 다른 소리가 끼면 리듬이 끊기고, 같은 순간에
	# 겹치면 두 소리가 한 음색으로 뭉쳐 더 높은 소리로 들린다 — 전에 겪은 그 문제다.
	if Weapons.get_weapon(attacker.weapon_id).get("basic_tick_sfx", false):
		return
	var a: int = attacker.owner_peer_id
	var b: int = target.owner_peer_id
	var clash_key := "clash>%d,%d" % [mini(a, b), maxi(a, b)]
	if now < _next_hit_at.get(clash_key, 0.0):
		return
	_next_hit_at[clash_key] = now + Combat.MELEE_HIT_INTERVAL
	# **부딪힘 소리가 이 순간의 피격음을 대신한다.** 쇳소리가 곧 "맞았다"는 소리라
	# 뒤에 몸통 타격음까지 붙으면 두 소리가 한 음색으로 뭉쳐 더 높은 소리로 들린다.
	# 문틈을 미리 채워 두면, 바로 뒤의 `server_apply_hit()` 이 내는 `damaged` 는
	# 조용히 지나간다 — 부딪힘이 쿨타임(0.6초)에 걸려 안 울린 타격은 그대로 피격음이 난다.
	# 쇳소리는 한 번뿐이라 그 순간만 막는다.
	_mute_hit_sfx(now, HIT_SFX_INTERVAL)
	_play_melee_clash_sfx.rpc()


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
	# 소총만 기본 공격에 총성이 붙는다. **무기 이름으로 가른다** — 바로 위 단검 분기와
	# 같은 방식이다. 소리 하나가 씬 하나라(`sfx_oneshot.gd`) 무기 표에 켬/끔 값을 두면
	# 그 값을 켠 다른 무기까지 소총 총성을 내게 된다.
	#
	# **경기 내내 울리는 것이 맞다**: 기본 공격은 조작 없이 간격마다 자동으로 나가고
	# (`_check_basic_attacks`), 총이 나가는데 소리가 없으면 그쪽이 더 어긋난다.
	# 대신 크기를 낮게 잡았다(-20dB, 씬에서). 소총 기본 간격은 1.2초이고 소리는
	# 0.78초라 서로 겹치지도 않는다.
	if weapon["name"] == "소총":
		_play_rifle_shot_sfx.rpc()
		# 이 탄이 맞으면 **소총만의 피격음**이 난다 (총성과 짝이다). 탄에 실어 보내는 것은
		# 맞는 순간을 아는 것이 탄이기 때문이다 — 알갱이·번개와 같은 방식이다.
		# **연사 탄에는 안 붙는다**: 그쪽은 이미 틱 소리(`special_tick_sfx`)가 리듬을 만든다.
		shot["impact_sfx"] = true
	# 활 — 활시위 소리. 소총과 같은 판단이다: 무기 이름으로 가르고, 경기 내내
	# 울리는 대신 크기를 낮게 잡았다(-20dB, 씬에서). 기본 간격은 0.7초이고 소리는
	# 0.70초로 맞춰 잘라 두어(앞뒤 무음 제거) 다음 발과 겹치지 않는다.
	elif weapon["name"] == "활":
		_play_bow_shot_sfx.rpc()
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
		# 양날 도끼가 상대 위로 떨어졌다 (예약이 그렇게 적어 온 경우만).
		# 여기까지 왔으면 아래에서 예약이 지워지므로 `_on_forced_landed()` 는 그냥
		# 지나간다 — 땅 착지음과 이 소리가 같이 울리는 일은 없다.
		if info.get("direct_hit_sfx", false):
			_play_axe_land_hit_sfx.rpc()
		if info.get("bleed_dps", 0.0) > 0.0:
			# 첫 타는 즉시 들어가고 그 뒤로 `interval`마다 이어진다.
			# 3초 출혈에 0.2초 간격이면 0·0.2·…·2.8초에 열다섯 번이다.
			_bleeds[target.owner_peer_id] = {
				"dps": info["bleed_dps"],
				"interval": info.get("bleed_interval", 1.0),
				"until": _now() + info["bleed_duration"],
				"next_at": _now(),
			}
		_special_pending.erase(peer_id)


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
##
## **소리는 이 박자를 따라가지 않는다.** 출혈은 `damaged` 를 `continuous` 로 내보내고
## (`Player.server_apply_dot`), 받는 쪽은 그것을 `DOT_SFX_INTERVAL`(0.6초) 문틈으로
## 거른다 — 촘촘하게 나눠도 3초에 다섯 번을 넘지 않으므로 웅웅거리지 않는다.
## 틱 소리("따다다닥")는 기본 공격 쪽에만 붙어 있어(`_try_damage_tick_sfx`)
## 출혈이 그 리듬에 끼어들지도 않는다.
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
		var interval: float = maxf(float(info.get("interval", 1.0)), 0.01)
		# **직전 예정 시각에 간격을 더한다** (`now + interval`이 아니다). 물리 프레임이
		# 0.0167초라 0.2초 간격은 늘 조금씩 늦게 걸리는데, 늦은 시각에서 다시 재면
		# 그 오차가 쌓여 3초 동안 들어가는 횟수가 열다섯에서 열넷으로 준다.
		info["next_at"] = float(info["next_at"]) + interval
		target.server_apply_dot(float(info["dps"]) * interval)


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
	_play_shotgun_blast.rpc(
		attacker.global_position + Vector2(0.0, Player.WEAPON_CENTER_Y),
		signf(float(attacker.facing)), reach, spread)
	# 소리도 **연출과 같은 자리**다 — 방아쇠를 당긴 순간이라 빗나가도 울린다.
	# 아래의 거리·각도·방패 검사는 전부 이 뒤에 온다.
	_play_shotgun_skill_sfx.rpc()
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
	# 크게 들어 올린 방패에 막혔다 (#222). 데미지도 넉백도 없다 —
	# 탄이 막혔을 때(`Projectile._blocked`)와 같다. 부채꼴 연출은 위에서 이미 띄웠으므로
	# 쏜 쪽에는 "여기까지였는데 막혔다"가 보인다.
	if _guarded_cone(attacker, target):
		return
	# 표에서 꺼낸 값은 Variant라 명시 타입으로 받는다 (#66).
	var near: float = weapon["special_damage"]
	var far: float = weapon["falloff_min_damage"]
	var damage := lerpf(near, far, clampf(distance / reach, 0.0, 1.0))
	target.server_apply_hit(damage, weapon["knockback"], attacker.global_position.x,
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
	var peer_id: int = attacker.owner_peer_id

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
	attacker.server_set_gauge(0.0)

	# 예고가 없는 값(0)이면 지금까지처럼 즉발이다 — 무기 표만 고쳐도 되돌릴 수 있게 남겨 둔다.
	if windup <= 0.0:
		_resolve_punch(attacker, shot)
		return true

	_play_punch_range.rpc(shot["origin"], aim, reach, spread, shot["charged"], windup)
	shot["at"] = _now() + windup
	_punch_pending[peer_id] = shot
	return true


## 예고가 찬 강펀치를 터뜨린다 (#231). 예약은 한 사람당 하나뿐이다 —
## 쿨타임(5초)이 예고(0.2초)보다 훨씬 길어서 겹칠 수가 없다.
func _tick_punches() -> void:
	var now := _now()
	for peer_id: int in _punch_pending.keys():
		var shot: Dictionary = _punch_pending[peer_id]
		if now < shot["at"]:
			continue
		_punch_pending.erase(peer_id)
		var attacker := get_player(peer_id)
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
	for peer_id: int in _sword_swings.keys():
		var swing: Dictionary = _sword_swings[peer_id]
		if now < swing["at"]:
			continue
		_sword_swings.erase(peer_id)
		var attacker := get_player(peer_id)
		if attacker == null or not attacker.alive:
			continue
		var target := _opponent_of(peer_id)
		if target == null or not target.alive:
			continue
		# 비율은 **맞는 순간의** 현재 체력에 걸린다 — 휘두르는 동안 깎였으면 그만큼 적다.
		target.server_apply_hit(target.hp * float(swing["hp_ratio"]),
			int(swing["knockback"]), attacker.global_position.x, 0.0, "special")
		_play_light_burst.rpc(target.global_position + Vector2(0.0, Player.BODY_BOTTOM))


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
	_play_heavy_punch.rpc(shot["origin"], aim, reach, shot["spread"], shot["charged"])
	# 소리도 주먹 연출과 **같은 자리**다. 누른 순간이 아니라 여기인 것은, 예고(0.5초)를
	# 두고 나서 들어가는 무기라 누를 때 울리면 소리가 그친 뒤에 주먹이 들어가기 때문이다.
	# 즉발이든(예고 0) 예고를 거치든 이 한 곳을 지나므로 두 길이 갈리지 않는다.
	_play_knuckle_punch_sfx.rpc()

	var target := _opponent_of(attacker.owner_peer_id)
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
	target.server_apply_hit(damage, int(shot["knockback"]), body.x, 0.0, "special")


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
		projectile.sparked.connect(_on_dagger_sparked)
		projectile.burst.connect(_on_cannon_burst)
		projectile.ticked.connect(_on_projectile_ticked)
		projectile.impacted.connect(_on_projectile_impacted)
		projectile.exploded.connect(_on_bomb_exploded)
	return projectile


## 서버에서 지우면 스포너가 클라이언트에서도 같이 지운다.
func _on_projectile_finished(projectile: Projectile) -> void:
	projectile.queue_free()


## 단검을 주우면 다시 들고 있는 상태가 된다.
func _on_dagger_picked_up(peer_id: int, projectile: Projectile) -> void:
	_dagger_held[peer_id] = true
	projectile.queue_free()
	# 단검이 손에 돌아오는 소리. **줍는 것과 특수(자동 재수집)가 같은 소리다** —
	# 둘 다 "떨어져 있던 단검이 손에 돌아왔다"는 하나의 사건이고, 다른 점은
	# 걸어가서 주웠는지 불러들였는지뿐이다.
	_play_dagger_return_sfx.rpc()


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
			#
			# **누른 프레임에 때리지 않는다** (#247). 검을 머리 위로 들어 올렸다
			# 내려베고, 다 내려온 순간에 들어간다 — 손에 든 검이 가만히 있는데
			# 상대가 맞으면 무엇이 때렸는지 화면에서 읽히지 않는다(강펀치 #231과 같은 이유).
			# 그림은 각 피어가 복제된 시작 신호를 받아 알아서 그리고, 시각은
			# `_tick_sword_swings()`가 잰다. 쿨타임은 지금까지처럼 누른 순간부터 돈다.
			# **소리는 누른 순간에 낸다 — 내려베는 순간이 아니다.** 이 특수는 검을
			# 들어 올렸다(0.26초) 내려베는(0.12초) 동작이고, 외침은 그 들어 올리는
			# 동작에 얹혀야 맞는다. 데미지가 들어가는 0.38초 뒤에 울리면 소리가
			# 동작을 뒤따라와서 "멈칫하고 내려친다"가 화면에만 남고 귀에는 안 남는다.
			# 사거리(150) 밖이라 위에서 돌아간 경우에는 울리지 않는다 — 쿨타임도
			# 돌지 않는 자리라 소리만 나면 쓴 것처럼 들린다.
			_play_sword_skill_sfx.rpc()
			attacker.server_start_swing(weapon["special_windup"], weapon["special_swing"])
			_sword_swings[peer_id] = {
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
			#
			# **소리는 걸기 전에 낸다** — 광선검 관통음과 같은 자리다. 화면에 나타나는
			# 것이 버프 표시뿐이고 날아가는 것도 때리는 것도 없어서, 켜진 순간을
			# 알려 줄 것이 소리 말고는 없다.
			_play_skill_cast_sfx.rpc()
			attacker.server_apply_buff("stun", weapon["stun_duration"],
				weapon["special_duration"])
			return true
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
			return _punch_cone(attacker, weapon)
		"광선검":
			# 관통 — 일정 시간 상대 무기의 막기를 무시한다.
			#
			# **소리는 걸기 전에 낸다** — 대포 총 발사음과 같은 자리다. 이 특수는 눈에
			# 보이는 것이 관통 빛무리뿐이고 날아가는 것이 없어서, 켜진 순간을 알려 주는
			# 것이 소리 말고는 없다. 쿨타임 8초라 자주 울리지도 않는다.
			_play_laser_sword_skill_sfx.rpc()
			attacker.server_apply_buff("pierce", 1.0, weapon["special_duration"])
			return true
		"장대":
			# 상시 사거리(`reach_multiplier`)가 아니라 **특수 전용 배율**을 쓴다.
			# 상시로 걸면 특수를 쓰지 않아도 근접 공격을 전부 막는다 (막기 판정 참고).
			#
			# **소리는 걸기 전에 낸다** — 망치·광선검과 같은 자리다. 봉이 길어지는 것은
			# 보이지만(`art_grows_with_reach`) 그 순간을 짚어 주는 소리가 없었다.
			_play_skill_cast_sfx.rpc()
			attacker.server_apply_buff("reach", weapon["special_reach_multiplier"],
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
			#
			# **소리는 걸기 전에 낸다** — 광선검 관통음과 같은 자리다. 특수가 켜지는 그
			# 순간이고, 벽에 부딪혀 일찍 끝나도 소리는 끝까지 울린다
			# (씬이 스스로 사라진다, `sfx_oneshot.gd`). 톱 소리가 회전부터 덮으므로
			# 도는 동안 조용한 구간이 생기지 않는다. 바람 소리는 그 뒤, 실제로
			# 내지르는 순간에 따로 난다(`_on_dash_launched()`).
			_play_chainsaw_dash_sfx.rpc()
			var spin: float = weapon.get("spin_time", 0.0)
			if spin > 0.0:
				attacker.server_start_forced("spin", spin)
			else:
				attacker.server_start_forced("dash", attacker.dash_time())
			_special_pending[peer_id] = {
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
			# **소리가 셋으로 갈린다** — 이 무기는 결과가 셋이라서다: 켜는 순간,
			# 상대에게 직격한 착지, 빗나가 땅에 닿은 착지. 여기서 내는 것은 첫째다
			# (솟는 순간; 전기톱 돌진음과 같은 자리다).
			_play_axe_skill_sfx.rpc()
			attacker.server_start_forced("rise", _rise_time())
			_special_pending[peer_id] = {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"modes": ["fall"],
				"landing_damage": weapon["landing_damage"],
				"landing_radius": weapon["landing_radius"],
				"landing_rupture_speed": weapon["landing_rupture_speed"],
				# 직격했을 때 낼 소리. **무기 이름으로 가르지 않고 여기 실어 보낸다** —
				# `_check_pending_specials()` 는 전기톱 돌진·글러브도 함께 지나가는
				# 공용 자리라, 거기서 이름을 다시 묻는 대신 예약에 적어 둔다
				# (`landing_radius` 가 착지 쪽 갈림을 겸하는 것과 같은 방식이다).
				"direct_hit_sfx": true,
			}
			return true
		"활":
			# 관통 화살 여러 발 — 벌어진 평행. **발 수는 무기 표가 정한다** (#128).
			# 전에는 여기서 3발을 하드코딩해 표의 special_projectiles 가 죽은 값이었다.
			var count: int = weapon.get("special_projectiles", 1)
			# 폭격 소리는 다발이어도 **한 번만** 울린다 — 소총 연사음과 같은 자리다.
			# 화살 다섯 발마다 울리면 같은 소리가 다섯 겹 겹쳐 다섯 배로 커진다.
			# 쏘기 전에 부른다: 아래 `_server_fire`가 탄이 나가는 그 순간이다.
			_play_bow_skill_sfx.rpc()
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"pierce_targets": true,
			}, _parallel_offsets(count, Combat.PARALLEL_SPACING))
			return true
		"대포 총":
			# 특수만 불꽃 꼬리 미사일이다 — 기본 공격 탄은 파란 구슬로 나간다
			# (무기 표의 `projectile_orb`; 전에는 공용 노란 막대였다).
			#
			# **소리는 특수에만 붙는다.** 기본 공격은 1.4초마다 조작 없이 자동으로
			# 나가서(`_check_basic_attacks`) 같은 소리를 달면 경기 내내 울린다 —
			# 스킬은 쿨타임 6초에 직접 누르는 것이라 한 번 울릴 값이 있다.
			# 쏘기 전에 부른다: 아래 `_server_fire`는 탄이 나가는 그 순간이다.
			_play_cannon_shot_sfx.rpc()
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
			#
			# **소리는 쏘기 전에 낸다** — 대포 총·활 특수와 같은 자리다.
			# 아래 `_server_fire`가 삼지창이 손을 떠나는 그 순간이다.
			_play_skill_cast_sfx.rpc()
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
			# 던지는 소리 (#261). **쏘기 전에 부른다** — 폭탄·대포 총·소총과 같은 자리로,
			# 아래 `_server_fire`가 표창이 손을 떠나는 그 순간이다.
			#
			# **강화든 아니든 같은 소리다.** 손에서 나가는 동작이 같아서다 — 무엇을
			# 던졌는지는 그림(`empowered_file`, 빨간 표창)이 이미 말하고, 강화 쪽은
			# 맞는 순간에 자기 소리(`shuriken_swap`)를 따로 낸다. 소리를 여기서
			# 둘로 가르면 같은 동작에 두 이름이 붙는다 (너클 강펀치와 같은 판단).
			_play_shuriken_throw_sfx.rpc()
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
			# 던지는 소리. 던지는 순간에 나므로 **터지는 소리(`exploded`)와 자리가 다르다** —
			# 사이에 도화선 3초가 있어서 둘이 겹치지 않는다. 쏘기 전에 부르는 것은
			# 대포 총·소총과 같다.
			_play_bomb_throw_sfx.rpc()
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
			#
			# 틱 소리는 탄에 실어 보낸다 — 소리가 나야 하는 순간이 "쏘는 때"가 아니라
			# **"맞는 때"**라서, 그때를 아는 것은 탄이다(`Projectile.ticked`).
			# 기본 공격 탄에는 실리지 않으므로 그쪽은 지금까지처럼 공용 피격음이다.
			#
			# **연사음은 한 번만 튼다.** 소리 파일 자체가 2초짜리 연발이라 지속시간
			# (`burst_duration`, 2초)과 길이를 맞춰 두었다 — 발마다 틀면 0.1초 간격으로
			# 20개가 겹쳐 웅웅거린다. 쏘기 전에 부르는 것은 대포 총과 같다.
			# 위의 틱 소리와는 자리가 다르다: 이건 **쏘는** 소리, 그건 **맞는** 소리다.
			_play_rifle_burst_sfx.rpc()
			_start_burst(peer_id, weapon["special_damage"], weapon["knockback"],
				weapon["burst_interval"], weapon["burst_duration"], 0, -1,
				{"tick_sfx": weapon.get("special_tick_sfx", false)})
			return true
		"단검":
			# 특수 = 자동 재수집. 주우러 가지 않아도 손으로 돌아온다.
			if _dagger_held.get(peer_id, true):
				return false   # 이미 들고 있으면 쓸 것이 없다
			_dagger_held[peer_id] = true
			for projectile: Projectile in projectiles_root.get_children():
				if projectile.pickup_owner == peer_id:
					projectile.queue_free()
			# 줍는 것과 같은 소리다 (`_on_dagger_picked_up()` 참고).
			# **위의 이미-들고-있음 검사 뒤에 온다** — 그쪽은 `false` 로 빠져나가
			# 쿨타임도 안 돌므로 아무 일도 일어나지 않은 것이고, 소리도 나면 안 된다.
			_play_dagger_return_sfx.rpc()
			return true
		"방패":
			# **하나뿐인 길게/짧게로 갈리는 특수다.** 길게(0.3초 이상, `Player.LONG_PRESS_TIME`)는
			# 크기 증가, 짧게는 던지기다. `long_press`는 **서버가 잰 것**이라 클라이언트가
			# 속일 수 없고, 길게가 확정되는 순간 뗄 때를 기다리지 않고 바로 발동한 뒤
			# 눌린 기록을 지운다 — 그래서 손을 뗄 때 던지기가 겹쳐 나가지 않고 쿨타임도
			# 한 번만 돈다 (`Player._check_long_press`·`_receive_skill` 참고).
			if long_press:
				# 소리는 걸기 전에 낸다 (광선검 관통음과 같은 자리) — 크기 증가는
				# 그림이 커지는 것 말고는 알림이 없어서, 켜진 순간을 소리로 짚어 준다.
				_play_shield_size_sfx.rpc()
				attacker.server_apply_buff("size", weapon["size_multiplier"], weapon["special_duration"])
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


## 강펀치가 곧 들어올 범위 (#231). 안쪽이 `windup`에 걸쳐 차오르므로 **언제 들어오는지**도
## 같이 보인다. 그리는 부채꼴은 실제로 맞는 부채꼴과 같다.
@rpc("authority", "call_local", "reliable")
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
@rpc("authority", "call_local", "reliable")
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


## 삼지창 특수가 맞혔다 (서버 전용 — 투사체가 알려 온다).
func _on_lightning_struck(at: Vector2) -> void:
	_play_lightning_strike.rpc(at)


## 단검이 맞혔다 (#250). 번개와 같은 짜임이다 — 탄은 신호만 내고 연출은 여기가 띄운다.
func _on_dagger_sparked(at: Vector2) -> void:
	_play_hit_sparks.rpc(at)


## 대포 총 포탄이 맞혔다 (서버 전용 — 투사체가 알려 온다). 위 둘과 같은 짜임이다.
func _on_cannon_burst(at: Vector2) -> void:
	_play_cannon_burst.rpc(at)


## 틱 소리를 내는 탄(소총 연사)이 맞혔다 (서버 전용 — 투사체가 알려 온다).
##
## **무기 표를 다시 보지 않는다.** 어느 무기의 연사인지는 탄을 쏠 때 이미 정해져
## `tick_sfx` 로 실려 있다 — 여기서 쏜 젤리의 지금 무기를 되짚으면, 탄이 날아가는 동안
## 라운드가 바뀌어 무기가 갈렸을 때(`server_set_weapon`) 엉뚱한 판단이 된다.
##
## 공용 피격음을 막는 것은 근접 틱과 같다 (`_try_damage_tick_sfx()`).
func _on_projectile_ticked() -> void:
	_mute_hit_sfx(_now(), DOT_SFX_INTERVAL)
	_play_damage_tick_sfx.rpc()


## 소총 기본 공격의 탄이 맞았다 (서버 전용 — 투사체가 알려 온다).
##
## **무기 표를 다시 보지 않는다** — 위의 틱과 같은 이유로, 어느 무기의 탄인지는 쏠 때
## 이미 `impact_sfx` 로 실려 있다.
##
## **공용 피격음을 대신한다.** 총알이 몸에 박히는 소리가 곧 "맞았다"는 소리라, 뒤에
## 몸통 타격음까지 붙으면 두 소리가 한 음색으로 뭉쳐 더 높은 소리로 들린다 —
## 근접 부딪힘 소리(`_try_melee_clash_sfx()`)에서 겪은 그대로다. 그래서 문틈을 미리
## 채워 두고, 바로 뒤의 `server_apply_hit()` 이 내는 `damaged` 는 조용히 지나가게 한다.
## 이 순서가 되도록 탄이 신호를 **때리기 전에** 낸다.
##
## 박자를 재지 않는다 — 소총 기본 간격(1.2초)이 곧 박자이고 소리는 0.22초다.
func _on_projectile_impacted() -> void:
	_mute_hit_sfx(_now(), HIT_SFX_INTERVAL)
	_play_rifle_hit_sfx.rpc()


## 폭탄이 터졌다 (서버 전용 — 투사체가 알려 온다).
##
## **공용 피격음을 막지 않는다.** 틱 소리(위)와 달리 이건 0.2초마다 되풀이되는 것이
## 아니라 한 번뿐이고, 터진 것과 그 안에 누가 있었는지는 서로 다른 소식이다 —
## 빗나간 폭탄도 터지는 소리는 나야 하고, 맞았으면 맞은 소리가 겹쳐 나는 편이 맞다.
## 연출도 같은 자리에서 띄운다 (#262) — 터진 순간이 곧 이 신호다. 소리와 짝이라
## 빗나간 폭탄에도 함께 뜬다.
func _on_bomb_exploded(at: Vector2, blast_radius: float) -> void:
	_play_bomb_explode_sfx.rpc()
	_play_bomb_blast.rpc(at, blast_radius)


## 어떤 피해든 들어갔다 (서버 전용 — 젤리가 알려 온다). 피격음을 울린다.
##
## **무기를 가리지 않는다.** 데미지가 지나가는 두 문에서만 신호가 오므로
## (`Player.damaged`), 무기가 늘어도 이 함수는 그대로다 — 그것이 "기본적으로" 울린다는 뜻이다.
##
## **한 소리는 전체에 하나다.** 맞은 젤리별로 세지 않는다 — 사거리가 같아 서로 동시에
## 들어갈 때(`is_blocked()` 의 "같은 사거리면 둘 다 들어간다") 젤리별로 울리면 같은
## 순간에 같은 소리가 둘 겹쳐 두 배로 커진다. 근접 부딪힘 소리를 한 쌍에 한 번으로
## 묶은 것과 같은 판단이다 (`_try_melee_clash_sfx()`).
##
## 박자를 재는 자리로 `_next_hit_at` 을 쓰는 것은 그 표가 라운드마다 비워지기 때문이다
## (`_start_round()`) — 따로 변수를 두면 비우는 곳 세 군데를 같이 고쳐야 하고,
## 한 곳을 빠뜨리면 지난 라운드의 시각이 남아 첫 타격이 조용해진다.
func _on_player_damaged(_peer_id: int, continuous: bool) -> void:
	if not _hit_sfx_due(_now(), continuous):
		return
	_play_hit_sfx.rpc()


## 기절하며 맞았다 (서버 전용 — 젤리가 알려 온다). 기절을 거는 무기는 둘뿐이고
## 둘 다 특수로만 건다: 망치 특수가 켜져 있는 동안의 근접 타격과, 던진 삼지창이다.
##
## **공용 피격음을 막지 않는다.** 데미지와 기절은 같은 타격의 다른 두 결과이고,
## 기절음은 그 위에 얹히는 표시다 — 광선검 틱처럼 0.2초마다 되풀이되어 웅웅거릴
## 일도 없다: 망치는 0.9초 간격(소리는 0.83초)이고 삼지창은 쿨타임 7초다.
func _on_player_stunned(_peer_id: int) -> void:
	_play_stun_hit_sfx.rpc()


## 너클 게이지가 75%를 넘어섰다 (서버 전용 — 젤리가 알려 온다, #225).
##
## **오라가 켜지는 그 순간이다.** 화면에서는 몸에 오라가 돌기 시작하고 게이지 바 색이
## 바뀌는데, 맞고 있는 사람은 자기 머리 위를 보고 있지 않다 — 소리가 "이제 강펀치가
## 달라진다"를 대신 알린다.
##
## 박자를 재지 않는다. 문턱을 넘는 것은 게이지가 0으로 돌아간 뒤에야 다시 있는 일이고
## (특수를 쓰거나 라운드가 바뀌거나), 그 사이에 두 번 울릴 길이 없다.
##
## **피격음과 같은 순간에 나간다** — 게이지는 맞아야 차기 때문이다. 그래서 씬의
## `volume_db` 를 피격음(-20)보다 낮게(-22) 잡아 두 소리가 한 덩어리로 뭉치지 않고
## 타격 아래에 깔리게 했다. 뜻이 다른 소리라 한쪽이 다른 쪽 자리를 대신할 수는 없다
## (`_mute_hit_sfx()` 가 근접 부딪힘에서 한 것과는 경우가 다르다).
func _on_player_gauge_charged(_peer_id: int) -> void:
	_play_knuckle_charged_sfx.rpc()


## 지금 피격음을 울릴 차례인가. 참을 돌려주면서 **다음 차례를 함께 미룬다** —
## 묻는 것과 미루는 것을 나누면 부르는 쪽이 한쪽을 빠뜨릴 수 있다.
##
## 시각을 인자로 받는 것은 박자를 눈으로 확인할 수 있게 하려는 것이다 (트리 없이 부른다).
func _hit_sfx_due(now: float, continuous: bool) -> bool:
	if now < _next_hit_at.get("hitsfx", 0.0):
		return false
	_next_hit_at["hitsfx"] = now + (DOT_SFX_INTERVAL if continuous else HIT_SFX_INTERVAL)
	return true


## 피격음을 `seconds` 동안 삼킨다 — 다른 소리가 그 자리를 대신할 때 쓴다.
##
## **얼마나 삼키는지를 부르는 쪽이 정한다.** 대신하는 소리가 한 번뿐이면(부딪힘 쇳소리)
## 그 순간만 막으면 되지만, 대신하는 소리가 **계속 이어지면**(0.2초마다 나는 틱)
## 한 순간만 막아서는 다음 틱과 함께 공용 피격음이 새어 나온다 — 그러면 둘이 겹쳐
## 리듬이 웅웅거림이 된다. 이어지는 소리는 그 간격보다 길게 막아야 한다.
func _mute_hit_sfx(now: float, seconds: float) -> void:
	_next_hit_at["hitsfx"] = now + seconds


## 삼지창 특수의 번개. `at`은 맞은 젤리의 발밑이고, 줄기는 화면 위에서 거기까지 내려온다.
@rpc("authority", "call_local", "reliable")
func _play_lightning_strike(at: Vector2) -> void:
	var bolt := LIGHTNING_STRIKE_SCENE.instantiate()
	# 위치를 붙이기 전에 넣는다 — `_ready()`가 이 값으로 줄기 모양의 씨앗을 잡는다.
	bolt.position = at
	effects_root.add_child(bolt)


## 단검에 맞은 자리에 튀는 빨간 알갱이 (#250). `at`은 날이 닿은 자리다.
##
## 위치를 붙이기 전에 넣는 것은 번개와 같은 이유다 — `_ready()`가 이 값으로 알갱이가
## 튀는 방향의 씨앗을 잡아서, 나중에 넣으면 모든 피격이 (0, 0)으로 같은 모양이 된다.
@rpc("authority", "call_local", "reliable")
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
@rpc("authority", "call_local", "reliable")
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
@rpc("authority", "call_local", "reliable")
func _play_cannon_burst(at: Vector2) -> void:
	var burst := CANNON_BURST_SCENE.instantiate()
	burst.position = at
	effects_root.add_child(burst)


## 대포 총 특수(미사일)를 쏠 때의 발사음. **소리라서 위치를 받지 않는다** —
## 연출과 달리 어디서 났는지를 화면에 남기지 않으므로 좌표가 쓸 데가 없다.
##
## `Effects` 아래에 붙는 것은 연출과 같다 (한 판이 끝나 그 밑을 비울 때 같이 사라진다).
@rpc("authority", "call_local", "reliable")
func _play_cannon_shot_sfx() -> void:
	effects_root.add_child(CANNON_SHOT_SFX_SCENE.instantiate())


## 근접 무기끼리 맞부딪히는 소리. 발사음과 같은 이유로 위치를 받지 않는다.
## 울릴 조건과 박자는 `_try_melee_clash_sfx()` 가 정한다.
@rpc("authority", "call_local", "reliable")
func _play_melee_clash_sfx() -> void:
	effects_root.add_child(MELEE_CLASH_SFX_SCENE.instantiate())


## 피해가 들어간 소리. 위 둘과 같은 이유로 위치를 받지 않는다.
## 울릴 박자는 `_on_player_damaged()` 가 정한다.
@rpc("authority", "call_local", "reliable")
func _play_hit_sfx() -> void:
	effects_root.add_child(HIT_SFX_SCENE.instantiate())


## 광선검 특수(관통)를 켤 때의 소리. 위 셋과 같은 이유로 위치를 받지 않는다.
## 박자를 재지 않는 것은 대포 총 발사음과 같다 — 쿨타임(8초)이 곧 박자다.
@rpc("authority", "call_local", "reliable")
func _play_laser_sword_skill_sfx() -> void:
	effects_root.add_child(LASER_SWORD_SKILL_SFX_SCENE.instantiate())


## 데미지가 들어갈 때마다 나는 짧은 틱. 울릴 조건은 `_try_damage_tick_sfx()` 가 정한다.
##
## **다른 소리보다 자주 오간다** — 광선검·전기톱은 초당 다섯 번, 소총 연사는 그 이상이다.
## 그래도 `reliable` 로 두는 것은 다른 소리·연출과 같은 길을 쓰기 위해서다: 순서가
## 어긋나거나 빠지면 "따다다닥"의 리듬이 그만큼 깨지고, 한 판에 오가는 양은
## 투사체 스폰(연사 20발)보다 적다.
@rpc("authority", "call_local", "reliable")
func _play_damage_tick_sfx() -> void:
	effects_root.add_child(DAMAGE_TICK_SFX_SCENE.instantiate())


## 단검이 손에 돌아오는 소리 (주워서든 특수로 불러들여서든).
##
## 박자를 재지 않는다. 한 번 돌아오면 다시 던져야 또 돌아올 수 있어서
## (`_dagger_held`), 연달아 울릴 길이 애초에 없다.
@rpc("authority", "call_local", "reliable")
func _play_dagger_return_sfx() -> void:
	effects_root.add_child(DAGGER_RETURN_SFX_SCENE.instantiate())


## 방패를 크게 들어 올리는 소리 (방패 특수의 길게 누르기).
##
## 박자를 재지 않는다. 쿨타임(5초)이 곧 박자이고, 길게/짧게가 갈리는 순간 한 번만
## 부른다 — 광선검 관통음과 같은 자리다. **던지기 쪽에는 안 붙는다**: 소리가 갈라져야
## 화면을 안 보고도 어느 쪽이 나갔는지 알 수 있다.
@rpc("authority", "call_local", "reliable")
func _play_shield_size_sfx() -> void:
	effects_root.add_child(SHIELD_SIZE_SFX_SCENE.instantiate())


## 소총 기본 공격의 총성. 울릴 조건은 `_try_ranged_basic()` 이 정한다.
##
## **박자를 따로 재지 않는다** — 기본 간격(1.2초)이 곧 박자다. 피격음처럼 여러 발이
## 한 순간에 몰리는 일이 없어서 뭉칠 것도 없다.
@rpc("authority", "call_local", "reliable")
func _play_rifle_shot_sfx() -> void:
	effects_root.add_child(RIFLE_SHOT_SFX_SCENE.instantiate())


## 소총 특수(연발)의 연사음. 특수를 켜는 순간 **한 번만** 울린다 —
## 소리 길이가 연사 지속시간과 같아서 그 2초를 통째로 덮는다.
## 소총 기본 공격의 탄이 몸에 맞는 소리. 울릴 조건은 `_on_projectile_impacted()` 이
## 정한다 — 그 자리에서 공용 피격음도 함께 막는다.
@rpc("authority", "call_local", "reliable")
func _play_rifle_hit_sfx() -> void:
	effects_root.add_child(RIFLE_HIT_SFX_SCENE.instantiate())


@rpc("authority", "call_local", "reliable")
func _play_rifle_burst_sfx() -> void:
	effects_root.add_child(RIFLE_BURST_SFX_SCENE.instantiate())


## 활 기본 공격의 활시위 소리. 울릴 조건은 `_try_ranged_basic()` 이 정한다.
##
## **박자를 따로 재지 않는다** — 기본 간격(0.7초)이 곧 박자이고, 소리를 그보다
## 짧게(0.70초) 잘라 두어 겹칠 자리가 없다.
@rpc("authority", "call_local", "reliable")
func _play_bow_shot_sfx() -> void:
	effects_root.add_child(BOW_SHOT_SFX_SCENE.instantiate())


## 활 특수(관통 화살 폭격)의 소리. 특수를 켜는 순간 **한 번만** 울린다 —
## 다발(5발)마다 울리면 한 번 크게 쏜 것이 아니라 다섯 배로 커진 소리가 된다.
##
## 박자를 재지 않는다. 쿨타임(6초)이 곧 박자다.
@rpc("authority", "call_local", "reliable")
func _play_bow_skill_sfx() -> void:
	effects_root.add_child(BOW_SKILL_SFX_SCENE.instantiate())


## 전기톱 특수(관통 돌진)의 톱 소리. 특수를 켜는 순간 한 번만 울린다.
##
## 박자를 재지 않는다 — 쿨타임(7초)이 곧 박자다. 소리는 1.62초이고, 제자리 회전
## 0.45초(#260)에 돌진이 길어도 화면 폭을 건너는 시간(약 1.03초, `Player.dash_time()`)이
## 붙어 1.48초다 — 회전부터 돌진 끝까지를 톱 소리가 거의 그대로 덮는다.
## **손에 든 톱이라 그대로 두었다** — 총성처럼 한 번 나고 끝나야 하는 소리가 아니다.
@rpc("authority", "call_local", "reliable")
func _play_chainsaw_dash_sfx() -> void:
	effects_root.add_child(CHAINSAW_DASH_SFX_SCENE.instantiate())


## 전기톱이 내지르는 순간 바람을 가르는 소리 (#260). 회전이 끝나는 그 순간에
## 한 번만 울린다 — 부르는 자리는 `_on_dash_launched()` 다.
##
## **톱 소리와 나뉘어 있는 이유**: 특수가 두 단계라 소리도 둘이다. 톱은 켜는 순간부터
## 계속 돌아가는 소리고, 바람은 내지르는 그 한 순간의 소리다 — 양날 도끼가 켜는 순간·
## 직격 착지·빗나간 착지로 셋을 나눈 것과 같은 판단이다.
##
## 크기는 톱 소리(-16dB)보다 조금 작게 잡았다(씬에서 -18dB) — 바람이 톱보다 크면
## 무엇을 들고 있는지가 뒤집혀 들린다.
@rpc("authority", "call_local", "reliable")
func _play_chainsaw_wind_sfx() -> void:
	effects_root.add_child(CHAINSAW_WIND_SFX_SCENE.instantiate())


## 검 특수("데마시아")의 외침. 울릴 조건은 `_execute_special()` 의 `"검"` 갈래가
## 정한다 — 사거리 안에서 실제로 발동한 경우만이다.
##
## 박자를 재지 않는다 — 쿨타임(6초)이 곧 박자다. 소리가 2.99초로 긴데, 데미지가
## 들어가는 것은 0.38초 뒤이므로 **소리는 판정보다 오래 남는다**. 그것이 맞다:
## 외침이 끝나야 한 방이 끝나는 무기다.
@rpc("authority", "call_local", "reliable")
func _play_sword_skill_sfx() -> void:
	effects_root.add_child(SWORD_SKILL_SFX_SCENE.instantiate())


## 양날 도끼 특수를 켜는 소리 (솟아오르는 순간). 울릴 조건은 `_execute_special()` 의
## `"양날 도끼"` 갈래가 정한다.
##
## 박자를 재지 않는다 — 쿨타임(`special_cooldown`)이 곧 박자다. 다만 이 소리는
## **착지음과 겹친다**: 솟는 데 0.25초(`_rise_time()`)이고 그만큼 떨어져 내리므로
## 공중에 있는 시간이 0.5초 안팎인데 이 소리는 1.60초다. 셋을 다르게 들리는 소리로
## 받았으므로 같은 소리가 겹쳐 커지는 문제는 아니고, 솟는 소리가 남은 채로 땅이
## 갈라지는 쪽이 순서대로 들린다.
@rpc("authority", "call_local", "reliable")
func _play_axe_skill_sfx() -> void:
	effects_root.add_child(AXE_SKILL_SFX_SCENE.instantiate())


## 양날 도끼가 **빗나가 땅에** 떨어진 소리. 울릴 조건은 `_on_forced_landed()` 가 정한다 —
## 땅 격파 연출(`_play_shockwave`)과 같은 순간, 같은 자리다.
@rpc("authority", "call_local", "reliable")
func _play_axe_land_ground_sfx() -> void:
	effects_root.add_child(AXE_LAND_GROUND_SFX_SCENE.instantiate())


## 양날 도끼가 **상대 위로** 떨어진 소리 (직격). 울릴 조건은
## `_check_pending_specials()` 가 정한다 — 예약에 `direct_hit_sfx` 가 적혀 있을 때만이다.
##
## 위의 땅 착지음과 **둘 중 하나만 울린다**. 직격하면 예약이 지워져 착지 쪽이 그냥
## 지나가고, 빗나가면 여기 올 것이 없다 — 한 번의 특수가 소리를 두 번 내지 않는다.
@rpc("authority", "call_local", "reliable")
func _play_axe_land_hit_sfx() -> void:
	effects_root.add_child(AXE_LAND_HIT_SFX_SCENE.instantiate())


## 망치·삼지창·장대 특수의 소리. 울릴 조건은 `_execute_special()` 의 그 세 갈래가 정한다.
##
## **셋이 같은 소리를 쓴다** — 받은 소리가 하나여서다. 무기마다 갈라 두면 같은 파일을
## 세 씬이 가리키게 되어, 나중에 하나를 바꿀 때 나머지 둘이 조용히 남는다.
## 소리를 무기별로 나눌 때가 오면 이 함수를 셋으로 가르는 것이 그 자리다.
##
## 박자를 재지 않는다 — 쿨타임(망치 8초, 삼지창 7초, 장대 10초)이 곧 박자다.
## 소리는 1.05초라 그 안에 두 번 울릴 길이 없다.
##
## 겹치는 것이 없는지도 봐 두었다: 망치·장대는 능력만 걸어서 이 순간에 다른 소리가
## 없고, 삼지창은 던지는 순간이라 맞을 때 나는 기절음(`_play_stun_hit_sfx`)과는
## 시각이 갈린다 — 날아가는 시간만큼 뒤다.
@rpc("authority", "call_local", "reliable")
func _play_skill_cast_sfx() -> void:
	effects_root.add_child(SKILL_CAST_SFX_SCENE.instantiate())


## 샷건 특수가 나갔다. 울릴 조건은 `_cone_blast()` 가 정한다 — 부채꼴 연출을 띄우는
## 그 자리이고, **맞았는지와 무관하다**: 빗나간 산탄도 총성은 난다.
##
## 실을 것이 없다. 부채꼴이 어디로 열렸는지는 연출(`_play_shotgun_blast`)이 이미 그리고,
## 소리에는 좌우가 없다 (`sfx_oneshot.gd`).
##
## 박자를 재지 않는다 — 쿨타임(2.5초)이 곧 박자이고 소리는 1.39초다. 샷건은 기본 공격이
## 없어서(무기 표의 `basic_damage: 0`) 이 소리와 겹칠 다른 소리도 없다. 다만 맞았으면
## 공용 피격음이 뒤따라 겹치는데, 그것은 막지 않는다 — 폭탄 터지는 소리와 같은 판단으로,
## 쏜 것과 맞은 것은 서로 다른 소식이다.
@rpc("authority", "call_local", "reliable")
func _play_shotgun_skill_sfx() -> void:
	effects_root.add_child(SHOTGUN_SKILL_SFX_SCENE.instantiate())


## 무기 선택 창이 떴다. 울릴 조건은 `_receive_pick_start()` 가 정한다 — 라운드마다 한 번,
## 창이 열리는 그 순간이다.
##
## **여기만 `@rpc` 가 아니다.** 위아래의 소리들은 서버가 판정을 끝내고 각 피어에게
## 알리는 것이라 원격 호출이 필요했지만, 이 소리를 부르는 자리(`_receive_pick_start`)는
## 이미 서버가 보낸 것을 받아 **각자의 화면에서** 도는 중이다. 여기에 `.rpc()` 를 또
## 붙이면 클라이언트가 남에게 소리를 시키는 꼴이 되고, 그 권한은 서버에만 있어서
## 조용히 막힌다.
##
## **헤드리스 서버에서는 이 함수가 아예 안 돈다** — 부르는 자리가 `call_remote` 라
## 서버 자신은 지나가지 않는다. 소리 장치가 없는 쪽에서 노드만 쌓이는 일이 없다.
##
## 박자를 재지 않는다 — 라운드 사이에 한 번뿐이고, 소리는 1.06초다. 이때 화면에서
## 나는 다른 소리도 없다: 판이 끝나 무기들이 멎은 뒤에 뜨는 창이다.
func _play_weapon_pick_sfx() -> void:
	effects_root.add_child(WEAPON_PICK_SFX_SCENE.instantiate())


## 표창을 던지는 소리 (#261). 울릴 조건은 특수의 "표창" 갈래가 정한다.
##
## 박자를 재지 않는다 — 쿨타임(2.5초)이 곧 박자이고 소리는 0.44초다. 폭탄 던지는
## 소리(`_play_bomb_throw_sfx`)와 같은 자리·같은 판단이다.
##
## **소리 파일 앞을 잘라 두었다** (0.86초 → 0.44초). 원본은 도는 소리(휙)가 0.45초쯤
## 이어진 뒤에야 "챡" 하는 정점이 왔다 — 부르는 자리는 표창이 손을 떠나는 그 순간인데
## 정작 손을 떠난 소리가 반 박자 늦게 들려서, 던지는 동작과 소리가 어긋나 보였다.
## 지금은 정점이 0.09초에 있다(앞에 0.08초의 짧은 도는 소리만 남겼다 — 아주 없애면
## 정점이 문턱 없이 튀어나와 딱딱하게 들린다). **파일을 바꿔서 맞췄지, 부르는 자리를
## 늦추지 않았다** — 늦추면 서버가 탄을 내는 시각과 소리가 갈라져 무엇을 기준으로
## 맞춘 것인지가 코드에서 사라진다.
##
## 크기를 낮게(-17dB, 씬에서) 잡은 것은 **자주 울리는 소리라서다** — 쿨타임이 짧은
## 축이라 경기 내내 들린다. 활시위(-20dB)가 같은 이유로 낮다.
@rpc("authority", "call_local", "reliable")
func _play_shuriken_throw_sfx() -> void:
	effects_root.add_child(SHURIKEN_THROW_SFX_SCENE.instantiate())


## 강화(빨간) 표창이 맞아 자리가 바뀌는 소리. 울릴 조건은 `_on_positions_swapped()` 가
## 정한다 — 위치 교환 연출과 같은 신호를 쓴다.
##
## 박자를 재지 않는다. 강화 표창은 뽑기(35%)로 하나씩 나가고 쿨타임이 2.5초라
## 연달아 울릴 길이 없다.
##
## **던지는 소리와 겹치지 않는다** (#261): 던지는 순간과 맞는 순간 사이에 표창이
## 날아가는 시간이 있고, 던지는 소리는 0.44초, 이쪽은 0.50초다.
@rpc("authority", "call_local", "reliable")
func _play_shuriken_swap_sfx() -> void:
	effects_root.add_child(SHURIKEN_SWAP_SFX_SCENE.instantiate())


## 폭탄을 던지는 소리. 울릴 조건은 특수의 "폭탄" 갈래가 정한다.
## 박자를 재지 않는다 — 쿨타임(3.5초)이 곧 박자다.
@rpc("authority", "call_local", "reliable")
func _play_bomb_throw_sfx() -> void:
	effects_root.add_child(BOMB_THROW_SFX_SCENE.instantiate())


## 폭탄이 터지는 소리. 울릴 조건은 `_on_bomb_exploded()` 가 정한다 —
## 도화선이 다 타서 터지든 닿아서 터지든 같은 한 곳(`Projectile._explode()`)을 지난다.
@rpc("authority", "call_local", "reliable")
func _play_bomb_explode_sfx() -> void:
	effects_root.add_child(BOMB_EXPLODE_SFX_SCENE.instantiate())


## 기절하며 맞는 소리 (망치 특수·삼지창 특수). 울릴 조건은 `_on_player_stunned()` 가 정한다.
##
## **무기마다 나누지 않았다** — 기절을 거는 것은 둘뿐이고 걸리는 쪽에서 일어나는 일이
## 같다. 무엇에 맞았는지는 화면이 말한다(망치는 앞에 서 있고, 삼지창은 번개가 내려친다).
@rpc("authority", "call_local", "reliable")
func _play_stun_hit_sfx() -> void:
	effects_root.add_child(STUN_HIT_SFX_SCENE.instantiate())


## 너클 게이지가 75%를 넘어선 소리 (#225). 울릴 조건은 `_on_player_gauge_charged()` 가
## 정한다 — 문턱을 넘는 그 한 번뿐이다.
##
## **누구의 게이지가 찼는지는 싣지 않는다.** 소리에 좌우가 없고(`sfx_oneshot.gd`),
## 오라와 게이지 바가 이미 누구인지를 화면에서 말한다.
@rpc("authority", "call_local", "reliable")
func _play_knuckle_charged_sfx() -> void:
	effects_root.add_child(KNUCKLE_CHARGED_SFX_SCENE.instantiate())


## 너클 특수(강펀치) 소리 (#225). 울릴 조건은 `_resolve_punch()` 가 정한다 —
## 주먹 연출이 뜨는 그 순간이고, **맞았는지와 무관하다**: 헛친 주먹도 소리는 난다
## (연출을 먼저 띄우는 것과 같은 이유다).
##
## 박자를 재지 않는다 — 쿨타임(5초)이 곧 박자이고, 예약은 한 사람당 하나뿐이라
## (`_tick_punches()`) 겹칠 자리가 없다.
##
## **충전(75% 이상)이든 아니든 같은 소리다.** 충전 여부는 연출이 통째로 달라지는 것으로
## 이미 드러나고(`heavy_punch.gd`), 소리를 둘로 가르면 파일이 하나뿐인 지금은 같은
## 파일을 두 씬이 가리키게 된다.
@rpc("authority", "call_local", "reliable")
func _play_knuckle_punch_sfx() -> void:
	effects_root.add_child(KNUCKLE_PUNCH_SFX_SCENE.instantiate())


## 빨간 표창이 자리를 바꿨다 (서버 전용 — 투사체가 알려 온다).
func _on_positions_swapped(from_position: Vector2, to_position: Vector2) -> void:
	_play_swap_burst.rpc(from_position, to_position)
	# 소리도 같은 자리에서 낸다 — 강화(빨간) 표창이 맞은 순간이 곧 이 신호다.
	#
	# **공용 피격음과 겹친다.** 이 표창도 데미지가 들어가게 되면서
	# (`Projectile._on_body_entered`가 자리를 바꾸기 전에 `server_apply_hit`을 지난다)
	# 맞은 소리와 바뀐 소리가 함께 난다. 소총 탄처럼 한쪽을 막지 않는 것은 폭탄과 같은
	# 이유다 — 맞았다는 것과 자리가 바뀌었다는 것은 서로 다른 소식이고, 둘 다 들려야
	# 무슨 일이 일어났는지가 소리만으로 갈린다.
	_play_shuriken_swap_sfx.rpc()


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


## 제자리 회전이 끝나 전기톱이 내지르기 시작했다 (#260). 서버 전용.
##
## **바람 소리는 여기서 난다 — 특수를 누른 자리가 아니다.** 누른 순간은 아직 제자리에서
## 도는 중이라, 거기서 울리면 바람이 회전에 얹혀 무엇의 소리인지 흐려진다. 이 순간이
## 정확히 "지금 내지른다"이고, 톱 소리(`_play_chainsaw_dash_sfx`)가 그 밑에 깔려 있다.
func _on_dash_launched(_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_play_chainsaw_wind_sfx.rpc()


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
	# 빗나가 땅에 닿은 착지음. **여기 오는 것은 양날 도끼뿐이다** — 위의
	# `landing_radius` 가 이미 그 갈림이고, 직격했으면 예약이 지워져 여기 올 것이
	# 없다(함수 주석 참고). 그래서 직격음과 이 소리는 서로를 밀어낸다.
	# 아래 `speed` 검사보다 앞에 둔다: 땅에 닿은 것은 격파가 뻗든 말든 일어난 일이다.
	_play_axe_land_ground_sfx.rpc()
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
