extends Control
## 판이 열리기 전에 세는 `3 · 2 · 1 · START!` (요청).
##
## **판마다 뜬다** — 무기를 고른 직후, 젤리가 자기 자리에 서 있는 채로 얼어 있는 동안이다
## (`main.gd` 의 `_finish_pick_phase` → `_play_countdown`). 경기마다 한 번인 표지 그림
## (`match_intro.gd`)과 달리 여기는 매 판이라 **빠르게 지나가야 한다** — 한 칸이
## `Combat.COUNTDOWN_STEP`(0.42초)이고 넷을 세도 1.7초다.
##
## 그림 파일 없이 `_draw()` 로만 그린다 (`point_gain.gd` 와 같은 방식). 언제 띄울지도,
## 그동안 젤리를 얼려 두는 것도 서버가 정하고 여기서는 보여주는 일만 한다.
##
## **뒤에 막을 깔지 않는다.** 세는 동안 두 사람은 서로의 자리와 손에 든 무기를 봐야 한다 —
## 그것을 보고 첫 움직임을 정하는 시간이라서, 화면을 덮으면 세는 뜻이 절반 없어진다.
## 대신 글자를 크게 하고 굵은 테두리를 둘러 어떤 맵 위에서도 읽히게 한다
## (전투 화면의 `Banner` 라벨이 쓰는 것과 같은 방식이다).

## 한 칸의 길이와 전체 길이. 서버가 이 값만큼 젤리를 얼려 두므로 여기서 따로 정하지 않는다.
const STEP := Combat.COUNTDOWN_STEP
const TOTAL := Combat.COUNTDOWN_TIME

## 칸마다 적을 글자. 마지막 칸만 낱말이라 크기와 색을 따로 잡는다.
const LABELS := ["3", "2", "1", "START!"]

## 글자 중심의 세로 위치(px, 기준 화면 1152×648). 화면 정가운데(324)보다 조금 위다 —
## 젤리는 아래쪽 지형에 서 있으므로 가운데에 두면 글자가 젤리와 겹친다.
const CENTER_Y := 268.0

const NUMBER_SIZE := 180
const START_SIZE := 128
const OUTLINE := 28

## 숫자는 흰 글자에 진한 테두리, `START!` 는 노란 글자에 진한 테두리다 —
## 색이 바뀌는 것 자체가 "이제 움직여도 된다"는 신호가 된다.
const NUMBER_COLOR := Color(1.0, 1.0, 1.0)
const START_COLOR := Color(1.0, 0.86, 0.24)
const OUTLINE_COLOR := Color(0.16, 0.11, 0.22)

## 튀어나오는 데 걸리는 시간(초)과 시작 크기. 한 칸이 짧으므로 이것도 짧아야 한다.
const POP_TIME := 0.13
const SCALE_FROM := 1.75
## 칸의 뒷부분에서 옅어지기 시작하는 지점(칸 길이에 대한 비율).
const FADE_FROM := 0.80

## 글자와 함께 바깥으로 퍼지는 고리. 숫자가 바뀌는 것만으로는 박자가 약하다.
const RING_TIME := 0.26
const RING_RADIUS := 200.0
const RING_SEGMENTS := 40

const FONT := preload("res://resources/display_font.tres")

## 칸이 넘어갔다 — `main.gd` 가 이때 그 칸의 소리를 낸다 (`point_gain.gd` 와 같은 짜임).
## 칸 번호(0=3, 1=2, 2=1, 3=START!)를 실어 보내므로 받는 쪽이 몇 번째인지 따로
## 기억하지 않아도 된다.
signal step_started(step: int)

var _elapsed := -1.0
## 이미 알린 칸. 소리는 칸마다 한 번만 나가야 하는데 `_step()` 은 매 프레임 같은 값을
## 주므로, 이것을 기억해 두지 않으면 한 칸에 소리가 스무 번 넘게 나간다.
var _announced := -1


func _ready() -> void:
	visible = false


## 처음부터 다시 센다. 소리는 `main.gd` 가 `step_started` 를 받아 따로 낸다 —
## 그림 노드가 소리까지 들면 소리만 바꾸고 싶을 때 이 파일을 건드려야 한다.
func play() -> void:
	_elapsed = 0.0
	_announced = -1
	visible = true
	_advance()
	queue_redraw()


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	if _elapsed >= TOTAL:
		_elapsed = -1.0
		_announced = -1
		visible = false
		return
	_advance()
	queue_redraw()


## 칸이 넘어갔으면 한 번 알린다.
func _advance() -> void:
	var step := _step()
	if step != _announced:
		_announced = step
		step_started.emit(step)


## 지금 칸의 번호(0=3, 1=2, 2=1, 3=START!).
func _step() -> int:
	return clampi(int(_elapsed / STEP), 0, LABELS.size() - 1)


## 지금 칸이 시작된 뒤 흐른 시간(초).
func _step_age() -> float:
	return _elapsed - float(_step()) * STEP


func _draw() -> void:
	if _elapsed < 0.0:
		return
	var step := _step()
	var age := _step_age()
	var is_start := step == LABELS.size() - 1

	var alpha := 1.0
	if age > STEP * FADE_FROM:
		alpha = clampf(1.0 - (age - STEP * FADE_FROM) / (STEP * (1.0 - FADE_FROM)), 0.0, 1.0)
	# `START!` 는 끝까지 남는다 — 이 글자가 사라지면서 판이 열리는 것이라야
	# "지금부터"가 글자와 같은 순간이 된다. 숫자는 다음 숫자에 자리를 넘기며 옅어진다.
	if is_start:
		alpha = 1.0

	_draw_ring(age, is_start, alpha)

	# 크게 왔다가 제 크기로 내려앉는다. 앞이 빨라야 친 것으로 보인다(ease-out).
	var pop := clampf(age / POP_TIME, 0.0, 1.0)
	var scale_now := lerpf(SCALE_FROM, 1.0, 1.0 - pow(1.0 - pop, 3.0))
	var size_now := START_SIZE if is_start else NUMBER_SIZE
	var color := START_COLOR if is_start else NUMBER_COLOR

	draw_set_transform(Vector2(size.x * 0.5, CENTER_Y), 0.0, Vector2.ONE * scale_now)
	var text: String = LABELS[step]
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_now).x
	# 밑선을 글자 높이의 절반쯤 내려 잡아 시각적으로 가운데에 온다.
	var at := Vector2(-width * 0.5, size_now * 0.36)
	draw_string_outline(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_now,
			OUTLINE, Color(OUTLINE_COLOR, alpha))
	draw_string(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_now,
			Color(color, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 글자와 함께 한 번 퍼지는 고리. `START!` 에서는 더 크고 굵게 퍼진다.
func _draw_ring(age: float, is_start: bool, alpha: float) -> void:
	var p := clampf(age / RING_TIME, 0.0, 1.0)
	if p >= 1.0:
		return
	var reach := RING_RADIUS * (1.6 if is_start else 1.0)
	var radius := reach * (1.0 - pow(1.0 - p, 2.5))
	var color := START_COLOR if is_start else NUMBER_COLOR
	draw_arc(Vector2(size.x * 0.5, CENTER_Y), radius, 0.0, TAU, RING_SEGMENTS,
			Color(color, 0.55 * (1.0 - p) * alpha), lerpf(10.0, 1.5, p), true)
