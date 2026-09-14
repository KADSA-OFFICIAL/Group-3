extends Control
## 가상 조이스틱 하나 — 한 사람 몫의 **이동·점프·급강하**를 전부 맡는다 (#322).
##
## **게임 로직은 이 노드를 모른다.** 손가락 위치를 보고 `Input.parse_input_event()` 로
## `p1_left`·`p2_jump` 같은 **액션을 흉내 내기만** 한다 — 그래서 `Player.read_input()` 도
## `WeaponPick._unhandled_input()` 도 한 줄 고치지 않았고, 키보드도 그대로 동작한다.
## 조작물을 더 만들 일이 생겨도 같은 방식으로 붙이면 된다.
##
## **손가락을 직접 받지 않는다** — 멀티터치는 `touch_controls.gd` 가 손가락 번호별로
## 나눠 주고, 여기는 `press()`·`drag()`·`release()` 세 개만 받는다. 두 사람이 동시에
## 미는 것이 이 게임의 전부라, 손가락 분배를 조작물마다 따로 하면 서로 끊어먹는다.

## 바닥 원의 반지름(px). 노드 크기는 이것의 두 배인 정사각이라 가운데가 곧 `size / 2` 다.
const RADIUS := 72.0
## 손잡이 반지름.
const KNOB_RADIUS := 34.0

## 액션이 나가는 문턱 (반지름에 대한 비율).
##
## **가로는 낮고 세로는 높다** — 걷다가 손가락이 조금 올라갔다고 뛰면 안 되기 때문이다.
## 반대로 좌우는 조금만 밀어도 나가야 걷기 시작이 굼뜨지 않다.
const MOVE_THRESHOLD := 0.32
const JUMP_THRESHOLD := 0.58
const FALL_THRESHOLD := 0.50

## **세기는 늘 1.0 이다 — 아날로그가 아니다.**
## `Player.apply_movement()` 이 `Input.get_axis()` 값을 속도에 그대로 곱하므로, 반쯤 민
## 손가락을 반쯤 걷는 것으로 넘기면 키보드와 이동 속도가 달라진다. 그것은 전투 수치를
## 건드리는 것과 같다 (#322 Non-goal).
const PRESS_STRENGTH := 1.0

## 젤리를 가리지 않을 만큼 옅게, 그러나 어떤 맵 배경 위에서도 보일 만큼 진하게.
## 조작물은 화면 아래를 차지하는데 젤리도 거기 서 있어서, 불투명하게 두면 발이 사라진다.
const BASE_COLOR := Color(0.16, 0.14, 0.22, 0.34)
const RIM_COLOR := Color(0.99, 0.95, 0.92, 0.46)
const KNOB_COLOR := Color(0.99, 0.95, 0.92, 0.72)
const KNOB_ACTIVE_COLOR := Color(0.96, 0.55, 0.78, 0.92)

## 이 조이스틱이 흉내 낼 액션의 주인. 씬에서 정한다 (1P·2P).
@export var player_id: int = 1

## 손잡이가 가운데에서 벗어난 만큼. 길이는 `RADIUS` 를 넘지 않는다.
var _knob := Vector2.ZERO
var _active := false

## 지금 눌린 것으로 쳐 둔 액션들. **바뀌는 순간에만** 이벤트를 내보내기 위해 들고 있다 —
## 매 프레임 다시 내보내면 `is_action_just_pressed()` 가 계속 참이 되어 점프가 연사된다.
var _held := {}


func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, RADIUS, BASE_COLOR)
	draw_arc(center, RADIUS, 0.0, TAU, 48, RIM_COLOR, 3.0, true)
	var knob_color := KNOB_ACTIVE_COLOR if _active else KNOB_COLOR
	draw_circle(center + _knob, KNOB_RADIUS, knob_color)


## 손가락이 내려앉았다. 누른 자리로 손잡이가 곧장 따라간다 —
## 가운데부터 다시 밀게 하면 짧은 화면에서 한 번에 못 민다.
func press(global_pos: Vector2) -> void:
	_active = true
	drag(global_pos)


func drag(global_pos: Vector2) -> void:
	if not _active:
		return
	_knob = (global_pos - (global_position + size * 0.5)).limit_length(RADIUS)
	_apply()
	queue_redraw()


func release() -> void:
	_active = false
	_knob = Vector2.ZERO
	_apply()
	queue_redraw()


## 눌러 둔 것을 전부 놓는다. 조작물이 접힐 때 부르지 않으면 **젤리가 계속 달린다** —
## 무기 선택 카드가 뜨는 순간이 그 자리다.
func release_all() -> void:
	release()


## 손잡이 위치를 액션으로 옮긴다.
func _apply() -> void:
	var v := _knob / RADIUS
	_set_action("left", v.x < -MOVE_THRESHOLD)
	_set_action("right", v.x > MOVE_THRESHOLD)
	_set_action("jump", v.y < -JUMP_THRESHOLD)
	_set_action("fast_fall", v.y > FALL_THRESHOLD)


## 액션 하나의 상태를 맞춘다. **달라졌을 때만** 이벤트를 내보낸다.
func _set_action(suffix: String, down: bool) -> void:
	if bool(_held.get(suffix, false)) == down:
		return
	_held[suffix] = down
	var ev := InputEventAction.new()
	ev.action = GameState.action(player_id, suffix)
	ev.pressed = down
	ev.strength = PRESS_STRENGTH if down else 0.0
	Input.parse_input_event(ev)
