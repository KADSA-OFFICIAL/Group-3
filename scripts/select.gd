extends Control
## 대기실 겸 무기 선택 화면.
##
## 자기 패널만 조작할 수 있고 상대 패널에는 서버가 보낸 상대 선택이 표시된다.
## 둘 다 준비되면 **서버 지시로** 전투 화면으로 전환된다.

@onready var panels := [$P1Panel, $P2Panel]
@onready var status_label: Label = $StatusLabel
@onready var go_button: Button = $GoButton
@onready var map_name_label: Label = $MapBox/MapName

var _my_panel: Control = null


func _ready() -> void:
	$HomeButton.pressed.connect(_on_home_pressed)
	go_button.pressed.connect(_on_ready_pressed)

	# 맵은 서버가 정한다. 현재 평지만 구현되어 있어 좌우 화살표는 비활성.
	$LeftArrow.disabled = true
	$RightArrow.disabled = true

	for panel in panels:
		panel.config_changed.connect(_on_my_config_changed)

	Lobby.lobby_changed.connect(_refresh)
	Lobby.match_starting.connect(_on_match_starting)
	Network.join_failed.connect(_on_disconnected)

	_refresh()


func _refresh() -> void:
	var me := multiplayer.get_unique_id()
	var my_slot := Lobby.slot_of(me)
	_my_panel = panels[my_slot] if my_slot >= 0 and my_slot < panels.size() else null

	for slot in panels.size():
		var panel: Control = panels[slot]
		panel.set_interactive(panel == _my_panel)
		# 내 패널은 내가 조작 중이므로 덮어쓰지 않는다
		if panel == _my_panel:
			continue
		if slot < Lobby.order.size():
			panel.apply_config(Lobby.config_for(Lobby.order[slot]))

	map_name_label.text = Lobby.map_name
	_update_status()


func _update_status() -> void:
	var me := multiplayer.get_unique_id()

	if Lobby.order.size() < 2:
		status_label.text = "상대 대기 중..."
		go_button.disabled = true
		go_button.text = "준비"
		return

	var opponent := 0
	for peer_id in Lobby.order:
		if peer_id != me:
			opponent = peer_id

	var mine := Lobby.is_ready(me)
	go_button.disabled = false
	go_button.text = "준비 취소" if mine else "준비"
	status_label.text = "나: %s   |   상대: %s" % [
		_ready_text(mine),
		_ready_text(Lobby.is_ready(opponent)),
	]


func _ready_text(flag: bool) -> String:
	return "준비 완료" if flag else "선택 중"


func _on_my_config_changed() -> void:
	if _my_panel == null:
		return
	Lobby.submit_config(_my_panel.get_config())


func _on_ready_pressed() -> void:
	Lobby.submit_ready(not Lobby.is_ready(multiplayer.get_unique_id()))


func _on_match_starting() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_disconnected(_reason: String) -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func _on_home_pressed() -> void:
	Network.leave()
	get_tree().change_scene_to_file("res://scenes/title.tscn")
