extends Control
## 타이틀 겸 접속 화면. 서버 주소를 입력해 접속한다.
## 헤드리스(서버)로 실행된 경우에는 UI 없이 바로 전투 화면으로 넘어간다.

@onready var address_edit: LineEdit = $AddressEdit
@onready var status_label: Label = $StatusLabel
@onready var start_button: Button = $StartButton


func _ready() -> void:
	# 서버는 Network 오토로드에서 이미 시작됐다 — 접속 UI가 필요 없다.
	if Network.is_server:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return

	address_edit.text = Network.DEFAULT_ADDRESS
	status_label.text = ""
	start_button.pressed.connect(_on_start_pressed)
	address_edit.text_submitted.connect(_on_address_submitted)
	Network.join_succeeded.connect(_on_join_succeeded)
	Network.join_failed.connect(_on_join_failed)


func _on_address_submitted(_text: String) -> void:
	_on_start_pressed()


func _on_start_pressed() -> void:
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		status_label.text = "서버 주소를 입력하세요."
		return

	status_label.text = "%s:%d 로 접속 중..." % [address, Network.PORT]
	start_button.disabled = true

	var err := Network.join_server(address)
	if err != OK:
		_on_join_failed("주소가 올바르지 않습니다: %s" % address)


func _on_join_succeeded() -> void:
	# 접속 후 바로 전투가 아니라 대기실 겸 무기 선택 화면으로 간다
	get_tree().change_scene_to_file("res://scenes/select.tscn")


func _on_join_failed(reason: String) -> void:
	status_label.text = reason
	start_button.disabled = false
