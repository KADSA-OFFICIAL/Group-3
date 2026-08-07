extends Control
## 게임 준비(캐릭터 선택) 화면.
##
## 온라인에서는 각자 자기 슬롯 패널만 조작하고, 바뀐 설정은 서버를 거쳐
## 상대 화면에 반영된다. 양쪽이 준비를 누르면 서버가 전투를 시작한다.
## 맵은 항상 랜덤이라 여기서 고르지 않는다.

@onready var map_name_label: Label = $MapBox/MapName
@onready var panels := {1: $P1Panel, 2: $P2Panel}
@onready var ready_button: Button = $GoButton
@onready var home_button: Button = $HomeButton


func _ready() -> void:
	randomize()
	# 맵은 랜덤이므로 선택 화살표를 쓰지 않는다.
	$LeftArrow.hide()
	$RightArrow.hide()
	map_name_label.text = "랜덤"

	home_button.pressed.connect(_on_home)
	ready_button.pressed.connect(_on_ready_pressed)
	Net.players_changed.connect(_refresh)
	Net.server_closed.connect(_on_server_closed)

	for slot: int in panels:
		panels[slot].config_changed.connect(_on_my_config_changed)

	_refresh()

	# 접속 직후 내 초기 설정을 상대에게 알린다.
	if Net.is_online() and Net.my_slot() != 0:
		Net.set_my_config(panels[Net.my_slot()].get_config())


## 자기 슬롯 패널만 열어주고, 상대 패널은 표시 전용으로 잠근다.
func _refresh() -> void:
	var mine: int = Net.my_slot()
	for slot: int in panels:
		var panel = panels[slot]
		var editable: bool = Net.mode == Net.Mode.LOCAL_2P or slot == mine
		panel.set_editable(editable)
		panel.set_status(_slot_status(slot, mine))
		# 내 패널은 내가 조작한 게 최신이므로 덮어쓰지 않는다.
		if not editable:
			var peer_id: int = Net.peer_for_slot(slot)
			if peer_id != 0:
				panel.apply_config(Net.players[peer_id]["config"])

	if Net.mode == Net.Mode.LOCAL_2P:
		ready_button.text = "GO!"
		ready_button.disabled = false
	else:
		ready_button.text = "준비 취소" if Net.am_i_ready() else "준비"
		ready_button.disabled = mine == 0


func _slot_status(slot: int, mine: int) -> String:
	if Net.mode == Net.Mode.LOCAL_2P:
		return "%dP" % slot
	var peer_id: int = Net.peer_for_slot(slot)
	if peer_id == 0:
		return "%dP  (비어 있음)" % slot
	var label := "%dP%s" % [slot, "  (나)" if slot == mine else ""]
	return label + ("  ✔ 준비" if Net.players[peer_id]["ready"] else "")


func _on_ready_pressed() -> void:
	if Net.mode == Net.Mode.LOCAL_2P:
		Net.start_local_match()
	else:
		Net.set_my_ready(not Net.am_i_ready())


func _on_my_config_changed(config: Dictionary) -> void:
	if Net.mode == Net.Mode.LOCAL_2P:
		# 로컬 2인은 네트워크를 타지 않으므로 슬롯별로 직접 채운다.
		for slot: int in panels:
			Net.players[slot]["config"] = panels[slot].get_config()
		return
	Net.set_my_config(config)


func _on_home() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func _on_server_closed() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")
