extends Control
## 라운드가 시작될 때 뜨는 무기 선택 카드 (#205).
##
## 카드는 **보여주고 누르는 일만** 한다 — 후보를 뽑는 것도, 고른 결과를 확정하는 것도
## 서버(`main.gd`)다. 여기서 하는 판단은 "이미 골랐는가" 하나뿐이고, 그것도 두 번
## 보내지 않으려는 것일 뿐 진짜 검증은 서버가 다시 한다.
##
## 카드에 들어가는 이름·그림·설명은 전부 무기 표에서 꺼낸다 —
## 이름은 `Weapons.names()`의 그 이름, 그림은 `Weapons.preview_texture()`(대기실과 같은 그림),
## 설명은 `Weapons.description()`("무기 증강 설명 리스트" 문서의 문구)다.

## 카드를 눌렀다. 넘기는 값은 서버가 보낸 후보 배열에서의 자리다 —
## 무기 이름을 보내면 클라이언트가 후보에 없는 무기를 적어 보낼 수 있다.
signal weapon_chosen(index: int)

## 안 고른 카드를 얼마나 어둡게 두는가.
const FADED := Color(0.45, 0.45, 0.5, 1.0)

@onready var _cards: Array = [$Cards/Card0, $Cards/Card1, $Cards/Card2]
@onready var _card_box: HBoxContainer = $Cards
@onready var _timer_label: Label = $Timer
@onready var _status: Label = $Status

## 아직 고를 수 있는가. 한 번 고르면 꺼지고 그 뒤로는 눌러도 아무 일도 없다.
var _armed := false
## 남은 시간을 세는 기준 시각. 0이면 세지 않는다 (관전자도 세지만 표시뿐이다).
var _ends_at := 0.0


func _ready() -> void:
	for index in _cards.size():
		_cards[index].pressed.connect(_on_card_pressed.bind(index))


## 남은 시간 표시. 진짜 마감은 서버가 재고 여기서는 보여주기만 한다 —
## 시계가 0에서 멈춰 있어도 서버가 자동 선택을 넣어 라운드를 연다.
func _process(_delta: float) -> void:
	if not visible or _ends_at <= 0.0:
		return
	var left := maxf(_ends_at - _now(), 0.0)
	_timer_label.text = "%d초" % ceili(left)


## 고를 수 있는 상태로 연다. `choices`는 서버가 이 기기 몫으로 뽑아 준 무기 이름들이다.
func open(choices: Array, seconds: float) -> void:
	_armed = true
	_ends_at = _now() + seconds
	_card_box.visible = true
	for index in _cards.size():
		var card: Button = _cards[index]
		if index >= choices.size():
			card.visible = false
			continue
		var weapon_name: String = choices[index]
		card.visible = true
		card.disabled = false
		card.modulate = Color.WHITE
		card.get_node("Art").weapon_id = weapon_name
		(card.get_node("Name") as Label).text = weapon_name
		(card.get_node("Desc") as Label).text = Weapons.description(weapon_name)
	_status.text = "이번 라운드에 들 무기를 고르세요"
	visible = true


## 고를 것이 없는 화면 (관전자). 카드를 잠그는 대신 아예 치운다 —
## 대기실에서 관전자를 다루는 방식과 같다 (이슈 #184).
func open_watching(seconds: float) -> void:
	_armed = false
	_ends_at = _now() + seconds
	_card_box.visible = false
	_status.text = "두 사람이 무기를 고르는 중..."
	visible = true


## 고른 뒤의 화면. 고른 카드만 남기고 나머지는 어둡게 둔다 —
## 카드를 통째로 치우면 무엇을 골랐는지 확인할 곳이 없어진다.
func mark_chosen(index: int) -> void:
	_armed = false
	for i in _cards.size():
		var card: Button = _cards[i]
		card.disabled = true
		card.modulate = Color.WHITE if i == index else FADED


func set_status(text: String) -> void:
	_status.text = text


func close() -> void:
	_armed = false
	_ends_at = 0.0
	visible = false


func _on_card_pressed(index: int) -> void:
	if not _armed:
		return
	mark_chosen(index)
	_status.text = "상대를 기다리는 중..."
	weapon_chosen.emit(index)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
