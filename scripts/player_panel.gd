extends Control
## 선택 창의 플레이어 한 명 분량 패널 (미리보기 + 무기/머리/색상 선택)

@export var mirrored := false          # 2P는 아이콘 열이 오른쪽으로
@export var default_color1 := 0
@export var default_color2 := 8

var weapon_i := 0
var head_i := 0
var color1_i := 0
var color2_i := 8

@onready var hbox: HBoxContainer = $HBox
@onready var icon_column: VBoxContainer = $HBox/IconColumn
@onready var weapon_button: Button = $HBox/IconColumn/WeaponButton
@onready var head_button: Button = $HBox/IconColumn/HeadButton
@onready var color1_button: Button = $HBox/IconColumn/Color1Button
@onready var color2_button: Button = $HBox/IconColumn/Color2Button
@onready var dropdown: OptionButton = $HBox/Center/PlayerDropdown
@onready var preview = $HBox/Center/Preview
@onready var random_button: Button = $HBox/Center/RandomButton


func _ready() -> void:
	color1_i = default_color1
	color2_i = default_color2
	if mirrored:
		hbox.move_child(icon_column, 1)
	dropdown.add_item("Player")
	dropdown.select(0)
	weapon_button.pressed.connect(_cycle.bind("weapon"))
	head_button.pressed.connect(_cycle.bind("head"))
	color1_button.pressed.connect(_cycle.bind("color1"))
	color2_button.pressed.connect(_cycle.bind("color2"))
	random_button.pressed.connect(_randomize_all)
	_update_ui()


func _cycle(what: String) -> void:
	match what:
		"weapon":
			weapon_i = (weapon_i + 1) % GameState.WEAPONS.size()
		"head":
			head_i = (head_i + 1) % GameState.HEADS.size()
		"color1":
			color1_i = (color1_i + 1) % GameState.COLORS.size()
		"color2":
			color2_i = (color2_i + 1) % GameState.COLORS.size()
	_update_ui()


func _randomize_all() -> void:
	weapon_i = randi() % GameState.WEAPONS.size()
	head_i = randi() % GameState.HEADS.size()
	color1_i = randi() % GameState.COLORS.size()
	color2_i = randi() % GameState.COLORS.size()
	_update_ui()


func _update_ui() -> void:
	weapon_button.text = "무기\n" + GameState.WEAPONS[weapon_i]
	head_button.text = "머리\n" + GameState.HEADS[head_i]
	preview.body_color = GameState.COLORS[color1_i]
	preview.eye_color = GameState.COLORS[color2_i]


func get_config() -> Dictionary:
	return {
		"weapon": GameState.WEAPONS[weapon_i],
		"head": GameState.HEADS[head_i],
		"color1": GameState.COLORS[color1_i],
		"color2": GameState.COLORS[color2_i],
	}
