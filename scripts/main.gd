extends Node2D


func _ready() -> void:
	$MapLabel.text = "맵: " + GameState.map_name


func _unhandled_input(event: InputEvent) -> void:
	# ESC로 선택 창으로 돌아가기
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/select.tscn")
