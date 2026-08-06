extends CharacterBody2D
## 젤리 플레이어. 서버 권위 이동.
##
## 클라이언트는 입력만 서버로 보내고 물리를 직접 계산하지 않는다.
## 서버가 apply_movement()로 위치를 정하고 결과를 양쪽에 복제하며,
## 클라이언트는 받은 위치로 보간해 표시한다.

## 이 플레이어를 조작하는 클라이언트의 peer id. 스폰할 때 서버가 정한다.
@export var owner_peer_id := 0
@export var player_name: String = "1P"
@export var jelly_color: Color = Color(1.0, 0.42, 0.55)
## 대기실에서 고른 무기 id. 값 보관만 하며 동작은 없다 —
## 무기 동작 구현은 공동작업자 담당이며 이 값을 읽어 자신을 붙이면 된다.
@export var weapon_id: String = ""

const SPEED := 320.0
const JUMP_VELOCITY := -560.0
const FAST_FALL_MULTIPLIER := 2.0
## 클라이언트가 서버 위치를 따라가는 속도. 클수록 즉각적이고 작을수록 부드럽다.
const INTERPOLATION_SPEED := 20.0

## 서버가 보관하는 최신 입력 (클라이언트에서 RPC로 갱신된다)
var _input_direction := 0.0
var _input_fast_fall := false
var _jump_queued := false

## 클라이언트가 서버로부터 받은 표시용 상태
var _target_position := Vector2.ZERO
var _remote_on_floor := false


func _ready() -> void:
	$Body.color = jelly_color
	$NameLabel.text = player_name
	_target_position = global_position


## 이 기기가 조작하는 플레이어인지.
func is_local_player() -> bool:
	return owner_peer_id == multiplayer.get_unique_id()


## 입력을 읽는 유일한 지점. 자기 플레이어가 아니면 빈 입력을 돌려준다.
func read_input() -> Dictionary:
	if not is_local_player():
		return {"direction": 0.0, "jump": false, "fast_fall": false}
	return {
		"direction": Input.get_axis("move_left", "move_right"),
		"jump": Input.is_action_just_pressed("jump"),
		"fast_fall": Input.is_action_pressed("fast_fall"),
	}


## 이동 적용. Input을 직접 읽지 않고 인자만 받는다 — 서버에서만 호출된다.
func apply_movement(input: Dictionary, delta: float) -> void:
	# 중력 (fast_fall 을 누르고 있으면 빠르게 낙하)
	if not is_on_floor():
		var gravity := get_gravity()
		if input["fast_fall"]:
			gravity *= FAST_FALL_MULTIPLIER
		velocity += gravity * delta

	if input["jump"] and is_on_floor():
		velocity.y = JUMP_VELOCITY

	velocity.x = input["direction"] * SPEED

	move_and_slide()


## 젤리 찌그러짐 연출. 서버·클라이언트 모두 복제된 속도·접지값으로 계산한다.
func _update_squash(grounded: bool, delta: float) -> void:
	var target_scale := Vector2.ONE
	if not grounded:
		target_scale = Vector2(0.9, 1.1)
	elif absf(velocity.x) > 1.0:
		target_scale = Vector2(1.1, 0.9)
	$Body.scale = $Body.scale.lerp(target_scale, 12.0 * delta)


func _physics_process(delta: float) -> void:
	if is_local_player():
		_send_input()

	if multiplayer.is_server():
		apply_movement(_take_input(), delta)
		_receive_state.rpc(global_position, velocity, is_on_floor())
		_update_squash(is_on_floor(), delta)
	else:
		# 클라이언트는 물리를 계산하지 않고 서버가 보낸 위치로 따라간다
		global_position = global_position.lerp(_target_position, minf(INTERPOLATION_SPEED * delta, 1.0))
		_update_squash(_remote_on_floor, delta)


## 자기 입력을 서버로 보낸다. 점프는 한 프레임짜리 엣지라 별도 reliable RPC로 보낸다.
func _send_input() -> void:
	var input := read_input()
	_receive_move_input.rpc_id(1, input["direction"], input["fast_fall"])
	if input["jump"]:
		_receive_jump.rpc_id(1)


## 서버가 보관 중인 입력을 꺼낸다. 점프는 한 번만 소비된다.
func _take_input() -> Dictionary:
	var input := {
		"direction": _input_direction,
		"jump": _jump_queued,
		"fast_fall": _input_fast_fall,
	}
	_jump_queued = false
	return input


## 이동 입력 수신 (서버 전용). 매 프레임 덮어써지므로 유실을 허용한다.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_move_input(direction: float, fast_fall: bool) -> void:
	if not multiplayer.is_server():
		return
	# 남의 플레이어를 조작하려는 입력은 무시한다
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	_input_direction = clampf(direction, -1.0, 1.0)
	_input_fast_fall = fast_fall


## 점프 입력 수신 (서버 전용). 유실되면 점프가 씹히므로 reliable로 받는다.
@rpc("any_peer", "call_remote", "reliable")
func _receive_jump() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	_jump_queued = true


## 서버가 정한 상태 수신 (클라이언트 전용).
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_state(server_position: Vector2, server_velocity: Vector2, on_floor: bool) -> void:
	_target_position = server_position
	velocity = server_velocity
	_remote_on_floor = on_floor
