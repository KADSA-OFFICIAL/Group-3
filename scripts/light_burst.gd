extends Node2D
## 검 특수 공격의 빛기둥 연출.
##
## 그림 파일 없이 `_draw()`로만 그린다 — 배경이 없어서 어떤 맵 위에 얹어도 빛만 남는다.
## 노드에 걸린 CanvasItemMaterial이 가산 혼합(blend_mode = Add)이라 겹칠수록 하얘진다.
##
## **순수 연출이라 판정과 전혀 얽히지 않는다.** 서버가 명중을 정한 뒤 각 피어가 자기 화면에
## 띄우고(`main.gd`의 `_play_light_burst`), 다 재생하면 스스로 `queue_free()`한다.
##
## 원점은 **맞은 젤리의 발밑**이다. 빛기둥은 거기서 위로 솟는다.

## 전체 재생 시간(초). 이 시간이 지나면 스스로 사라진다.
const DURATION := 0.9
## 빛기둥이 다 자라는 데 걸리는 시간. 짧을수록 "확" 솟는다.
const GROW_TIME := 0.16
## 이 시각부터 사라지기 시작한다.
const FADE_START := 0.45

## 부챗살은 촘촘해야 겹치면서 한 덩어리 빛으로 보인다. 성기면 막대 여러 개로 보인다.
const BEAM_COUNT := 26
## 수직에서 좌우로 벌어지는 각도(라디안). 0.68 ≈ 39도.
const FAN_SPREAD := 0.68
## 가운데 빛줄기가 다 자랐을 때 길이(px). 젤리 몸통이 72px이므로 그 4배쯤이다.
const BEAM_LENGTH := 300.0
## 끝으로 갈수록 벌어지는 배수. 밑동은 한 점에 모이고 위에서 퍼진다.
const TIP_FLARE := 3.0
## 빛줄기마다 넓고 옅은 것 위에 이 비율로 좁고 흰 심을 겹쳐 가운데를 하얗게 태운다.
const BEAM_CORE_RATIO := 0.34

const RING_RADIUS := 64.0
## 바닥에 누운 타원으로 보이게 하는 세로 눌림.
const RING_SQUASH := 0.3
const RING_SEGMENTS := 32

const SPARK_COUNT := 16
## 빛무리 하나를 몇 겹으로 쌓을지. 많을수록 감쇠가 매끄럽다.
const GLOW_STEPS := 26

## 가운데는 하얗고 가장자리로 갈수록 푸른 보라로 간다.
const CORE_COLOR := Color(1.0, 1.0, 1.0)
const BEAM_COLOR := Color(0.85, 0.93, 1.0)
const EDGE_COLOR := Color(0.62, 0.55, 1.0)

var _elapsed := 0.0
var _beams: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []


func _ready() -> void:
	# 양쪽 화면에 같은 모양이 뜨도록 위치로 씨앗을 잡는다. 연출이라 판정과는 무관하지만,
	# 같은 장면을 보고 이야기하는 게임이라 서로 다른 모양이 뜨면 헷갈린다.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(global_position.round()))

	for i in BEAM_COUNT:
		var spread := lerpf(-FAN_SPREAD, FAN_SPREAD, float(i) / float(BEAM_COUNT - 1))
		spread += rng.randf_range(-0.06, 0.06)
		var edge := absf(spread) / FAN_SPREAD
		_beams.append({
			"angle": -PI * 0.5 + spread,   # 화면 좌표는 y가 아래라 위가 -90도다
			"width": rng.randf_range(2.0, 5.0),
			# 바깥쪽일수록 짧게 잡아야 부챗살처럼 둥근 윤곽이 나온다.
			"length": BEAM_LENGTH * rng.randf_range(0.62, 1.0) * (1.0 - edge * 0.45),
			"color": CORE_COLOR.lerp(EDGE_COLOR, edge),
			"delay": rng.randf_range(0.0, 0.05),
			"flicker": rng.randf_range(7.0, 13.0),
		})

	for i in SPARK_COUNT:
		_sparks.append({
			"offset": Vector2(rng.randf_range(-46.0, 46.0), rng.randf_range(-8.0, 8.0)),
			"speed": rng.randf_range(120.0, 260.0),
			"size": rng.randf_range(1.5, 3.5),
			"delay": rng.randf_range(0.0, 0.25),
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
	_draw_ground_ring(fade)
	for beam: Dictionary in _beams:
		_draw_beam(beam, fade)
	_draw_core(fade)
	_draw_sparks(fade)


## 전체 밝기. FADE_START까지는 그대로 있다가 끝까지 사그라든다.
func _fade() -> float:
	if _elapsed <= FADE_START:
		return 1.0
	return clampf(1.0 - (_elapsed - FADE_START) / (DURATION - FADE_START), 0.0, 1.0)


## 자라난 정도(0~1). 확 솟았다가 끝에서 잦아든다.
func _grow(delay: float) -> float:
	var t := clampf((_elapsed - delay) / GROW_TIME, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


## 빛줄기 하나. 밑동은 좁고 진하며 끝으로 갈수록 벌어지면서 투명해진다.
func _draw_beam(beam: Dictionary, fade: float) -> void:
	var delay: float = beam["delay"]
	var grow := _grow(delay)
	if grow <= 0.0:
		return

	var full_length: float = beam["length"]
	var half: float = beam["width"] * 0.5
	var angle: float = beam["angle"]
	var flicker_rate: float = beam["flicker"]
	var color: Color = beam["color"]

	var dir := Vector2.RIGHT.rotated(angle)
	var perp := dir.orthogonal()
	var tip := dir * full_length * grow
	# 살아 있는 빛으로 보이게 밝기를 미세하게 떤다.
	var flicker := 0.85 + 0.15 * sin(_elapsed * flicker_rate)

	# 넓고 옅은 색 줄기 위에 좁고 흰 심을 겹친다. 가산 혼합이라 겹친 가운데가 하얗게 탄다.
	_draw_taper(perp, tip, half, color, 0.55 * fade * flicker)
	_draw_taper(perp, tip, half * BEAM_CORE_RATIO, CORE_COLOR, 0.9 * fade * flicker)


## 밑동은 좁고 진하며 끝으로 갈수록 벌어지면서 투명해지는 사다리꼴 하나.
func _draw_taper(perp: Vector2, tip: Vector2, half: float, color: Color, alpha: float) -> void:
	var root_color := Color(color, alpha)
	var tip_color := Color(color, 0.0)
	draw_polygon(
		PackedVector2Array([
			-perp * half,
			perp * half,
			tip + perp * half * TIP_FLARE,
			tip - perp * half * TIP_FLARE,
		]),
		PackedColorArray([root_color, root_color, tip_color, tip_color]))


## 밑동의 밝은 덩어리와 한가운데를 관통하는 흰 기둥.
func _draw_core(fade: float) -> void:
	var grow := _grow(0.0)
	# 넓고 옅은 것부터 좁고 진한 것까지 겹쳐 가운데로 갈수록 하얗게 태운다.
	_draw_glow(104.0 * grow, EDGE_COLOR, 0.5 * fade)
	_draw_glow(40.0 * grow, BEAM_COLOR, 0.7 * fade)
	_draw_glow(14.0 * grow, CORE_COLOR, 1.0 * fade)

	var height := BEAM_LENGTH * 0.88 * grow
	draw_polygon(
		PackedVector2Array([
			Vector2(-9.0, 0.0),
			Vector2(9.0, 0.0),
			Vector2(22.0, -height),
			Vector2(-22.0, -height),
		]),
		PackedColorArray([
			Color(CORE_COLOR, 0.95 * fade),
			Color(CORE_COLOR, 0.95 * fade),
			Color(CORE_COLOR, 0.0),
			Color(CORE_COLOR, 0.0),
		]))


## 가운데가 가장 밝고 가장자리로 갈수록 옅어지는 빛무리.
##
## 원 하나로 그리면 테두리가 딱 끊겨서 어두운 판때기처럼 보인다. 같은 옅기의 원을
## 크기만 줄여 가며 겹쳐 쌓으면 겹친 횟수만큼 밝아져서 가운데가 밝은 감쇠가 나온다.
func _draw_glow(radius: float, color: Color, alpha: float) -> void:
	var step_alpha := alpha / float(GLOW_STEPS)
	for i in range(GLOW_STEPS, 0, -1):
		draw_circle(Vector2.ZERO, radius * float(i) / float(GLOW_STEPS),
			Color(color, step_alpha))


## 바닥에 누운 빛 고리. 사그라들면서 조금 넓어진다.
func _draw_ground_ring(fade: float) -> void:
	var radius := RING_RADIUS * (0.35 + 0.65 * _grow(0.0)) * (1.35 - 0.35 * fade)
	var points := PackedVector2Array()
	for i in RING_SEGMENTS + 1:
		var a := TAU * float(i) / float(RING_SEGMENTS)
		points.append(Vector2(cos(a) * radius, sin(a) * radius * RING_SQUASH))
	draw_polyline(points, Color(BEAM_COLOR, 0.75 * fade), 3.0, true)


## 위로 흩어져 올라가는 작은 빛 알갱이.
func _draw_sparks(fade: float) -> void:
	for spark: Dictionary in _sparks:
		var delay: float = spark["delay"]
		var age := _elapsed - delay
		if age <= 0.0:
			continue
		var speed: float = spark["speed"]
		var size: float = spark["size"]
		var offset: Vector2 = spark["offset"]
		var pos := offset + Vector2(0.0, -speed * age)
		# 높이 올라갈수록 옅어진다.
		var life := clampf(1.0 + pos.y / (BEAM_LENGTH * 1.1), 0.0, 1.0)
		draw_circle(pos, size, Color(CORE_COLOR, life * fade * 0.9))
