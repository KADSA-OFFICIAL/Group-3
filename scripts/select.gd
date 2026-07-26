extends Control
## 게임 준비(캐릭터/맵 선택) 화면

var map_i := 0

@onready var map_name_label: Label = $MapBox/MapName
@onready var p1_panel = $P1Panel
@onready var p2_panel = $P2Panel


func _ready() -> void:
	randomize()
	$HomeButton.pressed.connect(_on_home)
	$LeftArrow.pressed.connect(_change_map.bind(-1))
	$RightArrow.pressed.connect(_change_map.bind(1))
	$GoButton.pressed.connect(_start_game)
	_update_map()


func _on_home() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func _change_map(dir: int) -> void:
	map_i = (map_i + dir + GameState.MAPS.size()) % GameState.MAPS.size()
	_update_map()


func _update_map() -> void:
	map_name_label.text = GameState.MAPS[map_i]


func _start_game() -> void:
	GameState.p1_config = p1_panel.get_config()
	GameState.p2_config = p2_panel.get_config()
	var chosen: String = GameState.MAPS[map_i]
	if chosen == "랜덤" or chosen != "평지":
		chosen = "평지"  # 아직 평지 맵만 구현되어 있음
	GameState.map_name = chosen
	get_tree().change_scene_to_file("res://scenes/main.tscn")
