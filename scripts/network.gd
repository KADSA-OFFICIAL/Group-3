extends Node
## 네트워크 연결 관리 (오토로드 싱글턴 Network).
## 연결 수립과 피어 알림만 담당하고 게임 로직은 다루지 않는다.
## 서버 주소는 여기에 적지 않는다 — 저장소가 공개라 실행 시 입력받는다.
##
## 방은 **포트 하나 = 방 하나** 로 나눈다.
## 서버 프로세스를 포트별로 하나씩 띄우므로 방끼리 완전히 독립적이다.
## 한 방이 죽어도 다른 방은 영향을 받지 않고, 방을 늘리려면 ROOMS 에 줄만 추가하면 된다
## (접속 화면 버튼은 이 목록을 보고 만들어지므로 씬은 손대지 않아도 된다).
## 헤드리스 서버는 `--port=7778` 처럼 포트를 지정해 실행한다 — 실행 방법은 docs/server.md.

signal server_started
signal join_succeeded
signal join_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

## 방 목록. **여기가 방 구성의 유일한 출처다** — 접속 화면의 방 버튼도 이 목록을 따른다.
## 서버컴 Windows 방화벽에 이 포트들이 전부 UDP 로 열려 있어야 한다.
const ROOMS := [
	{"name": "1번 방", "port": 7777},
	{"name": "2번 방", "port": 7778},
]
## 전용 서버이므로 서버 자신은 플레이어가 아니다. **방 하나당** 1 VS 1 = 클라이언트 2명.
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
		# 포트를 못 열었는데 그냥 두면 이 프로세스는 is_server 가 false 인 채로 살아남아
		# 클라이언트 취급을 받는다 — 헤드리스라 화면도 없어서 "서버 떠 있음"으로 착각하기 쉽다.
		# 그런 반쪽짜리 상태로 두지 말고 바로 끝낸다.
		if start_server(port_from_cmdline()) != OK:
			get_tree().quit(1)


## 헤드리스로 실행됐거나 --server 인자가 있으면 서버로 동작한다.
func should_run_as_server() -> bool:
	return DisplayServer.get_name() == "headless" or "--server" in OS.get_cmdline_args()


## `--port=7778` 형태의 실행 인자를 읽는다. 없으면 1번 방 포트를 쓴다.
## `godot --headless --path . -- --port=7778` 처럼 `--` 뒤에 붙여도 되고, 그냥 붙여도 된다.
func port_from_cmdline() -> int:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	for arg in args:
		if arg.begins_with("--port="):
			var value := arg.substr(7).strip_edges()
			if value.is_valid_int():
				return int(value)
			push_warning("--port 값이 숫자가 아닙니다: %s" % value)
	return ROOMS[0]["port"]


## 포트에 해당하는 방 이름. 목록에 없는 포트면 번호를 그대로 보여준다.
func room_name_for(target_port: int) -> String:
	for room in ROOMS:
		if room["port"] == target_port:
			return room["name"]
	return "포트 %d" % target_port


func start_server(target_port: int = ROOMS[0]["port"]) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(target_port, MAX_CLIENTS)
	if err != OK:
		push_error("서버 시작 실패 (포트 %d): %s — 이미 그 포트로 서버가 떠 있지 않은지 확인하세요." % [
			target_port, error_string(err),
		])
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	print("서버 시작 — %s, 포트 %d, 최대 %d명" % [room_name_for(target_port), target_port, MAX_CLIENTS])
	server_started.emit()
	return OK


func join_server(address: String, target_port: int = ROOMS[0]["port"]) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, target_port)
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
