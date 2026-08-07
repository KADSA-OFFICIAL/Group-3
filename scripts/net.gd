extends Node
## 온라인 연결 관리 (오토로드 싱글톤 Net)
##
## 리슨 서버(호스트가 같이 플레이) / 전용 서버 / 클라이언트를 모두 같은 코드 경로로 다룬다.
## 개발용 로컬 2인 모드(LOCAL_2P)는 피어를 만들지 않고 같은 인터페이스만 흉내낸다.

signal players_changed()
signal join_failed(reason: String)
signal server_closed()
signal game_starting()

## 포트 번호는 팀에서 정해지지 않았다. 기본값을 두지 않고 항상 명시적으로 받는다.
const MAX_CLIENTS := 2
const SLOTS := [1, 2]

enum Mode { NONE, LOCAL_2P, ONLINE }
## 서버가 들고 있는 진행 단계. 두 명이 다 붙으면 선택 창으로, 둘 다 준비하면 전투로 넘긴다.
enum Phase { LOBBY, SELECT, MATCH }

var mode: Mode = Mode.NONE
var phase: Phase = Phase.LOBBY
var dedicated := false          ## 이 인스턴스가 전용 서버인가 (여기서는 아무도 플레이하지 않음)
var host_is_dedicated := false  ## 접속한 서버가 전용 서버인가. 클라이언트도 알아야 방장을 정할 수 있다.
var players := {}               ## peer_id -> {"slot": int, "ready": bool, "config": Dictionary}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_check_dedicated_launch()


## `godot --headless -- --server --port=<포트>` 로 전용 서버 실행.
## 포트는 필수. 기본값을 임의로 정해두지 않는다.
func _check_dedicated_launch() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--server"):
		return
	var port := 0
	for arg: String in args:
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
	if port <= 0:
		push_error("전용 서버를 켜려면 --port=<포트번호> 를 함께 지정해야 합니다.")
		get_tree().quit(1)
		return
	var err := host_dedicated(port)
	if err != "":
		push_error(err)
		get_tree().quit(1)
	else:
		print("전용 서버 실행 중 — 포트 %d" % port)


# --- 연결 시작/종료 ---------------------------------------------------------

## 개발·테스트용. 한 기기에서 두 명이 플레이한다 (네트워크 없음).
func start_local_2p() -> void:
	leave()
	mode = Mode.LOCAL_2P
	phase = Phase.SELECT
	players = {
		1: {"slot": 1, "ready": true, "config": GameState.default_config(1)},
		2: {"slot": 2, "ready": true, "config": GameState.default_config(2)},
	}
	players_changed.emit()


## 이 기기가 서버 겸 플레이어가 된다.
func host(port: int) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return "포트 %d 를 열 수 없습니다 (오류 %d)" % [port, err]
	multiplayer.multiplayer_peer = peer
	mode = Mode.ONLINE
	phase = Phase.LOBBY
	dedicated = false
	host_is_dedicated = false
	players = {1: {"slot": 1, "ready": false, "config": GameState.default_config(1)}}
	players_changed.emit()
	return ""


## 플레이어 없이 서버만 돌린다. `godot --headless -- --server --port=<포트>` 로 실행.
func host_dedicated(port: int) -> String:
	var err := host(port)
	if err != "":
		return err
	dedicated = true
	host_is_dedicated = true
	players.clear()
	players_changed.emit()
	return ""


func join(address: String, port: int) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return "%s:%d 에 접속할 수 없습니다 (오류 %d)" % [address, port, err]
	multiplayer.multiplayer_peer = peer
	mode = Mode.ONLINE
	dedicated = false
	host_is_dedicated = false
	return ""


func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	mode = Mode.NONE
	phase = Phase.LOBBY
	dedicated = false
	host_is_dedicated = false
	players.clear()


# --- 조회 -------------------------------------------------------------------

func is_online() -> bool:
	return mode == Mode.ONLINE


## ENet 서버를 돌리고 있는가. 실제 패킷 중계 권한.
func is_server() -> bool:
	return mode != Mode.ONLINE or multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if mode == Mode.ONLINE else 1


## 이 기기가 조종하는 슬롯. 로컬 2인/전용 서버에서는 0 (조종 대상 없음 또는 둘 다).
func my_slot() -> int:
	if mode != Mode.ONLINE:
		return 0
	var me: int = my_id()
	return players[me]["slot"] if players.has(me) else 0


func peer_for_slot(slot: int) -> int:
	for id: int in players:
		if players[id]["slot"] == slot:
			return id
	return 0


func slot_filled(slot: int) -> bool:
	return peer_for_slot(slot) != 0


func both_connected() -> bool:
	return slot_filled(1) and slot_filled(2)


func everyone_ready() -> bool:
	if mode == Mode.LOCAL_2P:
		return true
	for slot: int in SLOTS:
		var id: int = peer_for_slot(slot)
		if id == 0 or not players[id]["ready"]:
			return false
	return true


## 내가 준비를 눌렀는가.
func am_i_ready() -> bool:
	var me: int = my_id()
	return players.has(me) and players[me]["ready"]


# --- 피어 이벤트 ------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# 정원 초과는 서버가 바로 끊는다.
	if _next_free_slot() == 0:
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(id)
	# 한 명이 나가면 처음 단계로 되돌린다. 남은 사람의 준비 상태도 푼다.
	phase = Phase.LOBBY
	for other: int in players:
		players[other]["ready"] = false
	_broadcast_players()


func _on_connected_to_server() -> void:
	_request_join.rpc_id(1, GameState.local_config)


func _on_connection_failed() -> void:
	leave()
	join_failed.emit("서버에 연결하지 못했습니다. 주소와 포트를 확인하세요.")


func _on_server_disconnected() -> void:
	leave()
	server_closed.emit()


func _next_free_slot() -> int:
	for slot: int in SLOTS:
		if not slot_filled(slot):
			return slot
	return 0


# --- 동기화 RPC -------------------------------------------------------------

@rpc("any_peer", "reliable")
func _request_join(config: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id: int = multiplayer.get_remote_sender_id()
	var slot: int = _next_free_slot()
	if slot == 0:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = {"slot": slot, "ready": false, "config": config}
	_broadcast_players()


func _broadcast_players() -> void:
	# 마지막 상대가 막 끊긴 순간에 rpc 를 쏘면 ENet 이 "max channels: 0" 오류를 낸다.
	# 보낼 상대가 없으면 로컬에서만 반영한다 (리슨 서버는 자기 UI 갱신이 필요하다).
	if multiplayer.get_peers().is_empty():
		_receive_players(players, dedicated)
	else:
		_receive_players.rpc(players, dedicated)
	_advance_if_possible()


## 서버 전용. 방장 없이 접속·준비 상태만 보고 다음 단계로 넘긴다.
func _advance_if_possible() -> void:
	if not multiplayer.is_server():
		return
	if phase == Phase.LOBBY and both_connected():
		phase = Phase.SELECT
		_goto_scene.rpc("res://scenes/select.tscn")
	elif phase == Phase.SELECT and both_connected() and everyone_ready():
		phase = Phase.MATCH
		_apply_match.rpc(_pick_map(), players)


## 맵은 항상 랜덤. 아직 안 만든 맵은 뽑히지 않는다.
func _pick_map() -> String:
	return GameState.IMPLEMENTED_MAPS.pick_random()


@rpc("authority", "call_local", "reliable")
func _receive_players(list: Dictionary, server_dedicated: bool) -> void:
	players = list
	host_is_dedicated = server_dedicated
	players_changed.emit()


## 내 캐릭터 설정이 바뀌었을 때 호출. 서버가 받아서 전원에게 다시 뿌린다.
func set_my_config(config: Dictionary) -> void:
	GameState.local_config = config
	if mode != Mode.ONLINE:
		return
	_submit_config.rpc_id(1, config)


@rpc("any_peer", "reliable")
func _submit_config(config: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id: int = multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id]["config"] = config
		_broadcast_players()


func set_my_ready(value: bool) -> void:
	if mode != Mode.ONLINE:
		return
	_submit_ready.rpc_id(1, value)


@rpc("any_peer", "reliable")
func _submit_ready(value: bool) -> void:
	if not multiplayer.is_server():
		return
	var id: int = multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id]["ready"] = value
		_broadcast_players()


# --- 화면 전환 --------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _goto_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)


## 로컬 2인 모드 전용. 온라인에서는 양쪽이 준비를 누르면 서버가 알아서 시작한다.
func start_local_match() -> void:
	if mode != Mode.LOCAL_2P:
		return
	_apply_match(_pick_map(), players)


@rpc("authority", "call_local", "reliable")
func _apply_match(map_name: String, list: Dictionary) -> void:
	players = list
	GameState.map_name = map_name
	GameState.configs.clear()
	for id: int in players:
		GameState.configs[players[id]["slot"]] = players[id]["config"]
	game_starting.emit()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
