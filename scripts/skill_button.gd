extends Control
## 궁극기(특수 공격) 버튼 하나 (#322).
##
## `virtual_stick.gd` 와 같은 방식이다 — 손가락을 직접 받지 않고 `touch_controls.gd` 가
## 나눠 주며, `Input.parse_input_event()` 로 `p1_skill`·`p2_skill` 을 흉내 낸다.
##
## **누르고 있는 시간이 그대로 유지되어야 한다** — 방패는 짧게/길게를 누른 길이로 가르고
## (`Player._check_long_press()`), 그 길이를 재는 것은 판정 쪽이다. 여기서 눌림을 한 프레임만
## 내보내면 긴 누름이 영영 안 나온다. 그래서 뗄 때까지 눌린 상태로 둔다.
##
## `Button` 을 쓰지 않고 직접 그리는 이유는 멀티터치다 — `Button` 은 마우스 에뮬레이션으로
## 오는 손가락 하나만 받아서, 두 사람이 동시에 누르면 한쪽이 먹힌다.

const RADIUS := 48.0

## 조이스틱과 같은 옅기다. 눌린 동안에만 진해져서 들어간 것이 보인다.
const BASE_COLOR := Color(0.16, 0.14, 0.22, 0.34)
const RIM_COLOR := Color(0.99, 0.95, 0.92, 0.46)
const PRESSED_COLOR := Color(0.8, 0.29, 0.56, 0.78)
const PRESSED_RIM_COLOR := Color(0.99, 0.95, 0.92, 0.86)

@export var player_id: int = 1

var _pressed := false


func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, RADIUS, PRESSED_COLOR if _pressed else BASE_COLOR)
	draw_arc(center, RADIUS, 0.0, TAU, 40,
			PRESSED_RIM_COLOR if _pressed else RIM_COLOR, 3.0, true)


func press(_global_pos: Vector2) -> void:
	_set_pressed(true)


## 손가락이 버튼 밖으로 미끄러져도 놓지 않는다 — 누르고 있는 중에 조금 움직이는 것은
## 흔한 일이고, 그때마다 특수가 끊기면 긴 누름을 유지할 수 없다.
func drag(_global_pos: Vector2) -> void:
	pass


func release() -> void:
	_set_pressed(false)


func release_all() -> void:
	release()


func _set_pressed(down: bool) -> void:
	if _pressed == down:
		return
	_pressed = down
	var ev := InputEventAction.new()
	ev.action = GameState.action(player_id, "skill")
	ev.pressed = down
	ev.strength = 1.0 if down else 0.0
	Input.parse_input_event(ev)
	queue_redraw()
