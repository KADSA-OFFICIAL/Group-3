extends Node
## 온라인 대기실 상태 (오토로드 싱글턴 Lobby, 이슈 #361). **서버가 권위를 갖는다.**
##
## 클라이언트는 자기 캐릭터와 준비 여부만 서버로 보내고, 서버가 전체 상태를 정리해
## 양쪽에 복제한다. 오프라인에서는 쓰이지 않는다 — 오프라인 선택값은 `GameState`에 있다.
##
## **자리는 접속한 순서다.** 먼저 붙은 피어가 1P(자리 0)다. 자리가 둘 다 찼거나 경기 중이면
## 사유를 알리고 끊는다 — 관전(#167)은 되살리지 않았으므로 셋째 피어가 머물 곳이 없다.
##
## **맵도 무기도 여기서 다루지 않는다** — 둘 다 라운드가 열릴 때 전투 화면의 서버가 뽑는다.

signal lobby_changed
## 둘 다 준비했다 — 전투 화면으로 가라는 서버 지시.
signal match_starting
## 경기가 끝났다 — 대기실로 돌아가라는 서버 지시. 상대가 나가서 접힌 경기면 사유가 실려 온다.
signal match_ended(reason: String)
## **자리를 가진 피어가** 나갔다 (서버). 거절당해 끊기는 피어는 여기 오지 않는다 —
## `Network.peer_left` 를 그대로 보면 셋째 피어를 돌려보내는 것만으로 진행 중인 경기가 접힌다.
signal player_left(peer_id: int)

## 들어갈 자리가 없는 피어를 사유를 보낸 뒤 이만큼 있다가 끊는다(초).
const REJECT_DROP_DELAY := 0.5

## 접속 순서. 먼저 들어온 peer가 1P(자리 0)다.
var order: Array = []
## peer_id -> {"character": String}
var configs: Dictionary = {}
## peer_id -> bool
var ready_flags: Dictionary = {}
## 지금 경기가 진행 중인가. 경기 중에 들어온 피어는 끼울 곳이 없어 돌려보낸다.
var in_match := false
## 대기실에 띄울 마지막 안내 (상대가 나가 경기가 접혔다 등). 대기실 화면이 한 번 읽고 비운다.
var notice := ""

## **서버 전용.** 서버의 전투 화면이 새 경기를 받을 수 있는가. 경기가 끝나면 서버는 그 씬을
## 잠깐 멈췄다가 다시 여는데(`main.gd`의 `_end_online_match`), **그 사이에 둘이 다시 준비하면**
## 클라이언트의 준비 신호(`_notify_ready`)가 곧 버려질 옛 씬으로 가서 새 씬이 영영 기다린다.
## 새 씬이 열리면서 `server_arena_ready()`로 켠다.
var _arena_ready := false

## **서버 전용.** 전투 화면 준비를 알린 피어. 젤리 위치처럼 매 프레임 가는 것은 여기에만
## 보낸다 — 대기실에 있는 피어에게 보내면 그쪽에는 노드가 없어 "Node not found"가 쌓인다.
var viewers: Array = []


func _ready() -> void:
	Network.peer_joined.connect(_on_peer_joined)
	Network.peer_left.connect(_on_peer_left)
	Network.join_failed.connect(func(_reason: String) -> void: reset())


func default_config(slot: int) -> Dictionary:
	return {"character": Characters.id_at(slot)}


func config_for(peer_id: int) -> Dictionary:
	return configs.get(peer_id, default_config(maxi(order.find(peer_id), 0)))


func slot_of(peer_id: int) -> int:
	return order.find(peer_id)


## 이 피어가 맡은 플레이어 번호 (1P는 1). 자리가 없으면 0.
func player_id_of(peer_id: int) -> int:
	var slot := slot_of(peer_id)
	return GameState.id_at(slot) if slot >= 0 else 0


func is_ready(peer_id: int) -> bool:
	return ready_flags.get(peer_id, false)


## 이 기기의 플레이어 번호. 아직 자리를 못 받았으면 0.
func my_player_id() -> int:
	return player_id_of(multiplayer.get_unique_id())


## 전투 노드를 이 피어에게 보여줄 것인가 (`MultiplayerSynchronizer` 가시성 필터).
##
## 필터는 **거부권만** 있고 허용을 주지 못한다. `public_visibility` 를 끄면 필터가 참이어도
## 아무에게도 안 보인다(#167에서 투사체가 통째로 사라진 원인이다) — 켜 둔 채로 걸 것.
func can_view(peer_id: int) -> bool:
	return viewers.has(peer_id)


## 들고 있던 대기실 상태를 버린다 (클라이언트). 옛 접속의 order 가 남아 있으면 새 접속에서
## 내 새 peer id 가 목록에 없는 채로 화면이 통째로 잠긴다 (#93).
func reset() -> void:
	if Network.is_server():
		return
	order = []
	configs = {}
	ready_flags = {}
	in_match = false
	lobby_changed.emit()


# ─────────────────────────── 클라이언트 → 서버 ───────────────────────────

func submit_config(config: Dictionary) -> void:
	_receive_config.rpc_id(1, config)


func submit_ready(flag: bool) -> void:
	_receive_ready.rpc_id(1, flag)


## 지금 상태를 다시 청한다. 접속 순간의 방송을 대기실 화면이 열리기 전에 받았을 수도,
## 놓쳤을 수도 있으므로 화면이 열릴 때 한 번 부른다. 상태를 바꾸지 않아 몇 번이든 안전하다.
func request_state() -> void:
	_request_state.rpc_id(1)


# ─────────────────────────── 서버 전용 ───────────────────────────

func _on_peer_joined(peer_id: int) -> void:
	if not Network.is_server():
		return
	var reason := ""
	if in_match:
		reason = "경기가 진행 중입니다. 끝난 뒤에 다시 접속하세요."
	elif order.size() >= Network.MAX_PLAYERS:
		reason = "자리가 꽉 찼습니다 (1 VS 1)."
	if reason != "":
		print("피어 %d 거절 — %s" % [peer_id, reason])
		# 사유를 먼저 보내고 **조금 뒤에** 끊는다 — 붙자마자 끊으면 사유가 도착하기 전에
		# 연결이 사라져, 받는 쪽에는 "서버와 연결이 끊겼습니다"만 남는다.
		_rejected.rpc_id(peer_id, reason)
		get_tree().create_timer(REJECT_DROP_DELAY).timeout.connect(Network.drop_peer.bind(peer_id))
		return
	order.append(peer_id)
	configs[peer_id] = default_config(order.find(peer_id))
	ready_flags[peer_id] = false
	print("피어 %d 입장 (%dP)" % [peer_id, order.find(peer_id) + 1])
	_broadcast()


func _on_peer_left(peer_id: int) -> void:
	if not Network.is_server():
		return
	viewers.erase(peer_id)
	if not order.has(peer_id):
		return
	order.erase(peer_id)
	configs.erase(peer_id)
	ready_flags.erase(peer_id)
	# 남은 사람이 혼자 준비된 채로 남지 않게 한다. 자리 번호도 하나씩 당겨진다 —
	# 2P 혼자 남으면 다음 상대를 기다리는 1P가 된다.
	for id in ready_flags:
		ready_flags[id] = false
	print("피어 %d 퇴장 (남은 %d명)" % [peer_id, order.size()])
	# 경기 중이었으면 판을 접는 것은 전투 화면(`main.gd`)이 한다 — 여기서 `in_match`를
	# 내리면 그쪽이 경기 중이었는지 알 수 없다.
	_broadcast()
	player_left.emit(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if not Network.is_server():
		return
	_send_state_to(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _receive_config(config: Dictionary) -> void:
	if not Network.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not order.has(sender) or in_match:
		return
	configs[sender] = _sanitize(config, order.find(sender))
	_broadcast()


@rpc("any_peer", "call_remote", "reliable")
func _receive_ready(flag: bool) -> void:
	if not Network.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not order.has(sender) or in_match:
		return
	ready_flags[sender] = flag
	_broadcast()
	_check_start()


## 클라이언트가 보낸 값이 목록에 있는 값인지 확인한다.
func _sanitize(config: Dictionary, slot: int) -> Dictionary:
	var base := default_config(slot)
	var character: String = config.get("character", base["character"])
	return {"character": character if Characters.has(character) else base["character"]}


func _check_start() -> void:
	if in_match or not _arena_ready or order.size() < Network.MAX_PLAYERS:
		return
	for peer_id in order:
		if not ready_flags.get(peer_id, false):
			return
	# 경기 중임을 먼저 켜고 알린다 — 이 뒤에 붙는 피어는 끼울 곳이 없다.
	in_match = true
	print("경기 시작 — %s" % [order])
	_broadcast()
	_begin_match.rpc()


## 전투 화면 준비를 알린 피어를 등록한다 (`main.gd` 가 부른다).
func server_add_viewer(peer_id: int) -> void:
	if Network.is_server() and not viewers.has(peer_id):
		viewers.append(peer_id)


## 서버의 전투 화면이 새로 열려 경기를 받을 수 있다 (서버 `main.gd` 의 `_ready`). 그 사이에
## 둘 다 준비해 두었으면 여기서 바로 시작한다.
func server_arena_ready() -> void:
	if not Network.is_server():
		return
	_arena_ready = true
	_check_start()


## 경기가 끝나 모두 대기실로 돌려보낸다 (서버 `main.gd` 가 부른다).
## 준비를 풀지 않으면 대기실에 도착하자마자 다시 시작해 버린다.
func server_end_match(reason := "") -> void:
	if not Network.is_server():
		return
	viewers.clear()
	_arena_ready = false
	for peer_id in ready_flags:
		ready_flags[peer_id] = false
	in_match = false
	print("경기 종료%s" % ("" if reason.is_empty() else " — " + reason))
	_broadcast()
	_end_match.rpc(reason)


func _send_state_to(peer_id: int) -> void:
	_receive_lobby.rpc_id(peer_id, order, configs, ready_flags, in_match)


func _broadcast() -> void:
	_receive_lobby.rpc(order, configs, ready_flags, in_match)
	lobby_changed.emit()


# ─────────────────────────── 서버 → 클라이언트 ───────────────────────────

@rpc("authority", "call_remote", "reliable")
func _receive_lobby(new_order: Array, new_configs: Dictionary, new_ready: Dictionary,
		new_in_match: bool) -> void:
	order = new_order
	configs = new_configs
	ready_flags = new_ready
	in_match = new_in_match
	lobby_changed.emit()


## 들어갈 자리가 없다는 답. 곧 연결이 끊기므로 사유만 남겨 둔다 — 끊김을 받은 화면이
## "서버와 연결이 끊겼습니다" 대신 이 사유를 보여준다.
@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	Network.last_failure = reason


@rpc("authority", "call_remote", "reliable")
func _begin_match() -> void:
	match_starting.emit()


@rpc("authority", "call_remote", "reliable")
func _end_match(reason: String) -> void:
	notice = reason
	match_ended.emit(reason)
