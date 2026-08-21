extends Control
## 타이틀 겸 접속 화면. **방을 고르고** 서버 주소를 입력해 접속한다.
## 헤드리스(서버)로 실행된 경우에는 UI 없이 바로 전투 화면으로 넘어간다.
##
## **역할은 여기서 고르지 않는다**(이슈 #180) — 관전 전용 빌드로 실행하면 관전, 아니면
## 플레이어다. 관전 빌드에서는 이 화면이 그 사실을 보여주기만 한다.
##
## 방 목록은 Network.ROOMS 가 유일한 출처다. 버튼 글자도 거기서 가져온다.

## 접속 대기 한계 시간(초).
## 방이 꽉 차면 ENet 이 조용히 거절해서 connection_failed 조차 오지 않는다.
## 그래서 직접 시간을 재지 않으면 "접속 중..." 에서 영원히 멈춘다.
const JOIN_TIMEOUT_SEC := 8.0

## 관전 빌드 표시 색 (ui_theme.tres 의 진한 라벤더). 크림 배경 위에서 4.2:1 이다.
const OBSERVER_COLOR := Color(0.42, 0.45, 0.82)

@onready var address_edit: LineEdit = $AddressEdit
@onready var status_label: Label = $StatusLabel
@onready var start_button: Button = $StartButton
@onready var sub_label: Label = $SubLabel
@onready var room_box: HBoxContainer = $RoomBox
## 씬에 놓인 방 버튼 1개. 나머지 방 버튼은 이걸 복제해서 만든다.
@onready var room_button_template: Button = $RoomBox/RoomButton

## 방 버튼들 (Network.ROOMS 와 같은 순서). _setup_room_buttons() 에서 채운다.
var room_buttons: Array[Button] = []

## 지금 고른 방 (Network.ROOMS 의 인덱스)
var _room_index := 0
## 접속 시도 중인지. 타임아웃이 지난 뒤에도 이 값이 true 면 실패로 처리한다.
var _joining := false
var _join_timer: Timer = null


func _ready() -> void:
	# 서버는 Network 오토로드에서 이미 시작됐다 — 접속 UI가 필요 없다.
	# _ready() 시점에는 트리가 아직 자식을 붙이는 중이라 씬을 바로 갈아치울 수 없다.
	if Network.is_server:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return

	address_edit.text = Network.DEFAULT_ADDRESS
	status_label.text = ""
	start_button.pressed.connect(_on_start_pressed)
	address_edit.text_submitted.connect(_on_address_submitted)
	Network.join_succeeded.connect(_on_join_succeeded)
	Network.join_failed.connect(_on_join_failed)

	# 이 노드에 붙여두면 씬이 바뀔 때 타이머도 같이 사라진다.
	_join_timer = Timer.new()
	_join_timer.one_shot = true
	_join_timer.timeout.connect(_on_join_timeout)
	add_child(_join_timer)

	_setup_room_buttons()
	_mark_observer_build()


## 관전 빌드임을 화면에 알린다 (이슈 #180).
##
## 실행 파일이 두 개(플레이어·관전)이므로 **어느 쪽을 켰는지 화면에서 알 수 있어야 한다** —
## 겉모습이 똑같으면 관전 기기로 플레이어를 하려다 "자리가 꽉 찼습니다"를 보고 헤맨다.
## 창 제목도 바꿔서 작업 표시줄에서 구분되게 한다.
func _mark_observer_build() -> void:
	if Lobby.my_role != Lobby.ROLE_OBSERVER:
		return
	sub_label.text = "JELLY WARS  —  관전 모드"
	sub_label.add_theme_color_override("font_color", OBSERVER_COLOR)
	start_button.text = "관전으로 접속"
	DisplayServer.window_set_title("젤리 워즈 — 관전")


## 방 버튼을 Network.ROOMS 개수만큼 만든다 — 목록에 줄을 추가하면 버튼도 같이 늘어난다.
## 씬의 RoomButton 이 첫 방이자 나머지의 원본이고, 복제본은 스타일과 ButtonGroup 을 그대로 물려받는다.
func _setup_room_buttons() -> void:
	room_buttons = [room_button_template]
	for i in range(1, Network.ROOMS.size()):
		var extra := room_button_template.duplicate() as Button
		room_box.add_child(extra)
		room_buttons.append(extra)

	for i in room_buttons.size():
		var button := room_buttons[i]
		var room_name: String = Network.ROOMS[i]["name"]
		button.text = room_name
		button.pressed.connect(_on_room_selected.bind(i))

	_room_index = clampi(_room_index, 0, room_buttons.size() - 1)
	room_buttons[_room_index].button_pressed = true


func _on_room_selected(index: int) -> void:
	_room_index = index
	status_label.text = ""


func _selected_port() -> int:
	return Network.ROOMS[_room_index]["port"]


func _set_inputs_enabled(flag: bool) -> void:
	start_button.disabled = not flag
	address_edit.editable = flag
	for button in room_buttons:
		button.disabled = not flag


func _role_text() -> String:
	return "관전으로" if Lobby.my_role == Lobby.ROLE_OBSERVER else "플레이어로"


func _on_address_submitted(_text: String) -> void:
	_on_start_pressed()


func _on_start_pressed() -> void:
	if _joining:
		return

	var address := address_edit.text.strip_edges()
	var target_port := _selected_port()

	# "192.168.0.5:7778" 처럼 포트를 직접 적으면 고른 방보다 그쪽을 우선한다.
	if address.contains(":"):
		var parts := address.split(":", false, 1)
		address = parts[0].strip_edges()
		if parts.size() > 1 and parts[1].strip_edges().is_valid_int():
			target_port = int(parts[1])

	if address.is_empty():
		status_label.text = "서버 주소를 입력하세요."
		return

	status_label.text = "%s (%s:%d) 로 %s 접속 중..." % [
		Network.room_name_for(target_port), address, target_port, _role_text(),
	]
	_joining = true
	_set_inputs_enabled(false)

	var err := Network.join_server(address, target_port)
	if err != OK:
		_on_join_failed("주소가 올바르지 않습니다: %s" % address)
		return

	_join_timer.start(JOIN_TIMEOUT_SEC)


## 방이 꽉 찼을 때 ENet 은 아무 신호 없이 거절한다. 그 경우가 여기로 온다.
func _on_join_timeout() -> void:
	if not _joining:
		return
	Network.leave()
	_on_join_failed("접속하지 못했습니다. 방이 꽉 찼거나 서버가 꺼져 있습니다.")


func _on_join_succeeded() -> void:
	_joining = false
	_join_timer.stop()
	# 접속 후 바로 전투가 아니라 대기실 겸 무기 선택 화면으로 간다
	get_tree().change_scene_to_file("res://scenes/select.tscn")


func _on_join_failed(reason: String) -> void:
	_joining = false
	if _join_timer != null:
		_join_timer.stop()
	status_label.text = reason
	_set_inputs_enabled(true)
