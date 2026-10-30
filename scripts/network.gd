extends Node
## 온라인 대전의 접속 관리 (오토로드 싱글턴 Network, 이슈 #361).
## 연결 수립과 피어 알림만 담당하고 게임 로직은 다루지 않는다.
##
## **기기가 모드를 정한다** (`is_online_platform()`). PC 는 #320 이전처럼 **온라인 전용**이고
## (타이틀의 버튼이 `접속`), 안드로이드는 지금처럼 **한 화면 2인 오프라인 전용**이다. 화면에서
## 고르는 곳은 없다 — 사용자가 정했다.
##
## 방은 **1번 방 하나**다(포트 7777). #320 이전에는 1·2·3번 방이 포트로 갈려 있었는데
## 1번 방만 되살렸다. 관전·버전 악수(#228)도 되살리지 않았다.
## **버전 악수가 없다는 것을 기억할 것** — RPC 는 함수 이름이 아니라 번호로 오가므로,
## 서버와 클라이언트의 `@rpc` 함수 목록이 다르면 엉뚱한 함수가 불린다. 서버는
## `run-server.bat` 이 늘 `origin/main` 으로 맞춰 띄우므로, 클라이언트도 같은 빌드를 써야 한다.
##
## 서버는 `--server` 인자로만 된다. **헤드리스라는 것만으로는 서버가 되지 않는다** —
## 커밋 전 헤드리스 검증(`CLAUDE.md`)이 오프라인 게임을 그대로 돌려야 하기 때문이다.
## 띄우는 방법은 docs/server.md.

signal join_succeeded
signal join_failed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

## 서버 포트. 서버컴 Windows 방화벽에 이 포트가 UDP 로 열려 있어야 한다.
## #320 이전의 `ROOMS` 에서 1번 방 자리다 — `run-server.bat` 도 같은 값을 쓴다.
const PORT := 7777
## 방 이름. 화면과 서버 로그에 적는다. 방이 하나뿐이라 고르는 곳은 없다.
const ROOM_NAME := "1번 방"
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

## 에디터 F5 로컬 시험의 서버 주소. 이 컴퓨터에 띄운 헤드리스 서버다.
const LOCAL_TEST_ADDRESS := "127.0.0.1"
## 로컬 시험의 자식 프로세스에 띄운 쪽의 PID 를 넘기는 인자. 자식은 이것을 보고
## 띄운 쪽이 사라지면 스스로 끝난다 — 에디터 정지(F8)는 프로세스를 그냥 죽여서
## 띄운 쪽이 자식을 정리할 틈이 없다. 낡은 코드의 서버가 7777 을 쥐고 남으면
## 다음 F5 의 서버가 포트를 못 열고, 새 클라이언트가 RPC 목록이 다른 서버에 붙는다.
##
## 살아 있는지는 PID 로 묻지 않고 **심박 파일**로 본다. 윈도의 `OS.is_process_running()` 은
## 자기가 띄운 프로세스만 알아서, 자식이 부모를 물으면 늘 거짓이다(그래서 1초 만에 다 꺼졌다).
## 띄운 쪽이 `user://local_test_<PID>.alive` 에 지금 시각을 0.5초마다 적고, 자식은 그 값이
## `LOCAL_TEST_STALE_SEC` 보다 오래되면 끝난다.
const LOCAL_TEST_PARENT_ARG := "--local-test-parent="
const LOCAL_TEST_STALE_SEC := 3.0

enum Role { OFFLINE, SERVER, CLIENT }

## 이 프로세스의 역할. **`multiplayer.is_server()` 대신 이것을 본다** — 접속이 끊긴 뒤에는
## 피어가 없어 `is_server()` 가 참이 되므로(내 id 가 1) 클라이언트를 서버로 착각한다.
var role := Role.OFFLINE

## 마지막 접속 실패 사유. 타이틀 화면이 한 번 읽고 비운다 — 전투 화면에서 끊기면
## 화면이 바뀐 뒤에 사유를 보여줘야 한다.
var last_failure := ""

## 에디터 F5 로 띄운 로컬 시험인가 (`_launch_local_test()`). 참이면 접속 주소가 127.0.0.1 이다.
var _local_test := false
## 로컬 시험에서 띄운 자식 프로세스(서버·두 번째 창)의 PID. 이 창이 닫힐 때 같이 끈다.
var _local_test_pids: Array[int] = []


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int) -> void: peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void: peer_left.emit(id))
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if "--server" in _cmdline_args():
		# 포트를 못 열었는데 그냥 두면 이 프로세스는 오프라인 게임으로 살아남는다 —
		# 헤드리스라 화면도 없어서 "서버 떠 있음"으로 착각하기 쉽다. 바로 끝낸다.
		if start_server() != OK:
			get_tree().quit(1)
	_watch_local_test_parent()
	if _should_launch_local_test():
		_launch_local_test()


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


func start_server() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		push_error("서버 시작 실패 (포트 %d): %s — 이미 그 포트로 서버가 떠 있지 않은지 확인하세요." % [
			PORT, error_string(err),
		])
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.SERVER
	print("서버 시작 — %s, 포트 %d, 플레이어 %d명" % [ROOM_NAME, PORT, MAX_PLAYERS])
	return OK


func join_server(address: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
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
	if _local_test:
		return LOCAL_TEST_ADDRESS
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


## 에디터 F5 로 창 있게 띄웠는가 — 그러면 혼자서 온라인을 확인하도록 로컬 시험을 띄운다.
##
## **에디터 빌드에서만** 켜진다(`editor` 기능 태그). 내보낸 exe 는 지금처럼 팀 서버에 붙는다.
## 헤드리스(커밋 전 검증), `--server`, `--address=`(팀 서버 등 다른 곳에 붙고 싶을 때),
## `--offline`, 그리고 로컬 시험이 띄운 자식 자신은 건드리지 않는다.
func _should_launch_local_test() -> bool:
	if not OS.has_feature("editor") or not is_online_platform():
		return false
	if DisplayServer.get_name() == "headless":
		return false
	for arg in _cmdline_args():
		if arg == "--server" or arg.begins_with("--address=") or arg.begins_with(LOCAL_TEST_PARENT_ARG):
			return false
	return true


## 이 컴퓨터에 헤드리스 서버 하나와 두 번째 창을 띄운다. 두 창은 화면 좌우에 나란히 놓고,
## 둘 다 127.0.0.1 의 그 서버로 접속한다. 서버 로그는 보이지 않는다 — 서버 쪽을 봐야 하면
## `run-server.bat` 처럼 콘솔에서 `--server` 를 따로 띄운다(그러면 여기 서버는 포트를 못 열고 끝난다).
func _launch_local_test() -> void:
	_local_test = true
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var parent := LOCAL_TEST_PARENT_ARG + str(OS.get_process_id())

	# 자식이 뜨자마자 읽으므로 심박을 먼저 적는다.
	var heartbeat_path := _heartbeat_path(OS.get_process_id())
	_write_heartbeat(heartbeat_path)
	var heartbeat := Timer.new()
	heartbeat.wait_time = 0.5
	heartbeat.timeout.connect(_write_heartbeat.bind(heartbeat_path))
	add_child(heartbeat)
	heartbeat.start()

	var server := OS.create_process(exe, ["--headless", "--path", project, "--", "--server", parent])
	if server > 0:
		_local_test_pids.append(server)
	else:
		push_error("로컬 시험 서버를 띄우지 못했습니다.")

	# 화면을 반으로 갈라 왼쪽은 이 창, 오른쪽은 두 번째 창. 16:9 로 맞추되 화면보다 높지 않게.
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var width := screen.size.x / 2
	var height := mini(width * 9 / 16, screen.size.y)
	var window := get_window()
	window.title += " — 로컬 시험 (왼쪽)"
	# 에디터의 게임 탭에 들어가 있으면(`--embedded`) 이 창의 크기·자리는 에디터가 정한다.
	if not "--embedded" in OS.get_cmdline_args():
		window.size = Vector2i(width, height)
		window.position = screen.position

	var second := OS.create_process(exe, [
		"--path", project,
		"--position", "%d,%d" % [screen.position.x + width, screen.position.y],
		"--resolution", "%dx%d" % [width, height],
		"--", "--address=" + LOCAL_TEST_ADDRESS, parent,
	])
	if second > 0:
		_local_test_pids.append(second)
	else:
		push_error("로컬 시험의 두 번째 창을 띄우지 못했습니다.")
	print("로컬 시험 — 서버 PID %d, 두 번째 창 PID %d, 주소 %s" % [server, second, LOCAL_TEST_ADDRESS])


## 로컬 시험이 띄운 자식이면 띄운 쪽을 1초마다 살핀다. 사라졌으면 같이 끝난다.
func _watch_local_test_parent() -> void:
	var parent_pid := 0
	for arg in _cmdline_args():
		if arg.begins_with(LOCAL_TEST_PARENT_ARG):
			parent_pid = arg.substr(LOCAL_TEST_PARENT_ARG.length()).to_int()
	if parent_pid <= 0:
		return
	if DisplayServer.get_name() != "headless":
		get_window().title += " — 로컬 시험 (오른쪽)"
	var path := _heartbeat_path(parent_pid)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(func() -> void:
		var file := FileAccess.open(path, FileAccess.READ)
		var beat := file.get_as_text().to_float() if file != null else 0.0
		if Time.get_unix_time_from_system() - beat > LOCAL_TEST_STALE_SEC:
			get_tree().quit()
	)
	add_child(timer)
	timer.start()


func _heartbeat_path(pid: int) -> String:
	return "user://local_test_%d.alive" % pid


func _write_heartbeat(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(str(Time.get_unix_time_from_system()))


func _exit_tree() -> void:
	if not _local_test:
		return
	# 자기가 띄운 자식이라 여기서는 `is_process_running()` 이 통한다.
	for pid in _local_test_pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	DirAccess.remove_absolute(_heartbeat_path(OS.get_process_id()))


func _cmdline_args() -> PackedStringArray:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return args
