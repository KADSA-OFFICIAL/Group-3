extends Node2D
## 전투 화면.
##
## 젤리는 씬에 미리 놓지 않고 여기서 스폰한다. 모든 피어가 같은 순서로
## 같은 이름(피어 ID)의 노드를 만들어야 MultiplayerSynchronizer 경로가 맞는다.
##
## 피격·점수·라운드 진행은 전부 서버가 판정하고 결과만 내려준다.
## 이 노드의 권한은 기본값(피어 1 = 서버)이라 authority RPC 를 그대로 쓸 수 있다.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const SPAWN_X := {1: 300.0, 2: 852.0}
const SPAWN_Y := 500.0

## 근접 "닿으면" 판정 거리. 젤리 몸통이 48px 이므로 두 몸통이 맞닿는 거리다.
## 무기별 사거리는 player.current_reach() 로 더한다.
const MELEE_REACH := 48.0

## 한 명이 죽고 다음 라운드가 시작될 때까지의 간격.
## TODO: 확정된 값이 아니다. 라운드 시작 무적 시간과 같은 값을 임시로 쓴다.
const ROUND_RESTART_DELAY := Combat.ROUND_START_GRACE

## 라운드마다 제시하는 무기 개수 (계획서: 모든 무기 중 랜덤 3개, 1개 선택).
const WEAPON_CHOICES := 3
## 고를 시간. 넘기면 남은 후보 중 하나가 자동으로 정해진다 (확정).
const WEAPON_PICK_TIME := 10.0

var scores := {1: 0, 2: 0}
var round_active := false
var _next_hit_at := {}       ## "공격자슬롯>피격자슬롯" -> 다음 기본 공격 가능 시각
var _special_ready_at := {}  ## 슬롯 -> 특수 공격 쿨타임이 끝나는 시각
## 강제 이동 중에 한 번만 터지는 특수 공격 (전기톱 돌진, 양날 도끼 낙하).
var _special_pending := {}   ## 슬롯 -> {damage, knockback, modes, bleed?}
## 출혈. 무적 시간을 무시하고 1초마다 들어간다 (확정).
var _bleeds := {}            ## 슬롯 -> {dps, until, next_at}
## 소총 연사. 한 번 누르면 지속시간(2초) 동안 자동으로 나간다 (확정).
var _bursts := {}            ## 슬롯 -> {until, next_at, interval, damage, knockback}

var _next_projectile_id := 1
## 단검을 손에 들고 있는가. 발사하면 false, 주우면 다시 true (확정).
var _dagger_held := {}       ## 슬롯 -> bool

## 라운드 시작 전 무기 선택 단계.
var picking := false
var _choices := {}           ## 슬롯 -> 제시된 무기 3개 (슬롯마다 다르다 — 확정)
var _picks := {}             ## 슬롯 -> 고른 무기
var _pick_deadline := 0.0

@onready var players_root: Node2D = $Players
@onready var projectiles_root: Node2D = $Projectiles
@onready var hud_p1: ProgressBar = $HUD/P1Bar
@onready var hud_p2: ProgressBar = $HUD/P2Bar
@onready var hud_score: Label = $HUD/Score
@onready var hud_center: Label = $HUD/CenterLabel
@onready var weapon_pick: Control = $WeaponPick
@onready var pick_rows: VBoxContainer = $WeaponPick/Rows
@onready var pick_timer_label: Label = $WeaponPick/TimeLabel


func _ready() -> void:
	$MapLabel.text = "맵: " + GameState.map_name
	$ControlsHint.text = _controls_hint()
	Net.server_closed.connect(_on_server_closed)
	weapon_pick.hide()
	_spawn_players()
	_update_hud()
	if Net.is_server():
		_start_weapon_pick()


func _spawn_players() -> void:
	if Net.mode == Net.Mode.LOCAL_2P:
		# 개발용: 한 기기에서 1P는 WASD, 2P는 화살표.
		_add_player("1", 1, true, "alt_")
		_add_player("2", 2, true, "")
		return

	for peer_id: int in Net.players:
		var slot: int = Net.players[peer_id]["slot"]
		var mine: bool = peer_id == Net.my_id() and not Net.dedicated
		_add_player(str(peer_id), slot, mine, "", peer_id)


func _add_player(node_name: String, slot: int, mine: bool, prefix: String, authority: int = 0) -> void:
	var p := PLAYER_SCENE.instantiate()
	p.name = node_name
	p.slot = slot
	p.locally_controlled = mine
	p.input_prefix = prefix
	p.position = Vector2(SPAWN_X[slot], SPAWN_Y)
	# 무기는 라운드 시작 전 선택 단계에서 정해진다.
	if authority != 0:
		p.set_multiplayer_authority(authority)
	p.died.connect(_on_player_died)
	p.special_requested.connect(_on_special_requested)
	p.add_to_group("jellies")
	players_root.add_child(p)


func get_player(slot: int) -> Node:
	for p: Node in players_root.get_children():
		if p.slot == slot:
			return p
	return null


# --- 무기 선택 단계 ---------------------------------------------------------
## 계획서의 핵심 루프: [무기 선택 → 라운드 → 승리자 1점] 반복.
## 슬롯마다 다른 3개를 제시하고, 10초 안에 안 고르면 자동으로 정해진다 (확정).

func _start_weapon_pick() -> void:
	if not Net.is_server():
		return
	_picks.clear()
	_choices = {
		1: Weapons.random_choices(WEAPON_CHOICES),
		2: Weapons.random_choices(WEAPON_CHOICES),
	}
	var deadline := Time.get_ticks_msec() / 1000.0 + WEAPON_PICK_TIME
	if Net.is_online():
		_begin_weapon_pick.rpc(_choices, deadline)
	else:
		_begin_weapon_pick(_choices, deadline)


@rpc("authority", "call_local", "reliable")
func _begin_weapon_pick(choices: Dictionary, deadline: float) -> void:
	picking = true
	round_active = false
	_choices = choices
	_pick_deadline = deadline
	hud_center.text = ""
	_build_pick_ui()
	weapon_pick.show()


## 내가 조종하는 슬롯의 후보만 버튼으로 만든다.
## 로컬 2인 모드에서는 둘 다 내 것이므로 두 줄이 나온다.
func _build_pick_ui() -> void:
	for child: Node in pick_rows.get_children():
		child.queue_free()

	for slot: int in [1, 2]:
		var p := get_player(slot)
		if p == null or not p.locally_controlled:
			continue
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 20)

		var tag := Label.new()
		tag.text = "%dP" % slot
		tag.custom_minimum_size = Vector2(60, 0)
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 26)
		row.add_child(tag)

		for weapon_name: String in _choices.get(slot, []):
			row.add_child(_make_pick_button(slot, weapon_name))
		pick_rows.add_child(row)


func _make_pick_button(slot: int, weapon_name: String) -> Button:
	var data := Weapons.get_weapon(weapon_name)
	var button := Button.new()
	button.custom_minimum_size = Vector2(260, 150)
	button.add_theme_font_size_override("font_size", 18)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var basic: String = data["basic"] if data["basic"] != "" else "없음"
	button.text = "%s\n\n기본: %s\n특수: %s" % [weapon_name, basic, data["special"]]
	button.pressed.connect(_on_pick_pressed.bind(slot, weapon_name))
	return button


func _on_pick_pressed(slot: int, weapon_name: String) -> void:
	# 이미 고른 줄은 다시 못 누르게 한다.
	if _picks.has(slot):
		return
	_picks[slot] = weapon_name
	_mark_row_chosen(slot, weapon_name)
	if Net.is_online() and not multiplayer.is_server():
		_submit_pick.rpc_id(1, slot, weapon_name)
	else:
		_server_receive_pick(slot, weapon_name)


func _mark_row_chosen(slot: int, weapon_name: String) -> void:
	for row: Node in pick_rows.get_children():
		var tag := row.get_child(0) as Label
		if tag.text != "%dP" % slot:
			continue
		tag.text = "%dP ✔" % slot
		for i: int in range(1, row.get_child_count()):
			var button := row.get_child(i) as Button
			button.disabled = true
			if button.text.begins_with(weapon_name + "\n"):
				button.modulate = Color(1.0, 0.9, 0.4)


@rpc("any_peer", "reliable")
func _submit_pick(slot: int, weapon_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if Net.players.get(sender, {}).get("slot", 0) != slot:
		return
	_server_receive_pick(slot, weapon_name)


func _server_receive_pick(slot: int, weapon_name: String) -> void:
	if not Net.is_server() or not picking:
		return
	if not weapon_name in _choices.get(slot, []):
		return
	_picks[slot] = weapon_name
	if _picks.size() >= 2:
		_finish_weapon_pick()


## 시간이 다 됐거나 둘 다 골랐을 때. 안 고른 쪽은 후보 중에서 자동으로 정한다 (확정).
func _finish_weapon_pick() -> void:
	if not Net.is_server() or not picking:
		return
	var chosen := {}
	for slot: int in [1, 2]:
		chosen[slot] = _picks.get(slot, _choices.get(slot, ["검"]).pick_random())
	if Net.is_online():
		_apply_weapons.rpc(chosen)
	else:
		_apply_weapons(chosen)
	_start_round()


@rpc("authority", "call_local", "reliable")
func _apply_weapons(chosen: Dictionary) -> void:
	picking = false
	weapon_pick.hide()
	for slot: int in chosen:
		var p := get_player(slot)
		if p != null:
			p.weapon = chosen[slot]


# --- 라운드 진행 (서버) -----------------------------------------------------

func _start_round() -> void:
	if not Net.is_server():
		return
	_next_hit_at.clear()
	_special_ready_at.clear()
	_special_pending.clear()
	_bleeds.clear()
	_bursts.clear()
	_dagger_held = {1: true, 2: true}
	for p: Node in projectiles_root.get_children():
		p.queue_free()
	for slot: int in [1, 2]:
		var p := get_player(slot)
		if p == null:
			continue
		var spawn := Vector2(SPAWN_X[slot], SPAWN_Y)
		# 로컬 2인 모드에는 피어가 없어서 rpc 를 쓸 수 없다.
		if Net.is_online():
			p.reset_for_round.rpc(spawn)
		else:
			p.reset_for_round(spawn)
	_broadcast_round_state(true, "")


func _on_player_died(slot: int) -> void:
	if not Net.is_server() or not round_active:
		return
	var winner: int = 2 if slot == 1 else 1
	scores[winner] += 1

	if scores[winner] >= Combat.POINTS_TO_WIN:
		_broadcast_round_state(false, "%dP 승리!" % winner)
		return

	_broadcast_round_state(false, "%dP 득점" % winner)
	await get_tree().create_timer(ROUND_RESTART_DELAY).timeout
	if is_inside_tree():
		_start_weapon_pick()


func _broadcast_round_state(active: bool, message: String) -> void:
	if Net.is_online():
		_set_round_state.rpc(active, scores[1], scores[2], message)
	else:
		_set_round_state(active, scores[1], scores[2], message)


@rpc("authority", "call_local", "reliable")
func _set_round_state(active: bool, s1: int, s2: int, message: String) -> void:
	round_active = active
	scores[1] = s1
	scores[2] = s2
	hud_center.text = message
	_update_hud()


# --- 피격 판정 (서버) -------------------------------------------------------
## 근접은 접촉 판정, 원거리는 투사체가 스스로 판정한다.
## 무기 17종의 기본 공격과 특수 공격이 모두 구현되어 있다.

func _physics_process(_delta: float) -> void:
	if picking:
		_update_pick_timer()
	if not Net.is_server():
		return
	if picking and Time.get_ticks_msec() / 1000.0 >= _pick_deadline:
		_finish_weapon_pick()
		return
	_sync_special_ready()
	if round_active:
		_check_melee_contact()
		_check_pending_specials()
		_tick_bleeds()
		_tick_bursts()


## 소총 연사 — 한 번 누르면 지속시간 동안 자동으로 나간다 (확정).
func _tick_bursts() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for slot: int in _bursts.keys():
		var info: Dictionary = _bursts[slot]
		var shooter := get_player(slot)
		if now >= info["until"] or shooter == null or not shooter.can_act():
			_bursts.erase(slot)
			continue
		if now < info["next_at"]:
			continue
		info["next_at"] = now + info["interval"]
		_server_fire(shooter, {
			"damage": info["damage"],
			"knockback": info["knockback"],
		})


## 출혈은 무적 시간을 무시하고 1초마다 들어간다 (확정).
func _tick_bleeds() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for slot: int in _bleeds.keys():
		var info: Dictionary = _bleeds[slot]
		if now >= info["until"]:
			_bleeds.erase(slot)
			continue
		if now < info["next_at"]:
			continue
		info["next_at"] = now + 1.0
		var p := get_player(slot)
		if p != null and p.alive:
			p.server_apply_dot(info["dps"])
		else:
			_bleeds.erase(slot)


## 돌진이 벽 없는 맵에서 무한히 이어지지 않게 하는 안전장치.
## 화면 폭을 돌진 속도로 지나가는 시간이면 충분하다.
func _dash_safety_time() -> float:
	var width: float = get_viewport().get_visible_rect().size.x
	return width / Player.FORCED_SPEED


## 상승에서 낙하로 넘어가는 시점. 일반 점프가 정점에 닿는 시간의 두 배 속도이므로 절반이다.
func _rise_time() -> float:
	return absf(Player.JUMP_VELOCITY) / Player.FORCED_SPEED * 0.5


## 강제 이동 중에 상대와 닿으면 특수 데미지가 한 번 들어간다.
func _check_pending_specials() -> void:
	for slot: int in _special_pending.keys():
		var attacker := get_player(slot)
		var target := get_player(2 if slot == 1 else 1)
		if attacker == null or target == null:
			_special_pending.erase(slot)
			continue
		if not attacker.is_forced():
			_special_pending.erase(slot)   # 동작이 끝났으면 기회는 사라진다
			continue
		var info: Dictionary = _special_pending[slot]
		if not attacker.forced_mode in info["modes"]:
			continue
		var reach: float = MELEE_REACH + attacker.current_reach()
		if attacker.global_position.distance_to(target.global_position) <= reach \
				and not is_blocked(attacker, target):
			target.server_apply_hit(info["damage"], info["knockback"],
				attacker.global_position.x, 0.0, "special")
			if info.get("bleed_dps", 0.0) > 0.0:
				var now := Time.get_ticks_msec() / 1000.0
				# 첫 타는 즉시 들어간다. 3초 출혈이면 0·1·2초에 세 번 = 문서상 총 12.
				_bleeds[target.slot] = {
					"dps": info["bleed_dps"],
					"until": now + info["bleed_duration"],
					"next_at": now,
				}
			_special_pending.erase(slot)


## 쿨타임 상태를 무기 도형 색에 쓰도록 내려준다.
func _sync_special_ready() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for slot: int in [1, 2]:
		var p := get_player(slot)
		if p == null:
			continue
		var ready_now: bool = now >= _special_ready_at.get(slot, 0.0)
		if p.special_ready != ready_now:
			if Net.is_online():
				p.set_special_ready.rpc(ready_now)
			else:
				p.set_special_ready(ready_now)


func _check_melee_contact() -> void:
	var p1 := get_player(1)
	var p2 := get_player(2)
	if p1 == null or p2 == null or not p1.alive or not p2.alive:
		return
	_try_hit(p1, p2)
	_try_hit(p2, p1)
	_try_ranged_basic(p1)
	_try_ranged_basic(p2)


## 원거리 무기의 기본 공격도 자동이다. basic_interval 마다 알아서 발사한다.
func _try_ranged_basic(attacker: Node) -> void:
	var weapon := Weapons.get_weapon(attacker.weapon)
	if weapon.is_empty() or weapon["basic_damage"] <= 0.0:
		return
	if weapon["basic_kind"] != "ranged":
		return
	if not attacker.can_act():
		return
	var key := "ranged>%d" % attacker.slot
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_hit_at.get(key, 0.0):
		return

	# 단검: 들고 있을 때만 나가고, 상대를 자동으로 따라간다. 쏘면 손에서 없어진다 (확정).
	if weapon["name"] == "단검":
		if not _dagger_held.get(attacker.slot, true):
			return
		_next_hit_at[key] = now + weapon["basic_interval"]
		_dagger_held[attacker.slot] = false
		_server_fire(attacker, {
			"damage": weapon["basic_damage"],
			"knockback": weapon["knockback"],
			"homing_slot": 2 if attacker.slot == 1 else 1,
			"use_gravity": true,
			"on_solid": "stay",
			"pickup_owner": attacker.slot,
		})
		return

	_next_hit_at[key] = now + weapon["basic_interval"]
	_server_fire(attacker, {
		"damage": weapon["basic_damage"],
		"knockback": weapon["knockback"],
	})


## 상대가 나를 보고 있고, 상대 무기가 내 무기보다 길면 막힌다 (확정).
## 같은 사거리면 둘 다 들어간다. 광선검의 관통은 이 판정을 무시한다.
func is_blocked(attacker: Node, target: Node) -> bool:
	if attacker.is_piercing():
		return false
	var toward_attacker := signf(attacker.global_position.x - target.global_position.x)
	if signf(float(target.facing)) != toward_attacker:
		return false   # 등을 보이고 있으면 못 막는다
	return target.current_reach() > attacker.current_reach()


func _try_hit(attacker: Node, target: Node) -> void:
	var weapon := Weapons.get_weapon(attacker.weapon)
	if weapon.is_empty() or weapon["basic_damage"] <= 0.0:
		return
	if not weapon["basic_kind"].begins_with("melee"):
		return
	if target.is_invulnerable() or is_blocked(attacker, target):
		return

	var reach: float = MELEE_REACH + attacker.current_reach()
	if attacker.global_position.distance_to(target.global_position) > reach:
		return

	# 지속 데미지 무기는 basic_interval 마다, 나머지는 피격 무적 시간이 간격을 정한다.
	var key := "%d>%d" % [attacker.slot, target.slot]
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_hit_at.get(key, 0.0):
		return
	var interval: float = maxf(weapon["basic_interval"], Combat.MELEE_HIT_INTERVAL)
	_next_hit_at[key] = now + interval

	target.server_apply_hit(weapon["basic_damage"], weapon["knockback"],
		attacker.global_position.x, 0.0, "basic")


# --- 투사체 ----------------------------------------------------------------
## 상대 무기에 막히지 않고, 속도는 무기와 무관하게 전부 같다 (확정).

## 서버만 호출한다. offsets 로 여러 발을 한 번에 낼 수 있다 (활 특수의 평행 3발).
func _server_fire(attacker: Node, base: Dictionary, offsets: Array = [0.0]) -> void:
	var dir := signf(float(attacker.facing))
	for offset: float in offsets:
		var data := base.duplicate()
		data["shooter_slot"] = attacker.slot
		data["velocity"] = Vector2(dir * Combat.PROJECTILE_SPEED, 0.0)
		# 무기 끝에서 나가게 한다.
		data["position"] = attacker.global_position + Vector2(
			dir * (MELEE_REACH * 0.5 + attacker.current_reach()), offset)
		var id := _next_projectile_id
		_next_projectile_id += 1
		if Net.is_online():
			_spawn_projectile.rpc(id, data)
		else:
			_spawn_projectile(id, data)


@rpc("authority", "call_local", "reliable")
func _spawn_projectile(id: int, data: Dictionary) -> void:
	var p := PROJECTILE_SCENE.instantiate()
	p.name = str(id)
	p.setup(data)
	projectiles_root.add_child(p)
	if Net.is_server():
		p.finished.connect(_on_projectile_finished)
		p.picked_up.connect(_on_dagger_picked_up)


## 단검을 주우면 다시 들고 있는 상태가 된다 (확정).
func _on_dagger_picked_up(slot: int, id: String) -> void:
	_dagger_held[slot] = true
	_on_projectile_finished(id)


func _on_projectile_finished(id: String) -> void:
	if Net.is_online():
		_despawn_projectile.rpc(id)
	else:
		_despawn_projectile(id)


@rpc("authority", "call_local", "reliable")
func _despawn_projectile(id: String) -> void:
	var p := projectiles_root.get_node_or_null(id)
	if p != null:
		p.queue_free()


# --- 특수 공격 (Shift) ------------------------------------------------------
## 방향은 바라보는 방향(좌우)으로만 나간다 (확정).
## 아직 투사체가 없어서, 던지거나 발사하는 무기는 구현되지 않았다.

## 로컬 플레이어가 Shift 를 눌렀다. 판정은 서버가 하므로 요청만 보낸다.
func _on_special_requested(slot: int, long_press: bool) -> void:
	if Net.is_online() and not multiplayer.is_server():
		_request_special.rpc_id(1, slot, long_press)
	else:
		_server_do_special(slot, long_press)


@rpc("any_peer", "reliable")
func _request_special(slot: int, long_press: bool) -> void:
	if not multiplayer.is_server():
		return
	# 남의 슬롯으로 특수 공격을 쏘지 못하게 막는다.
	var sender := multiplayer.get_remote_sender_id()
	if Net.players.get(sender, {}).get("slot", 0) != slot:
		return
	_server_do_special(slot, long_press)


func _server_do_special(slot: int, long_press: bool) -> void:
	if not Net.is_server() or not round_active:
		return
	var attacker := get_player(slot)
	var target := get_player(2 if slot == 1 else 1)
	if attacker == null or target == null or not attacker.can_act() or not attacker.alive:
		return

	var weapon := Weapons.get_weapon(attacker.weapon)
	if weapon.is_empty():
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now < _special_ready_at.get(slot, 0.0):
		return

	if not _execute_special(attacker, target, weapon, long_press):
		return
	_special_ready_at[slot] = now + weapon["special_cooldown"]


## 무기별 특수 공격. 발동했으면 true (쿨타임이 돌아간다).
func _execute_special(attacker: Node, target: Node, weapon: Dictionary, long_press: bool) -> bool:
	match weapon["name"]:
		"검":
			# 상대의 "현재 체력" 에 비례 (확정).
			var damage: float = target.hp * weapon["special_hp_ratio"]
			return _melee_special(attacker, target, damage, weapon["knockback"])
		"망치":
			return _melee_special(attacker, target, weapon["special_damage"],
				weapon["knockback"], weapon["stun_duration"])
		"글러브":
			# "단거리 주먹 발사" — 사거리만 살짝 늘린 즉시 판정으로 구현.
			return _melee_special(attacker, target, weapon["special_damage"],
				weapon["knockback"], 0.0, 1.5)
		"광선검":
			# 관통 — 일정 시간 상대 무기의 막기를 무시한다 (확정).
			attacker.server_apply_buff("pierce", 1.0, weapon["special_duration"])
			return true
		"너클":
			# 게이지 비례 데미지 → 쓰면 게이지는 전부 소모된다 (확정).
			var ratio: float = attacker.gauge / weapon["gauge_max"]
			var punch: float = lerpf(weapon["gauge_min_damage"], weapon["gauge_max_damage"], ratio)
			var landed := _melee_special(attacker, target, punch, weapon["knockback"])
			attacker.server_set_gauge(0.0)
			return landed
		"전기톱":
			# 관통 돌진. 속도는 일반 점프의 두 배, 벽에 부딪히면 끝난다 (확정).
			attacker.server_start_forced("dash", _dash_safety_time())
			_special_pending[attacker.slot] = {
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
			_special_pending[attacker.slot] = {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"modes": ["fall"],
			}
			return true
		"활":
			# 관통 화살 3발 — 살짝 벌어진 평행 (확정).
			var s := Combat.PARALLEL_SPACING
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"pierce_targets": true,
			}, [-s, 0.0, s])
			return true
		"대포 총":
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
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
		"단검":
			# 특수 = 자동 재수집. 주우러 가지 않아도 손으로 돌아온다 (확정).
			if _dagger_held.get(attacker.slot, true):
				return false   # 이미 들고 있으면 쓸 것이 없다
			_dagger_held[attacker.slot] = true
			for p: Node in projectiles_root.get_children():
				if p.pickup_owner == attacker.slot:
					_on_projectile_finished(p.name)
			return true
		"폭탄":
			# 던진 폭탄은 바닥에 남고, 3초 뒤 또는 닿으면 반경 200px 을 때린다 (확정).
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
		"삼지창":
			# 던지고 맞으면 기절. "자동 회수" 는 지금은 사라지는 것으로 처리하고,
			# 돌아오는 연출은 그래픽 작업 때 붙인다.
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"stun": weapon["stun_duration"],
			})
			return true
		"소총":
			# 한 번 누르면 3초간 자동 연사 (확정).
			var now2 := Time.get_ticks_msec() / 1000.0
			_bursts[attacker.slot] = {
				"until": now2 + weapon["burst_duration"],
				"next_at": now2,
				"interval": weapon["burst_interval"],
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
			}
			return true
		"표창":
			# 중력 영향을 받는다. 파란 표창(위치 교환)은 아직 미구현.
			_server_fire(attacker, {
				"damage": weapon["special_damage"],
				"knockback": weapon["knockback"],
				"use_gravity": true,
			})
			return true
		"장대":
			attacker.server_apply_buff("reach", weapon["reach_multiplier"], weapon["special_duration"])
			return true
		"방패":
			# 짧게 = 던지기, 길게 = 크기 증가 (확정).
			if long_press:
				attacker.server_apply_buff("size", weapon["size_multiplier"], weapon["special_duration"])
			else:
				_server_fire(attacker, {
					"damage": weapon["special_damage"],
					"knockback": weapon["knockback"],
				})
			return true
		_:
			return false  # 나머지 무기는 아직 미구현


## 바라보는 방향으로 사거리 안에 있으면 맞는다.
func _melee_special(attacker: Node, target: Node, damage: float, knockback: int,
		stun := 0.0, reach_bonus := 1.0) -> bool:
	var offset: float = target.global_position.x - attacker.global_position.x
	if signf(offset) != signf(float(attacker.facing)):
		return true  # 발동은 했지만 방향이 안 맞아 빗나감
	var reach: float = (MELEE_REACH + attacker.current_reach()) * reach_bonus
	if attacker.global_position.distance_to(target.global_position) > reach:
		return true  # 발동은 했지만 사거리 밖
	if is_blocked(attacker, target):
		return true  # 발동은 했지만 상대 무기에 막힘
	target.server_apply_hit(damage, knockback, attacker.global_position.x, stun, "special")
	return true


# --- 표시 ------------------------------------------------------------------

func _update_pick_timer() -> void:
	var left: float = maxf(_pick_deadline - Time.get_ticks_msec() / 1000.0, 0.0)
	pick_timer_label.text = "%.0f초" % ceilf(left)


func _update_hud() -> void:
	for slot: int in [1, 2]:
		var bar: ProgressBar = hud_p1 if slot == 1 else hud_p2
		var p := get_player(slot)
		bar.max_value = Combat.MAX_HP
		bar.value = p.hp if p != null else 0.0
	hud_score.text = "%d  :  %d" % [scores[1], scores[2]]


func _process(_delta: float) -> void:
	_update_hud()


func _controls_hint() -> String:
	if Net.mode == Net.Mode.LOCAL_2P:
		return "로컬 2인 테스트   |   1P: WASD + Space   |   2P: 방향키 + Shift   |   ESC: 나가기"
	return "이동: ← →   |   점프: ↑   |   빠른 낙하: ↓   |   스킬: Shift   |   ESC: 나가기"


func _on_server_closed() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/title.tscn")
