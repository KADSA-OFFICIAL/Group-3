extends Node
## 네트워크 연결 관리 (오토로드 싱글턴 Network).
## 연결 수립과 피어 알림만 담당하고 게임 로직은 다루지 않는다.
## 서버 주소는 `DEFAULT_ADDRESS` 하나로 고정이고 화면에 입력칸이 없다 (이슈 #198) —
## 붙을 주소는 `configured_address()`가 정한다(개발용 `--address=` 인자 → 기기 예외 파일 → 기본값).
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
## 전용 서버이므로 서버 자신은 플레이어가 아니다. **방 하나당** 1 VS 1 = 플레이어 2명.
## 이 값은 ENet 정원이 아니라 **싸우는 자리 수**다 — 자리 배정은 Lobby 가 한다.
const MAX_PLAYERS := 2
## 관전자 정원. 플레이어 자리를 차지하지 않고 보기만 하는 피어다 (이슈 #167).
const MAX_OBSERVERS := 4
## ENet 에 넘기는 실제 정원. 관전자도 피어이므로 여기에 포함되어야 접속이 열린다.
## 이 값만 늘리면 관전자로 들어올 수 있는 것이 아니다 — 역할 구분은 Lobby 가 한다.
const MAX_CLIENTS := MAX_PLAYERS + MAX_OBSERVERS
## 팀 서버 주소 (서버컴의 Tailscale 주소). **접속 화면에 입력칸은 없다** — 서버가 하나뿐이고
## 방은 포트로만 갈리므로 고를 것이 없다(이슈 #198).
##
## 주소가 바뀌면 **이 줄을 고치고 배포본을 다시 만들어야** 팀원들이 붙을 수 있다 —
## 화면에서 바꿀 방법이 없다. 그때는 docs/build.md 의 절차를 다시 밟는다.
##
## Tailscale 주소는 tailnet 안에서만 닿는 사설 주소라 외부에서 접속할 수 있는 대상이 아니지만,
## 이 저장소는 공개이므로 이 값은 공개되고 깃 이력에 남는다. 사용자가 알고 정한 것이다.
const DEFAULT_ADDRESS := "100.102.216.35"

## 기기별 주소 예외를 적어 두는 파일 (이슈 #195·#198). **읽기만 한다.**
##
## `user://` 는 실행 파일 밖(윈도우에서는 `%APPDATA%/Godot/app_userdata/Jelly Wars/`)이라
## 저장소에도 배포본에도 들어가지 않는다. 한 기기만 다른 서버(로컬 등)에 붙여야 할 때 쓴다.
## 실행 인자 `--address=` 가 이것보다 우선한다.
const CLIENT_CONFIG_PATH := "user://client.cfg"

## 접속 대기 한계 시간(초).
## **방이 꽉 차면 ENet 이 조용히 거절해서 `connection_failed` 조차 오지 않는다.**
## 그래서 직접 시간을 재지 않으면 "접속 중..." 에서 영원히 멈춘다.
## 접속 화면과 관전자의 방 전환이 같은 값을 쓴다 — 붙는 방식이 같으므로 한 곳에 둔다.
const JOIN_TIMEOUT_SEC := 8.0

var is_server := false

## 마지막으로 접속을 시도한 주소와 포트. **방을 옮길 때 주소를 다시 입력받지 않으려고** 기억한다
## (이슈 #184). 방은 포트로만 갈리므로 주소는 그대로 쓰고 포트만 바꿔 붙는다.
var last_address := ""
var current_port := 0

## 마지막 접속 실패 사유. 타이틀 화면이 한 번 읽고 비운다 —
## 전투 화면에서 방을 옮기다 실패하면 화면이 바뀐 뒤에 사유를 보여줘야 한다.
var last_failure := ""


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
	print("서버 시작 — %s, 포트 %d, 플레이어 %d명 + 관전 %d명" % [
		room_name_for(target_port), target_port, MAX_PLAYERS, MAX_OBSERVERS,
	])
	server_started.emit()
	return OK


func join_server(address: String, target_port: int = ROOMS[0]["port"]) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, target_port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = false
	last_address = address
	current_port = target_port
	return OK


## 접속을 끊고 **같은 주소의 다른 방(포트)** 으로 다시 붙는다 (이슈 #184).
##
## ENet 은 피어를 하나만 들 수 있으므로 **먼저 끊어야 한다** — 그래서 새 방 접속이 실패하면
## 원래 방으로 돌아갈 수 없다. 실패는 부르는 쪽이 타이틀 복귀로 처리한다.
func switch_room(target_port: int) -> Error:
	if last_address.is_empty():
		return ERR_UNCONFIGURED
	var address := last_address
	leave()
	return join_server(address, target_port)


## 이번 실행에서 붙을 서버 주소 (이슈 #198). 화면에 표시하고 접속에도 이 값을 쓴다.
##
## 정하는 순서가 중요하다.
## 1. `--address=` 실행 인자 — 개발·검증용. 로컬 서버에 붙을 유일한 방법이라 가장 우선한다.
## 2. `user://client.cfg` 의 `address` — 기기 한 대만 예외로 둘 때.
## 3. 코드에 박힌 팀 서버 주소(`DEFAULT_ADDRESS`) — 평소 모든 기기가 쓰는 값.
func configured_address() -> String:
	var from_args := address_from_cmdline()
	if not from_args.is_empty():
		return from_args
	var config := ConfigFile.new()
	if config.load(CLIENT_CONFIG_PATH) != OK:
		return DEFAULT_ADDRESS
	# ConfigFile 이 주는 값은 Variant 라 명시 타입으로 받는다.
	var saved: String = config.get_value("server", "address", DEFAULT_ADDRESS)
	saved = saved.strip_edges()
	return saved if not saved.is_empty() else DEFAULT_ADDRESS


## `--address=127.0.0.1` 형태의 실행 인자. 없으면 빈 문자열 (이슈 #198).
## `--port=` 와 같은 방식으로 `--` 앞이든 뒤든 받는다.
func address_from_cmdline() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	for arg in args:
		if arg.begins_with("--address="):
			return arg.substr(10).strip_edges()
	return ""


## 지금 쓰는 주소가 코드에 박힌 팀 서버 주소인가. 화면이 예외 상태를 알리는 데 쓴다.
func using_default_address() -> bool:
	return configured_address() == DEFAULT_ADDRESS


## 접속 실패 사유를 꺼내고 비운다. 두 번 읽어도 같은 사유가 또 뜨지 않게 한다.
func take_last_failure() -> String:
	var reason := last_failure
	last_failure = ""
	return reason


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
	last_failure = "서버에 연결하지 못했습니다."
	join_failed.emit(last_failure)


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	last_failure = "서버와 연결이 끊겼습니다."
	join_failed.emit(last_failure)
