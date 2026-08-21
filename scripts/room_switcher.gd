extends PanelContainer
## 관전자용 방 전환 줄 (이슈 #184). **대기실 화면과 전투 화면이 같은 것을 쓴다.**
##
## 지금 있는 방은 이름으로 적고 나머지 방은 버튼으로 낸다. 누르면 접속을 끊고 같은 주소의
## 다른 포트로 붙은 뒤 대기실로 들어간다 — 방은 포트로만 갈리므로 주소는 그대로다.
##
## **플레이어에게는 보이지 않는다.** 경기 중에 방을 옮기면 하던 판을 버리는 셈이다.
##
## 버튼은 씬에 박아 두지 않고 `Network.ROOMS` 개수만큼 만든다(접속 화면과 같은 방식) —
## 방 목록에 줄을 추가하면 여기도 따라 늘어난다.

## 방 이름 표시 색 (ui_theme.tres 의 진한 라벤더). 관전 표시에 쓰는 색과 같다.
const OBSERVER_COLOR := Color(0.42, 0.45, 0.82)

@onready var row: HBoxContainer = $Row
@onready var current_label: Label = $Row/CurrentLabel
## 씬에 놓인 버튼 1개. 나머지는 이걸 복제해서 만든다.
@onready var button_template: Button = $Row/RoomButton

var _buttons: Array[Button] = []
var _switch_timer: Timer = null
var _switching := false


## 지금 방을 옮기는 중인가. 접속 종료를 함께 듣는 화면(main.gd)이 이 값을 보고 비켜 준다 —
## 두 곳에서 씬을 갈아치우면 어느 쪽이 이길지 알 수 없다.
func is_switching() -> bool:
	return _switching


func _ready() -> void:
	# 관전 빌드가 아니거나 전용 서버면 이 줄 자체가 필요 없다.
	visible = not Network.is_server and Lobby.my_role == Lobby.ROLE_OBSERVER
	if not visible:
		return

	current_label.add_theme_color_override("font_color", OBSERVER_COLOR)
	Network.join_succeeded.connect(_on_joined)
	Network.join_failed.connect(_on_failed)

	# 이 노드에 붙여두면 씬이 바뀔 때 타이머도 같이 사라진다.
	_switch_timer = Timer.new()
	_switch_timer.one_shot = true
	_switch_timer.timeout.connect(_on_timeout)
	add_child(_switch_timer)

	_build_buttons()


## 방 하나당 버튼 하나. 지금 있는 방 버튼은 숨기고 이름표에 적는다.
func _build_buttons() -> void:
	_buttons = [button_template]
	for i in range(1, Network.ROOMS.size()):
		var extra := button_template.duplicate() as Button
		row.add_child(extra)
		_buttons.append(extra)

	for i in _buttons.size():
		var button := _buttons[i]
		var port: int = Network.ROOMS[i]["port"]
		button.text = Network.ROOMS[i]["name"]
		button.visible = port != Network.current_port
		button.pressed.connect(_on_room_pressed.bind(i))

	current_label.text = "관전: %s" % Network.room_name_for(Network.current_port)


func _on_room_pressed(index: int) -> void:
	if _switching:
		return
	var port: int = Network.ROOMS[index]["port"]
	_switching = true
	_set_buttons_enabled(false)
	current_label.text = "%s 로 이동 중..." % Network.ROOMS[index]["name"]

	if Network.switch_room(port) != OK:
		_on_failed("방을 옮기지 못했습니다.")
		return
	# 정원이 찬 방은 ENet 이 조용히 무시한다 — 직접 시간을 재지 않으면 여기서 영원히 멈춘다.
	_switch_timer.start(Network.JOIN_TIMEOUT_SEC)


## 새 방에 붙었다. 대기실로 들어가면 그 화면이 역할을 다시 신고한다
## (경기 중인 방이면 서버가 곧 전투 화면으로 보낸다 — 이슈 #182).
func _on_joined() -> void:
	if not _switching:
		return
	_switching = false
	_switch_timer.stop()
	get_tree().change_scene_to_file("res://scenes/select.tscn")


## 옮기다 실패했다. **먼저 끊은 뒤에 붙는 구조라 원래 방으로 돌아갈 수 없다** —
## 사유를 남기고 타이틀로 보낸다. 멈춘 화면에 그대로 두면 무슨 일인지 알 수 없다.
func _on_failed(reason: String) -> void:
	if not _switching:
		return
	_switching = false
	_switch_timer.stop()
	Network.last_failure = reason
	Network.leave()
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func _on_timeout() -> void:
	_on_failed("방이 꽉 찼거나 그 방 서버가 꺼져 있습니다.")


func _set_buttons_enabled(flag: bool) -> void:
	for button in _buttons:
		button.disabled = not flag
