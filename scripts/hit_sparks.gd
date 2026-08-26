extends Node2D
## 단검에 맞은 자리에 튀는 빨간 알갱이 (#250).
##
## 그림 파일 없이 `_draw()`로만 그린다 — `swap_burst.gd`·`light_burst.gd`와 같은 규칙이다.
## **판정과 전혀 얽히지 않는다.** 서버가 명중을 정한 뒤 각 피어가 자기 화면에 띄우고
## (`main.gd`의 `_play_hit_sparks`), 다 재생하면 스스로 `queue_free()`한다.
##
## **가산 혼합을 쓰지 않는다.** 위치 교환 섬광(`swap_burst`)처럼 크고 하얗게 번쩍이는 것은
## 가산이 어울리지만, 이쪽은 "작은 빨간 알갱이"가 요점이라 밝은 배경(평지 하늘) 위에서
## 하얗게 씻겨 나가면 색이 남지 않는다 (#112). 보통의 알파 혼합이라 잔디 위든 하늘 위든
## 같은 빨강으로 읽힌다 — 그래서 씬에 `CanvasItemMaterial`이 없다.
##
## 원점은 **단검이 닿은 자리**다. 젤리 발밑(번개)이나 몸 한가운데(위치 교환)가 아니라
## 날이 닿은 그 점이어야, 어디서 맞았는지가 화면에 남는다.

## 전체 재생 시간(초). 단검 기본 공격 간격(1초)보다 넉넉히 짧아야 다음 것과 겹치지 않는다.
const DURATION := 0.34

## 알갱이 수와 튀는 거리·크기. **작고 짧게** — 단검 하나에 맞은 것이라
## 위치 교환(18개·96px)처럼 크게 터지면 무엇에 맞았는지가 과장된다.
const SPARK_COUNT := 11
const SPARK_DISTANCE := 34.0
const SPARK_SIZE := 3.2
## 알갱이 뒤에 남는 짧은 꼬리의 길이 배수. 0이면 점으로만 보여 튀는 방향이 안 읽힌다.
const SPARK_TRAIL := 0.3
## 날아가는 동안 아래로 처지는 정도(px). 곧게만 날면 알갱이가 아니라 도형으로 보인다.
const SPARK_DROOP := 22.0

## 가운데 짧은 번쩍임. 알갱이만 있으면 어디서 튀었는지가 약하다.
const FLASH_RADIUS := 11.0
const FLASH_TIME := 0.1

## 가운데 번쩍임과 알갱이의 색.
##
## **둘 다 빨강이다** — 흰빛으로 태우면 밝은 배경(평지 하늘) 위에서 아무것도 안 남는다.
## 큰 섬광은 하얗게 태워도 크기로 읽히지만(`swap_burst`), 3px짜리 점은 색이 대비의 전부다.
const CORE_COLOR := Color(1.0, 0.38, 0.28)
const SPARK_COLOR := Color(0.96, 0.13, 0.10)
## 알갱이 밑에 한 겹 더 깔는 짙은 빨강. 작은 점은 어두운 테두리가 있어야 밝은 배경
## 위에서도 회색 티끌이 아니라 빨강으로 읽힌다.
const SPARK_EDGE := Color(0.52, 0.04, 0.03)
const SPARK_EDGE_GROW := 1.45

var _elapsed := 0.0
var _sparks: Array[Dictionary] = []


func _ready() -> void:
	# 양쪽 화면에 같은 모양이 뜨도록 위치로 씨앗을 잡는다 (`swap_burst.gd`와 같은 방식).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position.round()))
	for i in SPARK_COUNT:
		# 고르게 두른 뒤 조금씩 흔든다. 완전 무작위로 뽑으면 한쪽에 뭉친다.
		var angle := TAU * float(i) / float(SPARK_COUNT) + rng.randf_range(-0.2, 0.2)
		_sparks.append({
			"dir": Vector2.RIGHT.rotated(angle),
			"distance": SPARK_DISTANCE * rng.randf_range(0.45, 1.0),
			"size": SPARK_SIZE * rng.randf_range(0.6, 1.0),
		})


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_elapsed / DURATION, 0.0, 1.0)
	# 튀어 나가는 것은 빠르게 시작해 느려진다. 등속으로 날면 튄 것이 아니라 퍼진 것이 된다.
	var reach := 1.0 - (1.0 - t) * (1.0 - t)
	# **끝에서만 빠르게 사라진다.** 알파를 처음부터 고르게 내리면 3px짜리 점이 반쯤
	# 지난 시점에 이미 안 보여서, 튀는 것이 아니라 스르르 지워지는 것으로 보인다.
	var fade := 1.0 - t * t

	if _elapsed < FLASH_TIME:
		var flash := 1.0 - _elapsed / FLASH_TIME
		Art.draw_glow(self, Vector2.ZERO, FLASH_RADIUS * (0.6 + 0.4 * flash),
			CORE_COLOR, 0.85 * flash, 12)

	for spark in _sparks:
		var dir: Vector2 = spark["dir"]
		var flown: float = float(spark["distance"]) * reach
		var at := dir * flown + Vector2(0.0, SPARK_DROOP * t * t)
		var size := float(spark["size"]) * (0.55 + 0.45 * fade)
		var tail := at - dir * (flown * SPARK_TRAIL)
		draw_line(tail, at, Color(SPARK_EDGE, 0.6 * fade), size * SPARK_EDGE_GROW)
		draw_circle(at, size * SPARK_EDGE_GROW, Color(SPARK_EDGE, 0.75 * fade))
		draw_line(tail, at, Color(SPARK_COLOR, 0.8 * fade), size * 0.85)
		draw_circle(at, size, Color(SPARK_COLOR, fade))
