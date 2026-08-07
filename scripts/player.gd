class_name Player
extends CharacterBody2D
## 젤리 플레이어.
##
## 이동: 각 피어가 자기 젤리만 시뮬레이션하고 위치·속도·방향을 MultiplayerSynchronizer 로 보낸다.
## 체력·피격·상태이상·버프: 양쪽에서 결과가 갈리면 안 되므로 서버가 단독으로 판정하고 결과만 내려준다.

signal died(slot: int)
## 로컬 플레이어가 Shift 를 눌렀다. long_press 는 0.3초 이상 눌렀는지 (방패 구분용).
signal special_requested(slot: int, long_press: bool)

const SPEED := 320.0
const JUMP_VELOCITY := -560.0
const FAST_FALL_MULTIPLIER := 2.0

## 방패의 짧게/길게를 가르는 시간 (확정).
const LONG_PRESS_TIME := 0.3

## 강제 이동(전기톱 돌진, 양날 도끼 상승·낙하) 속도 — 일반 점프의 두 배 (확정).
const FORCED_SPEED := absf(JUMP_VELOCITY) * 2.0

## 젤리 느낌: 움직일 때 살짝 찌그러지기.
## TODO: 아래 값들은 아직 정해진 값이 아니다. 그래픽 담당과 젤리 연출을 만들 때 같이 정한다.
const SQUASH_AIRBORNE_SPEED := 20.0   # 임시값
const SQUASH_MOVING_SPEED := 1.0      # 임시값
const SQUASH_AIRBORNE := Vector2(0.9, 1.1)  # 임시값
const SQUASH_MOVING := Vector2(1.1, 0.9)    # 임시값

@export var slot: int = 1
## 이 기기가 이 젤리를 조종하는가. main.gd 가 스폰할 때 정해준다.
@export var locally_controlled := false
## 입력 액션 접두사. 기본 조작은 "", 로컬 2인 모드의 1P는 "alt_".
@export var input_prefix := ""

var hp := Combat.MAX_HP
var weapon := ""            ## "랜덤" 이 실제 무기로 확정된 이름
var alive := true
## 바라보는 방향 (1 오른쪽 / -1 왼쪽). 특수 공격은 이 방향으로 나간다 (확정).
var facing := 1

## 무적 시간은 기본 공격용과 특수 공격용을 따로 잰다 (확정).
## 합치면 기본 공격이 계속 무적을 새로 걸어서 특수 공격이 거의 안 들어간다.
var _invuln_until := {"basic": 0.0, "special": 0.0}
var _stun_until := 0.0
## 너클 게이지. 내가 맞을 때 충전된다 (확정).
var gauge := 0.0
## 특수 공격을 쓸 수 있는가. 서버가 쿨타임을 재고 이 값만 내려준다 (무기 도형 색에 쓴다).
var special_ready := true
var _reach_multiplier := 1.0
var _reach_until := 0.0
var _size_multiplier := 1.0
var _size_until := 0.0
## 광선검 특수 — 상대 무기의 막기를 무시한다 (확정). 지형·맵은 통과하지 못한다.
var _pierce_until := 0.0
var _skill_held_since := -1.0
## 강제 이동 상태. "" 이면 평소, "dash"(전기톱) / "rise"·"fall"(양날 도끼).
var forced_mode := ""
var _forced_deadline := 0.0

@onready var body: ColorRect = $Body
@onready var name_label: Label = $NameLabel
@onready var weapon_shape: ColorRect = $WeaponShape


func _ready() -> void:
	var config: Dictionary = GameState.get_config(slot)
	body.color = config["color1"]
	name_label.text = "%dP" % slot
	if locally_controlled:
		name_label.text += " (나)"
	if slot == 2:
		facing = -1
	_update_weapon_shape()


func _physics_process(delta: float) -> void:
	if locally_controlled:
		if forced_mode != "":
			_simulate_forced(delta)
		elif can_act():
			_simulate(delta)
			_read_skill_input()
		else:
			# 기절 중에는 조작 전부 불가 (확정). 중력만 계속 받는다.
			if not is_on_floor():
				velocity += get_gravity() * delta
			move_and_slide()
	_expire_buffs()
	_update_squash(delta)
	_update_weapon_shape()


func _simulate(delta: float) -> void:
	# 중력 (↓ 를 누르고 있으면 빠르게 낙하)
	if not is_on_floor():
		var gravity := get_gravity()
		if Input.is_action_pressed(input_prefix + "fast_fall"):
			gravity *= FAST_FALL_MULTIPLIER
		velocity += gravity * delta

	# 점프 (↑)
	if Input.is_action_just_pressed(input_prefix + "jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# 좌우 이동 (← / →) — 넉백으로 밀리는 중에는 입력이 즉시 덮어쓰지 않게 한다.
	var direction := Input.get_axis(input_prefix + "move_left", input_prefix + "move_right")
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
	if is_on_floor() or absf(velocity.x) <= SPEED:
		velocity.x = direction * SPEED
	elif direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * SPEED, SPEED * delta)

	move_and_slide()


## 강제 이동 중에는 조작이 전부 불가하다 (확정). 동작이 끝날 때까지 몸이 알아서 움직인다.
func _simulate_forced(delta: float) -> void:
	match forced_mode:
		"dash":
			velocity.x = facing * FORCED_SPEED
			if not is_on_floor():
				velocity += get_gravity() * delta
			move_and_slide()
			# 벽에 부딪히거나 안전장치 시간이 지나면 끝난다.
			if is_on_wall() or _now() >= _forced_deadline:
				_end_forced()
		"rise":
			velocity.y = -FORCED_SPEED
			move_and_slide()
			# 올라가는 힘이 다하면 낙하로 넘어간다.
			if _now() >= _forced_deadline:
				forced_mode = "fall"
		"fall":
			velocity.x = 0.0
			velocity.y = FORCED_SPEED
			move_and_slide()
			if is_on_floor():
				_end_forced()


func _end_forced() -> void:
	forced_mode = ""
	velocity = Vector2.ZERO


func is_forced() -> bool:
	return forced_mode != ""


## Shift 입력. 방패만 짧게/길게를 구분하므로, 누르고 있는 시간을 재서 뗄 때 판정한다.
func _read_skill_input() -> void:
	var action := input_prefix + "skill"
	var now := _now()
	if Input.is_action_just_pressed(action):
		_skill_held_since = now
	elif Input.is_action_pressed(action) and _skill_held_since >= 0.0:
		# 길게 누른 것이 확정되는 순간 바로 발동한다 (뗄 때까지 기다리지 않는다).
		if now - _skill_held_since >= LONG_PRESS_TIME:
			_skill_held_since = -1.0
			special_requested.emit(slot, true)
	elif Input.is_action_just_released(action) and _skill_held_since >= 0.0:
		_skill_held_since = -1.0
		special_requested.emit(slot, false)


func _update_squash(delta: float) -> void:
	var target_scale := Vector2.ONE
	if absf(velocity.y) > SQUASH_AIRBORNE_SPEED:
		target_scale = SQUASH_AIRBORNE
	elif absf(velocity.x) > SQUASH_MOVING_SPEED:
		target_scale = SQUASH_MOVING
	body.scale = body.scale.lerp(target_scale, 12.0 * delta)


## 무기는 임시 도형(막대)으로 그린다 (확정 — 그래픽 나오면 교체).
## 길이는 무기의 사거리, 방패의 크기 증가는 두께로 표현한다.
## 특수 공격 쿨타임은 도형 색으로만 보여준다 (확정 — 별도 UI 없음).
func _update_weapon_shape() -> void:
	var data := Weapons.get_weapon(weapon)
	if data.is_empty():
		weapon_shape.hide()
		return
	weapon_shape.show()
	var length := current_reach()
	var thickness := 10.0 * _size_multiplier
	weapon_shape.size = Vector2(length, thickness)
	weapon_shape.position = Vector2(0.0 if facing > 0 else -length, -thickness * 0.5)

	if not can_act():
		weapon_shape.color = Color(0.45, 0.45, 0.5)   # 기절
	elif special_ready:
		weapon_shape.color = Color(0.95, 0.95, 1.0)   # 특수 공격 가능
	else:
		weapon_shape.color = Color(0.55, 0.55, 0.62)  # 쿨타임 중


## 현재 사거리. 장대의 특수 공격이나 방패 크기 증가로 늘어난다.
func current_reach() -> float:
	var data := Weapons.get_weapon(weapon)
	if data.is_empty():
		return 0.0
	var base: float = 24.0 * data.get("reach_multiplier", 1.0)
	return base * _reach_multiplier * _size_multiplier


# --- 상태 조회 --------------------------------------------------------------

func is_invulnerable(source := "basic") -> bool:
	return _now() < _invuln_until.get(source, 0.0)


func is_stunned() -> bool:
	return _now() < _stun_until


## 관통 상태에서는 상대 무기가 공격을 막지 못한다.
func is_piercing() -> bool:
	return _now() < _pierce_until


func can_act() -> bool:
	return alive and not is_stunned() and forced_mode == ""


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _expire_buffs() -> void:
	var now := _now()
	if _reach_multiplier != 1.0 and now >= _reach_until:
		_reach_multiplier = 1.0
	if _size_multiplier != 1.0 and now >= _size_until:
		_size_multiplier = 1.0


# --- 피격·상태 (서버 판정) --------------------------------------------------

## 서버에서만 호출한다. 데미지를 적용하고 결과를 전원에게 내려준다.
##
## source 는 "basic" / "special" / "projectile".
## 기본과 특수는 무적 타이머가 따로 돌아가고,
## 허공을 나는 것("projectile")은 무적을 개별로 적용한다 — 공유 무적을 아예 타지 않아서
## 활 특수 3발처럼 같은 순간에 도착하는 것도 전부 들어간다 (확정).
func server_apply_hit(damage: float, knockback_level: int, from_x: float,
		stun := 0.0, source := "basic") -> void:
	if not alive:
		return
	if source != "projectile" and is_invulnerable(source):
		return
	var new_hp: float = maxf(hp - damage, 0.0)
	var direction := signf(global_position.x - from_x)
	if direction == 0.0:
		direction = 1.0
	# 너클은 내가 맞을 때 게이지가 찬다 (확정).
	var new_gauge := gauge
	var data := Weapons.get_weapon(weapon)
	if data.get("gauge_per_hit", 0.0) > 0.0:
		new_gauge = minf(gauge + data["gauge_per_hit"], data["gauge_max"])
	_broadcast_hit(new_hp, knockback_level, direction, stun, source, new_gauge)


## 출혈 같은 지속 데미지. 무적 시간을 무시하고 들어가고, 넉백도 없다 (확정).
func server_apply_dot(damage: float) -> void:
	if not alive:
		return
	var new_hp: float = maxf(hp - damage, 0.0)
	if Net.is_online():
		_receive_dot.rpc(new_hp)
	else:
		_receive_dot(new_hp)


@rpc("any_peer", "call_local", "reliable")
func _receive_dot(new_hp: float) -> void:
	if not _from_server():
		return
	hp = new_hp
	if hp <= 0.0 and alive:
		alive = false
		velocity = Vector2.ZERO
		forced_mode = ""
		modulate.a = 0.35
		died.emit(slot)


## 서버가 죽음까지 판정한다 (낙사 등 데미지 없는 사망 포함).
func server_kill() -> void:
	if not alive:
		return
	_broadcast_hit(0.0, Combat.Knockback.WEAK, 0.0, 0.0, "special", gauge)


## 서버에서만 호출한다. 사거리·크기 버프.
func server_apply_buff(kind: String, value: float, duration: float) -> void:
	if Net.is_online():
		_receive_buff.rpc(kind, value, duration)
	else:
		_receive_buff(kind, value, duration)


## 로컬 2인 모드에는 피어가 없어서 rpc 를 쓸 수 없다.
func _broadcast_hit(new_hp: float, knockback_level: int, direction: float,
		stun: float, source: String, new_gauge: float) -> void:
	if Net.is_online():
		_receive_hit.rpc(new_hp, knockback_level, direction, stun, source, new_gauge)
	else:
		_receive_hit(new_hp, knockback_level, direction, stun, source, new_gauge)


func _from_server() -> bool:
	if not Net.is_online():
		return true
	var sender := multiplayer.get_remote_sender_id()
	return sender == 0 or sender == 1


@rpc("any_peer", "call_local", "reliable")
func _receive_hit(new_hp: float, knockback_level: int, direction: float,
		stun: float, source: String, new_gauge: float) -> void:
	if not _from_server():
		return

	hp = new_hp
	gauge = new_gauge
	if source != "projectile":
		_invuln_until[source] = _now() + Combat.INVULNERABLE_TIME
	if stun > 0.0:
		_stun_until = _now() + stun

	# 넉백은 자기 젤리를 시뮬레이션하는 쪽에서만 적용한다.
	if locally_controlled and direction != 0.0:
		velocity = Combat.knockback_velocity(knockback_level, direction)

	if hp <= 0.0 and alive:
		alive = false
		velocity = Vector2.ZERO
		modulate.a = 0.35
		died.emit(slot)


@rpc("any_peer", "call_local", "reliable")
func set_special_ready(value: bool) -> void:
	if not _from_server():
		return
	special_ready = value


## 서버에서만 호출한다. 너클 게이지는 특수 공격을 쓰면 전부 소모된다 (확정).
func server_set_gauge(value: float) -> void:
	if Net.is_online():
		_receive_gauge.rpc(value)
	else:
		_receive_gauge(value)


@rpc("any_peer", "call_local", "reliable")
func _receive_gauge(value: float) -> void:
	if _from_server():
		gauge = value


## 서버에서만 호출한다. 강제 이동 시작.
func server_start_forced(mode: String, duration: float) -> void:
	if Net.is_online():
		_receive_forced.rpc(mode, duration)
	else:
		_receive_forced(mode, duration)


@rpc("any_peer", "call_local", "reliable")
func _receive_forced(mode: String, duration: float) -> void:
	if not _from_server():
		return
	forced_mode = mode
	_forced_deadline = _now() + duration
	_skill_held_since = -1.0


@rpc("any_peer", "call_local", "reliable")
func _receive_buff(kind: String, value: float, duration: float) -> void:
	if not _from_server():
		return
	match kind:
		"reach":
			_reach_multiplier = value
			_reach_until = _now() + duration
		"size":
			_size_multiplier = value
			_size_until = _now() + duration
		"pierce":
			_pierce_until = _now() + duration


## 라운드 시작 시 서버가 부른다.
@rpc("any_peer", "call_local", "reliable")
func reset_for_round(spawn_position: Vector2) -> void:
	if not _from_server():
		return
	hp = Combat.MAX_HP
	gauge = 0.0
	alive = true
	modulate.a = 1.0
	velocity = Vector2.ZERO
	global_position = spawn_position
	facing = 1 if slot == 1 else -1
	_stun_until = 0.0
	_reach_multiplier = 1.0
	_size_multiplier = 1.0
	_pierce_until = 0.0
	_skill_held_since = -1.0
	forced_mode = ""
	var grace := _now() + Combat.ROUND_START_GRACE
	_invuln_until = {"basic": grace, "special": grace}
