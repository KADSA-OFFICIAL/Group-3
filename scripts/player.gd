extends CharacterBody2D
## 젤리 플레이어 이동 스크립트.
## input_prefix에 따라 1P(WASD) / 2P(방향키) 입력을 받는다.

@export var input_prefix: String = "p1"
@export var player_name: String = "1P"
@export var jelly_color: Color = Color(1.0, 0.42, 0.55)

const SPEED := 320.0
const JUMP_VELOCITY := -560.0
const FAST_FALL_MULTIPLIER := 2.0


func _ready() -> void:
	# 선택 창에서 고른 색을 적용
	jelly_color = GameState.get_config(input_prefix)["color1"]
	$Body.color = jelly_color
	$NameLabel.text = player_name


func _physics_process(delta: float) -> void:
	# 중력 (S / ↓ 를 누르고 있으면 빠르게 낙하)
	if not is_on_floor():
		var gravity := get_gravity()
		if Input.is_action_pressed(input_prefix + "_down"):
			gravity *= FAST_FALL_MULTIPLIER
		velocity += gravity * delta

	# 점프 (W / ↑)
	if Input.is_action_just_pressed(input_prefix + "_up") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# 좌우 이동 (A·D / ←·→)
	var direction := Input.get_axis(input_prefix + "_left", input_prefix + "_right")
	velocity.x = direction * SPEED

	move_and_slide()

	# 젤리 느낌: 움직일 때 살짝 찌그러지기
	var target_scale := Vector2.ONE
	if not is_on_floor():
		target_scale = Vector2(0.9, 1.1)
	elif direction != 0.0:
		target_scale = Vector2(1.1, 0.9)
	$Body.scale = $Body.scale.lerp(target_scale, 12.0 * delta)
