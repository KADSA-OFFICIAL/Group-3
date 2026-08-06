extends Control
## 선택 창의 플레이어 한 명 분량 패널 (미리보기 + 무기/머리/색상 선택)
##
## 온라인에서는 자기 패널만 조작할 수 있고(`set_interactive`),
## 상대 패널은 서버가 보낸 값을 `apply_config()`로 표시만 한다.

## 이 패널의 선택이 사용자 조작으로 바뀌었을 때 (서버 전송용)
signal config_changed

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


## 조작 가능 여부. 상대 패널은 false로 두어 표시 전용이 된다.
func set_interactive(value: bool) -> void:
	for button in [weapon_button, head_button, color1_button, color2_button, random_button]:
		button.disabled = not value


## 서버가 보낸 선택값을 그대로 표시한다. config_changed를 내보내지 않는다.
func apply_config(config: Dictionary) -> void:
	weapon_i = maxi(GameState.WEAPONS.find(config.get("weapon", "")), 0)
	head_i = maxi(GameState.HEADS.find(config.get("head", "")), 0)
	color1_i = maxi(GameState.COLORS.find(config.get("color1", Color.BLACK)), 0)
	color2_i = maxi(GameState.COLORS.find(config.get("color2", Color.BLACK)), 0)
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
	config_changed.emit()


func _randomize_all() -> void:
	weapon_i = randi() % GameState.WEAPONS.size()
	head_i = randi() % GameState.HEADS.size()
	color1_i = randi() % GameState.COLORS.size()
	color2_i = randi() % GameState.COLORS.size()
	_update_ui()
	config_changed.emit()


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
