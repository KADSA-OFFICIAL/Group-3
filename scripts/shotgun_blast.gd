extends Node2D
## 샷건 특수의 부채꼴 발사 연출.
##
## `light_burst.gd`(검 특수)와 같은 규칙이다 — 그림 파일 없이 `_draw()`로만 그리고,
## 노드에 가산 혼합이 걸려 있어 겹칠수록 하얘진다. **판정과 전혀 얽히지 않는다.**
## 서버가 발사를 정한 뒤 각 피어가 자기 화면에 띄우고(`main.gd`의 `_play_shotgun_blast`),
## 다 재생하면 스스로 `queue_free()`한다.
##
## **그리는 부채꼴은 실제로 맞는 부채꼴과 같아야 한다** (폭탄 반경을 그린 이유 #140과
## 같다). 사거리와 각도를 무기 표에서 그대로 받아 쓰는 것은 그래서다 — 여기서 눈에
## 좋으라고 늘리면 플레이어가 배운 범위가 실제와 어긋난다.
##
## 원점은 **총구**이고 `aim`이 바라보는 쪽(+1 오른쪽 / -1 왼쪽)이다.

## 전체 재생 시간(초). 한 번 뿜고 사라지는 것이라 짧다.
const DURATION := 0.32
## 이 시각부터 사그라들기 시작한다.
const FADE_START := 0.10

## 부채꼴을 채우는 갈래 수. 성기면 부채가 아니라 선 몇 개로 보인다.
const RAY_COUNT := 22
## 갈래 하나가 다 뻗는 데 걸리는 시간(초). 짧을수록 "확" 터진다.
const GROW_TIME := 0.09
## 갈래 뿌리의 폭(px)과 끝으로 갈수록 벌어지는 배수.
const RAY_ROOT_WIDTH := 7.0
const RAY_TIP_FLARE := 2.6

## 총구의 밝은 덩어리 반지름(px).
const MUZZLE_RADIUS := 26.0

## 가운데는 하얗고 바깥으로 갈수록 청록으로 간다 (참고 그림의 색).
const CORE_COLOR := Color(1.0, 1.0, 1.0)
const MID_COLOR := Color(0.62, 0.98, 1.0)
const EDGE_COLOR := Color(0.16, 0.72, 0.95)

## 부모가 **add_child 전에** 넣어 준다. 기본값은 무기 표가 없을 때의 대비값이다.
var aim := 1.0
var reach := 200.0
## 부채꼴 **전체** 각도(도). 절반씩 위아래로 벌어진다.
var spread := 70.0

var _elapsed := 0.0
var _rays: Array[Dictionary] = []


func _ready() -> void:
	# 양쪽 화면에 같은 모양이 뜨도록 위치로 씨앗을 잡는다 (`light_burst.gd`와 같은 방식).
	# **위치는 add_child 전에 들어와 있어야 한다** — `_ready()`는 붙는 순간 돌기 때문에,
	# 나중에 위치를 넣으면 모든 발사가 (0, 0)으로 같은 씨앗을 받는다.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position.round()))
	var half := deg_to_rad(spread) * 0.5
	for i in RAY_COUNT:
		# 부채꼴 안에 고르게 두른 뒤 조금씩 흔든다. 완전 무작위로 뽑으면 한쪽에 뭉친다.
		var t := float(i) / float(RAY_COUNT - 1)
		var angle := lerpf(-half, half, t) + rng.randf_range(-0.03, 0.03)
		# 가장자리 갈래를 짧게 잡아야 부채 끝이 둥글게 마감된다.
		var edge := absf(angle) / maxf(half, 0.001)
		_rays.append({
			"angle": angle,
			"length": reach * rng.randf_range(0.82, 1.0) * (1.0 - edge * 0.22),
			"width": RAY_ROOT_WIDTH * rng.randf_range(0.7, 1.3),
			"color": CORE_COLOR.lerp(EDGE_COLOR, edge),
			"delay": rng.randf_range(0.0, 0.04),
		})


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var fade := _fade()
	if fade <= 0.0:
		return
	for ray: Dictionary in _rays:
		_draw_ray(ray, fade)
	_draw_muzzle(fade)


## 전체 밝기. FADE_START까지 그대로 있다가 끝까지 사그라든다.
func _fade() -> float:
	if _elapsed <= FADE_START:
		return 1.0
	return clampf(1.0 - (_elapsed - FADE_START) / (DURATION - FADE_START), 0.0, 1.0)


## 뻗어 나간 정도(0~1). 확 튀어나가고 끝에서 느려진다.
func _grow(delay: float) -> float:
	var t := clampf((_elapsed - delay) / GROW_TIME, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


## 갈래 하나. 뿌리는 좁고 진하며 끝으로 갈수록 벌어지면서 투명해진다.
func _draw_ray(ray: Dictionary, fade: float) -> void:
	var grow := _grow(ray["delay"])
	if grow <= 0.0:
		return
	var length: float = ray["length"]
	var half_width: float = ray["width"] * 0.5
	var color: Color = ray["color"]
	# 바라보는 쪽을 0도로 두고 위아래로 벌린다.
	var dir := Vector2(aim, 0.0).rotated(float(ray["angle"]))
	var perp := dir.orthogonal()
	var tip := dir * length * grow
	# 넓고 옅은 것 위에 좁고 흰 심을 겹친다. 가산 혼합이라 겹친 가운데가 하얗게 탄다.
	_draw_taper(perp, tip, half_width, color, 0.55 * fade)
	_draw_taper(perp, tip, half_width * 0.38, CORE_COLOR, 0.9 * fade)


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


## 총구에서 터지는 밝은 덩어리. 사그라들며 조금 커진다.
func _draw_muzzle(fade: float) -> void:
	var swell := 0.7 + 0.5 * _grow(0.0)
	Art.draw_glow(self, Vector2.ZERO, MUZZLE_RADIUS * 1.9 * swell, EDGE_COLOR, 0.5 * fade)
	Art.draw_glow(self, Vector2.ZERO, MUZZLE_RADIUS * swell, MID_COLOR, 0.7 * fade)
	Art.draw_glow(self, Vector2.ZERO, MUZZLE_RADIUS * 0.45 * swell, CORE_COLOR, 0.95 * fade)
