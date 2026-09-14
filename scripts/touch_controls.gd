extends Control
## 화면 터치 조작물 전체 (#322). 조이스틱 2개 + 궁극기 버튼 2개를 담고,
## **손가락을 번호별로 갈라 나눠 주는 일**을 한다.
##
## ## 왜 여기서 한꺼번에 받나
##
## 두 사람이 한 화면을 잡는 게임이라 **동시에 눌리는 것이 정상**이다. 그런데 Godot 의
## `Button`·`_gui_input` 은 마우스 에뮬레이션으로 올라오는 **손가락 하나만** 받는다 —
## 조작물마다 따로 받게 두면 두 번째 손가락이 통째로 없는 것이 되어, 한쪽이 미는 동안
## 다른 쪽이 굳는다. `InputEventScreenTouch.index`(손가락 번호)를 볼 수 있는 곳은
## `_input()` 하나뿐이라, 받는 곳을 여기 하나로 모으고 조작물에는 나눠만 준다.
##
## ## 마우스도 같이 받는다
##
## PC 에서 F5 로 확인할 길을 없애지 않기 위해서다. 기기에서는 손가락 하나가 터치와
## 에뮬레이션된 마우스로 **두 번** 올라오지만, 둘 다 같은 조작물로 가고 조작물의
## `press()` 는 같은 상태를 다시 넣는 것이라 겹쳐도 탈이 없다.

## 마우스를 손가락 번호로 취급할 때 쓰는 값. 실제 손가락 번호는 0 이상이라 겹치지 않는다.
const MOUSE_FINGER := -1

## 전체 화면을 덮는 화면들. 하나라도 떠 있으면 조작물은 접힌다 —
## 무기 카드는 직접 터치해야 하고, 그 위에 조이스틱이 떠 있으면 카드를 가린다.
## 결과 화면·경기 표지도 화면을 통째로 가져가는 것이라 같이 넣는다.
##
## **목록으로 둔 이유**는 덮는 화면이 더 생겨도 씬에서 한 줄 더하면 끝나게 하기 위해서다 —
## 이름을 코드에 박으면 연출이 늘 때마다 이 파일을 고쳐야 한다.
@export var covers: Array[NodePath] = []

@onready var _pads: Array[Control] = [
	$P1Stick, $P1Skill, $P2Stick, $P2Skill,
]

## 플레이어 번호 → 그 사람의 궁극기 버튼 (#334). 쿨타임을 넘겨줄 곳을 바로 찾는다 —
## `_pads` 를 훑어 `player_id` 를 보는 것보다 씬 구조가 그대로 드러난다.
@onready var _skills := {1: $P1Skill, 2: $P2Skill}

## 손가락 번호 → 그 손가락이 잡고 있는 조작물.
var _fingers := {}


func _ready() -> void:
	for path in covers:
		var overlay := get_node_or_null(path)
		if overlay != null:
			overlay.visibility_changed.connect(_refresh)
	_refresh()


## 덮는 화면이 떠 있으면 접는다. **접을 때 잡고 있던 것을 놓아야 한다** —
## 안 놓으면 밀던 방향이 눌린 채로 남아 무기를 고르는 동안 젤리가 계속 달린다.
func _refresh() -> void:
	var blocked := false
	for path in covers:
		var overlay := get_node_or_null(path)
		if overlay != null and overlay.visible:
			blocked = true
	if visible == (not blocked):
		return
	visible = not blocked
	if blocked:
		_release_everything()


## 궁극기 버튼에 쿨타임을 넘긴다 (#334). `main.gd` 의 `_sync_special_ready()` 가 부른다 —
## 남은 시간을 아는 것은 전투 판정의 주인인 거기이고, 여기는 나눠 주기만 한다
## (손가락을 나눠 주는 것과 같은 자리라 창구를 하나로 둔다).
##
## **접혀 있어도 받아 둔다** — 무기 카드가 떠 있는 동안에도 쿨타임은 흐르므로,
## 다시 펴질 때 이미 맞는 값을 들고 있어야 한 프레임 동안 옛 칸이 보이지 않는다.
func set_cooldown(player_id: int, remaining: float, total: float) -> void:
	var skill: Control = _skills.get(player_id)
	if skill != null:
		skill.set_cooldown(remaining, total)


func _release_everything() -> void:
	_fingers.clear()
	for pad in _pads:
		pad.release_all()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventScreenTouch:
		_handle_press(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_press(MOUSE_FINGER, event.position, event.pressed)
	elif event is InputEventMouseMotion:
		_handle_drag(MOUSE_FINGER, event.position)


func _handle_press(finger: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var pad := _pad_at(pos)
		if pad == null:
			return
		_fingers[finger] = pad
		pad.press(pos)
		get_viewport().set_input_as_handled()
		return

	# 뗀 손가락. 잡고 있던 것이 없으면 남의 화면을 만진 것이라 할 일이 없다.
	if not _fingers.has(finger):
		return
	var held: Control = _fingers[finger]
	_fingers.erase(finger)
	held.release()
	get_viewport().set_input_as_handled()


func _handle_drag(finger: int, pos: Vector2) -> void:
	if not _fingers.has(finger):
		return
	var held: Control = _fingers[finger]
	held.drag(pos)
	get_viewport().set_input_as_handled()


## 이 자리를 맡은 조작물. 조이스틱은 원이지만 **네모 칸 전체**를 받는다 —
## 원 밖을 살짝 짚었다고 안 잡히면 보지 않고 더듬는 손가락이 자꾸 헛짚는다.
func _pad_at(pos: Vector2) -> Control:
	for pad in _pads:
		if pad.get_global_rect().has_point(pos):
			return pad
	return null
