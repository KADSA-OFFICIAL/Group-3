extends Node
## 온라인 대전의 접속 관리 (오토로드 싱글턴 Network, 이슈 #361).
## 연결 수립과 피어 알림만 담당하고 게임 로직은 다루지 않는다.
##
## **기기가 모드를 정한다** (`is_online_platform()`). PC 는 #320 이전처럼 **온라인 전용**이고
## (타이틀의 버튼이 `접속`), 안드로이드는 지금처럼 **한 화면 2인 오프라인 전용**이다. 화면에서
## 고르는 곳은 없다 — 사용자가 정했다.
##
## 방은 **포트 하나 = 서버 프로세스 하나**로 갈린다(#409). `ROOMS` 의 1번 방(7777)·2번 방(7778)이다.
## 서버를 방마다 따로 띄우므로 방끼리 완전히 독립적이다 — 한 방에서 경기가 진행 중이어도
## 다른 방은 두 사람을 받는다. #320 이전의 3번 방, 관전·버전 악수(#228)는 되살리지 않았다.
## **버전 악수가 없다는 것을 기억할 것** — RPC 는 함수 이름이 아니라 번호로 오가므로,
## 서버와 클라이언트의 `@rpc` 함수 목록이 다르면 엉뚱한 함수가 불린다. 서버는
## `run-server.bat` 이 늘 `origin/main` 으로 맞춰 띄우므로, 클라이언트도 같은 빌드를 써야 한다.
##
## 서버는 `--server` 인자로만 되고, 어느 방인지는 `--room=2` 로 고른다(없으면 1번 방).
## **헤드리스라는 것만으로는 서버가 되지 않는다** — 커밋 전 헤드리스 검증(`CLAUDE.md`)이 오프라인 게임을 그대로 돌려야 하기 때문이다.
## 띄우는 방법은 docs/server.md.

signal join_succeeded
signal join_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

## 방 목록. **방 구성의 유일한 출처다** — 타이틀의 방 버튼과 서버가 이 목록을 따른다.
## 서버컴 Windows 방화벽에 이 포트들이 전부 UDP 로 열려 있어야 한다.
## `run-server.bat` 은 이 목록을 읽지 못하고 포트를 따로 적어 두므로, **방을 더하면
## 그 스크립트의 `ROOM_COUNT`·`ROOM_PORT_BASE` 도 같이 맞춘다.**
const ROOMS := [
	{"name": "1번 방", "port": 7777},
	{"name": "2번 방", "port": 7778},
]
## 1 VS 1 이므로 접속을 받는 자리는 둘이다. 세 번째는 `Lobby` 가 사유를 알리고 끊는다 —
## ENet 정원으로 막으면 아무 신호 없이 거절돼서 "접속 중..."에 멈춰 보인다.
const MAX_PLAYERS := 2
## ENet 에 넘기는 실제 정원. 넘친 한 사람이 사유를 듣고 나갈 자리를 남긴다.
const MAX_CLIENTS := MAX_PLAYERS + 1

## 팀 서버 주소 (서버컴의 Tailscale 주소). **접속 화면에 입력칸은 없다**(#198과 같다).
##
## 주소가 바뀌면 **이 줄을 고치고 배포본을 다시 만들어야** 팀원들이 붙을 수 있다.
## Tailscale 주소는 tailnet 안에서만 닿는 사설 주소라 외부에서 접속할 수 있는 대상이
## 아니지만, 이 저장소는 공개이므로 이 값은 공개되고 깃 이력에 남는다(#198에서 사용자가 정했다).
## 기기(폰 포함)에 Tailscale 이 켜져 있어야 이 주소에 닿는다.
const DEFAULT_ADDRESS := "100.102.216.35"

## 접속 대기 한계 시간(초). ENet 은 서버가 꺼져 있으면 꽤 오래 기다리다 실패하므로
## 직접 시간을 잰다 — 안 재면 "접속 중..."에서 오래 멈춘다.
const JOIN_TIMEOUT_SEC := 8.0

enum Role { OFFLINE, SERVER, CLIENT }

## 이 프로세스의 역할. **`multiplayer.is_server()` 대신 이것을 본다** — 접속이 끊긴 뒤에는
## 피어가 없어 `is_server()` 가 참이 되므로(내 id 가 1) 클라이언트를 서버로 착각한다.
var role := Role.OFFLINE

## 마지막 접속 실패 사유. 타이틀 화면이 한 번 읽고 비운다 — 전투 화면에서 끊기면
## 화면이 바뀐 뒤에 사유를 보여줘야 한다.
var last_failure := ""

## 지금 붙었거나 붙을 방(`ROOMS` 의 인덱스). 클라이언트는 타이틀이 `join_room()` 으로 정하고,
## 서버는 `--room=` 인자로 정한다.
var room_index := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int) -> void: peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void: peer_left.emit(id))
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if "--server" in _cmdline_args():
		room_index = room_index_from_cmdline()
		if room_index < 0:
			push_error("--room 값이 1~%d 가 아닙니다." % ROOMS.size())
			room_index = 0
			get_tree().quit(1)
			return
		# 포트를 못 열었는데 그냥 두면 이 프로세스는 오프라인 게임으로 살아남는다 —
		# 헤드리스라 화면도 없어서 "서버 떠 있음"으로 착각하기 쉽다. 바로 끝낸다.
		if start_server() != OK:
			get_tree().quit(1)


## 이 기기가 온라인으로 하는 기기인가. **PC 는 온라인, 그 밖(안드로이드)은 오프라인**이다.
##
## `pc` 기능 태그는 윈도·맥·리눅스에서 켜진다 — 에디터 F5 도 PC 이므로 온라인 타이틀이 뜬다.
##
## **`--offline` 실행 인자는 개발·검증용이다** (`--address=` 와 같은 자리). PC 에서 오프라인
## 흐름을 확인할 길이 그것뿐이라 남겼다 — 커밋 전 헤드리스 검증이 한 경기를 돌리는 데 쓴다.
## 배포본을 그렇게 실행하라고 안내하지 말 것: PC 는 온라인 전용이라는 것이 사용자가 정한 규칙이다.
func is_online_platform() -> bool:
	return OS.has_feature("pc") and not "--offline" in _cmdline_args()


## 온라인 서버인가.
func is_server() -> bool:
	return role == Role.SERVER


## 온라인 클라이언트인가. **판정을 하지 않는 쪽**이다 — 젤리·투사체는 서버가 보낸 대로 그린다.
func is_client() -> bool:
	return role == Role.CLIENT


## 온라인인가 (서버든 클라이언트든).
func is_online() -> bool:
	return role != Role.OFFLINE


## 판정을 하는 쪽인가 — 오프라인이거나 온라인 서버. 전투 판정과 상태 변경이 이것을 본다.
func has_authority() -> bool:
	return role != Role.CLIENT


## 지금 방의 이름. 화면과 서버 로그에 적는다.
func room_name() -> String:
	return ROOMS[room_index]["name"]


## 지금 방의 UDP 포트.
func room_port() -> int:
	return ROOMS[room_index]["port"]


## `--room=2` 실행 인자가 가리키는 방의 인덱스. 인자가 없으면 1번 방(0)이고, **값이 잘못됐으면 -1** 이다 —
## 오타 난 값으로 조용히 1번 방에 뜨면 1번 방 서버가 없던 자리에 엉뚱하게 뜨므로 호출한 쪽이 끝낸다.
func room_index_from_cmdline() -> int:
	for arg in _cmdline_args():
		if arg.begins_with("--room="):
			var value := arg.substr(7).strip_edges()
			if value.is_valid_int() and int(value) >= 1 and int(value) <= ROOMS.size():
				return int(value) - 1
			return -1
	return 0


func start_server() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(room_port(), MAX_CLIENTS)
	if err != OK:
		push_error("서버 시작 실패 (%s, 포트 %d): %s — 이미 그 포트로 서버가 떠 있지 않은지 확인하세요." % [
			room_name(), room_port(), error_string(err),
		])
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.SERVER
	print("서버 시작 — %s, 포트 %d, 플레이어 %d명" % [room_name(), room_port(), MAX_PLAYERS])
	return OK


## `index` 번째 방(`ROOMS` 의 인덱스)에 붙는다.
func join_room(address: String, index: int) -> Error:
	room_index = clampi(index, 0, ROOMS.size() - 1)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, room_port())
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	return OK


## 이번 실행에서 붙을 서버 주소.
## `--address=` 실행 인자가 있으면 그것을 쓴다 — 개발·검증용으로 로컬 서버에 붙을 유일한 방법이다.
func configured_address() -> String:
	for arg in _cmdline_args():
		if arg.begins_with("--address="):
			var value := arg.substr(10).strip_edges()
			if not value.is_empty():
				return value
	return DEFAULT_ADDRESS


## 접속 실패 사유를 꺼내고 비운다. 두 번 읽어도 같은 사유가 또 뜨지 않게 한다.
func take_last_failure() -> String:
	var reason := last_failure
	last_failure = ""
	return reason


## 접속을 끊고 오프라인으로 돌아온다. 오프라인이면 아무 일도 없다.
func leave() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	# null 이 아니라 `OfflineMultiplayerPeer` 로 되돌린다 — 오프라인 게임이 `call_local` RPC 를
	# 로컬 호출로 쓰므로(`player.gd`·`main.gd`) 피어 자리가 비면 안 된다.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.OFFLINE


## 서버가 피어 하나를 끊는다. 보낸 것이 다 나간 뒤에 닫힌다 — 끊기 직전에 보낸 사유가 그걸 탄다.
func drop_peer(peer_id: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer != null:
		peer.disconnect_peer(peer_id)


func _on_connected_to_server() -> void:
	join_succeeded.emit()


func _on_connection_failed() -> void:
	_fail("서버에 연결하지 못했습니다.")


func _on_server_disconnected() -> void:
	_fail("서버와 연결이 끊겼습니다.")


## 접속이 깨졌다. 사유를 남겨 두고 오프라인으로 돌아온다 — 사유를 먼저 적은 사람(`Lobby`가
## 받은 거절 사유 등)이 있으면 덮어쓰지 않는다.
func _fail(reason: String) -> void:
	if last_failure.is_empty():
		last_failure = reason
	var shown := last_failure
	leave()
	join_failed.emit(shown)


func _cmdline_args() -> PackedStringArray:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return args
