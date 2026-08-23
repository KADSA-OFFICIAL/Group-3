extends Node2D
## 양날 도끼가 착지할 때 바닥에 퍼지는 충격파 (#167).
##
## `light_burst.gd`(검)·`lightning_strike.gd`(삼지창)와 같은 규칙이다 — 그림 파일 없이
## `_draw()`로만 그리고, 노드에 가산 혼합이 걸려 있어 겹칠수록 하얘진다.
## **판정과 전혀 얽히지 않는다.** 서버가 착지를 정한 뒤 각 피어가 자기 화면에 띄우고
## (`main.gd`의 `_play_shockwave`), 다 재생하면 스스로 `queue_free()`한다.
##
## **이 연출이 없으면 안 되는 이유**: 착지 범위 데미지는 눈에 보이는 것이 하나도 없다.
## 맞는 쪽은 도끼가 옆에 떨어졌을 뿐인데 체력이 줄어서 왜 맞았는지 알 수 없고, 쓰는 쪽은
## 얼마나 가까이 떨어뜨려야 하는지 알 수 없다. 폭탄 반경을 화면에 그린 이유(#140)와 같다.
##
## 원점은 **떨어진 자리(발밑)**다. 고리는 거기서 좌우로 퍼진다.
## 반경은 `main.gd`가 무기 표의 `landing_radius`를 넘겨 준다 — 보이는 크기와 실제로
## 맞는 범위가 어긋나면 이 연출은 오히려 거짓말이 된다.

## 전체 재생 시간(초). 착지는 순간이라 짧아야 한다.
const DURATION := 0.34
## 고리가 다 퍼지는 데 걸리는 시간. 나머지 시간은 옅어지는 데 쓴다.
const GROW_TIME := 0.18
## 바닥에 누운 타원으로 보이게 하는 세로 눌림.
const SQUASH := 0.34
## 고리 두께(px). 다 퍼졌을 때를 기준으로 하고 옅어지며 같이 얇아진다.
const RING_WIDTH := 9.0
## 고리를 몇 조각으로 나눠 그릴지.
const SEGMENTS := 48
## 고리 안쪽을 채우는 옅은 빛의 진하기.
const FILL_ALPHA := 0.16
## 흙먼지 조각 수와 그 크기(px).
const CHUNK_COUNT := 10
const CHUNK_RADIUS := 7.0
## 조각이 튀어 오르는 높이(px)와 퍼지는 거리 비율.
const CHUNK_RISE := 34.0
const CHUNK_SPREAD := 0.85

## 도끼 날의 붉은색에 맞춘다 — 무엇이 떨어져서 생긴 충격파인지 색으로 읽히게 한다.
const RING_COLOR := Color(1.0, 0.45, 0.32)
const CORE_COLOR := Color(1.0, 0.92, 0.86)

## 퍼질 반경(px). `main.gd`가 무기 표의 `landing_radius`를 그대로 넘긴다.
var radius := 160.0

var _elapsed := 0.0
var _chunks: Array[Dictionary] = []


func _ready() -> void:
	# 흙먼지 모양은 노드 이름으로 씨앗을 잡은 난수라 **양쪽 화면에 같게** 뜬다.
	# 이름은 각 피어가 같은 순서로 붙이므로 같다.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	for i in CHUNK_COUNT:
		_chunks.append({
			"at": rng.randf_range(-1.0, 1.0),
			"rise": rng.randf_range(0.55, 1.0),
			"size": rng.randf_range(0.5, 1.0),
		})


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var grow := clampf(_elapsed / GROW_TIME, 0.0, 1.0)
	# 처음에 빠르고 끝에서 느리게 퍼진다 — 등속으로 퍼지면 밀려나는 힘이 안 느껴진다.
	var spread := 1.0 - pow(1.0 - grow, 2.4)
	var fade := 1.0 - clampf(_elapsed / DURATION, 0.0, 1.0)
	var now_radius := radius * spread
	if now_radius <= 1.0:
		return

	# 안쪽을 옅게 채워 "범위"로 읽히게 한다. 고리만 있으면 선 하나로 보인다.
	_draw_ellipse(now_radius, Color(RING_COLOR, FILL_ALPHA * fade), true, 0.0)
	# 고리 — 바깥 테두리가 곧 맞는 경계다.
	_draw_ellipse(now_radius, Color(RING_COLOR, 0.85 * fade), false, RING_WIDTH * fade)
	_draw_ellipse(now_radius * 0.82, Color(CORE_COLOR, 0.55 * fade), false,
		RING_WIDTH * 0.5 * fade)

	# 흙먼지 — 고리를 따라 좌우로 튀어 오른다. 고리만 있으면 도형처럼 보인다.
	for chunk: Dictionary in _chunks:
		var at: float = chunk["at"]
		var rise: float = chunk["rise"]
		var size: float = chunk["size"]
		var x := now_radius * at * CHUNK_SPREAD
		# 위로 솟았다 내려온다. sin 한 번이면 올라갔다 떨어지는 모양이 나온다.
		var y := -CHUNK_RISE * rise * sin(PI * grow)
		Art.draw_glow(self, Vector2(x, y), CHUNK_RADIUS * size,
			CORE_COLOR, 0.6 * fade)


## 바닥에 누운 타원 하나. `filled`면 채우고, 아니면 `width` 두께의 고리를 그린다.
func _draw_ellipse(ring_radius: float, color: Color, filled: bool, width: float) -> void:
	if filled:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SQUASH))
		draw_circle(Vector2.ZERO, ring_radius, color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if width <= 0.1:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SQUASH))
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, SEGMENTS, color, width, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
