extends Node
## 대기실 상태 (오토로드 싱글턴 Lobby). **서버가 권위를 갖는다.**
##
## 클라이언트는 자기 선택과 준비 여부만 서버로 보내고, 서버가 전체 상태를
## 정리해 양쪽에 복제한다. 무기 "랜덤" 확정도 서버가 해야 양쪽이 같은 값을 갖는다.
##
## 무기 **동작**은 여기서 다루지 않는다 — 무기 id 문자열을 전달하는 것까지가 범위다.

signal lobby_changed
signal match_starting

const DEFAULT_MAP := "평지"

## 접속 순서. 먼저 들어온 peer가 1P(슬롯 0)다.
var order: Array = []
## peer_id -> {"weapon": String, "head": String, "color1": Color, "color2": Color}
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
		"head": GameState.HEADS[0],
		"color1": GameState.COLORS[slot % GameState.COLORS.size()],
		"color2": GameState.COLORS[8],
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


## 클라이언트가 보낸 값이 목록에 있는 값인지 확인한다.
func _sanitize(config: Dictionary, slot: int) -> Dictionary:
	var base := default_config(slot)
	var weapon: String = config.get("weapon", base["weapon"])
	var head: String = config.get("head", base["head"])
	return {
		"weapon": weapon if GameState.WEAPONS.has(weapon) else base["weapon"],
		"head": head if GameState.HEADS.has(head) else base["head"],
		"color1": config.get("color1", base["color1"]),
		"color2": config.get("color2", base["color2"]),
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
	_broadcast()
	_begin_match.rpc()


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
