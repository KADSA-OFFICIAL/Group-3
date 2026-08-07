class_name Player
extends CharacterBody2D
## 젤리 플레이어. 이동도 전투도 **서버 권위**다.
##
## 클라이언트는 입력만 서버로 보내고 물리를 직접 계산하지 않는다.
## 서버가 apply_movement()로 위치를 정하고 결과를 양쪽에 복제하며,
## 클라이언트는 받은 위치로 보간해 표시한다.
##
## 체력·피격·상태이상·버프도 서버가 단독으로 판정하고 결과만 내려준다.
## 실제 공격 판정(누가 누구를 언제 때리는가)은 main.gd가 들고 있고,
## 여기 있는 server_* 함수들이 그 결과를 받는 창구다.
## 무기 수치는 scripts/weapons.gd, 공통 수치는 scripts/combat.gd에 있다.

## 서버에서만 발생한다. 인자는 죽은 플레이어의 peer id.
signal died(peer_id: int)
## 서버에서만 발생한다. 이 플레이어가 특수 공격(Shift)을 요청했다.
## long_press는 LONG_PRESS_TIME 이상 눌렀는지 (방패의 짧게/길게 구분용).
signal special_requested(peer_id: int, long_press: bool)

## 이 플레이어를 조작하는 클라이언트의 peer id. 스폰할 때 서버가 정한다.
@export var owner_peer_id := 0
@export var player_name: String = "1P"
## 대기실에서 고른 캐릭터 이름 (예: "분홍"). 그림은 Characters 표에서 꺼낸다.
@export var character_id: String = ""
## 대기실에서 서버가 확정한 무기 이름 (예: "광선검", "망치").
## 수치는 Weapons.get_weapon()으로 꺼내 쓴다 — 통합 가이드: docs/weapon-system.md
@export var weapon_id: String = ""

const SPEED := 320.0
const JUMP_VELOCITY := -560.0
const FAST_FALL_MULTIPLIER := 2.0
## 클라이언트가 서버 위치를 따라가는 속도. 클수록 즉각적이고 작을수록 부드럽다.
const INTERPOLATION_SPEED := 20.0

## 방패의 짧게/길게를 가르는 시간. 서버가 잰다.
const LONG_PRESS_TIME := 0.3
## 강제 이동(전기톱 돌진, 양날 도끼 상승·낙하) 속도 — 일반 점프의 두 배.
const FORCED_SPEED := absf(JUMP_VELOCITY) * 2.0
## 무기 도형의 기본 길이. 여기에 무기별 배율이 곱해진다.
const BASE_REACH := 24.0
## 캐릭터를 화면에 그릴 높이(px). 그림의 투명 여백은 빼고 실제로 보이는 부분의 높이다.
const BODY_HEIGHT := 72.0
## 발이 닿는 높이 — 충돌 상자(48x56)의 아래쪽 모서리.
const BODY_BOTTOM := 28.0
## 넉백 직후 좌우 입력이 속도를 덮어쓰지 못하는 시간.
##
## 서버가 매 프레임 velocity.x를 입력값으로 덮어쓰기 때문에, 이 잠금이 없으면
## 이동 속도(320)보다 약한 넉백(약 200·중 400의 감속 구간)이 다음 프레임에
## 그대로 지워져서 밀리는 것이 보이지 않는다.
const KNOCKBACK_CONTROL_LOCK := 0.2

## 전투 상태. 서버가 정하고 RPC로 양쪽에 복제된다.
var hp := Combat.MAX_HP
var alive := true
## 바라보는 방향 (1 오른쪽 / -1 왼쪽). 특수 공격은 이 방향으로 나간다.
var facing := 1
## 너클 게이지. 내가 맞을 때 충전된다.
var gauge := 0.0
## 특수 공격을 쓸 수 있는가. 서버가 쿨타임을 재고 이 값만 내려준다 (무기 도형 색에 쓴다).
var special_ready := true
## 강제 이동 상태. ""이면 평소, "dash"(전기톱) / "rise"·"fall"(양날 도끼).
var forced_mode := ""

## 무적 시간은 기본 공격용과 특수 공격용을 따로 잰다.
## 합치면 기본 공격이 계속 무적을 새로 걸어서 특수 공격이 거의 안 들어간다.
var _invuln_until := {"basic": 0.0, "special": 0.0}
var _stun_until := 0.0
## 광선검 특수 — 상대 무기의 막기를 무시한다. 지형은 통과하지 못한다.
var _pierce_until := 0.0
var _reach_multiplier := 1.0
var _reach_until := 0.0
var _size_multiplier := 1.0
var _size_until := 0.0
var _forced_deadline := 0.0
var _knockback_until := 0.0

## 서버가 보관하는 최신 입력 (클라이언트에서 RPC로 갱신된다)
var _input_direction := 0.0
var _input_fast_fall := false
var _jump_queued := false
## 서버가 재는 Shift 누른 시각. 음수면 안 누르고 있다.
var _skill_held_since := -1.0

## 그림을 BODY_HEIGHT에 맞추는 배율. 찌그러짐은 여기에 곱해진다.
var _body_base_scale := Vector2.ONE
## 그림 좌우 여백이 달라 생기는 치우침 보정. 뒤집으면 부호도 뒤집는다.
var _body_offset_x := 0.0

## 클라이언트가 서버로부터 받은 표시용 상태
var _target_position := Vector2.ZERO
var _remote_on_floor := false
## 클라이언트가 Shift 엣지를 잡기 위해 들고 있는 직전 상태
var _skill_was_pressed := false


func _ready() -> void:
	_apply_character()
	$NameLabel.text = player_name
	_target_position = global_position
	# 투사체가 사거리 안의 젤리를 찾을 때 쓴다.
	add_to_group("jellies")
	if multiplayer.is_server():
		# 스폰 직후 바로 맞지 않도록 잠깐 무적을 준다.
		var grace := _now() + Combat.ROUND_START_GRACE
		_invuln_until = {"basic": grace, "special": grace}
	_update_weapon_shape()


## 이 기기가 조작하는 플레이어인지.
func is_local_player() -> bool:
	return owner_peer_id == multiplayer.get_unique_id()


## 입력을 읽는 유일한 지점. 자기 플레이어가 아니면 빈 입력을 돌려준다.
func read_input() -> Dictionary:
	if not is_local_player():
		return {"direction": 0.0, "jump": false, "fast_fall": false, "skill": false}
	return {
		"direction": Input.get_axis("move_left", "move_right"),
		"jump": Input.is_action_just_pressed("jump"),
		"fast_fall": Input.is_action_pressed("fast_fall"),
		"skill": Input.is_action_pressed("skill"),
	}


## 이동 적용. Input을 직접 읽지 않고 인자만 받는다 — 서버에서만 호출된다.
func apply_movement(input: Dictionary, delta: float) -> void:
	# 강제 이동 중에는 조작이 전부 불가하다. 동작이 끝날 때까지 몸이 알아서 움직인다.
	if forced_mode != "":
		_apply_forced(delta)
		return

	# 기절·사망 중에도 조작 불가. 중력만 계속 받는다.
	if not can_act():
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return

	# 중력 (fast_fall 을 누르고 있으면 빠르게 낙하)
	if not is_on_floor():
		var gravity := get_gravity()
		if input["fast_fall"]:
			gravity *= FAST_FALL_MULTIPLIER
		velocity += gravity * delta

	if input["jump"] and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction: float = input["direction"]
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
	# 넉백으로 밀리는 동안에는 입력이 속도를 즉시 덮어쓰지 않게 한다.
	if _now() >= _knockback_until:
		velocity.x = direction * SPEED
	elif direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * SPEED, SPEED * delta)

	move_and_slide()


## 강제 이동. 서버에서만 호출된다.
func _apply_forced(delta: float) -> void:
	match forced_mode:
		"dash":
			velocity.x = facing * FORCED_SPEED
			if not is_on_floor():
				velocity += get_gravity() * delta
			move_and_slide()
			# 벽에 부딪히거나 안전장치 시간이 지나면 끝난다.
			if is_on_wall() or _now() >= _forced_deadline:
				server_end_forced()
		"rise":
			velocity.y = -FORCED_SPEED
			move_and_slide()
			# 올라가는 힘이 다하면 낙하로 넘어간다.
			if _now() >= _forced_deadline:
				_receive_forced.rpc("fall", 0.0)
		"fall":
			velocity.x = 0.0
			velocity.y = FORCED_SPEED
			move_and_slide()
			if is_on_floor():
				server_end_forced()


## 캐릭터 그림을 붙이고 크기·위치를 맞춘다.
##
## 원화는 정사각 캔버스에 투명 여백을 두고 그려져 있어서 파일 크기를 그대로 쓰면
## 발이 땅에서 뜬다. 그래서 여백을 뺀 실제 그림 영역을 재서 그 아래쪽을 발밑에 맞춘다.
func _apply_character() -> void:
	if not Characters.has(character_id):
		character_id = Characters.default_id()
	var sprite: Sprite2D = $Body
	var texture := Characters.texture(character_id)
	sprite.texture = texture
	if texture == null:
		return
	var texture_size := Vector2(texture.get_size())
	var content := Characters.content_rect(texture)
	if content.size.y <= 0.0:
		return

	var factor := BODY_HEIGHT / content.size.y
	_body_base_scale = Vector2.ONE * factor
	sprite.scale = _body_base_scale
	# 스프라이트는 자기 위치를 중심으로 그려진다 — 여백만큼 밀어서 그림의 좌우 가운데가
	# 몸 중심에, 아래쪽이 충돌 상자 바닥에 오게 한다.
	_body_offset_x = (texture_size.x * 0.5 - content.position.x - content.size.x * 0.5) * factor
	var offset_y := (texture_size.y * 0.5 - content.position.y - content.size.y) * factor
	sprite.position = Vector2(_body_offset_x, BODY_BOTTOM + offset_y)


## 젤리 찌그러짐 연출. 서버·클라이언트 모두 복제된 속도·접지값으로 계산한다.
## 그림마다 원본 크기가 달라 찌그러짐은 기본 배율에 곱해서 쓴다.
func _update_squash(grounded: bool, delta: float) -> void:
	var target_scale := Vector2.ONE
	if not grounded:
		target_scale = Vector2(0.9, 1.1)
	elif absf(velocity.x) > 1.0:
		target_scale = Vector2(1.1, 0.9)
	$Body.scale = $Body.scale.lerp(_body_base_scale * target_scale, 12.0 * delta)


## 무기는 임시 도형(막대)으로 그린다 — 그래픽이 나오면 교체한다.
## 길이는 무기의 사거리, 방패의 크기 증가는 두께로 표현한다.
## 특수 공격 쿨타임은 도형 색으로만 보여준다 (별도 UI 없음).
func _update_weapon_shape() -> void:
	var shape: ColorRect = $WeaponShape
	if Weapons.get_weapon(weapon_id).is_empty():
		shape.hide()
		return
	shape.show()
	var length := current_reach()
	var thickness := 10.0 * _size_multiplier
	shape.size = Vector2(length, thickness)
	shape.position = Vector2(0.0 if facing > 0 else -length, -thickness * 0.5)

	if not can_act():
		shape.color = Color(0.45, 0.45, 0.5)   # 기절·사망·강제 이동
	elif special_ready:
		shape.color = Color(0.95, 0.95, 1.0)   # 특수 공격 가능
	else:
		shape.color = Color(0.55, 0.55, 0.62)  # 쿨타임 중


## 현재 사거리. 장대의 특수 공격이나 방패 크기 증가로 늘어난다.
func current_reach() -> float:
	var data := Weapons.get_weapon(weapon_id)
	if data.is_empty():
		return 0.0
	var base: float = BASE_REACH * data.get("reach_multiplier", 1.0)
	return base * _reach_multiplier * _size_multiplier


func _physics_process(delta: float) -> void:
	if is_local_player():
		_send_input()

	if multiplayer.is_server():
		_check_long_press()
		apply_movement(_take_input(), delta)
		_receive_state.rpc(global_position, velocity, is_on_floor(), facing)
		_update_squash(is_on_floor(), delta)
	else:
		# 클라이언트는 물리를 계산하지 않고 서버가 보낸 위치로 따라간다
		global_position = global_position.lerp(_target_position, minf(INTERPOLATION_SPEED * delta, 1.0))
		_update_squash(_remote_on_floor, delta)

	_expire_buffs()
	_update_weapon_shape()
	# 바라보는 방향으로 그림을 뒤집는다. facing은 서버가 정해 양쪽에 복제된다.
	# 뒤집으면 그림이 스프라이트 중심을 기준으로 반전되므로 여백 보정도 반대로 간다.
	var flipped := facing < 0
	$Body.flip_h = flipped
	$Body.position.x = -_body_offset_x if flipped else _body_offset_x


## 자기 입력을 서버로 보낸다.
## 점프와 Shift는 한 프레임짜리 엣지라 별도 reliable RPC로 보낸다.
func _send_input() -> void:
	var input := read_input()
	_receive_move_input.rpc_id(1, input["direction"], input["fast_fall"])
	if input["jump"]:
		_receive_jump.rpc_id(1)
	var skill: bool = input["skill"]
	if skill != _skill_was_pressed:
		_skill_was_pressed = skill
		_receive_skill.rpc_id(1, skill)


## 서버가 보관 중인 입력을 꺼낸다. 점프는 한 번만 소비된다.
func _take_input() -> Dictionary:
	var input := {
		"direction": _input_direction,
		"jump": _jump_queued,
		"fast_fall": _input_fast_fall,
	}
	_jump_queued = false
	return input


## 길게 누른 것이 확정되는 순간 바로 발동한다 (뗄 때까지 기다리지 않는다).
## 서버 전용 — 누른 시간을 서버가 재야 클라이언트가 길게/짧게를 속일 수 없다.
func _check_long_press() -> void:
	if _skill_held_since < 0.0:
		return
	if _now() - _skill_held_since >= LONG_PRESS_TIME:
		_skill_held_since = -1.0
		special_requested.emit(owner_peer_id, true)


# ─────────────────────────── 입력 수신 (서버 전용) ───────────────────────────

## 이동 입력 수신. 매 프레임 덮어써지므로 유실을 허용한다.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_move_input(direction: float, fast_fall: bool) -> void:
	if not _is_owner_input():
		return
	_input_direction = clampf(direction, -1.0, 1.0)
	_input_fast_fall = fast_fall


## 점프 입력 수신. 유실되면 점프가 씹히므로 reliable로 받는다.
@rpc("any_peer", "call_remote", "reliable")
func _receive_jump() -> void:
	if not _is_owner_input():
		return
	_jump_queued = true


## Shift 누름·뗌 수신. 엣지라 유실되면 안 되므로 reliable로 받는다.
@rpc("any_peer", "call_remote", "reliable")
func _receive_skill(pressed: bool) -> void:
	if not _is_owner_input():
		return
	if pressed:
		_skill_held_since = _now()
	elif _skill_held_since >= 0.0:
		_skill_held_since = -1.0
		special_requested.emit(owner_peer_id, false)


## 서버가 받은 입력 RPC가 이 플레이어의 주인이 보낸 것인지.
## 없으면 남의 플레이어를 조작할 수 있다.
func _is_owner_input() -> bool:
	if not multiplayer.is_server():
		return false
	return multiplayer.get_remote_sender_id() == owner_peer_id


## 서버가 정한 상태 수신 (클라이언트 전용).
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_state(server_position: Vector2, server_velocity: Vector2, on_floor: bool, server_facing: int) -> void:
	_target_position = server_position
	velocity = server_velocity
	_remote_on_floor = on_floor
	facing = server_facing


# ─────────────────────────── 상태 조회 ───────────────────────────

func is_invulnerable(source := "basic") -> bool:
	return _now() < _invuln_until.get(source, 0.0)


func is_stunned() -> bool:
	return _now() < _stun_until


## 관통 상태에서는 상대 무기가 공격을 막지 못한다.
func is_piercing() -> bool:
	return _now() < _pierce_until


func is_forced() -> bool:
	return forced_mode != ""


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


# ─────────────────────────── 피격·상태 (서버 판정) ───────────────────────────
# server_* 함수는 서버에서만 호출한다. 결과를 authority RPC로 양쪽에 복제한다.

## 데미지를 적용하고 결과를 전원에게 내려준다.
##
## source 는 "basic" / "special" / "projectile".
## 기본과 특수는 무적 타이머가 따로 돌아가고,
## 허공을 나는 것("projectile")은 공유 무적을 아예 타지 않는다 —
## 활 특수 3발처럼 같은 순간에 도착하는 것도 전부 들어간다.
func server_apply_hit(damage: float, knockback_level: int, from_x: float,
		stun := 0.0, source := "basic") -> void:
	if not multiplayer.is_server() or not alive:
		return
	if source != "projectile" and is_invulnerable(source):
		return
	var new_hp: float = maxf(hp - damage, 0.0)
	var direction := signf(global_position.x - from_x)
	if direction == 0.0:
		direction = 1.0
	# 너클은 내가 맞을 때 게이지가 찬다.
	var new_gauge := gauge
	var data := Weapons.get_weapon(weapon_id)
	if data.get("gauge_per_hit", 0.0) > 0.0:
		new_gauge = minf(gauge + data["gauge_per_hit"], data["gauge_max"])
	_receive_hit.rpc(new_hp, knockback_level, direction, stun, source, new_gauge)


## 출혈 같은 지속 데미지. 무적 시간을 무시하고 들어가고, 넉백도 없다.
func server_apply_dot(damage: float) -> void:
	if not multiplayer.is_server() or not alive:
		return
	_receive_dot.rpc(maxf(hp - damage, 0.0))


## 데미지 없는 사망 (낙사 등).
func server_kill() -> void:
	if not multiplayer.is_server() or not alive:
		return
	_receive_dot.rpc(0.0)


## 사거리·크기·관통 버프.
func server_apply_buff(kind: String, value: float, duration: float) -> void:
	if not multiplayer.is_server():
		return
	_receive_buff.rpc(kind, value, duration)


## 너클 게이지는 특수 공격을 쓰면 전부 소모된다.
func server_set_gauge(value: float) -> void:
	if not multiplayer.is_server():
		return
	_receive_gauge.rpc(value)


## 특수 공격 쿨타임 상태. 무기 도형 색에 쓴다.
func server_set_special_ready(value: bool) -> void:
	if not multiplayer.is_server() or special_ready == value:
		return
	_receive_special_ready.rpc(value)


## 강제 이동 시작.
func server_start_forced(mode: String, duration: float) -> void:
	if not multiplayer.is_server():
		return
	_receive_forced.rpc(mode, duration)


func server_end_forced() -> void:
	if not multiplayer.is_server():
		return
	_receive_forced.rpc("", 0.0)


# ─────────────────────────── 결과 수신 (서버 → 전원) ───────────────────────────

@rpc("authority", "call_local", "reliable")
func _receive_hit(new_hp: float, knockback_level: int, direction: float,
		stun: float, source: String, new_gauge: float) -> void:
	hp = new_hp
	gauge = new_gauge
	if source != "projectile":
		_invuln_until[source] = _now() + Combat.INVULNERABLE_TIME
	if stun > 0.0:
		_stun_until = _now() + stun
	# 넉백은 물리를 계산하는 서버에서만 적용한다.
	if multiplayer.is_server() and direction != 0.0:
		velocity = Combat.knockback_velocity(knockback_level, direction)
		_knockback_until = _now() + KNOCKBACK_CONTROL_LOCK
	_check_death()


@rpc("authority", "call_local", "reliable")
func _receive_dot(new_hp: float) -> void:
	hp = new_hp
	_check_death()


func _check_death() -> void:
	if hp > 0.0 or not alive:
		return
	alive = false
	velocity = Vector2.ZERO
	forced_mode = ""
	modulate.a = 0.35
	if multiplayer.is_server():
		died.emit(owner_peer_id)


@rpc("authority", "call_local", "reliable")
func _receive_special_ready(value: bool) -> void:
	special_ready = value


@rpc("authority", "call_local", "reliable")
func _receive_gauge(value: float) -> void:
	gauge = value


@rpc("authority", "call_local", "reliable")
func _receive_forced(mode: String, duration: float) -> void:
	forced_mode = mode
	_forced_deadline = _now() + duration
	if mode == "":
		velocity = Vector2.ZERO
	else:
		_skill_held_since = -1.0


@rpc("authority", "call_local", "reliable")
func _receive_buff(kind: String, value: float, duration: float) -> void:
	match kind:
		"reach":
			_reach_multiplier = value
			_reach_until = _now() + duration
		"size":
			_size_multiplier = value
			_size_until = _now() + duration
		"pierce":
			_pierce_until = _now() + duration
