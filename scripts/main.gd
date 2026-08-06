extends Node2D
## 전투 화면. 서버가 접속한 클라이언트마다 플레이어를 하나씩 스폰한다.
## 이 단계는 스폰까지만 담당한다 — 이동 동기화는 3단계에서 추가한다.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SPAWN_POSITIONS := [Vector2(300, 500), Vector2(852, 500)]
const PLAYER_COLORS := [Color(1.0, 0.42, 0.55), Color(0.36, 0.55, 1.0)]

@onready var players_root: Node2D = $Players
@onready var spawner: MultiplayerSpawner = $PlayerSpawner


func _ready() -> void:
	$MapLabel.text = "맵: " + GameState.map_name
	# 스폰 함수는 모든 피어에서 등록되어야 한다 — 서버 판정보다 먼저 설정한다.
	spawner.spawn_function = _spawn_player

	if multiplayer.is_server():
		Network.peer_left.connect(_on_peer_left)
	else:
		# 씬이 준비된 뒤에 서버에 알린다. 접속 직후 바로 스폰하면
		# 클라이언트가 아직 이 씬을 로드하기 전이라 스폰을 놓칠 수 있다.
		_notify_ready.rpc_id(1)


## 클라이언트가 전투 화면 준비를 마쳤음을 서버에 알린다.
@rpc("any_peer", "call_remote", "reliable")
func _notify_ready() -> void:
	if not multiplayer.is_server():
		return
	_add_player(multiplayer.get_remote_sender_id())


func _add_player(peer_id: int) -> void:
	if players_root.has_node("Player_%d" % peer_id):
		return
	spawner.spawn({"peer_id": peer_id, "index": players_root.get_child_count()})


## 모든 피어에서 호출되어 플레이어 노드를 만든다. 반환한 노드는 spawn_path 아래에 붙는다.
func _spawn_player(data: Dictionary) -> Node:
	var peer_id: int = data["peer_id"]
	var index: int = data["index"]
	var player := PLAYER_SCENE.instantiate()
	player.name = "Player_%d" % peer_id
	player.owner_peer_id = peer_id
	player.player_name = "%dP" % (index + 1)
	player.jelly_color = PLAYER_COLORS[index % PLAYER_COLORS.size()]
	player.position = SPAWN_POSITIONS[index % SPAWN_POSITIONS.size()]
	return player


func _on_peer_left(peer_id: int) -> void:
	var player := players_root.get_node_or_null("Player_%d" % peer_id)
	if player:
		player.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# ESC로 접속을 끊고 타이틀로 돌아간다
	if event.is_action_pressed("ui_cancel"):
		Network.leave()
		get_tree().change_scene_to_file("res://scenes/title.tscn")
