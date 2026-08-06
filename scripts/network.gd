extends Node
## 네트워크 연결 관리 (오토로드 싱글턴 Network).
## 연결 수립과 피어 알림만 담당하고 게임 로직은 다루지 않는다.
## 서버 주소는 여기에 적지 않는다 — 저장소가 공개라 실행 시 입력받는다.

signal server_started
signal join_succeeded
signal join_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

## 서버컴 Windows 방화벽에 열어둔 UDP 포트와 일치해야 한다.
const PORT := 7777
## 전용 서버이므로 서버 자신은 플레이어가 아니다. 1 VS 1 = 클라이언트 2명.
const MAX_CLIENTS := 2
## 로컬 테스트용 기본값. 실제 서버 주소는 접속 화면에서 입력한다.
const DEFAULT_ADDRESS := "127.0.0.1"

var is_server := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if should_run_as_server():
		start_server()


## 헤드리스로 실행됐거나 --server 인자가 있으면 서버로 동작한다.
func should_run_as_server() -> bool:
	return DisplayServer.get_name() == "headless" or "--server" in OS.get_cmdline_args()


func start_server() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		push_error("서버 시작 실패 (포트 %d): %s" % [PORT, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	print("서버 시작 — 포트 %d, 최대 %d명" % [PORT, MAX_CLIENTS])
	server_started.emit()
	return OK


func join_server(address: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = false
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_server = false


func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)


func _on_connected_to_server() -> void:
	join_succeeded.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	join_failed.emit("서버에 연결하지 못했습니다.")


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	join_failed.emit("서버와 연결이 끊겼습니다.")
