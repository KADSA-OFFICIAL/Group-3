class_name Projectile
extends Area2D
## 허공을 나는 것 (화살·총알·표창·산탄·던진 단검·폭탄 등).
##
## 서버만 이동과 판정을 하고, 클라이언트는 동기화된 위치를 그린다.
## 상대 무기에 막히지 않는다 — 회피로만 피한다.
##
## 스폰·디스폰은 main.gd의 ProjectileSpawner(MultiplayerSpawner)가 맡는다.
## 서버에서 queue_free()하면 클라이언트에서도 함께 사라진다.

## 서버가 이 투사체를 없애야 할 때 알린다.
signal finished(projectile: Node)
## 바닥에 남은 것(단검)을 주인이 주웠다.
signal picked_up(peer_id: int, projectile: Node)

## 허공을 나는 것은 공유 무적을 타지 않는다. 항상 "projectile" 이다.
const SOURCE := "projectile"
## 단검을 주울 수 있는 거리. 젤리 몸통(48px)에 닿으면 줍는 셈이다.
const PICKUP_RANGE := 48.0
## 중력을 받는 것(표창·폭탄·떨어진 단검)에 적용할 가속도.
const GRAVITY := 980.0

## 바닥에 닿은 뒤 굴러가기 시작하는 속도(px/s) — `on_solid = "roll"` (#131).
const ROLL_SPEED := 300.0
## 구르면서 받는 감속(px/s^2). 굴러가는 거리는 이 둘이 정한다:
## 거리 = ROLL_SPEED^2 / (2 * ROLL_FRICTION) = 60px. 젤리 몸통(48px) 하나 조금 넘는다.
const ROLL_FRICTION := 750.0
## 무기 그림으로 그릴 때 날 끝에서 손잡이 끝까지의 길이(px). 젤리 몸통(48px)보다 조금 짧다.
const ART_LENGTH := 40.0

# ─────────────────────── 미사일 불꽃 꼬리 (대포 총 특수, #121) ───────────────────────
## 불꽃 꼬리의 전체 길이(px). `size_scale`이 곱해진다. 젤리 몸통(72px)의 두 배 가까이 되어야
## 날아가는 동안 "긴 꼬리"로 읽힌다 — 짧으면 그냥 밝은 점으로 보인다.
const FLAME_LENGTH := 132.0
## 불꽃이 가장 불룩한 곳의 반폭(px).
const FLAME_HALF_WIDTH := 20.0
## 불꽃이 가장 굵어지는 지점(0~1). 머리에서 조금 뒤에서 부풀었다가 꼬리로 뾰족해진다.
const FLAME_BELLY := 0.16
## 머리 쪽(t=0) 폭의 비율. 0이면 한 점에서 시작해 불꽃이 끊겨 보인다.
const FLAME_ROOT_RATIO := 0.30
## 꼬리 윤곽을 몇 조각으로 나눠 그릴지. 클수록 매끄럽다.
const FLAME_SEGMENTS := 16
## 미사일 머리의 빛무리 반지름(px).
const HEAD_RADIUS := 13.0
## 꼬리 안에서 흐르는 가는 불꽃 가닥 수.
const WISP_COUNT := 6
## 불꽃이 떠는 속도(라디안/초). 빠를수록 타오르는 느낌이 난다.
const FLAME_FLICKER_RATE := 24.0

## 가운데는 하얗고 바깥으로 갈수록 푸르다.
const FLAME_CORE := Color(1.0, 1.0, 1.0)
const FLAME_MID := Color(0.72, 0.94, 1.0)
const FLAME_EDGE := Color(0.25, 0.60, 1.0)

# ─────────────────────────── 결정질 화살 (활, #125) ───────────────────────────
## 화살 전체 길이(px). 길쭉해야 "결정 창"으로 읽힌다 — 짧으면 마름모 덩어리가 된다.
const ARROW_LENGTH := 60.0
## 가장 넓은 곳의 반폭(px). 길이의 1/8쯤이라 날렵하다.
const ARROW_HALF_WIDTH := 7.5
## 앞에서부터 이 비율 되는 곳이 가장 넓다(어깨). 여기서 뒤로는 한 점으로 좁아진다.
const ARROW_SHOULDER_RATIO := 0.34
## 어깨 뒤 이 비율 되는 곳에 곁가지 결정이 붙는다.
const ARROW_SHARD_RATIO := 0.62
## 뒤에 남는 짧은 빛 자락의 길이(px). 미사일 꼬리보다 훨씬 짧다 — 화살이지 로켓이 아니다.
const ARROW_TRAIL_LENGTH := 52.0

## 결정 색. 가운데가 희고 가장자리가 짙푸르다.
const ARROW_CORE := Color(1.0, 1.0, 1.0)
const ARROW_MID := Color(0.55, 0.88, 1.0)
const ARROW_EDGE := Color(0.20, 0.45, 0.95)

## 쏜 플레이어의 peer id. 자기 자신은 맞지 않는다.
var shooter_peer := 0
var damage := 0.0
var knockback := Combat.Knockback.WEAK
var stun := 0.0
## 상대를 관통해서 계속 날아가는가 (활 특수).
var pierce_targets := false
var use_gravity := false
## 벽·바닥에 닿았을 때 — "vanish" 사라짐 / "stay" 남음 / "return" 즉시 회수.
var on_solid := "vanish"
## 거리에 따라 데미지가 줄어드는 무기(샷건)용. 0 이면 감소 없음.
var falloff_min_damage := 0.0
var falloff_distance := 0.0
## 이 peer의 젤리를 자동으로 따라간다 (단검). 0 이면 직선.
var homing_peer := 0
## 이 시간이 지나면 스스로 터진다 (폭탄). 0 이면 안 터진다.
var fuse := 0.0
## 터질 때 이 반경 안을 때린다 (폭탄). 0 이면 단발 명중.
var explosion_radius := 0.0
## 바닥에 남았을 때 이 peer의 주인이 주울 수 있다 (단검).
var pickup_owner := 0
## 이 무기의 그림으로 그린다 (단검). 비어 있거나 그림이 없는 무기면 노란 막대로 그린다.
var art_weapon: String = ""
## 이 **파일**의 그림으로 그린다 (폭탄). `art_weapon`보다 우선한다 —
## 무기 하나에 그림이 둘일 때(일반/강화 폭탄) 이름만으로는 고를 수 없다 (#131).
var art_file: String = ""
## 그림을 진행 방향으로 돌리지 않는다 (폭탄). 돌리면 도화선이 앞을 향한다 (#131).
var art_upright := false
## 탄 크기 배율 (대포 총). 1.0 이면 씬에 잡아 둔 기본 크기다.
var size_scale := 1.0
## 푸른 불꽃 꼬리를 단 미사일로 그린다 (대포 총 특수, #121).
var missile := false
## 푸른 결정질 화살로 그린다 (활, #125).
var arrow := false
## 0보다 크면 넉백 단계 대신 이 속도로 민다 (대포 총 미사일, #121).
var knockback_speed := 0.0

var velocity := Vector2.ZERO

var _spawn_time := 0.0
var _landed := false
var _origin := Vector2.ZERO
var _hit_peers := {}
var _done := false
var _has_art := false
var _last_position := Vector2.ZERO
## 불꽃을 그릴 진행 방향(단위 벡터). 꼬리는 이 반대쪽으로 뻗는다.
var _draw_dir := Vector2.RIGHT
var _flame_time := 0.0
var _wisps: Array[Dictionary] = []

@onready var visual: ColorRect = $Visual
@onready var art_sprite: Sprite2D = $ArtSprite
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


## 모든 피어에서 스폰 데이터로 호출된다 (add_child 전).
func setup(data: Dictionary) -> void:
	shooter_peer = data["shooter_peer"]
	damage = data["damage"]
	knockback = data["knockback"]
	stun = data.get("stun", 0.0)
	pierce_targets = data.get("pierce_targets", false)
	use_gravity = data.get("use_gravity", false)
	on_solid = data.get("on_solid", "vanish")
	falloff_min_damage = data.get("falloff_min_damage", 0.0)
	falloff_distance = data.get("falloff_distance", 0.0)
	homing_peer = data.get("homing_peer", 0)
	fuse = data.get("fuse", 0.0)
	explosion_radius = data.get("explosion_radius", 0.0)
	pickup_owner = data.get("pickup_owner", 0)
	art_weapon = data.get("art", "")
	art_file = data.get("art_file", "")
	art_upright = data.get("art_upright", false)
	size_scale = data.get("size_scale", 1.0)
	missile = data.get("missile", false)
	arrow = data.get("arrow", false)
	knockback_speed = data.get("knockback_speed", 0.0)
	velocity = data["velocity"]
	position = data["position"]
	_origin = position


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_spawn_time = _now()
	_last_position = position
	_apply_art()
	_apply_size()
	if missile or arrow:
		_setup_drawn()
		return
	if _has_art:
		_face(velocity)
	elif velocity.x < 0.0:
		visual.position.x = -visual.size.x


## 무기 그림을 붙인다. 그림이 없으면 지금까지의 노란 막대를 그대로 쓴다.
##
## 원화는 정사각 캔버스에 투명 여백을 두고 그려져 있어 파일 크기를 그대로 쓰면 그림이
## 한쪽으로 쏠린다. 캐릭터·무기와 같이 `Art.content_rect()`로 여백을 뺀 영역을 기준으로 잡되,
## 여기서는 회전을 하므로 위치가 아니라 `Sprite2D.offset`(회전과 함께 도는 값)으로 보정한다.
func _apply_art() -> void:
	# 파일 지정이 무기 이름보다 우선한다 (일반/강화 폭탄).
	var texture: Texture2D = null
	if not art_file.is_empty():
		texture = Weapons.texture_file(art_file)
	elif not art_weapon.is_empty():
		texture = Weapons.texture(art_weapon)
	if texture == null:
		return
	var content := Art.content_rect(texture)
	if content.size.y <= 0.0:
		return
	var texture_size := Vector2(texture.get_size())
	art_sprite.texture = texture
	art_sprite.offset = texture_size * 0.5 - content.position - content.size * 0.5
	art_sprite.scale = Vector2.ONE * (ART_LENGTH / content.size.y)
	_has_art = true
	visual.hide()
	art_sprite.show()


## 탄 크기를 배율만큼 키운다 (대포 총, #118).
##
## **그림과 판정을 함께** 키워야 보이는 크기와 실제로 맞는 범위가 어긋나지 않는다.
##
## 충돌 상자(RectangleShape2D)는 씬의 sub_resource라 **모든 투사체가 같은 자원을 공유한다** —
## `shape.size`를 직접 고치면 대포 총 탄 하나 때문에 활·샷건 탄까지 같이 커지고,
## 그 무기로 갈아타도 크기가 돌아오지 않는다. 그래서 모양이 아니라 노드의 `scale`을 바꾼다.
func _apply_size() -> void:
	if is_equal_approx(size_scale, 1.0):
		return
	collision_shape.scale = Vector2.ONE * size_scale
	if _has_art:
		art_sprite.scale *= size_scale
		return
	# 노란 막대는 세로 가운데가 원점이라, 키운 뒤 다시 가운데로 맞춰야 한다.
	visual.size *= size_scale
	visual.position.y = -visual.size.y * 0.5


## 그림 방향 맞추기. 원화는 날 끝이 위를 향하므로 진행 방향으로 90도 더 돌린다.
func _face(direction: Vector2) -> void:
	if art_upright:
		return   # 폭탄 — 돌리면 도화선이 앞을 향한다 (#131)
	if direction.length_squared() < 0.01:
		return   # 멈춰 있으면 마지막 방향 그대로 (바닥에 꽂힌 단검)
	art_sprite.rotation = direction.angle() + PI * 0.5


## 그리기는 모든 피어가 한다. 클라이언트는 속도를 받지 않으므로 복제된 위치의
## 변화로 진행 방향을 잡는다 — 유도(단검)로 방향이 바뀌어도 그림이 따라 돈다.
func _process(delta: float) -> void:
	if not _has_art and not missile:
		return
	var moved := position - _last_position
	_last_position = position
	if _has_art:
		_face(moved)
	if missile or arrow:
		# 유도(단검)나 포물선(활)처럼 방향이 바뀌는 것에도 그림이 따라 돌도록
		# 위치 변화로 진행 방향을 잡는다. 화살촉이 궤도를 따라 기울어진다.
		if moved.length_squared() >= 0.01:
			_draw_dir = moved.normalized()
		_flame_time += delta
		queue_redraw()


## 직접 그리는 탄(미사일·화살) 준비. 노란 막대는 이들이 대신하므로 감춘다.
##
## 불꽃 가닥 모양은 노드 이름(`Projectile_<id>`)으로 씨앗을 잡은 난수라 **양쪽 화면에 같게**
## 뜬다. 이름은 스폰 데이터의 id에서 나오므로 모든 피어에서 같다.
func _setup_drawn() -> void:
	visual.hide()
	if velocity.length_squared() >= 0.01:
		_draw_dir = velocity.normalized()
	if not missile:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	for i in WISP_COUNT:
		_wisps.append({
			# 본줄기 안에서 흐르게 각을 좁게 잡는다 — 넓으면 옆으로 삐친 선으로 보인다.
			"angle": rng.randf_range(-0.16, 0.16),
			"length": rng.randf_range(0.62, 1.05),
			"width": rng.randf_range(0.10, 0.24),
			"rate": rng.randf_range(11.0, 19.0),
			"phase": rng.randf_range(0.0, TAU),
		})


## 미사일과 푸른 불꽃 꼬리 (#121).
##
## 그림 파일 없이 `_draw()`로만 그린다 — 씬 루트에 걸린 가산 혼합 덕에 겹칠수록 하얗게
## 타오르고, 그 혼합은 **이 그리기에만** 적용되어 자식(`Visual`·`ArtSprite`)에는 영향이 없다.
##
## **노드를 회전시키지 않고** 방향 벡터로 직접 그린다. 루트를 돌리면 `CollisionShape2D`까지
## 같이 돌아 판정이 달라진다 — 연출 때문에 맞는 범위가 변하면 안 된다.
func _draw() -> void:
	if arrow:
		_draw_arrow()
		return
	if not missile:
		return
	var back := -_draw_dir
	var perp := back.orthogonal()
	var flicker := 0.85 + 0.15 * sin(_flame_time * FLAME_FLICKER_RATE)
	var length := FLAME_LENGTH * size_scale * flicker
	var half := FLAME_HALF_WIDTH * size_scale

	# 넓고 푸른 것부터 좁고 흰 것까지 겹쳐 가운데를 하얗게 태운다.
	_draw_plume(back, perp, length, half, FLAME_EDGE, 0.50)
	_draw_plume(back, perp, length * 0.78, half * 0.60, FLAME_MID, 0.60)
	_draw_plume(back, perp, length * 0.50, half * 0.32, FLAME_CORE, 0.90)

	# 꼬리 안에서 흐르는 가는 가닥. 본줄기 위에 얹어 결을 만든다.
	for wisp: Dictionary in _wisps:
		var rate: float = wisp["rate"]
		var phase: float = wisp["phase"]
		var angle: float = wisp["angle"]
		var wisp_length: float = wisp["length"]
		var wisp_width: float = wisp["width"]
		var dir := back.rotated(angle + sin(_flame_time * rate + phase) * 0.05)
		_draw_plume(dir, dir.orthogonal(), length * wisp_length, half * wisp_width,
			FLAME_CORE, 0.22)

	# 머리 — 불꽃이 뿜어져 나오는 밝은 덩어리.
	Art.draw_glow(self, Vector2.ZERO, HEAD_RADIUS * size_scale * 1.7, FLAME_EDGE, 0.50)
	Art.draw_glow(self, Vector2.ZERO, HEAD_RADIUS * size_scale, FLAME_MID, 0.70)
	Art.draw_glow(self, Vector2.ZERO, HEAD_RADIUS * size_scale * 0.45, FLAME_CORE, 1.0)


## 불꽃 덩어리 하나. 머리 뒤에서 불룩해졌다가 꼬리로 갈수록 뾰족해지며 투명해진다.
##
## 사다리꼴 하나로 그리면 옆선이 곧아서 "막대"로 보인다. 윤곽을 여러 조각으로 나눠
## 폭과 옅기를 따로 주면 덩어리진 불꽃이 된다.
func _draw_plume(back: Vector2, perp: Vector2, length: float, half: float,
		color: Color, alpha: float) -> void:
	if length <= 0.0 or half <= 0.0:
		return
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	# 한쪽 윤곽을 머리에서 꼬리로 훑고,
	for i in FLAME_SEGMENTS + 1:
		var t := float(i) / float(FLAME_SEGMENTS)
		points.append(back * (length * t) + perp * (half * _plume_width(t)))
		colors.append(Color(color, alpha * _plume_alpha(t)))
	# 반대쪽 윤곽을 꼬리에서 머리로 되짚어 하나의 폴리곤으로 닫는다.
	for i in range(FLAME_SEGMENTS, -1, -1):
		var t := float(i) / float(FLAME_SEGMENTS)
		points.append(back * (length * t) - perp * (half * _plume_width(t)))
		colors.append(Color(color, alpha * _plume_alpha(t)))
	draw_polygon(points, colors)


## 꼬리 위치별 폭(0~1). FLAME_BELLY에서 가장 굵고 꼬리 끝에서 0이 된다.
func _plume_width(t: float) -> float:
	var rise := clampf(t / FLAME_BELLY, 0.0, 1.0)
	var fall := clampf((1.0 - t) / (1.0 - FLAME_BELLY), 0.0, 1.0)
	var swell := FLAME_ROOT_RATIO + (1.0 - FLAME_ROOT_RATIO) * pow(rise, 0.6)
	return swell * pow(fall, 0.85)


## 꼬리 위치별 옅기(0~1). 머리 쪽이 진하고 꼬리로 갈수록 사라진다.
func _plume_alpha(t: float) -> float:
	return pow(1.0 - t, 1.35)


## 결정질 화살 (#125).
##
## 미사일과 같은 규칙이다 — 그림 파일 없이 `_draw()`로만 그리고, **노드를 회전시키지 않는다**
## (루트를 돌리면 `CollisionShape2D`까지 돌아 판정이 달라진다).
## 진행 방향은 위치 변화로 잡으므로 **포물선을 따라 화살촉이 기울어진다.**
##
## 같은 윤곽을 크기만 줄여 세 번 겹친다. 가산 혼합이라 겹칠수록 밝아져서
## 가장자리는 짙푸르고 가운데는 흰 결정처럼 보인다.
func _draw_arrow() -> void:
	var forward := _draw_dir
	var perp := forward.orthogonal()
	# 뒤로 남는 짧은 빛 자락. 화살이 지나온 길을 알려 주되 로켓처럼 길면 안 된다.
	_draw_plume(-forward, perp, ARROW_TRAIL_LENGTH * size_scale,
		ARROW_HALF_WIDTH * size_scale * 0.7, ARROW_EDGE, 0.30)
	Art.draw_glow(self, Vector2.ZERO, ARROW_LENGTH * size_scale * 0.38, ARROW_EDGE, 0.35)
	# 겹칠 때 **폭을 길이보다 많이** 줄인다. 그래야 흰 심이 길이를 따라 남아
	# 가운데가 하얗게 빛나는 결정이 된다 — 둘 다 줄이면 심이 작은 덩어리가 된다.
	_draw_arrow_body(forward, perp, size_scale, size_scale, ARROW_EDGE, 0.55)
	_draw_arrow_body(forward, perp, size_scale * 0.88, size_scale * 0.58, ARROW_MID, 0.75)
	_draw_arrow_body(forward, perp, size_scale * 0.72, size_scale * 0.28, ARROW_CORE, 0.95)


## 화살 윤곽 한 겹 — 앞이 뾰족하고 어깨에서 가장 넓다가 **뒤로도 한 점으로** 좁아지는
## 결정 창. 뒤를 뭉툭하게 두거나 날개를 달면 촉이 둘 달린 것처럼 보인다.
func _draw_arrow_body(forward: Vector2, perp: Vector2,
		length_scale: float, width_scale: float, color: Color, alpha: float) -> void:
	var half_length := ARROW_LENGTH * 0.5 * length_scale
	var half_width := ARROW_HALF_WIDTH * width_scale
	var tip := forward * half_length
	var tail := -forward * half_length
	var shoulder := forward * (half_length - ARROW_LENGTH * ARROW_SHOULDER_RATIO * length_scale)
	var tint := Color(color, alpha)

	# 본체 — 앞뒤로 뾰족한 연꼴
	draw_polygon(
		PackedVector2Array([
			tip,
			shoulder + perp * half_width,
			tail,
			shoulder - perp * half_width,
		]),
		PackedColorArray([tint, tint, tint, tint]))

	# 곁가지 결정 — 몸통 뒤쪽에서 바깥·뒤로 삐져나온 얇은 조각
	var shard := forward * (half_length - ARROW_LENGTH * ARROW_SHARD_RATIO * length_scale)
	var out := perp * half_width * 1.8
	var back := forward * half_width * 1.6
	draw_polygon(
		PackedVector2Array([shard, shard + out - back, shard - back * 0.7]),
		PackedColorArray([tint, tint, tint]))
	draw_polygon(
		PackedVector2Array([shard, shard - out - back, shard - back * 0.7]),
		PackedColorArray([tint, tint, tint]))


func _physics_process(delta: float) -> void:
	# 이동은 서버만 계산한다. 클라이언트는 동기화된 위치를 받는다.
	if not multiplayer.is_server() or _done:
		return

	# 도화선 (폭탄) — 바닥에 놓여 있어도 시간이 되면 터진다.
	if fuse > 0.0 and _now() - _spawn_time >= fuse:
		_explode()
		return

	# 바닥에 닿은 뒤 굴러가는 것 (폭탄) — 감속해서 스스로 멈춘다.
	if _landed and on_solid == "roll" and not is_zero_approx(velocity.x):
		var speed := maxf(absf(velocity.x) - ROLL_FRICTION * delta, 0.0)
		velocity.x = signf(velocity.x) * speed
		position += velocity * delta

	# 바닥에 남은 것은 주인이 다가오면 회수된다 (단검).
	if _landed:
		if pickup_owner != 0:
			var owner_jelly := _find_jelly(pickup_owner)
			if owner_jelly != null and position.distance_to(owner_jelly.global_position) <= PICKUP_RANGE:
				_done = true
				picked_up.emit(pickup_owner, self)
		return

	# 유도 (단검) — 상대를 향해 방향을 계속 고친다.
	if homing_peer != 0:
		var target := _find_jelly(homing_peer)
		if target != null:
			velocity = (target.global_position - position).normalized() * Combat.PROJECTILE_SPEED

	if use_gravity:
		velocity.y += GRAVITY * delta
	position += velocity * delta

	# 맵에서 완전히 벗어나면 정리한다.
	var screen := get_viewport_rect().size
	if Combat.is_out_of_bounds(position, screen) or position.y < -Combat.FALL_MARGIN_SIDE:
		_finish()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _find_jelly(peer_id: int) -> Node:
	for jelly: Node in get_tree().get_nodes_in_group("jellies"):
		if jelly.owner_peer_id == peer_id:
			return jelly
	return null


## 폭탄 — 반경 안의 상대를 때리고 사라진다.
func _explode() -> void:
	if _done:
		return
	for jelly: Node in get_tree().get_nodes_in_group("jellies"):
		if jelly.owner_peer_id == shooter_peer or not jelly.alive:
			continue
		if position.distance_to(jelly.global_position) <= explosion_radius:
			jelly.server_apply_hit(damage, knockback, position.x, stun, SOURCE, knockback_speed)
	_finish()


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server() or _done:
		return

	if body is Player:
		var peer_id: int = body.owner_peer_id
		if peer_id == shooter_peer or _hit_peers.has(peer_id) or not body.alive:
			return
		# 폭탄은 닿으면 터진다 (문서: "피격하거나 일정 시간이 지나면").
		if explosion_radius > 0.0:
			_explode()
			return
		_hit_peers[peer_id] = true
		body.server_apply_hit(_damage_at(position), knockback, _origin.x, stun, SOURCE, knockback_speed)
		# 주울 수 있는 것(단검)은 맞힌 뒤에도 사라지지 않고 바닥으로 떨어진다.
		# 안 그러면 한 번만 쓸 수 있는 무기가 된다.
		if pickup_owner != 0:
			homing_peer = 0
			velocity = Vector2.ZERO
			use_gravity = true
			return
		if not pierce_targets:
			_finish()
		return

	# 벽·바닥·기물
	match on_solid:
		"vanish", "return":
			_finish()
		"stay":
			velocity = Vector2.ZERO
			_landed = true
		"roll":
			# 세로 속도만 죽이고 가로로 조금 굴린다 (#131).
			# **가지고 있던 속도를 넘겨받지 않고 ROLL_SPEED 로 깎는다** — 안 그러면
			# 1120px/s 로 날아온 폭탄이 화면을 가로질러 굴러간다.
			# 발판을 벗어났다 다시 떨어진 경우에는 남은 속도가 더 작으므로 그쪽을 쓴다.
			var keep := minf(absf(velocity.x), ROLL_SPEED)
			velocity = Vector2(signf(velocity.x) * keep, 0.0)
			_landed = true


## 굴러서 발판 끝을 벗어났다 — 다시 떨어진다 (#131).
##
## 이게 없으면 폭탄이 발판 밖 허공을 그대로 굴러간다. 떨어지다 아래 바닥에 닿으면
## `_on_body_entered`가 다시 굴리는데, 그때는 남은 속도가 더 작아 조금만 구른다.
func _on_body_exited(body: Node) -> void:
	if not multiplayer.is_server() or _done or not _landed:
		return
	if on_solid != "roll" or body is Player:
		return
	_landed = false


## 샷건처럼 거리에 따라 데미지가 줄어드는 경우.
func _damage_at(where: Vector2) -> float:
	if falloff_distance <= 0.0:
		return damage
	var traveled: float = _origin.distance_to(where)
	var t: float = clampf(traveled / falloff_distance, 0.0, 1.0)
	return lerpf(damage, falloff_min_damage, t)


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit(self)
