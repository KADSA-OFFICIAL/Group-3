extends Control
## 타이틀 화면. **시작을 누르면 선택 창으로 간다** (#320).
##
## 예전에는 접속 화면이었다 — 서버 주소를 글자로 보여주고 방을 골라 붙었고, 관전
## 빌드인지도 여기서 알렸다. 오프라인 한 화면 2인이 되면서 고를 것도 기다릴 것도
## 없어져 표지 그림과 시작 버튼만 남았다. **되살리지 말 것**: 주소·방·역할은 이제
## 뜻이 없다.
##
## **키보드 조작 안내(`StatusLabel`)도 없앴다** (이슈 #327). 조작이 화면 위의 조이스틱과
## 궁극기 버튼이 된 뒤로(#322) 기기에 없는 키를 첫 화면에서 알려 주는 글이 되어 있었다.
## 대신 들어갈 안내를 만들지 않은 것은 **조작물이 화면에 보이는 것 자체가 설명이기**
## 때문이다. PC 키 배치는 `README.md` 에 적혀 있다.

@onready var start_button: Button = $StartButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/select.tscn")
