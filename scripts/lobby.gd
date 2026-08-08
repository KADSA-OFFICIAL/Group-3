extends Node
## 대기실 상태 (오토로드 싱글턴 Lobby). **서버가 권위를 갖는다.**
##
## 클라이언트는 자기 선택과 준비 여부만 서버로 보내고, 서버가 전체 상태를
## 정리해 양쪽에 복제한다. 무기 "랜덤" 확정도 서버가 해야 양쪽이 같은 값을 갖는다.
##
## 무기 **동작**은 여기서 다루지 않는다 — 무기 id 문자열을 전달하는 것까지가 범위다.

signal lobby_changed
signal match_starting
## 경기가 끝나 대기실로 돌아가라는 서버 지시.
signal match_ended

## 대기실 기본 맵. 실제 맵 목록은 Maps 표가 들고 있다.
const DEFAULT_MAP := Maps.RANDOM

## 접속 순서. 먼저 들어온 peer가 1P(슬롯 0)다.
var order: Array = []
## peer_id -> {"weapon": String, "character": String, "map": String}
##
## 맵은 **플레이어마다 하나씩** 고르고, 시작할 때 서버가 둘 중 하나를 뽑는다 (`_pick_map`).
var configs: Dictionary = {}
## peer_id -> bool
var ready_flags: Dictionary = {}
var map_name := DEFAULT_MAP


func _ready() -> void:
	Network.peer_joined.connect(_on_peer_joined)
	Network.peer_left.connect(_on_peer_left)


func default_config(slot: int) -> Dictionary:
	return {
		"weapon": Weapons.RANDOM,
		"character": Characters.id_at(slot),
		"map": Maps.RANDOM,
	}


func config_for(peer_id: int) -> Dictionary:
	return configs.get(peer_id, default_config(maxi(order.find(peer_id), 0)))


func slot_of(peer_id: int) -> int:
	return order.find(peer_id)


func is_ready(peer_id: int) -> bool:
	return ready_flags.get(peer_id, false)


## 내 선택을 서버에 알린다 (클라이언트에서 호출).
func submit_config(config: Dictionary) -> void:
	_receive_config.rpc_id(1, config)


## 내 준비 여부를 서버에 알린다 (클라이언트에서 호출).
func submit_ready(flag: bool) -> void:
	_receive_ready.rpc_id(1, flag)


## 내 맵 선택을 서버에 알린다 (클라이언트에서 호출). 상대 선택은 건드리지 않는다.
func submit_map(new_map: String) -> void:
	_receive_map.rpc_id(1, new_map)


## 대기실 상태를 서버에 다시 청한다 (클라이언트에서 호출).
##
## 접속 순간 서버가 보내는 브로드캐스트 한 번만 믿으면, 그것을 놓쳤을 때 클라이언트가
## 옛 상태에 갇힌다 — order 에 내 peer id 가 없으니 자기 패널을 못 찾아 대기실의
## 모든 조작이 죽고, 다시 받을 방법도 없다(이슈 #93). 그래서 받는 쪽에서도 청한다.
## 서버 판정은 Network.is_server 로 한다 — 접속이 끊긴 뒤에는 peer 가 없어
## multiplayer.is_server() 가 참이 되어(내 id 가 1) 클라이언트를 서버로 착각한다.
func request_state() -> void:
	if Network.is_server:
		return
	_request_state.rpc_id(1)


## 들고 있던 대기실 상태를 버린다 (클라이언트에서 호출).
##
## 옛 접속의 order 가 남아 있으면 새 접속에서 내 새 peer id 가 목록에 없는 채로
## "2명이 있는데 그중에 나는 없는" 상태가 된다. 그 상태는 화면상 정상과 구별되지 않는다.
func reset() -> void:
	if Network.is_server:
		return
	order = []
	configs = {}
	ready_flags = {}
	map_name = DEFAULT_MAP
	lobby_changed.emit()


## 이 플레이어가 고른 맵. 아직 없으면 슬롯 기본값.
## 표에서 꺼낸 값은 Variant라 명시 타입으로 받는다.
func map_of(peer_id: int) -> String:
	var picked: String = config_for(peer_id).get("map", DEFAULT_MAP)
	return picked


## 이 플레이어가 고른 무기. 시작 전에는 "랜덤"일 수 있다.
func weapon_of(peer_id: int) -> String:
	var picked: String = config_for(peer_id).get("weapon", Weapons.RANDOM)
	return picked


# ─────────────────────────── 서버 전용 ───────────────────────────

func _on_peer_joined(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not order.has(peer_id):
		order.append(peer_id)
	configs[peer_id] = default_config(order.find(peer_id))
	ready_flags[peer_id] = false
	_broadcast()


func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	order.erase(peer_id)
	configs.erase(peer_id)
	ready_flags.erase(peer_id)
	# 인원이 빠지면 남은 사람의 준비도 해제한다 — 혼자 준비된 채로 남지 않도록
	for id in ready_flags:
		ready_flags[id] = false
	_broadcast()


@rpc("any_peer", "call_remote", "reliable")
func _receive_config(config: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not order.has(sender):
		return
	configs[sender] = _sanitize(config, order.find(sender))
	_broadcast()


@rpc("any_peer", "call_remote", "reliable")
func _receive_ready(flag: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not order.has(sender):
		return
	ready_flags[sender] = flag
	_broadcast()
	_check_start()


## 청한 피어에게만 지금 상태를 보낸다. 상태를 바꾸지 않으므로 몇 번을 청해도 안전하다.
@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if not multiplayer.is_server():
		return
	_receive_lobby.rpc_id(multiplayer.get_remote_sender_id(), order, configs, ready_flags, map_name)


## 보낸 사람의 맵 선택만 바꾼다. 상대 것은 건드리지 않는다.
@rpc("any_peer", "call_remote", "reliable")
func _receive_map(new_map: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not order.has(sender):
		return
	var config: Dictionary = configs.get(sender, default_config(order.find(sender)))
	config["map"] = new_map
	configs[sender] = _sanitize(config, order.find(sender))
	_broadcast()


## 클라이언트가 보낸 값이 목록에 있는 값인지 확인한다.
func _sanitize(config: Dictionary, slot: int) -> Dictionary:
	var base := default_config(slot)
	var weapon: String = config.get("weapon", base["weapon"])
	var character: String = config.get("character", base["character"])
	var map: String = config.get("map", base["map"])
	return {
		"weapon": weapon if GameState.WEAPONS.has(weapon) else base["weapon"],
		"character": character if Characters.has(character) else base["character"],
		# "랜덤"은 실제 맵이 아니지만 선택지로는 유효하다.
		"map": map if GameState.MAPS.has(map) else base["map"],
	}


## "랜덤"을 실제 무기로 확정한다. 서버에서만 호출되므로 양쪽이 같은 값을 받는다.
## 클라이언트가 각자 뽑으면 서로 다른 무기가 되므로 이 호출을 클라이언트로 옮기지 말 것.
## 뽑기 자체는 무기 표가 들고 있다 — 무기 시스템 통합 가이드: docs/weapon-system.md
func _resolve_weapon(weapon: String) -> String:
	return Weapons.resolve(weapon)


## 둘이 고른 맵 중 하나를 뽑는다. **서버에서만 호출한다.**
##
## 각자의 "랜덤"을 먼저 실제 맵으로 확정한 뒤에 뽑는다 — 순서를 바꾸면 "랜덤"이
## 그대로 후보가 되어 한 번 더 뽑기가 일어난다.
func _pick_map() -> String:
	var picks: Array[String] = []
	for peer_id in order:
		picks.append(Maps.resolve(map_of(peer_id)))
	if picks.is_empty():
		return Maps.resolve(Maps.RANDOM)
	return picks.pick_random()


func _check_start() -> void:
	if order.size() < 2:
		return
	for peer_id in order:
		if not ready_flags.get(peer_id, false):
			return
	for peer_id in order:
		var config: Dictionary = configs[peer_id]
		config["weapon"] = _resolve_weapon(config["weapon"])
		configs[peer_id] = config
	# 맵도 여기서 확정해야 양쪽이 같은 지형을 깐다.
	map_name = _pick_map()
	_broadcast()
	_begin_match.rpc()


## 경기가 끝나면 준비를 풀고 양쪽을 대기실로 돌려보낸다 (서버에서만 호출).
## 준비를 풀지 않으면 대기실에 도착하자마자 다시 시작해 버린다.
func server_end_match() -> void:
	if not multiplayer.is_server():
		return
	for peer_id in ready_flags:
		ready_flags[peer_id] = false
	_broadcast()
	_end_match.rpc()


func _broadcast() -> void:
	_receive_lobby.rpc(order, configs, ready_flags, map_name)
	lobby_changed.emit()


# ─────────────────────────── 클라이언트 전용 ───────────────────────────

@rpc("authority", "call_remote", "reliable")
func _receive_lobby(new_order: Array, new_configs: Dictionary, new_ready: Dictionary, new_map: String) -> void:
	order = new_order
	configs = new_configs
	ready_flags = new_ready
	map_name = new_map
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _begin_match() -> void:
	match_starting.emit()


@rpc("authority", "call_remote", "reliable")
func _end_match() -> void:
	match_ended.emit()
