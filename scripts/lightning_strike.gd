extends Node2D
## 삼지창 특수가 명중했을 때 위에서 내려치는 번개.
##
## `light_burst.gd`(검 특수)와 같은 규칙이다 — 그림 파일 없이 `_draw()`로만 그리고,
## 노드에 가산 혼합이 걸려 있어 겹칠수록 하얘진다. **판정과 전혀 얽히지 않는다.**
## 서버가 명중을 정한 뒤 각 피어가 자기 화면에 띄우고(`main.gd`의 `_play_lightning_strike`),
## 다 재생하면 스스로 `queue_free()`한다.
##
## 원점은 **맞은 젤리의 발밑**이다. 번개는 화면 위에서 여기까지 내려온다.
##
## 번개는 한 번 번쩍이는 것이 아니라 **줄기를 갈아 끼우며 몇 번 떤다** — 한 모양으로
## 가만히 있으면 번개가 아니라 분홍색 막대로 보인다.

## 전체 재생 시간(초). 번개는 짧아야 번개로 보인다.
const DURATION := 0.4
## 이 시각부터 사그라들기 시작한다.
const FADE_START := 0.16

## 줄기를 몇 번 갈아 끼울지, 그리고 한 번이 유지되는 시간(초).
const STRIKE_COUNT := 3
const STRIKE_INTERVAL := 0.06

## 줄기가 뻗어 오는 높이(px). 화면 높이(648)보다 커서 위쪽 화면 밖에서 들어온다.
const HEIGHT := 700.0
## 줄기를 몇 도막으로 꺾을지. 적으면 지그재그가 성기고 많으면 지저분해진다.
const SEGMENTS := 14
## 꺾이는 폭(px). 명중 지점으로 갈수록 0에 가까워진다 —
## 끝이 흔들리면 어디를 때린 것인지 흐려진다.
const SPREAD := 46.0

## 줄기 세 겹의 굵기(px). 넓고 옅은 것 위에 좁고 흰 것을 겹쳐 가운데를 태운다.
const WIDTH_EDGE := 22.0
const WIDTH_MID := 11.0
const WIDTH_CORE := 4.0

## 갈라져 나오는 가지 하나의 길이 비율과 꺾이는 폭.
const FORK_RATIO := 0.32
const FORK_SPREAD := 70.0

## 명중 지점의 빛덩이 반지름(px).
const FLASH_RADIUS := 58.0

## 튀는 별 알갱이. 참고 그림에 노란 네 갈래 별이 흩어져 있다.
const STAR_COUNT := 7
const STAR_DISTANCE := 104.0
const STAR_RADIUS := 13.0

## 참고 그림의 자홍색. 가운데는 하얗게 태워서 "번쩍"이 보이게 한다.
const CORE_COLOR := Color(1.0, 1.0, 1.0)
const BOLT_COLOR := Color(1.0, 0.55, 1.0)
const EDGE_COLOR := Color(0.78, 0.16, 0.95)
const STAR_COLOR := Color(1.0, 0.95, 0.62)

var _elapsed := 0.0
## 갈아 끼울 줄기들. 하나마다 {"main": 줄기, "fork": 가지}.
var _strikes: Array[Dictionary] = []
var _stars: Array[Dictionary] = []


func _ready() -> void:
	# 양쪽 화면에 같은 모양이 뜨도록 위치로 씨앗을 잡는다 (`light_burst.gd`와 같은 방식).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position.round()))

	for i in STRIKE_COUNT:
		var bolt := _build_bolt(rng, SPREAD)
		_strikes.append({"main": bolt, "fork": _build_fork(rng, bolt)})

	for i in STAR_COUNT:
		# 명중 지점 주위로 고르게 두른 뒤 조금씩 흔든다.
		var angle := TAU * float(i) / float(STAR_COUNT) + rng.randf_range(-0.2, 0.2)
		_stars.append({
			"dir": Vector2.RIGHT.rotated(angle),
			"distance": STAR_DISTANCE * rng.randf_range(0.5, 1.0),
			"radius": STAR_RADIUS * rng.randf_range(0.55, 1.0),
			"delay": rng.randf_range(0.0, 0.08),
			"spin": rng.randf_range(-0.6, 0.6),
		})


## 위에서 명중 지점까지 내려오는 지그재그 한 줄.
##
## 점 0이 화면 위이고 마지막 점이 원점(명중 지점)이다. 흔들림에 `1.0 - t`를 곱해
## **아래로 갈수록 곧게** 만든다.
func _build_bolt(rng: RandomNumberGenerator, spread: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		points.append(Vector2(rng.randf_range(-spread, spread) * (1.0 - t), -HEIGHT * (1.0 - t)))
	return points


## 줄기 중간에서 갈라져 허공으로 사라지는 가지 하나.
func _build_fork(rng: RandomNumberGenerator, bolt: PackedVector2Array) -> PackedVector2Array:
	var from_index := int(SEGMENTS * rng.randf_range(0.25, 0.55))
	var start: Vector2 = bolt[from_index]
	var away := signf(rng.randf_range(-1.0, 1.0))
	if away == 0.0:
		away = 1.0
	var steps := maxi(int(SEGMENTS * FORK_RATIO), 3)
	var points := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		points.append(start + Vector2(
			away * FORK_SPREAD * t + rng.randf_range(-14.0, 14.0),
			HEIGHT * FORK_RATIO * t * 0.75))
	return points


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
	var strike: Dictionary = _strikes[_strike_index()]
	_draw_bolt(strike["fork"], fade * 0.7, 0.55)
	_draw_bolt(strike["main"], fade, 1.0)
	_draw_flash(fade)
	_draw_stars(fade)


## 전체 밝기. FADE_START까지 그대로 있다가 끝까지 사그라든다.
func _fade() -> float:
	if _elapsed <= FADE_START:
		return 1.0
	return clampf(1.0 - (_elapsed - FADE_START) / (DURATION - FADE_START), 0.0, 1.0)


## 지금 보여줄 줄기. 시간이 지나며 다음 것으로 넘어가 번개가 떠는 것처럼 보인다.
func _strike_index() -> int:
	return mini(int(_elapsed / STRIKE_INTERVAL), STRIKE_COUNT - 1)


## 줄기 한 줄을 세 겹으로 그린다. 가산 혼합이라 겹친 가운데가 하얗게 탄다.
func _draw_bolt(points: PackedVector2Array, fade: float, thickness: float) -> void:
	if points.size() < 2:
		return
	draw_polyline(points, Color(EDGE_COLOR, 0.5 * fade), WIDTH_EDGE * thickness, true)
	draw_polyline(points, Color(BOLT_COLOR, 0.7 * fade), WIDTH_MID * thickness, true)
	draw_polyline(points, Color(CORE_COLOR, 0.95 * fade), WIDTH_CORE * thickness, true)


## 명중 지점의 빛덩이. 사그라들며 조금 넓어진다.
func _draw_flash(fade: float) -> void:
	var swell := 1.0 + 0.5 * (1.0 - fade)
	Art.draw_glow(self, Vector2.ZERO, FLASH_RADIUS * 1.8 * swell, EDGE_COLOR, 0.55 * fade)
	Art.draw_glow(self, Vector2.ZERO, FLASH_RADIUS * swell, BOLT_COLOR, 0.7 * fade)
	Art.draw_glow(self, Vector2.ZERO, FLASH_RADIUS * 0.4 * swell, CORE_COLOR, 0.9 * fade)


## 사방으로 튀는 네 갈래 별.
func _draw_stars(fade: float) -> void:
	for star: Dictionary in _stars:
		var delay: float = star["delay"]
		var age := _elapsed - delay
		if age <= 0.0:
			continue
		# 처음에 확 튀어나가고 끝에서 느려진다.
		var t := clampf(age / (DURATION - delay), 0.0, 1.0)
		var spread := 1.0 - pow(1.0 - t, 3.0)
		var dir: Vector2 = star["dir"]
		var distance: float = star["distance"]
		var radius: float = star["radius"]
		var spin: float = star["spin"]
		var life := (1.0 - t) * fade
		_draw_star(dir * distance * spread, radius * (0.4 + 0.6 * life),
			spin * spread, Color(STAR_COLOR, 0.95 * life))


## 네 갈래 별 하나. 긴 갈래와 짧은 갈래를 번갈아 두른 팔각형이다.
func _draw_star(at: Vector2, radius: float, spin: float, color: Color) -> void:
	if radius <= 0.0:
		return
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for i in 8:
		var angle := TAU * float(i) / 8.0 - PI * 0.5 + spin
		var reach := radius if i % 2 == 0 else radius * 0.3
		points.append(at + Vector2(cos(angle), sin(angle)) * reach)
		colors.append(color)
	draw_polygon(points, colors)
