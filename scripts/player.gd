extends CharacterBody2D
## 젤리 플레이어. 각 기기는 자기 소유 플레이어만 조작한다.
## 노드의 멀티플레이 권한은 서버가 갖는다 — 3단계에서 서버 권위 이동으로 확장한다.

## 이 플레이어를 조작하는 클라이언트의 peer id. 스폰할 때 서버가 정한다.
@export var owner_peer_id := 0
@export var player_name: String = "1P"
@export var jelly_color: Color = Color(1.0, 0.42, 0.55)

const SPEED := 320.0
const JUMP_VELOCITY := -560.0
const FAST_FALL_MULTIPLIER := 2.0


func _ready() -> void:
	$Body.color = jelly_color
	$NameLabel.text = player_name


## 이 기기가 조작하는 플레이어인지.
func is_local_player() -> bool:
	return owner_peer_id == multiplayer.get_unique_id()


## 입력을 읽는 유일한 지점. 3단계에서는 이 결과를 서버로 전송하도록 바꾼다.
func read_input() -> Dictionary:
	if not is_local_player():
		return {"direction": 0.0, "jump": false, "fast_fall": false}
	return {
		"direction": Input.get_axis("move_left", "move_right"),
		"jump": Input.is_action_just_pressed("jump"),
		"fast_fall": Input.is_action_pressed("fast_fall"),
	}


## 이동 적용. Input을 직접 읽지 않고 인자로만 받는다 — 3단계에서 서버가 호출한다.
func apply_movement(input: Dictionary, delta: float) -> void:
	# 중력 (fast_fall 을 누르고 있으면 빠르게 낙하)
	if not is_on_floor():
		var gravity := get_gravity()
		if input["fast_fall"]:
			gravity *= FAST_FALL_MULTIPLIER
		velocity += gravity * delta

	if input["jump"] and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction: float = input["direction"]
	velocity.x = direction * SPEED

	move_and_slide()

	# 젤리 느낌: 움직일 때 살짝 찌그러지기
	var target_scale := Vector2.ONE
	if not is_on_floor():
		target_scale = Vector2(0.9, 1.1)
	elif direction != 0.0:
		target_scale = Vector2(1.1, 0.9)
	$Body.scale = $Body.scale.lerp(target_scale, 12.0 * delta)


func _physics_process(delta: float) -> void:
	apply_movement(read_input(), delta)
