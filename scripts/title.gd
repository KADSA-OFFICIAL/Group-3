extends Control


func _ready() -> void:
	$StartButton.pressed.connect(_on_online)
	$LocalButton.pressed.connect(_on_local)
	# 전용 서버로 실행됐으면 UI는 의미가 없다.
	if Net.dedicated:
		$SubLabel.text = "전용 서버 실행 중"
		$StartButton.disabled = true
		$LocalButton.disabled = true


func _on_online() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_local() -> void:
	Net.start_local_2p()
	get_tree().change_scene_to_file("res://scenes/select.tscn")
