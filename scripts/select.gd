extends Control
## 선택 창. **1P·2P가 각자 캐릭터를 고르고 시작을 누른다** (#320).
##
## **두 패널을 다 조작할 수 있다** — 한 화면이므로 "내 패널"이 따로 없다. 예전에는
## 대기실이어서 자기 패널만 만질 수 있었고, 상대 선택은 서버가 보내 준 것을 표시만
## 했으며, 둘 다 준비를 눌러야 서버 지시로 전투가 열렸다. 지금은 기다릴 상대가 없다.
##
## **무기는 여기서 고르지 않는다**(#205) — 라운드가 시작될 때마다 전투 화면에서 고른다.
##
## 고른 값은 `GameState`에 적히고 전투 화면이 그것을 읽어 젤리를 세운다.

## 조작 안내. 타이틀 화면과 같은 글이다 — 시작 직전에 한 번 더 보여준다.
const CONTROLS_TEXT := "1P   W A S D  ·  Shift          2P   ← ↑ ↓ →  ·  Space"

@onready var panels := [$P1Panel, $P2Panel]
@onready var status_label: Label = $StatusLabel
@onready var go_button: Button = $GoButton


func _ready() -> void:
	$HomeButton.pressed.connect(_on_home_pressed)
	go_button.pressed.connect(_on_go_pressed)

	# **가운데 두 칸(맵·무기)이 아예 없다** (요청). 맵도 무기도 라운드가 시작될 때 전투
	# 화면에서 정해지므로(`main.gd`의 `_start_round`·`_begin_pick_phase`) 이 화면에서는
	# 고를 것이 없었고, 남아 있던 것은 "라운드마다 정해집니다"라고만 적힌 안내판 둘이었다.
	# 안내판을 치우고 그 자리에 `StatusLabel`·`GoButton`을 올려 1P | 시작 | 2P 로 만들었다.
	for slot in panels.size():
		var panel: Control = panels[slot]
		panel.apply_config(GameState.config_for(GameState.id_at(slot)))
		panel.config_changed.connect(_on_config_changed.bind(slot))

	status_label.text = CONTROLS_TEXT


func _on_config_changed(slot: int) -> void:
	GameState.set_config(GameState.id_at(slot), panels[slot].get_config())


func _on_go_pressed() -> void:
	# 화면에 보이는 것이 그대로 전투로 넘어가야 한다 — 신호를 놓친 칸이 있어도
	# 여기서 두 패널을 한 번 더 읽어 적는다.
	for slot in panels.size():
		GameState.set_config(GameState.id_at(slot), panels[slot].get_config())
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_home_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")
