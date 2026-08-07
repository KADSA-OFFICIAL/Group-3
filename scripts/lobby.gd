extends Control
## 온라인 로비. 방을 열거나 주소를 넣어 접속한다.

@onready var address_edit: LineEdit = $Panel/VBox/AddressRow/AddressEdit
@onready var port_edit: LineEdit = $Panel/VBox/AddressRow/PortEdit
@onready var host_button: Button = $Panel/VBox/ButtonRow/HostButton
@onready var join_button: Button = $Panel/VBox/ButtonRow/JoinButton
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var slot1_label: Label = $Panel/VBox/Slots/Slot1
@onready var slot2_label: Label = $Panel/VBox/Slots/Slot2
@onready var back_button: Button = $BackButton


func _ready() -> void:
	Net.leave()
	host_button.pressed.connect(_on_host)
	join_button.pressed.connect(_on_join)
	back_button.pressed.connect(_on_back)
	Net.players_changed.connect(_refresh)
	Net.join_failed.connect(_on_join_failed)
	Net.server_closed.connect(_on_server_closed)
	_refresh()


## 포트는 팀에서 정해진 값이 없어서 기본값을 두지 않았다. 반드시 입력받는다.
func _port() -> int:
	return port_edit.text.strip_edges().to_int()


func _on_host() -> void:
	var port := _port()
	if port <= 0:
		status_label.text = "포트 번호를 입력하세요."
		return
	var err := Net.host(port)
	if err != "":
		status_label.text = err
		return
	status_label.text = "방을 열었습니다. 상대가 접속하기를 기다리는 중…"
	_refresh()


func _on_join() -> void:
	var address := address_edit.text.strip_edges()
	if address == "":
		status_label.text = "접속할 서버 주소를 입력하세요."
		return
	var port := _port()
	if port <= 0:
		status_label.text = "포트 번호를 입력하세요."
		return
	var err := Net.join(address, port)
	if err != "":
		status_label.text = err
		return
	status_label.text = "%s 에 접속하는 중…" % address
	_refresh()


func _on_join_failed(reason: String) -> void:
	status_label.text = reason
	_refresh()


func _on_server_closed() -> void:
	status_label.text = "서버와의 연결이 끊어졌습니다."
	_refresh()


func _on_back() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/title.tscn")


## 두 명이 다 붙으면 서버가 알아서 선택 창으로 넘긴다. 여기서 누를 버튼은 없다.
func _refresh() -> void:
	host_button.disabled = Net.is_online()
	join_button.disabled = Net.is_online()
	address_edit.editable = not Net.is_online()
	port_edit.editable = not Net.is_online()

	slot1_label.text = "1P  " + ("접속됨" if Net.slot_filled(1) else "비어 있음")
	slot2_label.text = "2P  " + ("접속됨" if Net.slot_filled(2) else "비어 있음")

	if Net.is_online() and Net.both_connected():
		status_label.text = "두 명 모두 접속했습니다. 캐릭터 선택으로 넘어갑니다…"
