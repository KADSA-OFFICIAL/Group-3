extends Control
## 타이틀 화면. **시작을 누르면 선택 창으로 간다** (#320).
##
## 예전에는 접속 화면이었다 — 서버 주소를 글자로 보여주고 방을 골라 붙었고, 관전
## 빌드인지도 여기서 알렸다. 오프라인 한 화면 2인이 되면서 고를 것도 기다릴 것도
## 없어져 표지 그림과 시작 버튼만 남았다. **되살리지 말 것**: 주소·방·역할은 이제
## 뜻이 없다.

## 화면 아래에 적어 두는 조작 안내. 게임 안에 조작을 알려 주는 곳이 여기뿐이라
## 두 사람 몫을 한 줄로 보여준다 (`project.godot` 의 `[input]` 과 같아야 한다).
const CONTROLS_TEXT := "1P   W A S D  ·  Shift          2P   ← ↑ ↓ →  ·  Space"

@onready var start_button: Button = $StartButton
@onready var status_label: Label = $StatusLabel


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	status_label.text = CONTROLS_TEXT


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/select.tscn")
