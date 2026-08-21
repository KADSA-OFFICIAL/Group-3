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
## 무기 그림을 그릴 높이(px). 캐릭터보다 조금 작아야 손에 든 것처럼 보인다.
const WEAPON_HEIGHT := 56.0
## 무기 그림의 최대 가로(px). 가로로 긴 원화(전기톱·대포 총)가 몸통(48px)을 덮지 않게 한다.
## 세로로 긴 무기는 여기에 걸리지 않아 WEAPON_HEIGHT 그대로다.
const WEAPON_MAX_WIDTH := 80.0
## 무기를 몸 중심에서 얼마나 옆으로 둘지. 바라보는 쪽에 놓인다.
const WEAPON_OFFSET_X := 26.0
## 무기 그림의 세로 중심. 몸 한가운데쯤이다.
const WEAPON_CENTER_Y := -8.0

## 관통(광선검 특수) 중임을 알리는 빛. 광선검 날에 맞춘 민트빛이다.
const PIERCE_COLOR := Color(0.55, 0.95, 0.85)
## 관통 중 무기에 곱하는 색. 1을 넘겨서 날이 타오르게 만든다.
const PIERCE_TINT := Color(0.8, 1.5, 1.35)
## 빛무리 크기와 그 중심(몸 한가운데). 몸이 48x72라 이 정도면 몸을 감싼다.
const PIERCE_AURA_RADIUS := 58.0
const PIERCE_AURA_CENTER := Vector2(0.0, -8.0)
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
## 지금 어떤 포즈의 원화를 입고 있는가 (#176). 평소에는 `Characters.POSE_IDLE`이고,
## 죽는 순간 자신은 패배 포즈, 점수를 얻은 상대는 승리 포즈가 된다.
## 라운드가 다시 시작되면 평소로 돌아온다 — 안 되돌리면 다음 라운드로 새어 나간다.
var pose := Characters.POSE_IDLE
## 너클 게이지. 내가 맞을 때 충전된다.
var gauge := 0.0
## 특수 공격을 쓸 수 있는가. 서버가 쿨타임을 재고 이 값만 내려준다 (무기 도형 색에 쓴다).
var special_ready := true
## 강제 이동 상태. ""이면 평소, "dash"(전기톱) / "rise"·"fall"(양날 도끼).
var forced_mode := ""
## 다음에 던질 것이 **강화** 폭탄인가 (#134).
##
## 던지는 순간에 뽑으면 손에 들고 보여줄 수가 없어서, 서버가 미리 뽑아 복제한다.
## 첫 스폰값은 스폰 데이터로 들어오고(`main.gd._spawn_player`), 그 뒤로는
## `server_set_empowered()`가 갱신한다 — 라운드 시작과 던진 직후다.
var empowered_ready := false

## 무적 시간은 기본 공격용과 특수 공격용을 따로 잰다.
## 합치면 기본 공격이 계속 무적을 새로 걸어서 특수 공격이 거의 안 들어간다.
var _invuln_until := {"basic": 0.0, "special": 0.0}
var _stun_until := 0.0
## 광선검 특수 — 상대 무기의 막기를 무시한다. 지형은 통과하지 못한다.
var _pierce_until := 0.0
## 지난 프레임에 관통 빛을 그렸는가. 꺼진 프레임에 한 번 더 다시 그려 지우려고 들고 있다.
var _aura_shown := false
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
## 배율 1일 때의 여백 보정(원본 픽셀 단위). 실제 보정은 그때그때 배율을 곱해서 쓴다 —
## 찌그러짐으로 배율이 흔들려도 발밑과 좌우 중심이 그대로 있어야 하기 때문이다.
var _body_offset_unit := Vector2.ZERO
## 무기 그림의 여백 보정. 그림이 없는 무기면 쓰이지 않는다.
var _weapon_offset := Vector2.ZERO
## 이 무기에 그림이 있는가. 없으면 지금까지처럼 임시 막대로 그린다.
var _weapon_has_art := false
## 이 무기의 원화가 왼쪽을 보고 그려졌는가. 그렇다면 뒤집는 조건이 반대가 된다 (#109).
var _weapon_faces_left := false

## 클라이언트가 서버로부터 받은 표시용 상태
var _target_position := Vector2.ZERO
var _remote_on_floor := false
## 클라이언트가 Shift 엣지를 잡기 위해 들고 있는 직전 상태
var _skill_was_pressed := false


func _ready() -> void:
	_apply_character()
	_apply_weapon()
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
##
## 포즈가 바뀔 때도 이 함수를 다시 부른다 (#176) — 승리·패배 원화는 평소 그림과
## 비율이 달라서(눕는 포즈는 가로가 길다) 배율과 여백 보정을 처음부터 다시 재야 한다.
func _apply_character() -> void:
	if not Characters.has(character_id):
		character_id = Characters.default_id()
	var sprite: Sprite2D = $Body
	var texture := Characters.pose_texture(character_id, pose)
	sprite.texture = texture
	if texture == null:
		return
	var texture_size := Vector2(texture.get_size())
	var content := Art.content_rect(texture)
	if content.size.y <= 0.0:
		return

	var factor := BODY_HEIGHT / content.size.y
	_body_base_scale = Vector2.ONE * factor
	sprite.scale = _body_base_scale
	# 스프라이트는 자기 위치를 중심으로 그려진다 — 여백만큼 밀어서 그림의 좌우 가운데가
	# 몸 중심에, 아래쪽이 충돌 상자 바닥에 오게 한다.
	# 배율을 곱하기 전 값으로 들고 있다가 _place_body()가 그때의 배율로 환산한다.
	_body_offset_unit = Vector2(
		texture_size.x * 0.5 - content.position.x - content.size.x * 0.5,
		texture_size.y * 0.5 - content.position.y - content.size.y)
	_place_body()


## 지금 배율에 맞춰 그림 위치를 잡는다. 발밑이 항상 충돌 상자 바닥에 오게 하는 곳이다.
##
## Sprite2D 는 자기 위치를 **중심으로** 확대·축소한다. 그래서 찌그러짐으로 세로 배율이
## 커지면 머리와 발이 같이 벌어져 발이 바닥을 뚫고, 작아지면 발이 뜬다 (이슈 #85).
## 배율이 바뀔 때마다 여백 보정을 다시 환산해서 기준점을 발밑으로 되돌린다.
func _place_body() -> void:
	var sprite: Sprite2D = $Body
	var offset := _body_offset_unit * sprite.scale
	# 뒤집으면 그림이 스프라이트 중심을 기준으로 반전되므로 좌우 보정도 반대로 간다.
	if sprite.flip_h:
		offset.x = -offset.x
	sprite.position = Vector2(offset.x, BODY_BOTTOM + offset.y)


## 젤리 찌그러짐 연출. 서버·클라이언트 모두 복제된 속도·접지값으로 계산한다.
## 그림마다 원본 크기가 달라 찌그러짐은 기본 배율에 곱해서 쓴다.
func _update_squash(grounded: bool, delta: float) -> void:
	var target_scale := Vector2.ONE
	if not grounded:
		target_scale = Vector2(0.9, 1.1)
	elif absf(velocity.x) > 1.0:
		target_scale = Vector2(1.1, 0.9)
	$Body.scale = $Body.scale.lerp(_body_base_scale * target_scale, 12.0 * delta)
	# 배율이 바뀌었으니 발밑이 바닥에 남아 있도록 위치를 다시 잡는다.
	_place_body()


## 손에 들 무기 그림 (#134).
##
## 강화가 준비된 폭탄은 강화 그림을 든다 — 무기 표에 `empowered_file`이 있고
## 서버가 미리 뽑아 둔 값이 true 일 때만이다. 그림이 없으면 평소 것으로 돌아간다.
func _weapon_texture() -> Texture2D:
	if empowered_ready:
		var file: String = Weapons.get_weapon(weapon_id).get("empowered_file", "")
		var empowered := Weapons.texture_file(file)
		if empowered != null:
			return empowered
	return Weapons.texture(weapon_id)


## 무기 그림을 붙이고 크기를 맞춘다. 그림이 없는 무기면 막대 쪽을 쓴다.
func _apply_weapon() -> void:
	var sprite: Sprite2D = $WeaponSprite
	var texture := _weapon_texture()
	sprite.texture = texture
	_weapon_has_art = texture != null
	_weapon_faces_left = Weapons.art_faces_left(weapon_id)
	if texture == null:
		return
	var texture_size := Vector2(texture.get_size())
	var content := Art.content_rect(texture)
	if content.size.y <= 0.0 or content.size.x <= 0.0:
		_weapon_has_art = false
		return
	# 세로를 WEAPON_HEIGHT에 맞추되 가로가 WEAPON_MAX_WIDTH를 넘지 않게 한다.
	# 세로만 맞추면 가로로 긴 원화(전기톱 2.69:1)가 몸통 3배 폭으로 터진다 (이슈 #105).
	var factor := minf(WEAPON_HEIGHT / content.size.y, WEAPON_MAX_WIDTH / content.size.x)
	# 뭉툭한 원화는 두 제한을 다 통과하고도 몸통만 해진다 (이슈 #158). 세로 규칙은
	# 검처럼 가늘고 긴 무기를 기준으로 잡은 것이고, 가로 제한은 세로로 긴 것을 못 잡듯
	# 정사각에 가까운 것도 못 잡는다. 그런 무기만 표에서 배율을 더 준다.
	factor *= Weapons.art_scale(weapon_id)
	sprite.scale = Vector2.ONE * factor
	# 캐릭터와 마찬가지로 여백을 뺀 실제 그림의 가운데를 기준으로 놓는다.
	_weapon_offset = Vector2(
		(texture_size.x * 0.5 - content.position.x - content.size.x * 0.5) * factor,
		(texture_size.y * 0.5 - content.position.y - content.size.y * 0.5) * factor,
	)


## 관통 빛은 매 프레임 모양이 바뀌니 켜져 있는 동안 계속 다시 그린다.
## 꺼진 프레임에도 한 번 더 그려야 화면에서 지워진다 — 안 그러면 마지막 모양이 남는다.
func _update_pierce_aura() -> void:
	var piercing := is_piercing()
	if piercing or _aura_shown:
		_aura_shown = piercing
		queue_redraw()


## 관통(광선검 특수) 중에 몸 뒤로 도는 빛.
##
## 자식 노드(`Body`)보다 **먼저** 그려져서 젤리 뒤에 깔린다 — 그래서 별도 노드가 필요 없다.
## 씬 루트에 걸린 가산 혼합은 이 그리기에만 적용되고 자식 스프라이트에는 영향이 없다.
##
## `_pierce_until`이 `_receive_buff`로 양쪽 피어에 복제되므로 두 화면에 똑같이 뜬다.
func _draw() -> void:
	if not is_piercing():
		return
	var pulse := 0.72 + 0.28 * sin(_now() * 9.0)
	# 맵 배경이 밝은 편(평지 잔디가 0.36·0.66·0.32)이라 가산 혼합이 쉽게 묻힌다.
	# 넓고 옅은 것 위에 좁고 진한 것을 겹쳐야 잔디 위에서도 빛으로 읽힌다.
	Art.draw_glow(self, PIERCE_AURA_CENTER, PIERCE_AURA_RADIUS * (1.25 + 0.12 * pulse),
		PIERCE_COLOR, 0.5 * pulse)
	Art.draw_glow(self, PIERCE_AURA_CENTER, PIERCE_AURA_RADIUS * (0.92 + 0.08 * pulse),
		PIERCE_COLOR, 0.9 * pulse)
	# 윤곽선을 덧그려 "지금 켜져 있다"가 확실히 보이게 한다.
	draw_arc(PIERCE_AURA_CENTER, PIERCE_AURA_RADIUS * 0.82, 0.0, TAU, 44,
		Color(PIERCE_COLOR, 0.95 * pulse), 3.5, true)


## 무기 표시. 그림이 있으면 그림을, 없으면 지금까지의 임시 막대를 쓴다.
## 어느 쪽이든 특수 공격 쿨타임 상태를 밝기·색으로 보여준다 (별도 UI 없음).
func _update_weapon_shape() -> void:
	var shape: ColorRect = $WeaponShape
	var sprite: Sprite2D = $WeaponSprite
	if Weapons.get_weapon(weapon_id).is_empty():
		shape.hide()
		sprite.hide()
		return

	if _weapon_has_art:
		shape.hide()
		sprite.show()
		# 원화는 오른쪽 보기가 기본이라 왼쪽을 볼 때 뒤집는다. 다만 왼쪽을 보고 그려진
		# 원화(전기톱)는 조건이 정반대다 — 안 그러면 톱날이 등 뒤로 간다 (#109).
		# 뒤집으면 그림이 스프라이트 중심을 기준으로 반전되므로 여백 보정도 반대로 간다.
		var flipped := (facing < 0) != _weapon_faces_left
		sprite.flip_h = flipped
		var offset_x := -_weapon_offset.x if flipped else _weapon_offset.x
		sprite.position = Vector2(
			facing * WEAPON_OFFSET_X + offset_x,
			WEAPON_CENTER_Y + _weapon_offset.y,
		)
		if is_piercing():
			sprite.modulate = PIERCE_TINT              # 관통 중 — 날이 타오른다
		elif not can_act():
			sprite.modulate = Color(0.45, 0.45, 0.5)   # 기절·사망·강제 이동
		elif special_ready:
			sprite.modulate = Color.WHITE              # 특수 공격 가능
		else:
			sprite.modulate = Color(0.7, 0.7, 0.75)    # 쿨타임 중
		return

	# 그림이 없는 무기 — 길이는 사거리, 두께는 크기 증가를 나타낸다.
	sprite.hide()
	shape.show()
	var length := current_reach()
	var thickness := 10.0 * _size_multiplier
	shape.size = Vector2(length, thickness)
	shape.position = Vector2(0.0 if facing > 0 else -length, -thickness * 0.5)

	if is_piercing():
		shape.color = PIERCE_COLOR             # 관통 중 (그림이 아직 없는 무기용)
	elif not can_act():
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
		_send_state()
		_update_squash(is_on_floor(), delta)
	else:
		# 클라이언트는 물리를 계산하지 않고 서버가 보낸 위치로 따라간다
		global_position = global_position.lerp(_target_position, minf(INTERPOLATION_SPEED * delta, 1.0))
		_update_squash(_remote_on_floor, delta)

	_expire_buffs()
	_update_pierce_aura()
	_update_weapon_shape()
	# 바라보는 방향으로 그림을 뒤집는다. facing은 서버가 정해 양쪽에 복제된다.
	# 여백 보정의 부호는 _place_body()가 flip_h를 보고 맞춘다.
	$Body.flip_h = facing < 0
	_place_body()


## 위치·속도를 **전투 화면에 있는 피어에게만** 보낸다 (서버 전용, 매 프레임).
##
## 브로드캐스트(`rpc()`)로 보내면 대기실에 앉아 있는 피어에게도 날아간다 — 그쪽에는 이 노드가
## 없으니 받을 수 없고 "Node not found" 오류만 초당 60번 쌓인다. 관전이 생기면서
## 전투 화면 밖에 있는 피어가 정상 상태가 되었으므로(이슈 #167) 대상을 골라 보낸다.
func _send_state() -> void:
	for peer in Lobby.viewers:
		_receive_state.rpc_id(peer, global_position, velocity, is_on_floor(), facing)


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
## `knockback_speed`가 0보다 크면 단계 대신 그 속도로 민다 (대포 총 미사일, #121).
func server_apply_hit(damage: float, knockback_level: int, from_x: float,
		stun := 0.0, source := "basic", knockback_speed := 0.0) -> void:
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
	_receive_hit.rpc(new_hp, knockback_level, direction, stun, source, new_gauge, knockback_speed)


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


## 다음 라운드를 위해 되살린다. 위치·방향은 맵의 스폰 지점을 서버가 정해서 넘긴다.
func server_reset(spawn_position: Vector2, spawn_facing: int) -> void:
	if not multiplayer.is_server():
		return
	_receive_reset.rpc(spawn_position, spawn_facing)


## 사거리·크기·관통 버프.
func server_apply_buff(kind: String, value: float, duration: float) -> void:
	if not multiplayer.is_server():
		return
	_receive_buff.rpc(kind, value, duration)


## 다음 폭탄이 강화인지를 서버가 정해 양쪽에 알린다 (#134).
##
## **뽑기는 main.gd가 한다** — 전투 판정의 주인이 거기이고, 라운드 시작과 던진 직후라는
## 시점도 거기가 안다. 여기는 결과를 복제하고 그림을 갈아 끼우는 일만 한다.
func server_set_empowered(value: bool) -> void:
	if not multiplayer.is_server():
		return
	_receive_empowered.rpc(value)


## 승리·패배 포즈 (#176). 판정은 main.gd가 한다 — 누가 점수를 얻었는지 아는 곳이 거기다.
##
## **패배 포즈는 여기를 거치지 않는다** — `_check_death()`가 이미 모든 피어에서 돌아가므로
## 죽음과 함께 저절로 복제된다. 라운드 대기 중에 남은 쪽이 또 떨어져도(그때
## `_on_player_died()`는 일찍 돌아온다) 패배 포즈가 빠지지 않는 이유다.
func server_set_pose(value: String) -> void:
	if not multiplayer.is_server() or pose == value:
		return
	_receive_pose.rpc(value)


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
		stun: float, source: String, new_gauge: float, knockback_speed := 0.0) -> void:
	hp = new_hp
	gauge = new_gauge
	if source != "projectile":
		_invuln_until[source] = _now() + Combat.INVULNERABLE_TIME
	if stun > 0.0:
		_stun_until = _now() + stun
	# 넉백은 물리를 계산하는 서버에서만 적용한다.
	if multiplayer.is_server() and direction != 0.0:
		velocity = Combat.knockback_velocity(knockback_level, direction, knockback_speed)
		_knockback_until = _now() + KNOCKBACK_CONTROL_LOCK
	_check_death()


## 손에 든 폭탄이 바뀐다 (#134). 그림만 갈아 끼우므로 판정과는 무관하다.
@rpc("authority", "call_local", "reliable")
func _receive_empowered(value: bool) -> void:
	if empowered_ready == value:
		return
	empowered_ready = value
	_apply_weapon()


## 포즈만 바꾼다 (#176). 판정과는 무관하고 그림을 갈아 끼우는 일만 한다.
@rpc("authority", "call_local", "reliable")
func _receive_pose(value: String) -> void:
	if pose == value:
		return
	pose = value
	_apply_character()


@rpc("authority", "call_local", "reliable")
func _receive_dot(new_hp: float) -> void:
	hp = new_hp
	_check_death()


## 이 함수는 모든 피어에서 돌아간다 (_receive_hit·_receive_dot이 복제되므로).
## 그래서 패배 포즈는 여기서 걸어도 따로 RPC를 보내지 않아도 양쪽에 같이 뜬다.
func _check_death() -> void:
	if hp > 0.0 or not alive:
		return
	alive = false
	velocity = Vector2.ZERO
	forced_mode = ""
	# 반투명으로 죽음을 알리던 것을 포즈가 대신한다 (#176). 흐리게 두면 눕는 원화의
	# 땀방울·효과선이 어두운 맵(용암) 배경에 묻혀 보이지 않는다.
	modulate.a = 1.0
	pose = Characters.POSE_LOSE
	_apply_character()
	if multiplayer.is_server():
		died.emit(owner_peer_id)


## 라운드 초기화. 전투 중에 붙는 상태를 **하나도 남기지 않고** 되돌린다 —
## 여기서 빠뜨린 값은 다음 라운드로 새어 나간다(기절인 채로 시작, 버프 유지 등).
@rpc("authority", "call_local", "reliable")
func _receive_reset(spawn_position: Vector2, spawn_facing: int) -> void:
	hp = Combat.MAX_HP
	alive = true
	facing = spawn_facing
	gauge = 0.0
	special_ready = true
	forced_mode = ""
	modulate.a = 1.0
	# 지난 라운드의 승리·패배 포즈를 벗긴다 (#176) — 안 되돌리면 눕거나 팔을 든 채 싸운다.
	pose = Characters.POSE_IDLE
	_apply_character()

	global_position = spawn_position
	_target_position = spawn_position
	velocity = Vector2.ZERO
	_remote_on_floor = false

	var grace := _now() + Combat.ROUND_START_GRACE
	_invuln_until = {"basic": grace, "special": grace}
	_stun_until = 0.0
	_pierce_until = 0.0
	_reach_multiplier = 1.0
	_reach_until = 0.0
	_size_multiplier = 1.0
	_size_until = 0.0
	_forced_deadline = 0.0
	_knockback_until = 0.0

	# 들고 있던 입력도 지운다 — 죽는 순간 누르고 있던 키가 이어지지 않도록.
	_input_direction = 0.0
	_input_fast_fall = false
	_jump_queued = false
	_skill_held_since = -1.0
	_skill_was_pressed = false


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
