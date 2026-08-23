extends Node2D
## 빨간 표창의 1P·2P 위치 교환 연출. **두 자리에 각각 하나씩** 뜬다.
##
## `light_burst.gd`(검 특수)와 같은 규칙이다 — 그림 파일 없이 `_draw()`로만 그리고,
## 노드에 가산 혼합이 걸려 있어 겹칠수록 하얘진다. **판정과 전혀 얽히지 않는다.**
## 서버가 교환을 정한 뒤 각 피어가 자기 화면에 띄우고(`main.gd`의 `_play_swap_burst`),
## 다 재생하면 스스로 `queue_free()`한다.
##
## 원점은 **젤리 몸 한가운데**다(발밑이 아니다) — 몸 전체가 사라졌다 나타나는 것이라
## 발밑에서 솟는 검 특수와는 중심이 다르다.
##
## 위치 교환은 화면에서 가장 알아채기 어려운 사건이다(젤리 둘이 그냥 자리를 바꾼다).
## 그래서 **떠난 자리와 도착한 자리 양쪽에** 같은 표시를 띄워, 눈이 둘을 잇게 만든다.

## 전체 재생 시간(초). 위치 교환은 순간에 끝나므로 길게 남으면 지저분하다.
const DURATION := 0.45
## 이 시각부터 사그라들기 시작한다.
const FADE_START := 0.14

## 퍼져 나가는 고리의 처음과 끝 반지름(px). 젤리 몸통(48px)에서 시작해 그 두 배쯤까지 간다.
const RING_START := 12.0
const RING_END := 84.0
const RING_WIDTH := 5.0
const RING_SEGMENTS := 34

## 바깥으로 튀는 알갱이 수와 그 거리·크기.
const SPARK_COUNT := 18
const SPARK_DISTANCE := 96.0
const SPARK_SIZE := 3.4
## 알갱이가 그리는 짧은 꼬리의 길이 배수. 0이면 점으로만 보인다.
const SPARK_TRAIL := 0.22

## 가운데 섬광 반지름(px).
const FLASH_RADIUS := 34.0

## 빨간 표창 그림에 맞춘 붉은색. 가운데는 하얗게 태워서 "번쩍"이 보이게 한다.
const CORE_COLOR := Color(1.0, 0.92, 0.88)
const EDGE_COLOR := Color(0.95, 0.16, 0.12)

var _elapsed := 0.0
var _sparks: Array[Dictionary] = []


func _ready() -> void:
	# 양쪽 화면에 같은 모양이 뜨도록 위치로 씨앗을 잡는다 (`light_burst.gd`와 같은 방식).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position.round()))
	for i in SPARK_COUNT:
		# 고르게 두른 뒤 조금씩 흔든다. 완전 무작위로 뽑으면 한쪽에 뭉친다.
		var angle := TAU * float(i) / float(SPARK_COUNT) + rng.randf_range(-0.12, 0.12)
		_sparks.append({
			"dir": Vector2.RIGHT.rotated(angle),
			"distance": SPARK_DISTANCE * rng.randf_range(0.55, 1.0),
			"size": SPARK_SIZE * rng.randf_range(0.6, 1.0),
			"delay": rng.randf_range(0.0, 0.05),
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
	_draw_flash(fade)
	_draw_ring(fade)
	_draw_sparks(fade)


## 전체 밝기. FADE_START까지 그대로 있다가 끝까지 사그라든다.
func _fade() -> float:
	if _elapsed <= FADE_START:
		return 1.0
	return clampf(1.0 - (_elapsed - FADE_START) / (DURATION - FADE_START), 0.0, 1.0)


## 퍼진 정도(0~1). 처음에 확 튀어나가고 끝에서 느려진다.
func _spread(delay := 0.0) -> float:
	var t := clampf((_elapsed - delay) / DURATION, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


## 가운데 섬광 — 젤리가 사라진/나타난 지점을 짚어 준다.
func _draw_flash(fade: float) -> void:
	# 넓고 옅은 것 위에 좁고 흰 것을 겹쳐 가운데를 하얗게 태운다.
	var shrink := 1.0 - 0.45 * _spread()
	Art.draw_glow(self, Vector2.ZERO, FLASH_RADIUS * 1.9 * shrink, EDGE_COLOR, 0.55 * fade)
	Art.draw_glow(self, Vector2.ZERO, FLASH_RADIUS * shrink, CORE_COLOR, 0.9 * fade)


## 바깥으로 퍼지는 고리. 넓어지면서 얇아지고 옅어진다.
func _draw_ring(fade: float) -> void:
	var spread := _spread()
	var radius := lerpf(RING_START, RING_END, spread)
	var points := PackedVector2Array()
	for i in RING_SEGMENTS + 1:
		var a := TAU * float(i) / float(RING_SEGMENTS)
		points.append(Vector2(cos(a), sin(a)) * radius)
	# 굵은 붉은 고리 위에 가는 흰 고리를 겹친다.
	var width := RING_WIDTH * (1.0 - 0.6 * spread)
	draw_polyline(points, Color(EDGE_COLOR, 0.85 * fade), width, true)
	draw_polyline(points, Color(CORE_COLOR, 0.7 * fade), width * 0.4, true)


## 사방으로 튀는 알갱이. 짧은 꼬리를 달아 "튀어나갔다"가 보이게 한다.
func _draw_sparks(fade: float) -> void:
	for spark: Dictionary in _sparks:
		var delay: float = spark["delay"]
		var spread := _spread(delay)
		if spread <= 0.0:
			continue
		var dir: Vector2 = spark["dir"]
		var distance: float = spark["distance"]
		var size: float = spark["size"]
		var at := dir * distance * spread
		# 멀리 갈수록 작아지고 옅어진다.
		var life := (1.0 - spread) * fade
		var tail := at - dir * distance * SPARK_TRAIL * spread
		draw_line(tail, at, Color(EDGE_COLOR, 0.7 * life), size * 0.8)
		draw_circle(at, size * (0.4 + 0.6 * life), Color(CORE_COLOR, 0.95 * life))
