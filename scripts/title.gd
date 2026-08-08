extends Control
## 타이틀 겸 접속 화면. **방을 고르고** 서버 주소를 입력해 접속한다.
## 헤드리스(서버)로 실행된 경우에는 UI 없이 바로 전투 화면으로 넘어간다.
##
## 방 목록은 Network.ROOMS 가 유일한 출처다. 버튼 글자도 거기서 가져온다.

## 접속 대기 한계 시간(초).
## 방이 꽉 차면 ENet 이 조용히 거절해서 connection_failed 조차 오지 않는다.
## 그래서 직접 시간을 재지 않으면 "접속 중..." 에서 영원히 멈춘다.
const JOIN_TIMEOUT_SEC := 8.0

@onready var address_edit: LineEdit = $AddressEdit
@onready var status_label: Label = $StatusLabel
@onready var start_button: Button = $StartButton
@onready var room_buttons: Array[Button] = [$Room1Button, $Room2Button]

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


## 방 버튼 글자와 개수를 Network.ROOMS 에 맞춘다.
## 목록보다 버튼이 많으면 남는 버튼은 숨긴다 — 방을 줄여도 화면이 깨지지 않도록.
func _setup_room_buttons() -> void:
	for i in room_buttons.size():
		var button := room_buttons[i]
		if i >= Network.ROOMS.size():
			button.visible = false
			continue
		button.text = Network.ROOMS[i]["name"]
		button.pressed.connect(_on_room_selected.bind(i))

	_room_index = clampi(_room_index, 0, Network.ROOMS.size() - 1)
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

	status_label.text = "%s (%s:%d) 로 접속 중..." % [
		Network.room_name_for(target_port), address, target_port,
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
