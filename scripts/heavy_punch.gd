extends Node2D
## 너클 특수 '강펀치'의 부채꼴 연출 (#225).
##
## `shotgun_blast.gd`와 같은 규칙이다 — 그림 파일 없이 `_draw()`로만 그리고, 노드에
## 가산 혼합이 걸려 있어 겹칠수록 하얘진다. **판정과 전혀 얽히지 않는다.**
## 서버가 발동을 정한 뒤 각 피어가 자기 화면에 띄우고(`main.gd`의 `_play_heavy_punch`),
## 다 재생하면 스스로 `queue_free()`한다.
##
## **그리는 부채꼴은 실제로 맞는 부채꼴과 같다** — 사거리와 각도를 무기 표에서 그대로
## 받는다(샷건과 같은 이유, #140). 눈에 좋으라고 늘리면 배운 범위가 실제와 어긋난다.
##
## **`charged`가 켜지면 디자인이 통째로 달라진다** (게이지 75% 이상). 같은 기술인데
## 색만 바뀌는 것이 아니라 결정 조각과 고리가 더 붙는다 — 게이지를 모아서 쓴 것이
## 화면에서 확실히 달라 보여야 하기 때문이다.
##
## 원점은 **주먹**이고 `aim`이 바라보는 쪽(+1 오른쪽 / -1 왼쪽)이다.

## 전체 재생 시간(초). 충전 상태는 조금 더 길게 남는다.
const DURATION := 0.30
const DURATION_CHARGED := 0.42
## 이 비율을 지나면 사그라들기 시작한다.
const FADE_AT := 0.34

## 부채꼴을 채우는 갈래 수. 샷건(22)보다 적고 굵다 — 산탄이 아니라 주먹이다.
const RAY_COUNT := 11
const RAY_COUNT_CHARGED := 15
## 갈래 하나가 다 뻗는 데 걸리는 시간(초). 짧을수록 "퍽" 들어간다.
const GROW_TIME := 0.07
## 갈래 뿌리의 폭(px)과 끝으로 갈수록 벌어지는 배수. 샷건보다 두껍다.
const RAY_ROOT_WIDTH := 13.0
const RAY_TIP_FLARE := 1.7

## 주먹 자리에서 터지는 덩어리 반지름(px).
const FIST_RADIUS := 30.0

## 충전 상태에서만 날아가는 결정 조각 수와 길이(px).
const SHARD_COUNT := 7
const SHARD_LENGTH := 34.0
const SHARD_WIDTH := 11.0

## 평소 색 — 흰 심 + 호박색. "맨주먹으로 내지른 것"의 색이다.
const CORE := Color(1.0, 1.0, 1.0)
const PLAIN_MID := Color(1.0, 0.86, 0.58)
const PLAIN_EDGE := Color(1.0, 0.55, 0.22)

## 충전 색 — 자홍/보라 + 청록 결정. 참고 스크린샷의 오라와 같은 계열이라
## 오라가 돌던 젤리가 그 색으로 내지르는 것으로 읽힌다.
const CHARGED_MID := Color(0.98, 0.45, 0.95)
const CHARGED_EDGE := Color(0.55, 0.30, 0.95)
const CHARGED_SHARD := Color(0.55, 0.95, 1.0)

## 부모가 **add_child 전에** 넣어 준다. 기본값은 무기 표가 없을 때의 대비값이다.
var aim := 1.0
var reach := 150.0
## 부채꼴 **전체** 각도(도). 절반씩 위아래로 벌어진다.
var spread := 80.0
## 게이지 75% 이상에서 나간 강펀치인가.
var charged := false

var _elapsed := 0.0
var _rays: Array[Dictionary] = []
var _shards: Array[Dictionary] = []


func _ready() -> void:
	# 양쪽 화면에 같은 모양이 뜨도록 위치로 씨앗을 잡는다 (`shotgun_blast.gd`와 같은 방식).
	# **위치는 add_child 전에 들어와 있어야 한다** — `_ready()`는 붙는 순간 돌기 때문이다.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position.round()))
	var half := deg_to_rad(spread) * 0.5
	var count := RAY_COUNT_CHARGED if charged else RAY_COUNT
	var mid := CHARGED_MID if charged else PLAIN_MID
	var edge_color := CHARGED_EDGE if charged else PLAIN_EDGE
	for i in count:
		# 부채꼴 안에 고르게 두른 뒤 조금씩 흔든다. 완전 무작위로 뽑으면 한쪽에 뭉친다.
		var t := float(i) / float(count - 1)
		var angle := lerpf(-half, half, t) + rng.randf_range(-0.04, 0.04)
		var edge := absf(angle) / maxf(half, 0.001)
		_rays.append({
			"angle": angle,
			# **가운데 갈래가 가장 길다.** 판정도 가운데가 가장 세므로(`punch_edge_ratio`)
			# 그림에서도 가운데가 앞으로 튀어나와 있어야 무엇이 센지 읽힌다.
			"length": reach * rng.randf_range(0.88, 1.0) * (1.0 - edge * 0.42),
			"width": RAY_ROOT_WIDTH * rng.randf_range(0.75, 1.25) * (1.0 - edge * 0.3),
			"color": mid.lerp(edge_color, edge),
			"delay": rng.randf_range(0.0, 0.03),
		})
	if not charged:
		return
	for i in SHARD_COUNT:
		var t := float(i) / float(SHARD_COUNT - 1)
		_shards.append({
			"angle": lerpf(-half * 0.85, half * 0.85, t) + rng.randf_range(-0.06, 0.06),
			"distance": reach * rng.randf_range(0.45, 0.95),
			"length": SHARD_LENGTH * rng.randf_range(0.7, 1.35),
			"spin": rng.randf_range(-0.5, 0.5),
			"delay": rng.randf_range(0.0, 0.06),
		})


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration():
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var fade := _fade()
	if fade <= 0.0:
		return
	for ray: Dictionary in _rays:
		_draw_ray(ray, fade)
	_draw_fist(fade)
	# 결정 조각과 고리는 충전 상태에만 붙는다 — 두 디자인을 가르는 것이 이 둘이다.
	for shard: Dictionary in _shards:
		_draw_shard(shard, fade)
	if charged:
		_draw_ring(fade)


func _duration() -> float:
	return DURATION_CHARGED if charged else DURATION


## 전체 밝기. 앞쪽 `FADE_AT`까지 그대로 있다가 끝까지 사그라든다.
func _fade() -> float:
	var span := _duration()
	var hold := span * FADE_AT
	if _elapsed <= hold:
		return 1.0
	return clampf(1.0 - (_elapsed - hold) / (span - hold), 0.0, 1.0)


## 뻗어 나간 정도(0~1). 확 튀어나가고 끝에서 느려진다.
func _grow(delay: float) -> float:
	var t := clampf((_elapsed - delay) / GROW_TIME, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


## 갈래 하나. 뿌리는 좁고 진하며 끝으로 갈수록 벌어지면서 투명해진다.
func _draw_ray(ray: Dictionary, fade: float) -> void:
	var grow := _grow(ray["delay"])
	if grow <= 0.0:
		return
	var half_width: float = ray["width"] * 0.5
	var dir := Vector2(aim, 0.0).rotated(float(ray["angle"]))
	var perp := dir.orthogonal()
	var tip := dir * float(ray["length"]) * grow
	# 넓고 옅은 것 위에 좁고 흰 심을 겹친다. 가산 혼합이라 겹친 가운데가 하얗게 탄다.
	_draw_taper(perp, tip, half_width, ray["color"], 0.6 * fade)
	_draw_taper(perp, tip, half_width * 0.34, CORE, 0.95 * fade)


## 뿌리는 좁고 진하며 끝으로 갈수록 벌어지면서 투명해지는 사다리꼴 하나.
func _draw_taper(perp: Vector2, tip: Vector2, half: float, color: Color, alpha: float) -> void:
	var root := Color(color, alpha)
	var edge := Color(color, 0.0)
	draw_polygon(
		PackedVector2Array([
			-perp * half,
			perp * half,
			tip + perp * half * RAY_TIP_FLARE,
			tip - perp * half * RAY_TIP_FLARE,
		]),
		PackedColorArray([root, root, edge, edge]))


## 주먹 자리에서 터지는 덩어리. 사그라들며 조금 커진다.
func _draw_fist(fade: float) -> void:
	var swell := 0.75 + 0.55 * _grow(0.0)
	var scale := 1.35 if charged else 1.0
	var mid := CHARGED_MID if charged else PLAIN_MID
	var edge := CHARGED_EDGE if charged else PLAIN_EDGE
	Art.draw_glow(self, Vector2.ZERO, FIST_RADIUS * 2.0 * swell * scale, edge, 0.5 * fade)
	Art.draw_glow(self, Vector2.ZERO, FIST_RADIUS * swell * scale, mid, 0.75 * fade)
	Art.draw_glow(self, Vector2.ZERO, FIST_RADIUS * 0.42 * swell * scale, CORE, 0.95 * fade)


## 청록 결정 조각 하나 (충전 전용). 마름모를 앞으로 날려 보낸다.
func _draw_shard(shard: Dictionary, fade: float) -> void:
	var grow := _grow(shard["delay"])
	if grow <= 0.0:
		return
	var dir := Vector2(aim, 0.0).rotated(float(shard["angle"]) + float(shard["spin"]) * grow)
	var perp := dir.orthogonal()
	var center := dir * float(shard["distance"]) * grow
	var half_len := float(shard["length"]) * 0.5
	var half_wide := SHARD_WIDTH * 0.5
	var body := Color(CHARGED_SHARD, 0.85 * fade)
	var tipc := Color(CORE, 0.95 * fade)
	draw_polygon(
		PackedVector2Array([
			center - dir * half_len,
			center + perp * half_wide,
			center + dir * half_len,
			center - perp * half_wide,
		]),
		PackedColorArray([tipc, body, tipc, body]))


## 충전 강펀치가 밀어내는 고리. 부채꼴 끝을 따라 한 바퀴 훑는다.
func _draw_ring(fade: float) -> void:
	var grow := _grow(0.02)
	if grow <= 0.0:
		return
	var half := deg_to_rad(spread) * 0.5
	var facing := 0.0 if aim > 0.0 else PI
	draw_arc(Vector2.ZERO, reach * 0.92 * grow, facing - half, facing + half, 40,
		Color(CHARGED_MID, 0.8 * fade), 5.0, true)
	draw_arc(Vector2.ZERO, reach * 0.72 * grow, facing - half, facing + half, 40,
		Color(CORE, 0.5 * fade), 2.5, true)
