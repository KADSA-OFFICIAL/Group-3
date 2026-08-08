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

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
## 맵에 Spawns가 없을 때만 쓰는 대비값. 정상 경로에서는 맵 씬이 위치를 들고 있다.
const SPAWN_POSITIONS := [Vector2(300, 500), Vector2(852, 500)]

## 근접 "닿으면" 판정 거리. 젤리 몸통이 48px이므로 두 몸통이 맞닿는 거리다.
## 무기별 사거리는 player.current_reach()로 더한다.
const MELEE_REACH := 48.0

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
## 단검을 손에 들고 있는가. 발사하면 false, 주우면 다시 true.
var _dagger_held := {}
var _next_projectile_id := 1
## 다음 라운드를 시작할 시각. 0이면 예약 없음 (진행 중이거나 경기가 끝났다).
var _round_restart_at := 0.0
## 경기가 끝났으면 더 이상 라운드를 시작하지 않는다.
var _match_over := false
## 대기실로 돌려보낼 시각. 0이면 예약 없음.
var _return_at := 0.0

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
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var projectile_spawner: MultiplayerSpawner = $ProjectileSpawner
@onready var result_overlay: Control = $UI/HUD/ResultOverlay
## jelly_preview.gd는 class_name이 없어 타입을 붙이지 않는다 (player_panel.gd와 같은 방식).
@onready var result_jelly = $UI/HUD/ResultOverlay/Jelly
@onready var result_label: Label = $UI/HUD/ResultOverlay/ResultLabel
@onready var result_score: Label = $UI/HUD/ResultOverlay/ScoreLabel


func _ready() -> void:
	$MapLabel.text = "맵: " + Lobby.map_name
	# 지형은 모든 피어에서 똑같이 깔려야 한다 — 스폰보다 먼저 붙인다.
	# 서버가 대기실에서 "랜덤"을 확정해 두므로 양쪽이 같은 맵을 받는다.
	_load_map(Lobby.map_name)
	# 스폰 함수는 모든 피어에서 등록되어야 한다 — 서버 판정보다 먼저 설정한다.
	player_spawner.spawn_function = _spawn_player
	projectile_spawner.spawn_function = _spawn_projectile

	# 경기가 끝나면 서버 지시로 대기실에 돌아간다 (서버 자신은 이 씬에 머문다).
	Lobby.match_ended.connect(_on_match_ended)

	if multiplayer.is_server():
		Network.peer_left.connect(_on_peer_left)
	else:
		# 씬이 준비된 뒤에 서버에 알린다. 접속 직후 바로 스폰하면
		# 클라이언트가 아직 이 씬을 로드하기 전이라 스폰을 놓칠 수 있다.
		_notify_ready.rpc_id(1)


## 클라이언트가 전투 화면 준비를 마쳤음을 서버에 알린다.
@rpc("any_peer", "call_remote", "reliable")
func _notify_ready() -> void:
	if not multiplayer.is_server():
		return
	_add_player(multiplayer.get_remote_sender_id())


func _add_player(peer_id: int) -> void:
	if players_root.has_node("Player_%d" % peer_id):
		return
	# 슬롯과 선택값은 대기실에서 서버가 확정한 것을 그대로 쓴다
	var index: int = Lobby.slot_of(peer_id)
	if index < 0:
		index = players_root.get_child_count()
	var config: Dictionary = Lobby.config_for(peer_id)
	var player := player_spawner.spawn({
		"peer_id": peer_id,
		"index": index,
		"weapon_id": config["weapon"],
		"character": config["character"],
	}) as Player
	if player == null:
		return
	# 특수 공격 요청과 사망은 서버에서만 발생한다.
	player.special_requested.connect(_on_special_requested)
	player.died.connect(_on_player_died)
	_dagger_held[peer_id] = true
	if not scores.has(peer_id):
		scores[peer_id] = 0
	_broadcast_round(banner)


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
	player.position = _spawn_position(index)
	player.facing = _spawn_facing(index)
	return player


func _on_peer_left(peer_id: int) -> void:
	var player := players_root.get_node_or_null("Player_%d" % peer_id)
	if player:
		player.queue_free()
	_special_ready_at.erase(peer_id)
	_special_pending.erase(peer_id)
	_bleeds.erase(peer_id)
	_bursts.erase(peer_id)
	_dagger_held.erase(peer_id)
	# 키가 "공격자>피격자" 조합이라 한쪽이 빠지면 전부 의미가 없어진다.
	_next_hit_at.clear()


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

	for player: Player in players_root.get_children():
		var index := maxi(Lobby.slot_of(player.owner_peer_id), 0)
		player.server_reset(_spawn_position(index), _spawn_facing(index))
		_dagger_held[player.owner_peer_id] = true

	_broadcast_round("")


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
	if _return_at > 0.0 and now >= _return_at:
		_return_at = 0.0
		Lobby.server_end_match()
		_server_reset_match()


## 전용 서버는 씬을 벗어나지 않으므로 다음 경기를 위해 직접 판을 비운다.
## 이걸 안 하면 다음 경기에서 점수가 이어지고 플레이어가 다시 스폰되지 않는다.
func _server_reset_match() -> void:
	for player in players_root.get_children():
		player.queue_free()
	for projectile in projectiles_root.get_children():
		projectile.queue_free()
	scores.clear()
	banner = ""
	_hide_result()
	_match_over = false
	_round_restart_at = 0.0
	_next_hit_at.clear()
	_special_ready_at.clear()
	_special_pending.clear()
	_bleeds.clear()
	_bursts.clear()
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
	if my_player == null:
		return   # 전용 서버처럼 자기 플레이어가 없는 피어는 보여줄 것이 없다
	_play_result(winner_peer == me, my_player.character_id)


func _play_result(is_winner: bool, character_id: String) -> void:
	_kill_result_tweens()
	result_jelly.character_id = character_id
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
	if target.is_invulnerable() or is_blocked(attacker, target):
		return

	var reach: float = MELEE_REACH + attacker.current_reach()
	if attacker.global_position.distance_to(target.global_position) > reach:
		return

	# 지속 데미지 무기는 basic_interval 마다, 나머지는 근접 공격 간격이 정한다.
	var key := "%d>%d" % [attacker.owner_peer_id, target.owner_peer_id]
	var now := _now()
	if now < _next_hit_at.get(key, 0.0):
		return
	_next_hit_at[key] = now + maxf(weapon["basic_interval"], Combat.MELEE_HIT_INTERVAL)

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
		})
		return

	_next_hit_at[key] = now + weapon["basic_interval"]
	_server_fire(attacker, {
		"damage": weapon["basic_damage"],
		"knockback": weapon["knockback"],
	})


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
		if now >= info["until"] or shooter == null or not shooter.can_act():
			_bursts.erase(peer_id)
			continue
		if now < info["next_at"]:
			continue
		info["next_at"] = now + info["interval"]
		_server_fire(shooter, {
			"damage": info["damage"],
			"knockback": info["knockback"],
		})


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
## 상대 무기에 막히지 않고, 속도는 무기와 무관하게 전부 같다.

## 서버에서만 호출한다. offsets로 여러 발을 한 번에 낼 수 있다 (활 특수의 평행 3발).
func _server_fire(attacker: Player, base: Dictionary, offsets: Array = [0.0]) -> void:
	var dir := signf(float(attacker.facing))
	for offset: float in offsets:
		var data := base.duplicate()
		data["id"] = _next_projectile_id
		_next_projectile_id += 1
		data["shooter_peer"] = attacker.owner_peer_id
		data["velocity"] = Vector2(dir * Combat.PROJECTILE_SPEED, 0.0)
		# 무기 끝에서 나가게 한다.
		data["position"] = attacker.global_position + Vector2(
			dir * (MELEE_REACH * 0.5 + attacker.current_reach()), offset)
		projectile_spawner.spawn(data)


## 모든 피어에서 호출되어 투사체 노드를 만든다.
func _spawn_projectile(data: Dictionary) -> Node:
	var projectile := PROJECTILE_SCENE.instantiate() as Projectile
	projectile.name = "Projectile_%d" % int(data["id"])
	projectile.setup(data)
	if multiplayer.is_server():
		projectile.finished.connect(_on_projectile_finished)
		projectile.picked_up.connect(_on_dagger_picked_up)
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
			# 상대의 "현재 체력"에 비례.
			return _melee_special(attacker, target, target.hp * weapon["special_hp_ratio"],
				weapon["knockback"])
		"망치":
			return _melee_special(attacker, target, weapon["special_damage"],
				weapon["knockback"], weapon["stun_duration"])
		"글러브":
			# "단거리 주먹 발사" — 사거리만 살짝 늘린 즉시 판정으로 구현.
			return _melee_special(attacker, target, weapon["special_damage"],
				weapon["knockback"], 0.0, 1.5)
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
			attacker.server_apply_buff("reach", weapon["reach_multiplier"], weapon["special_duration"])
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
			attacker.server_start_forced("rise", _rise_time())
			_special_pending[peer_id] = {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"modes": ["fall"],
			}
			return true
		"활":
			# 관통 화살 3발 — 살짝 벌어진 평행.
			var spacing := Combat.PARALLEL_SPACING
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"pierce_targets": true,
			}, [-spacing, 0.0, spacing])
			return true
		"대포 총":
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
			})
			return true
		"삼지창":
			# 던지고 맞으면 기절. "자동 회수"는 지금은 사라지는 것으로 처리하고,
			# 돌아오는 연출은 그래픽 작업 때 붙인다.
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"stun": weapon["stun_duration"],
			})
			return true
		"샷건":
			# 거리에 따라 30 → 10 으로 줄어든다.
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"falloff_min_damage": weapon["falloff_min_damage"],
				"falloff_distance": 400.0,  # TODO: 감소 기준 거리는 미확정
			})
			return true
		"표창":
			# 중력 영향을 받는다. 파란 표창(위치 교환)은 아직 미구현.
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"use_gravity": true,
			})
			return true
		"폭탄":
			# 던진 폭탄은 바닥에 남고, 3초 뒤 또는 닿으면 반경 200px을 때린다.
			var empowered: bool = randf() < weapon["empowered_chance"]
			_server_fire(attacker, {
				"damage": weapon["empowered_damage"] if empowered else weapon["special_damage"],
				"knockback": weapon["empowered_knockback"] if empowered else weapon["knockback"],
				"use_gravity": true,
				"on_solid": "stay",
				"fuse": 3.0,
				"explosion_radius": 200.0,
			})
			return true
		"소총":
			# 한 번 누르면 지속시간 동안 자동 연사.
			var now := _now()
			_bursts[peer_id] = {
				"until": now + weapon["burst_duration"],
				"next_at": now,
				"interval": weapon["burst_interval"],
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
			}
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
			# 짧게 = 던지기, 길게 = 크기 증가.
			if long_press:
				attacker.server_apply_buff("size", weapon["size_multiplier"], weapon["special_duration"])
			else:
				_server_fire(attacker, {
					"damage": weapon["special_damage"],
					"knockback": weapon["knockback"],
				})
			return true
		_:
			return false


## 바라보는 방향으로 사거리 안에 있으면 맞는다.
## 빗나가도 발동은 한 것이므로 true — 쿨타임은 돌아간다.
func _melee_special(attacker: Player, target: Player, damage: float, knockback: int,
		stun := 0.0, reach_bonus := 1.0) -> bool:
	var offset: float = target.global_position.x - attacker.global_position.x
	if signf(offset) != signf(float(attacker.facing)):
		return true  # 방향이 안 맞아 빗나감
	var reach: float = (MELEE_REACH + attacker.current_reach()) * reach_bonus
	if attacker.global_position.distance_to(target.global_position) > reach:
		return true  # 사거리 밖
	if is_blocked(attacker, target):
		return true  # 상대 무기에 막힘
	target.server_apply_hit(damage, knockback, attacker.global_position.x, stun, "special")
	return true


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
func _update_hud() -> void:
	for slot in 2:
		var bar := $UI/HUD.get_node("P%dBar" % (slot + 1)) as ProgressBar
		var label := $UI/HUD.get_node("P%dName" % (slot + 1)) as Label
		var score_label := $UI/HUD.get_node("P%dScore" % (slot + 1)) as Label
		var player: Player = null
		var peer_id := 0
		if slot < Lobby.order.size():
			peer_id = Lobby.order[slot]
			player = get_player(peer_id)
		score_label.text = _score_text(int(scores.get(peer_id, 0)))
		if player == null:
			bar.value = 0.0
			label.text = "%dP —" % (slot + 1)
			continue
		bar.max_value = Combat.MAX_HP
		bar.value = player.hp
		label.text = "%dP  %s" % [slot + 1, player.weapon_id]

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
