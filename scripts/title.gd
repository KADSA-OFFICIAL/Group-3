extends Control


func _ready() -> void:
	$StartButton.pressed.connect(_on_start)


func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/select.tscn")
