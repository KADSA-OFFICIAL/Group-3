extends Control
## 타이틀 화면. 버튼 하나(`StartButton`)뿐이고, 누르면 한 화면 2인 선택 창으로 간다(#320).
##
## **키보드 조작 안내는 없다** (이슈 #327). 조작이 화면 위의 조이스틱과 궁극기 버튼이 된
## 뒤로(#322) 기기에 없는 키를 첫 화면에서 알려 주는 글이 되어 있었다. 대신 들어갈 안내를
## 만들지 않은 것은 **조작물이 화면에 보이는 것 자체가 설명이기** 때문이다. PC 키 배치는
## `README.md` 에 적혀 있다.

@onready var start_button: Button = $StartButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/select.tscn")
