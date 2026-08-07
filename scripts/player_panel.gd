extends Control
## 선택 창의 플레이어 한 명 분량 패널 (미리보기 + 머리/색상 선택)
##
## 온라인에서는 자기 슬롯 패널만 조작할 수 있고, 상대 패널은
## 네트워크로 받은 설정을 표시만 한다.
##
## 무기는 여기서 고르지 않는다. 계획서대로 라운드마다 3개 중 1개를 고른다.

signal config_changed(config: Dictionary)

@export var mirrored := false          # 2P는 아이콘 열이 오른쪽으로
@export var slot := 1

var head_i := 0
var color1_i := 0
var color2_i := 8
var editable := true

@onready var hbox: HBoxContainer = $HBox
@onready var icon_column: VBoxContainer = $HBox/IconColumn
@onready var head_button: Button = $HBox/IconColumn/HeadButton
@onready var color1_button: Button = $HBox/IconColumn/Color1Button
@onready var color2_button: Button = $HBox/IconColumn/Color2Button
@onready var slot_label: Label = $HBox/Center/SlotLabel
@onready var preview = $HBox/Center/Preview
@onready var random_button: Button = $HBox/Center/RandomButton


func _ready() -> void:
	color1_i = slot - 1
	if mirrored:
		hbox.move_child(icon_column, 1)
	head_button.pressed.connect(_cycle.bind("head"))
	color1_button.pressed.connect(_cycle.bind("color1"))
	color2_button.pressed.connect(_cycle.bind("color2"))
	random_button.pressed.connect(_randomize_all)
	_update_ui()


## 이 패널을 조작할 수 있는지. 상대 패널은 false.
func set_editable(value: bool) -> void:
	editable = value
	for button: Button in [head_button, color1_button, color2_button, random_button]:
		button.disabled = not value
	_update_ui()


func set_status(text: String) -> void:
	slot_label.text = text


func _cycle(what: String) -> void:
	match what:
		"head":
			head_i = (head_i + 1) % GameState.HEADS.size()
		"color1":
			color1_i = (color1_i + 1) % GameState.COLORS.size()
		"color2":
			color2_i = (color2_i + 1) % GameState.COLORS.size()
	_update_ui()
	config_changed.emit(get_config())


func _randomize_all() -> void:
	head_i = randi() % GameState.HEADS.size()
	color1_i = randi() % GameState.COLORS.size()
	color2_i = randi() % GameState.COLORS.size()
	_update_ui()
	config_changed.emit(get_config())


func _update_ui() -> void:
	head_button.text = "머리\n" + GameState.HEADS[head_i]
	preview.body_color = GameState.COLORS[color1_i]
	preview.eye_color = GameState.COLORS[color2_i]


func get_config() -> Dictionary:
	return {
		"head": GameState.HEADS[head_i],
		"color1": GameState.COLORS[color1_i],
		"color2": GameState.COLORS[color2_i],
	}


## 네트워크로 받은 설정을 그대로 반영한다.
func apply_config(config: Dictionary) -> void:
	if config.is_empty():
		return
	head_i = maxi(GameState.HEADS.find(config.get("head", "")), 0)
	color1_i = maxi(GameState.COLORS.find(config.get("color1", Color.BLACK)), 0)
	color2_i = maxi(GameState.COLORS.find(config.get("color2", Color.BLACK)), 0)
	_update_ui()
