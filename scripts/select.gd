extends Control
## 선택 창. **1P·2P가 각자 캐릭터를 고르고 시작을 누른다** (#320).
##
## **두 패널을 다 조작할 수 있다** — 한 화면이므로 "내 패널"이 따로 없다.
##
## **온라인(#361)에서는 대기실이 된다.** 서버가 정해 준 자리의 패널만 조작하고, 상대 패널은
## 서버가 보내 준 상대 선택을 표시만 한다. `시작!` 대신 `준비`를 누르고, 둘 다 준비하면
## **서버 지시로** 전투 화면으로 간다. 상태(상대 대기 중·준비 여부)는 `StatusLabel` 이
## 적는다 — 오프라인에서는 숨어 있다(키보드 안내를 없앤 #325와 무관하다: 적는 것이 접속 상태다).
##
## **무기는 여기서 고르지 않는다**(#205) — 라운드가 시작될 때마다 전투 화면에서 고른다.
##
## 오프라인에서 고른 값은 `GameState`에 적히고 전투 화면이 그것을 읽어 젤리를 세운다.

@onready var panels := [$P1Panel, $P2Panel]
@onready var go_button: Button = $GoButton
@onready var status_label: Label = $StatusLabel

## 온라인에서 내가 조작하는 패널. 아직 자리를 못 받았으면 null.
var _my_panel: Control = null


func _ready() -> void:
	$HomeButton.pressed.connect(_on_home_pressed)
	go_button.pressed.connect(_on_go_pressed)

	# **가운데 두 칸(맵·무기)이 아예 없다** (요청). 맵도 무기도 라운드가 시작될 때 전투
	# 화면에서 정해지므로(`main.gd`의 `_start_round`·`_begin_pick_phase`) 이 화면에서는
	# 고를 것이 없었고, 남아 있던 것은 "라운드마다 정해집니다"라고만 적힌 안내판 둘이었다.
	# 안내판을 치우고 그 자리에 `GoButton`을 올려 1P | 시작 | 2P 로 만들었다.
	# 키보드 안내(`StatusLabel`)도 없앴다 (이슈 #325) — 조작이 화면 위의 조이스틱과
	# 궁극기 버튼이 된 뒤로(#322) 기기에 없는 키를 시작 직전에 알려 주고 있었다.
	for slot in panels.size():
		var panel: Control = panels[slot]
		panel.config_changed.connect(_on_config_changed.bind(slot))

	if Network.is_client():
		_setup_online()
		return
	for slot in panels.size():
		panels[slot].apply_config(GameState.config_for(GameState.id_at(slot)))


func _on_config_changed(slot: int) -> void:
	if Network.is_client():
		if panels[slot] == _my_panel:
			Lobby.submit_config(_my_panel.get_config())
		return
	GameState.set_config(GameState.id_at(slot), panels[slot].get_config())


func _on_go_pressed() -> void:
	Sfx.play("confirm", 0.0, false)
	if Network.is_client():
		Lobby.submit_ready(not Lobby.is_ready(multiplayer.get_unique_id()))
		return
	# 화면에 보이는 것이 그대로 전투로 넘어가야 한다 — 신호를 놓친 칸이 있어도
	# 여기서 두 패널을 한 번 더 읽어 적는다.
	for slot in panels.size():
		GameState.set_config(GameState.id_at(slot), panels[slot].get_config())
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_home_pressed() -> void:
	Sfx.play("click")
	# 온라인이면 접속도 끊는다 — 홈은 대기실을 떠난다는 뜻이다.
	Network.leave()
	get_tree().change_scene_to_file("res://scenes/title.tscn")


# ─────────────────────────── 온라인 대기실 (#361) ───────────────────────────

func _setup_online() -> void:
	status_label.visible = true
	Lobby.lobby_changed.connect(_refresh)
	Lobby.match_starting.connect(_on_match_starting)
	Network.join_failed.connect(_on_disconnected)
	# 접속 순간의 방송을 이 화면이 열리기 전에 받았을 수도, 놓쳤을 수도 있다 — 한 번 더 청한다.
	Lobby.request_state()
	_refresh()


## 대기실 상태를 화면에 반영한다.
##
## **트리를 벗어난 뒤에는 아무것도 하지 않는다.** 씬 전환은 프레임 끝에 일어나므로 그 사이에
## 도착한 서버 방송이 이미 떼어진 이 노드로 들어온다.
func _refresh() -> void:
	if not is_inside_tree():
		return
	var me := multiplayer.get_unique_id()
	var my_slot := Lobby.slot_of(me)
	_my_panel = panels[my_slot] if my_slot >= 0 and my_slot < panels.size() else null
	for slot in panels.size():
		var panel: Control = panels[slot]
		panel.set_interactive(panel == _my_panel)
		# 내 패널은 내가 조작 중이므로 덮어쓰지 않는다 — 서버 답이 늦게 오면 방금 바꾼 것이
		# 한 번 되돌아갔다 다시 바뀐다.
		if panel == _my_panel:
			continue
		if slot < Lobby.order.size():
			panel.apply_config(Lobby.config_for(Lobby.order[slot]))
	_update_status()


func _update_status() -> void:
	var me := multiplayer.get_unique_id()
	go_button.text = "준비"
	# 목록에 내 자리가 없으면 준비를 보내도 서버가 버린다 — 눌러도 아무 일 없는 버튼을
	# 켜 두면 "전부 클릭이 안 된다"로만 보인다 (#93).
	if Lobby.slot_of(me) < 0:
		status_label.text = "대기실 정보를 받는 중..."
		go_button.disabled = true
		return
	var notice := Lobby.notice
	if Lobby.order.size() < Network.MAX_PLAYERS:
		status_label.text = notice if notice != "" else "상대를 기다리는 중..."
		go_button.disabled = true
		return
	Lobby.notice = ""
	var opponent := 0
	for peer_id in Lobby.order:
		if peer_id != me:
			opponent = peer_id
	var mine := Lobby.is_ready(me)
	go_button.disabled = false
	go_button.text = "준비 취소" if mine else "준비"
	status_label.text = "나: %s   |   상대: %s" % [_ready_text(mine), _ready_text(Lobby.is_ready(opponent))]


func _ready_text(flag: bool) -> String:
	return "준비 완료" if flag else "고르는 중"


## 서버의 경기 시작 지시. 이미 화면을 떠났다면 무시한다.
func _on_match_starting() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/main.tscn")


## 서버와 끊겼다. 사유는 `Network.last_failure` 에 남아 타이틀이 보여준다.
func _on_disconnected(_reason: String) -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/title.tscn")
