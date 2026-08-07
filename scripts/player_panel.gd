extends Control
## 선택 창의 플레이어 한 명 분량 패널 (미리보기 + 무기/머리/캐릭터 선택)
##
## 온라인에서는 자기 패널만 조작할 수 있고(`set_interactive`),
## 상대 패널은 서버가 보낸 값을 `apply_config()`로 표시만 한다.

## 이 패널의 선택이 사용자 조작으로 바뀌었을 때 (서버 전송용)
signal config_changed

@export var mirrored := false          # 2P는 아이콘 열이 오른쪽으로
@export var default_character := 0

var weapon_i := 0
var head_i := 0
var character_i := 0

@onready var hbox: HBoxContainer = $HBox
@onready var icon_column: VBoxContainer = $HBox/IconColumn
@onready var weapon_button: Button = $HBox/IconColumn/WeaponButton
@onready var head_button: Button = $HBox/IconColumn/HeadButton
@onready var character_button: Button = $HBox/IconColumn/CharacterButton
@onready var dropdown: OptionButton = $HBox/Center/PlayerDropdown
@onready var preview = $HBox/Center/Preview
@onready var random_button: Button = $HBox/Center/RandomButton


func _ready() -> void:
	character_i = default_character % GameState.CHARACTERS.size()
	if mirrored:
		hbox.move_child(icon_column, 1)
	dropdown.add_item("Player")
	dropdown.select(0)
	weapon_button.pressed.connect(_cycle.bind("weapon"))
	head_button.pressed.connect(_cycle.bind("head"))
	character_button.pressed.connect(_cycle.bind("character"))
	random_button.pressed.connect(_randomize_all)
	_update_ui()


## 조작 가능 여부. 상대 패널은 false로 두어 표시 전용이 된다.
func set_interactive(value: bool) -> void:
	for button in [weapon_button, head_button, character_button, random_button]:
		button.disabled = not value


## 서버가 보낸 선택값을 그대로 표시한다. config_changed를 내보내지 않는다.
func apply_config(config: Dictionary) -> void:
	weapon_i = maxi(GameState.WEAPONS.find(config.get("weapon", "")), 0)
	head_i = maxi(GameState.HEADS.find(config.get("head", "")), 0)
	character_i = maxi(GameState.CHARACTERS.find(config.get("character", "")), 0)
	_update_ui()


func _cycle(what: String) -> void:
	match what:
		"weapon":
			weapon_i = (weapon_i + 1) % GameState.WEAPONS.size()
		"head":
			head_i = (head_i + 1) % GameState.HEADS.size()
		"character":
			character_i = (character_i + 1) % GameState.CHARACTERS.size()
	_update_ui()
	config_changed.emit()


func _randomize_all() -> void:
	weapon_i = randi() % GameState.WEAPONS.size()
	head_i = randi() % GameState.HEADS.size()
	character_i = randi() % GameState.CHARACTERS.size()
	_update_ui()
	config_changed.emit()


func _update_ui() -> void:
	weapon_button.text = "무기\n" + GameState.WEAPONS[weapon_i]
	head_button.text = "머리\n" + GameState.HEADS[head_i]
	character_button.text = "캐릭터\n" + GameState.CHARACTERS[character_i]
	preview.character_id = GameState.CHARACTERS[character_i]


func get_config() -> Dictionary:
	return {
		"weapon": GameState.WEAPONS[weapon_i],
		"head": GameState.HEADS[head_i],
		"character": GameState.CHARACTERS[character_i],
	}
