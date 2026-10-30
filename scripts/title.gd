extends Control
## 타이틀 화면. 버튼 하나(`StartButton`)뿐이고, **무엇을 하는지는 기기가 정한다** (#361).
##
## - **PC 는 온라인 전용이다** — 버튼이 `접속`이고, 누르면 팀 서버의 1번 방
##   (`Network.DEFAULT_ADDRESS`:`Network.PORT`)에 붙는다. 붙으면 선택 창이 온라인 대기실로 열린다.
##   #320 이전과 같은 흐름이고, 그때 있던 방 고르기·주소 표시·관전 빌드는 되살리지 않았다.
## - **안드로이드는 오프라인 전용이다** — 버튼이 `시작`이고, 누르면 한 화면 2인 선택 창으로 간다(#320).
##
## 화면에서 모드를 고르는 곳은 없다 — 사용자가 기기별로 정했다(`Network.is_online_platform()`).
##
## **키보드 조작 안내는 없다** (이슈 #327). 조작이 화면 위의 조이스틱과 궁극기 버튼이 된
## 뒤로(#322) 기기에 없는 키를 첫 화면에서 알려 주는 글이 되어 있었다. 대신 들어갈 안내를
## 만들지 않은 것은 **조작물이 화면에 보이는 것 자체가 설명이기** 때문이다. PC 키 배치는
## `README.md` 에 적혀 있다. 지금의 `StatusLabel` 은 그 안내가 아니라 **온라인 접속 상태**만
## 적는다(#361) — 오프라인에서는 늘 비어 있다.

@onready var start_button: Button = $StartButton
@onready var status_label: Label = $StatusLabel

## 접속 시도 중인지. 시간이 다 됐는데도 true 면 실패로 처리한다.
var _joining := false
var _join_timer: Timer = null


func _ready() -> void:
	# 전용 서버는 화면이 없다 — 바로 전투 화면으로 가서 두 사람을 기다린다 (#361).
	# `_ready()` 시점에는 트리가 아직 자식을 붙이는 중이라 씬을 바로 갈아치울 수 없다.
	if Network.is_server():
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return

	start_button.pressed.connect(_on_start_pressed)
	if not Network.is_online_platform():
		return

	start_button.text = "접속"
	Network.join_succeeded.connect(_on_join_succeeded)
	Network.join_failed.connect(_on_join_failed)
	# 앞 화면에서 끊겨 여기로 밀려 왔으면 사유를 보여준다 — 전투 중에 끊기면 화면이
	# 바뀐 뒤에 알려줄 수밖에 없다.
	status_label.text = Network.take_last_failure()

	# 이 노드에 붙여두면 씬이 바뀔 때 타이머도 같이 사라진다.
	_join_timer = Timer.new()
	_join_timer.one_shot = true
	_join_timer.timeout.connect(_on_join_timeout)
	add_child(_join_timer)


func _on_start_pressed() -> void:
	if Network.is_online_platform():
		_join()
		return
	get_tree().change_scene_to_file("res://scenes/select.tscn")


func _join() -> void:
	if _joining:
		return
	var address := Network.configured_address()
	status_label.text = "%s 접속 중..." % Network.ROOM_NAME
	start_button.disabled = true
	_joining = true
	if Network.join_server(address) != OK:
		_on_join_failed("주소가 올바르지 않습니다: %s" % address)
		return
	_join_timer.start(Network.JOIN_TIMEOUT_SEC)


## 서버가 꺼져 있으면 ENet 이 꽤 오래 기다리다 실패한다. 그 전에 직접 끊는다.
func _on_join_timeout() -> void:
	if not _joining:
		return
	Network.leave()
	_on_join_failed("접속하지 못했습니다 — 서버나 Tailscale 이 꺼져 있습니다.")


func _on_join_succeeded() -> void:
	_joining = false
	_join_timer.stop()
	get_tree().change_scene_to_file("res://scenes/select.tscn")


func _on_join_failed(reason: String) -> void:
	_joining = false
	if _join_timer != null:
		_join_timer.stop()
	# 사유는 여기서 바로 보여주므로 남겨 두지 않는다 — 남기면 다음에 이 화면이 열릴 때 또 뜬다.
	Network.take_last_failure()
	status_label.text = reason
	start_button.disabled = false
