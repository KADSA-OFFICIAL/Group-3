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
## peer_id -> {"weapon": String, "character": String}
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


## 맵 선택을 서버에 알린다 (클라이언트에서 호출). 맵은 둘이 공유하는 하나뿐이라
## 누가 바꾸든 양쪽에 적용된다.
func submit_map(new_map: String) -> void:
	_receive_map.rpc_id(1, new_map)


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


@rpc("any_peer", "call_remote", "reliable")
func _receive_map(new_map: String) -> void:
	if not multiplayer.is_server():
		return
	if not order.has(multiplayer.get_remote_sender_id()):
		return
	# 목록에 없는 값은 무시한다 — "랜덤"은 실제 맵이 아니지만 선택지로는 유효하다.
	if new_map != Maps.RANDOM and not Maps.has(new_map):
		return
	map_name = new_map
	_broadcast()


## 클라이언트가 보낸 값이 목록에 있는 값인지 확인한다.
func _sanitize(config: Dictionary, slot: int) -> Dictionary:
	var base := default_config(slot)
	var weapon: String = config.get("weapon", base["weapon"])
	var character: String = config.get("character", base["character"])
	return {
		"weapon": weapon if GameState.WEAPONS.has(weapon) else base["weapon"],
		"character": character if Characters.has(character) else base["character"],
	}


## "랜덤"을 실제 무기로 확정한다. 서버에서만 호출되므로 양쪽이 같은 값을 받는다.
## 클라이언트가 각자 뽑으면 서로 다른 무기가 되므로 이 호출을 클라이언트로 옮기지 말 것.
## 뽑기 자체는 무기 표가 들고 있다 — 무기 시스템 통합 가이드: docs/weapon-system.md
func _resolve_weapon(weapon: String) -> String:
	return Weapons.resolve(weapon)


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
	# 맵 "랜덤"도 여기서 확정해야 양쪽이 같은 지형을 깐다.
	map_name = Maps.resolve(map_name)
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
