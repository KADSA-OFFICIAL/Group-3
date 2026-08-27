extends Node
## 대기실 상태 (오토로드 싱글턴 Lobby). **서버가 권위를 갖는다.**
##
## 클라이언트는 자기 선택과 준비 여부만 서버로 보내고, 서버가 전체 상태를
## 정리해 양쪽에 복제한다. 맵 "랜덤" 확정도 서버가 해야 양쪽이 같은 지형을 깐다.
##
## **역할(플레이어·관전) 배정도 여기가 한다**(이슈 #167). 접속만으로는 자리가 생기지 않고,
## 클라이언트가 `submit_role()` 로 알려야 서버가 order(플레이어) 또는 observers(관전)에 넣는다.
## 정원이 차면 배정하지 않고 사유를 돌려준다 — 조용히 잠기는 상태를 만들지 않기 위해서다.
## 어느 역할로 신고할지는 **실행 파일이 정한다**(`is_observer_build()`, 이슈 #180).
##
## **무기는 여기서 다루지 않는다**(#205). 라운드가 시작될 때마다 전투 화면에서 고르므로
## 대기실 설정에는 무기 항목 자체가 없다 — 무기 선택은 `main.gd`의 무기 선택 단계에 있다.

signal lobby_changed
signal match_starting
## 경기가 끝나 대기실로 돌아가라는 서버 지시.
signal match_ended
## 원한 역할로 들어갈 수 없다는 서버의 답 (자리가 꽉 찼을 때).
signal role_rejected(reason: String)

## 역할. 접속 화면에서 고르고 접속 직후 서버에 알린다 (이슈 #167).
const ROLE_PLAYER := "player"
const ROLE_OBSERVER := "observer"

## 접속 순서. 먼저 들어온 peer가 1P(슬롯 0)다.
##
## **접속만으로는 여기에 들어오지 않는다** — 클라이언트가 `submit_role()`로 플레이어라고
## 알려야 서버가 자리를 준다. 관전자는 여기가 아니라 observers 에 들어간다.
var order: Array = []
## 관전자 peer 목록. 플레이어 자리를 차지하지 않고 대기실·경기를 보기만 한다.
var observers: Array = []
## peer_id -> {"character": String}
##
## **맵은 여기 없다** (요청). 대기실에서 사람마다 하나씩 고르던 것을 없앴고, 지금은
## 라운드가 열릴 때마다 전투 화면의 서버가 새로 뽑는다 (`main.gd`의 `_start_round`).
## 그래서 대기실은 맵에 대해 아무것도 알지 못하고, 알 필요도 없다.
var configs: Dictionary = {}
## peer_id -> bool
var ready_flags: Dictionary = {}
## 지금 경기가 진행 중인가. 경기 중에 들어온 관전자는 이 값을 보고
## "다음 경기부터 볼 수 있다"고 안내받는다 (경기 도중 난입은 이슈 #167의 non-goal).
var in_match := false

## 이 기기의 역할 (**클라이언트 쪽 의사**). 접속 후 서버에 알린다.
## 실제 배정 결과는 order·observers 로 확인한다 — 서버가 정원을 보고 거절할 수 있다.
##
## **고르는 값이 아니라 실행 파일이 정하는 값이다**(이슈 #180) — `_ready()`에서 한 번 정해지고
## 그 뒤로 바뀌지 않는다. reset() 도 이 값을 지우지 않는다.
var my_role := ROLE_PLAYER


func _ready() -> void:
	# 관전 빌드는 관전으로만 접속한다. 화면에 고르는 곳이 없다.
	my_role = ROLE_OBSERVER if is_observer_build() else ROLE_PLAYER
	Network.peer_left.connect(_on_peer_left)


## 이 실행 파일이 관전 전용 빌드인가 (이슈 #180).
##
## 관전 빌드는 export 프리셋에 `observer` 기능 태그가 박혀 있다 — 실행 파일을 나누면
## 기기마다 역할을 고르는 절차가 없어지고 잘못 고를 일도 없다. 만드는 방법은 docs/build.md.
##
## `--observe` 인자도 같은 효과를 낸다. 빌드 없이(에디터·헤드리스) 관전을 확인할 길이
## 필요해서다 — 검증용 계측이 아니라 정식 경로다.
func is_observer_build() -> bool:
	if OS.has_feature("observer"):
		return true
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return "--observe" in args


func default_config(slot: int) -> Dictionary:
	return {
		"character": Characters.id_at(slot),
	}


func config_for(peer_id: int) -> Dictionary:
	return configs.get(peer_id, default_config(maxi(order.find(peer_id), 0)))


func slot_of(peer_id: int) -> int:
	return order.find(peer_id)


func is_ready(peer_id: int) -> bool:
	return ready_flags.get(peer_id, false)


## 관전자인가. 서버가 배정한 결과이므로 클라이언트도 복제된 목록으로 판단할 수 있다.
func is_observer(peer_id: int) -> bool:
	return observers.has(peer_id)


## 서버가 나를 어느 쪽으로든 등록했는가.
## 이게 false 인 동안에는 대기실에서 아무 조작도 통하지 않는다 — 화면은 그 사실을 알려야 한다.
func knows_me() -> bool:
	var me := multiplayer.get_unique_id()
	return slot_of(me) >= 0 or is_observer(me)


## 관전 자리가 남았는가. 플레이어 자리를 거절당한 클라이언트가 관전으로 바꿀 수 있는지 판단한다.
func observer_slots_open() -> bool:
	return observers.size() < Network.MAX_OBSERVERS


## 내 선택을 서버에 알린다 (클라이언트에서 호출).
func submit_config(config: Dictionary) -> void:
	_receive_config.rpc_id(1, config)


## 내 준비 여부를 서버에 알린다 (클라이언트에서 호출).
func submit_ready(flag: bool) -> void:
	_receive_ready.rpc_id(1, flag)


## 내 역할을 서버에 알리고 지금 상태를 받아온다 (클라이언트에서 호출).
##
## **자리 배정과 상태 요청을 한 RPC로 합쳐 둔 것이 중요하다.** 접속 순간 서버가 보내는
## 브로드캐스트 한 번만 믿으면, 그것을 놓쳤을 때 클라이언트가 옛 상태에 갇힌다 — order 에
## 내 peer id 가 없으니 자기 패널을 못 찾아 대기실의 모든 조작이 죽고, 다시 받을 방법도
## 없다(이슈 #93). 이 호출은 상태를 바꾸지 않거나(이미 등록된 경우) 없던 자리를 만들 뿐이라
## **몇 번을 되풀이해도 안전하다** — 답이 유실되면 화면이 다시 부른다.
##
## 서버 판정은 Network.is_server 로 한다 — 접속이 끊긴 뒤에는 peer 가 없어
## multiplayer.is_server() 가 참이 되어(내 id 가 1) 클라이언트를 서버로 착각한다.
func submit_role(role: String) -> void:
	if Network.is_server:
		return
	my_role = role if role == ROLE_OBSERVER else ROLE_PLAYER
	_receive_role.rpc_id(1, my_role)


## 들고 있던 대기실 상태를 버린다 (클라이언트에서 호출).
##
## 옛 접속의 order 가 남아 있으면 새 접속에서 내 새 peer id 가 목록에 없는 채로
## "2명이 있는데 그중에 나는 없는" 상태가 된다. 그 상태는 화면상 정상과 구별되지 않는다.
func reset() -> void:
	if Network.is_server:
		return
	order = []
	observers = []
	configs = {}
	ready_flags = {}
	in_match = false
	lobby_changed.emit()


# ─────────────────────── 전투 화면에 있는 피어 (서버 전용) ───────────────────────
## **복제하지 않는다.** 서버가 전투 노드의 RPC를 누구에게 보낼지 정하는 데만 쓴다.
##
## 관전이 생기면서 "접속해 있지만 전투 화면 밖에 있는 피어"가 정상 상태가 되었다(이슈 #167) —
## 경기 중에 들어와 다음 경기를 기다리는 관전자, 자리를 거절당해 대기실에 남은 클라이언트가
## 그렇다. 그 피어에게 Player 노드의 RPC를 보내면 그쪽에는 그 노드가 없어
## "Node not found" 오류가 **초당 60번** 쌓인다. 그래서 위치 복제는 이 목록으로만 보낸다.
var viewers: Array = []


## 이 피어에게 전투 노드를 보여줄 것인가. **`MultiplayerSynchronizer` 가시성 필터로 쓴다**
## (이슈 #182) — 플레이어·투사체의 `Sync` 노드에 서버가 이 함수를 걸어 둔다.
##
## 가시성으로 거르면 두 가지가 같이 해결된다.
## 1. 대기실에 앉아 있는 피어에게 스폰이 가지 않는다 — 그쪽에는 씬이 없어 오류만 쌓였다.
## 2. **뒤늦게 viewer 가 된 피어에게 그때 스폰이 나간다** — 경기 도중에 들어온 관전자가
##    이미 스폰된 플레이어를 받는 유일한 경로다.
##
## 필터는 **거부권만** 있고 허용을 주지 못한다. `public_visibility` 를 끄면 필터가 참이어도
## 아무에게도 안 보인다(이슈 #167에서 투사체가 통째로 사라진 원인이다) — 켜 둔 채로 걸 것.
func can_view(peer_id: int) -> bool:
	return viewers.has(peer_id)


## 전투 화면 준비를 알린 피어를 등록한다 (main.gd 가 부른다).
func server_add_viewer(peer_id: int) -> void:
	if not multiplayer.is_server() or viewers.has(peer_id):
		return
	viewers.append(peer_id)


func server_remove_viewer(peer_id: int) -> void:
	viewers.erase(peer_id)


## 경기가 끝나 모두 대기실로 돌아갈 때 비운다. 안 비우면 대기실에 있는 피어에게
## 다음 경기의 첫 프레임까지 위치가 날아간다.
func server_clear_viewers() -> void:
	viewers.clear()


# ─────────────────────────── 서버 전용 ───────────────────────────

## 접속한 피어에게 역할을 배정한다. 정원이 차면 사유를 알려 주고 배정하지 않는다.
##
## 자리 배정을 **접속이 아니라 이 RPC**에서 하는 이유는 관전자와 플레이어를 구분해야 하기
## 때문이다 — 접속 시점에는 서버가 어느 쪽인지 알 수 없다. 그래서 등록되지 않은 피어가
## 잠깐 존재하고, 대기실 화면은 그동안 "정보를 받는 중"으로 잠긴다.
@rpc("any_peer", "call_remote", "reliable")
func _receive_role(role: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var changed := false

	if role == ROLE_OBSERVER:
		if not observers.has(sender):
			if observers.size() >= Network.MAX_OBSERVERS:
				# 상태를 먼저 보낸다 — 거절 안내를 띄우는 화면이 방 구성을 알아야 한다.
				_send_state_to(sender)
				_role_rejected.rpc_id(sender, "관전 자리가 꽉 찼습니다.")
				return
			_release_player_slot(sender)
			observers.append(sender)
			changed = true
			print("피어 %d 관전 입장 (관전 %d명)" % [sender, observers.size()])
	elif not order.has(sender):
		if order.size() >= Network.MAX_PLAYERS:
			_send_state_to(sender)
			_role_rejected.rpc_id(sender, "플레이어 자리가 꽉 찼습니다.")
			return
		observers.erase(sender)
		order.append(sender)
		configs[sender] = default_config(order.find(sender))
		ready_flags[sender] = false
		changed = true
		print("피어 %d 플레이어 입장 (%dP)" % [sender, order.find(sender) + 1])

	if changed:
		_broadcast()
	else:
		# 이미 등록된 피어의 되풀이 요청 — 상태만 다시 보낸다.
		_send_state_to(sender)

	# 경기 중에 들어온 **관전자만** 전투 화면으로 따로 보낸다 (이슈 #182).
	# 위에서 상태(맵 이름 포함)를 먼저 보냈으므로 순서가 맞다 — 반대면 맵 없이 씬을 연다.
	# 플레이어는 끼어들지 않는다. 경기 도중에 자리를 받았으면 다음 경기를 기다린다.
	if in_match and observers.has(sender):
		_begin_match.rpc_id(sender)


## 플레이어였던 피어가 관전으로 바꿀 때 자리를 비운다.
func _release_player_slot(peer_id: int) -> void:
	if not order.has(peer_id):
		return
	order.erase(peer_id)
	configs.erase(peer_id)
	ready_flags.erase(peer_id)
	# 남은 사람이 혼자 준비된 채로 남지 않게 준비를 해제한다 (_on_peer_left 와 같은 이유).
	for id in ready_flags:
		ready_flags[id] = false


func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	server_remove_viewer(peer_id)
	if observers.has(peer_id):
		observers.erase(peer_id)
		print("피어 %d 관전 퇴장 (관전 %d명)" % [peer_id, observers.size()])
		_broadcast()
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


## 그 피어에게만 지금 상태를 보낸다. 상태를 바꾸지 않으므로 몇 번이든 안전하다.
func _send_state_to(peer_id: int) -> void:
	_receive_lobby.rpc_id(peer_id, order, configs, ready_flags, observers, in_match)


## 클라이언트가 보낸 값이 목록에 있는 값인지 확인한다.
func _sanitize(config: Dictionary, slot: int) -> Dictionary:
	var base := default_config(slot)
	var character: String = config.get("character", base["character"])
	return {
		"character": character if Characters.has(character) else base["character"],
	}


func _check_start() -> void:
	# 이미 경기 중이면 새로 시작하지 않는다 (이슈 #182). 경기 도중에 빈 자리를 받은
	# 클라이언트가 준비를 누르면 진행 중인 경기 위에 또 시작해 버린다.
	if in_match:
		return
	if order.size() < 2:
		return
	for peer_id in order:
		if not ready_flags.get(peer_id, false):
			return
	# **여기서 확정할 것이 없다.** 무기는 라운드마다 전투 화면에서 고르고 (#205),
	# 맵도 라운드마다 전투 화면의 서버가 뽑는다 (요청) — 전에는 맵만 여기서 정했다.
	# 경기 중임을 먼저 켜고 알린다 — 이 뒤에 들어온 관전자는 다음 경기를 기다려야 한다.
	in_match = true
	_broadcast()
	# 관전자도 같은 지시를 받아 함께 전투 화면으로 들어간다.
	_begin_match.rpc()


## 경기가 끝나면 준비를 풀고 양쪽을 대기실로 돌려보낸다 (서버에서만 호출).
## 준비를 풀지 않으면 대기실에 도착하자마자 다시 시작해 버린다.
func server_end_match() -> void:
	if not multiplayer.is_server():
		return
	for peer_id in ready_flags:
		ready_flags[peer_id] = false
	in_match = false
	_broadcast()
	_end_match.rpc()


func _broadcast() -> void:
	_receive_lobby.rpc(order, configs, ready_flags, observers, in_match)
	lobby_changed.emit()


# ─────────────────────────── 클라이언트 전용 ───────────────────────────

@rpc("authority", "call_remote", "reliable")
func _receive_lobby(
	new_order: Array,
	new_configs: Dictionary,
	new_ready: Dictionary,
	new_observers: Array,
	new_in_match: bool,
) -> void:
	order = new_order
	configs = new_configs
	ready_flags = new_ready
	observers = new_observers
	in_match = new_in_match
	lobby_changed.emit()


## 원한 역할로 못 들어갔다는 서버의 답. 화면이 사유를 띄우고 다른 선택을 제시한다.
@rpc("authority", "call_remote", "reliable")
func _role_rejected(reason: String) -> void:
	role_rejected.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _begin_match() -> void:
	match_starting.emit()


@rpc("authority", "call_remote", "reliable")
func _end_match() -> void:
	match_ended.emit()
