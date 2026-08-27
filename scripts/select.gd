extends Control
## 대기실 겸 캐릭터·맵 선택 화면.
##
## **무기는 여기서 고르지 않는다**(#205) — 라운드가 시작될 때마다 전투 화면에서 고른다.
##
## 자기 패널만 조작할 수 있고 상대 패널에는 서버가 보낸 상대 선택이 표시된다.
## 둘 다 준비되면 **서버 지시로** 전투 화면으로 전환된다.
##
## **관전자도 이 화면을 쓴다**(이슈 #167). 자기 패널이 없으니 전부 잠기고, 두 플레이어가
## 준비하면 같은 `match_starting` 지시를 받아 함께 전투 화면으로 들어간다.
## 경기 중에 들어온 관전자는 이 화면을 스치고 바로 그 경기로 들어간다(이슈 #182).

## 대기실 정보를 다시 청하는 간격(초). 내 자리를 받을 때까지 반복한다.
const SYNC_RETRY_SEC := 1.0

@onready var panels := [$P1Panel, $P2Panel]
@onready var status_label: Label = $StatusLabel
@onready var go_button: Button = $GoButton
## 맵 카드 좌우 절반의 배경 그림과 그 아래 이름표. 순서가 슬롯(1P·2P)이다 (#289).
@onready var map_previews := [$MapBox/ScreenRect/Map1, $MapBox/ScreenRect/Map2]
@onready var map_labels: Array[Label] = [$MapBox/Map1Name, $MapBox/Map2Name]

var _my_panel: Control = null
var _sync_timer: Timer = null
## 원한 역할로 못 들어갔다는 서버의 답을 받았는가. 받았으면 되풀이 요청을 멈추고
## 사유를 띄운다 — 계속 청해도 자리가 생기지 않는다.
var _rejected := ""


func _ready() -> void:
	$HomeButton.pressed.connect(_on_home_pressed)
	go_button.pressed.connect(_on_ready_pressed)

	# 맵은 둘이 공유하는 하나뿐이라 누가 바꾸든 양쪽에 적용된다.
	# 값을 정하는 것은 서버이고 여기서는 "다음/이전" 요청만 보낸다.
	$LeftArrow.pressed.connect(_cycle_map.bind(-1))
	$RightArrow.pressed.connect(_cycle_map.bind(1))

	for panel in panels:
		panel.config_changed.connect(_on_my_config_changed)

	Lobby.lobby_changed.connect(_refresh)
	Lobby.match_starting.connect(_on_match_starting)
	Lobby.role_rejected.connect(_on_role_rejected)
	Network.join_failed.connect(_on_disconnected)

	# 동기화를 먼저 시작한다 — `Lobby.reset()`이 들고 있던 상태를 버리고 `lobby_changed`로
	# 화면을 한 번 갱신해 준다. 순서를 바꾸면 **방을 옮겨 온 첫 프레임에 옛 방의 상태가**
	# 그려진다(이슈 #184에서 관전자가 방을 옮길 때 실제로 한 프레임 보였다).
	_start_sync()
	_refresh()


## 내 역할을 알리고 대기실 상태를 서버에서 새로 받아 온다.
##
## 들고 있던 것을 먼저 버리는 이유는 옛 접속의 order 가 남아 있을 수 있어서다 — 그러면
## 내 새 peer id 가 목록에 없는 채로 화면이 통째로 잠긴다(이슈 #93).
## 청한 답도 유실될 수 있으므로 자리를 받을 때까지 되풀이한다.
## 자리 배정 자체가 이 요청으로 일어나므로(이슈 #167) 되풀이가 곧 재시도이기도 하다.
func _start_sync() -> void:
	if Network.is_server:
		return

	Lobby.reset()
	_rejected = ""

	# 이 노드에 붙여두면 씬이 바뀔 때 타이머도 같이 사라진다.
	if _sync_timer == null:
		_sync_timer = Timer.new()
		_sync_timer.wait_time = SYNC_RETRY_SEC
		_sync_timer.timeout.connect(_on_sync_retry)
		add_child(_sync_timer)
	_sync_timer.start()

	Lobby.submit_role(Lobby.my_role)


func _on_sync_retry() -> void:
	# 관전자는 order 가 아니라 observers 에 들어가므로 자리 확인은 knows_me() 로 한다.
	if Lobby.knows_me():
		_sync_timer.stop()
		return
	Lobby.submit_role(Lobby.my_role)


## 원한 역할의 자리가 없다는 답. 되풀이해도 소용없으니 멈추고 화면에 사유를 띄운다.
func _on_role_rejected(reason: String) -> void:
	_rejected = reason
	if _sync_timer != null:
		_sync_timer.stop()
	_refresh()


## 대기실 상태를 화면에 반영한다.
##
## **트리를 벗어난 뒤에는 아무것도 하지 않는다.** 씬 전환은 프레임 끝에 일어나므로 그 사이에
## 도착한 서버 방송이 이미 떼어진 이 노드로 들어온다 — 그때는 `multiplayer` 도 null 이라
## 손대는 즉시 오류가 난다. 관전자가 경기 중에 들어오고 나가면서 방송이 늘어 잘 드러난다.
func _refresh() -> void:
	if not is_inside_tree():
		return

	# 플레이어 자리를 거절당했는데 그 자리가 비었다 — 다시 신청한다.
	# 사람이 나갈 때까지 기다렸다가 손으로 다시 접속하게 만들 이유가 없다.
	# 신호 처리 중에 상태를 갈아치우지 않도록 다음 프레임으로 미룬다.
	if _rejected != "" and Lobby.my_role == Lobby.ROLE_PLAYER \
			and Lobby.order.size() < Network.MAX_PLAYERS:
		_start_sync.call_deferred()
		return

	var me := multiplayer.get_unique_id()
	var my_slot := Lobby.slot_of(me)
	_my_panel = panels[my_slot] if my_slot >= 0 and my_slot < panels.size() else null
	# 관전자에게는 조작할 것이 하나도 없다 — 잠근 버튼을 남기지 않고 치운다 (이슈 #184).
	var observing := Lobby.my_role == Lobby.ROLE_OBSERVER

	for slot in panels.size():
		var panel: Control = panels[slot]
		panel.set_interactive(panel == _my_panel)
		panel.set_display_only(observing)
		# 내 패널은 내가 조작 중이므로 덮어쓰지 않는다
		if panel == _my_panel:
			continue
		if slot < Lobby.order.size():
			panel.apply_config(Lobby.config_for(Lobby.order[slot]))

	# 내 자리가 없으면(관전자·정보 대기 중) 맵 화살표도 잠근다 — 눌러도 서버가 버린다.
	# 관전자는 영영 자리가 없으므로 잠그는 대신 아예 치운다.
	var can_pick := my_slot >= 0
	$LeftArrow.disabled = not can_pick
	$RightArrow.disabled = not can_pick
	$LeftArrow.visible = not observing
	$RightArrow.visible = not observing
	# 준비 버튼도 관전자에게는 누를 일이 없다. 문구는 상태 줄이 대신 알려준다.
	go_button.visible = not observing

	_refresh_maps()
	_update_status()


## 양쪽이 고른 맵을 나란히 보여준다. 실제로 쓸 맵은 시작할 때 서버가 둘 중 하나를 뽑는다.
##
## 이름만 적으면 맵을 외우지 못한 사람은 무엇을 고르고 있는지 알 수 없어서(#289)
## 카드 배경에 그 맵의 배경 원화를 깐다 — **왼쪽 절반이 1P, 오른쪽 절반이 2P**다.
## 이름표도 각 절반 아래에 하나씩 두어 어느 그림이 누구 것인지 위치로 읽힌다.
##
## `map_previews`에는 타입을 붙이지 않는다 — `map_preview.gd`에 class_name이 없어
## `Control`로 받으면 `map_name` 대입이 파싱되지 않는다(`panels`와 같은 방식).
func _refresh_maps() -> void:
	for slot in panels.size():
		var picked := ""
		if slot < Lobby.order.size():
			picked = Lobby.map_of(Lobby.order[slot])
			map_labels[slot].text = "%dP  %s" % [slot + 1, picked]
		else:
			# 아직 안 들어온 자리. 그림도 단색으로 남아 "모른다"로 읽힌다.
			map_labels[slot].text = "%dP  —" % (slot + 1)
		map_previews[slot].map_name = picked


func _update_status() -> void:
	var me := multiplayer.get_unique_id()

	# 자리를 거절당했다 — 사유와 나갈 길만 알려 준다.
	#
	# **여기서 역할을 바꾸는 조작은 두지 않는다**(이슈 #170·#180). 역할은 화면이 아니라
	# 실행한 파일이 정하므로 바꿀 수단 자체가 없다 — 관전으로 보려면 관전 빌드로 접속해야 한다.
	# 자리가 비면 알아서 다시 신청하므로(`_refresh`) 기다리는 것만으로도 들어갈 수는 있다.
	if _rejected != "":
		if Lobby.observer_slots_open():
			status_label.text = "%s  관전 빌드로 접속하면 볼 수 있어요." % _rejected
		else:
			status_label.text = "%s  방이 꽉 찼습니다 — 홈으로 나가세요." % _rejected
		go_button.disabled = true
		go_button.text = "준비"
		return

	# 관전자는 준비를 보낼 것이 없다. 버튼을 켜 두면 눌러도 아무 일 없는 버튼이 된다.
	if Lobby.is_observer(me):
		status_label.text = _observer_status()
		go_button.disabled = true
		go_button.text = "관전 중"
		return

	# 목록에 내 자리가 없으면 준비를 보내도 서버가 버린다 — 눌러도 아무 일 없는
	# 버튼을 활성화해 두면 "전부 클릭이 안 된다"로만 보인다(이슈 #93).
	if Lobby.slot_of(me) < 0:
		status_label.text = "대기실 정보를 받는 중..."
		go_button.disabled = true
		go_button.text = "준비"
		return

	# 경기 도중에 빈 자리를 받았다 — 끼어들지 않고 기다린다 (이슈 #182).
	# 서버도 `in_match` 동안에는 새 경기를 시작하지 않으므로 버튼을 켜 두면 헛누름이 된다.
	if Lobby.in_match:
		status_label.text = "경기가 진행 중입니다. 끝나면 시작할 수 있어요.%s" % _observer_suffix()
		go_button.disabled = true
		go_button.text = "준비"
		return

	if Lobby.order.size() < 2:
		status_label.text = "상대 대기 중...%s" % _observer_suffix()
		go_button.disabled = true
		go_button.text = "준비"
		return

	var opponent := 0
	for peer_id in Lobby.order:
		if peer_id != me:
			opponent = peer_id

	var mine := Lobby.is_ready(me)
	go_button.disabled = false
	go_button.text = "준비 취소" if mine else "준비"
	status_label.text = "나: %s   |   상대: %s%s" % [
		_ready_text(mine),
		_ready_text(Lobby.is_ready(opponent)),
		_observer_suffix(),
	]


## 관전자에게 보여줄 안내. 관전자는 이 화면에서 기다리기만 하므로 무엇을 기다리는지 적는다 —
## 플레이어가 덜 왔는지, 준비를 안 했는지, 경기 중이라 들어가는 중인지.
func _observer_status() -> String:
	if Lobby.in_match:
		# 서버가 곧 이 피어를 전투 화면으로 보낸다 (이슈 #182) — 잠깐 스치는 문구다.
		return "관전 중 — 진행 중인 경기로 들어갑니다..."
	if Lobby.order.size() < Network.MAX_PLAYERS:
		return "관전 중 — 플레이어를 기다립니다. (%d/%d)" % [
			Lobby.order.size(), Network.MAX_PLAYERS,
		]
	return "관전 중 — 두 사람이 준비하면 함께 들어갑니다."


## 플레이어에게 보여줄 관전 인원. 아무도 없으면 아무 말도 하지 않는다.
func _observer_suffix() -> String:
	if Lobby.observers.is_empty():
		return ""
	return "   ·   관전 %d명" % Lobby.observers.size()


func _ready_text(flag: bool) -> String:
	return "준비 완료" if flag else "선택 중"


## 내 맵 선택을 한 칸 옮겨 서버에 알린다. 상대 선택은 바뀌지 않는다.
## 표시는 서버가 보낸 값을 받아서 갱신된다.
func _cycle_map(step: int) -> void:
	var me := multiplayer.get_unique_id()
	if Lobby.slot_of(me) < 0:
		return
	var maps := GameState.MAPS
	var index := maxi(maps.find(Lobby.map_of(me)), 0)
	Lobby.submit_map(maps[posmod(index + step, maps.size())])


func _on_my_config_changed() -> void:
	if _my_panel == null:
		return
	Lobby.submit_config(_my_panel.get_config())


func _on_ready_pressed() -> void:
	Lobby.submit_ready(not Lobby.is_ready(multiplayer.get_unique_id()))


## 서버의 경기 시작 지시. 관전자도 같은 지시로 함께 들어간다.
## 이미 화면을 떠났다면 무시한다 — 전환 대기 중에 지시가 한 번 더 와도 문제가 없어야 한다.
func _on_match_starting() -> void:
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## 접속이 끊겼다. 방을 옮기는 중이면 그쪽(room_switcher.gd)이 화면을 옮기므로 손대지 않는다 —
## 두 곳에서 씬을 갈아치우면 어느 쪽이 이길지 알 수 없다.
func _on_disconnected(_reason: String) -> void:
	if not is_inside_tree() or $RoomSwitcher.is_switching():
		return
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func _on_home_pressed() -> void:
	Network.leave()
	get_tree().change_scene_to_file("res://scenes/title.tscn")
