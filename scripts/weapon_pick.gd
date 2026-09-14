extends Control
## 라운드가 시작될 때 뜨는 무기 선택 카드 (#205).
##
## 카드는 **보여주고 누르는 일만** 한다 — 후보를 뽑는 것도, 고른 결과를 확정하는 것도
## `main.gd`다. 여기서 하는 판단은 "이미 골랐는가" 하나뿐이고, 그것도 한 번 더
## 눌리는 것을 막으려는 것일 뿐이다.
##
## **한 화면에서 차례로 고른다** (#320). 창은 한 벌이고 `open()`이 받은 번호가 지금
## 고르는 사람이다 — 1P가 고르면 `main.gd`가 곧바로 2P 몫으로 다시 연다.
## 마우스로 눌러도 되고 **그 사람 키로 골라도 된다**: 좌우로 카드를 옮기고
## 특수(`skill`)나 점프로 정한다. 키보드 앞에 둘이 앉아 있으므로 마우스 하나를
## 주고받게 하지 않는다.
##
## 카드에 들어가는 이름·그림·설명은 전부 무기 표에서 꺼낸다 —
## 이름은 `Weapons.names()`의 그 이름, 그림은 `Weapons.preview_texture()`(선택 창과 같은 그림),
## 설명은 `Weapons.description()`("무기 증강 설명 리스트" 문서의 문구)다.

## 카드를 눌렀다. 넘기는 값은 `main.gd` 가 뽑아 준 후보 배열에서의 자리다 —
## 무기 이름으로 주고받으면 후보에 없는 무기가 확정될 수 있다.
signal weapon_chosen(index: int)

## 안 고른 카드를 얼마나 어둡게 두는가.
const FADED := Color(0.45, 0.45, 0.5, 1.0)
## 키보드 자리가 아닌 카드의 옅기. `FADED`보다 옅게 둔다 — 저쪽은 "고르지 않은 것"이고
## 이쪽은 "아직 고를 수 있는 것"이라, 같은 짙기면 이미 고른 화면처럼 보인다.
const UNFOCUSED := Color(0.74, 0.74, 0.8, 1.0)

## ── 등장 연출 (#263) ──
## 카드 한 장이 떠오르는 데 걸리는 시간(초). 빛이 타올랐다 가라앉는 것까지 포함이다.
const INTRO_TIME := 0.62
## 다음 카드가 늦게 뜨는 간격(초). **아주 짧다** — 길면 차례로 뜨는 것이 아니라
## 세 번 따로 뜨는 것으로 보이고, 20초 시계가 도는 화면에서 기다림이 된다.
const INTRO_STAGGER := 0.07
## 카드가 커지기 시작하는 크기. 1.0에서 시작하면 떠오르는 것이 아니라 켜지는 것이 된다.
const INTRO_SCALE_FROM := 0.86
## 카드가 제 크기·옅기에 닿는 시점(0~1). 나머지 구간에서는 빛만 가라앉는다 —
## **카드는 빛보다 먼저 자리를 잡아야 한다.** 빛과 같이 끝나면 다 사라질 때까지
## 카드가 흔들리는 것으로 보인다.
const INTRO_SETTLE := 0.45
## 어둡기가 다 깔리는 데 걸리는 시간(초). 카드보다 먼저 자리를 잡아 바탕이 된다.
const DIM_TIME := 0.28

@onready var _cards: Array = [$Cards/Card0, $Cards/Card1, $Cards/Card2]
@onready var _card_box: HBoxContainer = $Cards
@onready var _timer_label: Label = $Timer
@onready var _status: Label = $Status
@onready var _dim: ColorRect = $Dim
@onready var _shine: CardShine = $Shine

## 어둡기의 평소 짙기. 씬에 적힌 값을 그대로 들고 있다가 연출이 그 값까지 채운다 —
## 여기에 숫자를 다시 적으면 씬에서 색을 고쳤을 때 두 곳이 갈라진다.
var _dim_alpha := 0.78
## 등장 연출을 시작한 시각. 음수면 도는 중이 아니다.
var _intro_started_at := -1.0

## 아직 고를 수 있는가. 한 번 고르면 꺼지고 그 뒤로는 눌러도 아무 일도 없다.
var _armed := false
## 지금 고르는 사람 (1P는 1, 2P는 2). 0이면 열려 있지 않다 —
## **어느 쪽 키를 읽을지도 이 번호가 정한다**.
var _picker := 0
## 키보드로 짚고 있는 카드 자리. 마우스로 누르면 그 자리로 따라간다.
var _cursor := 0
## 남은 시간을 세는 기준 시각. 0이면 세지 않는다.
var _ends_at := 0.0


func _ready() -> void:
	for index in _cards.size():
		_cards[index].pressed.connect(_on_card_pressed.bind(index))
	_dim_alpha = _dim.color.a
	_shine.cards = _cards


## 남은 시간 표시와 등장 연출.
##
## **시계가 멈춰 있어도 연출은 돈다** — 어둡기가 깔리는 것도 등장 연출의 일부다.
func _process(_delta: float) -> void:
	if not visible:
		return
	_tick_intro()
	if _ends_at <= 0.0:
		return
	# 진짜 마감은 `main.gd` 가 재고 여기서는 보여주기만 한다 — 시계가 0에서 멈춰 있어도
	# 그쪽이 대신 뽑아 라운드를 연다.
	var left := maxf(_ends_at - _now(), 0.0)
	_timer_label.text = "%d초" % ceili(left)


## 등장 연출 한 프레임 (#263). 어둡기 → 카드 크기·옅기 → 빛의 순서로 몬다.
##
## **`modulate` 는 알파만 건드린다.** 색 자체는 `mark_chosen()` 이 쓰는 자리라
## (고른 카드는 흰색, 나머지는 `FADED`), 연출이 통째로 덮으면 연출 도중에 고른 사람의
## 화면에서 어둡게 처리가 한 프레임 만에 지워진다. 알파만 1.0으로 채워 올리면 두 쪽이
## 서로를 지우지 않는다.
func _tick_intro() -> void:
	if _intro_started_at < 0.0:
		return
	var elapsed := _now() - _intro_started_at
	_dim.color.a = _dim_alpha * minf(elapsed / DIM_TIME, 1.0)

	var shine_progress: Array = []
	var running := elapsed < DIM_TIME
	for index in _cards.size():
		var card: Control = _cards[index]
		# 장마다 조금씩 늦게 시작한다.
		var local := (elapsed - INTRO_STAGGER * float(index)) / INTRO_TIME
		shine_progress.append(clampf(local, 0.0, 1.0))
		if local >= 1.0:
			# 다 끝났으면 평소 값으로 못박는다 — 계산한 값으로 두면 부동소수 찌꺼기가
			# 남아 카드가 0.999배로 서 있게 된다.
			card.scale = Vector2.ONE
			card.modulate.a = 1.0
			continue
		running = true
		var settle := clampf(local / INTRO_SETTLE, 0.0, 1.0)
		# 감속해서 제 크기에 닿는다 — 등속으로 커지면 부푸는 것으로 보인다.
		settle = 1.0 - (1.0 - settle) * (1.0 - settle)
		card.pivot_offset = card.size * 0.5
		card.scale = Vector2.ONE * lerpf(INTRO_SCALE_FROM, 1.0, settle)
		card.modulate.a = settle

	_shine.refresh(shine_progress)
	if not running:
		_end_intro()


## 등장 연출을 끝내고 화면을 평소 값으로 못박는다.
##
## **연출이 끝난 뒤의 모습은 지금까지와 완전히 같아야 한다** — 남는 것이 있으면
## 라운드마다 조금씩 쌓인다.
func _end_intro() -> void:
	_intro_started_at = -1.0
	_dim.color.a = _dim_alpha
	_shine.hide()
	for card: Control in _cards:
		card.scale = Vector2.ONE
		card.modulate.a = 1.0


## 등장 연출을 처음부터 다시 시작한다. 창을 여는 두 곳이 함께 부른다.
func _start_intro() -> void:
	_intro_started_at = _now()
	_dim.color.a = 0.0
	_shine.show()
	var zeros: Array = []
	for card: Control in _cards:
		card.pivot_offset = card.size * 0.5
		card.scale = Vector2.ONE * INTRO_SCALE_FROM
		card.modulate.a = 0.0
		zeros.append(0.0)
	_shine.refresh(zeros)


## 고를 수 있는 상태로 연다. `choices`는 `main.gd`가 이 사람 몫으로 뽑아 준 무기 이름들이고
## `player_id`는 지금 고를 차례인 사람이다.
func open(choices: Array, seconds: float, player_id: int) -> void:
	_armed = true
	_picker = player_id
	_cursor = 0
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
	_status.text = "%dP 차례 — 이번 라운드에 들 무기를 고르세요" % _picker
	visible = true
	_refresh_cursor()
	# 카드 내용을 다 채운 **뒤에** 연출을 건다 (#263) — 먼저 걸면 빈 카드가 떠오른다.
	_start_intro()


## 키보드로 짚은 자리를 옮긴다. 양 끝에서 멈추지 않고 돌아간다 — 카드가 셋뿐이라
## 끝에서 막히면 되돌아가는 동안 잘못 짚기 쉽다.
func _move_cursor(step: int) -> void:
	var count := _visible_card_count()
	if count <= 0:
		return
	_cursor = (_cursor + step + count) % count
	_refresh_cursor()


## 짚은 카드만 밝게 둔다.
func _refresh_cursor() -> void:
	if not _armed:
		return
	for i in _cards.size():
		var card: Button = _cards[i]
		if not card.visible:
			continue
		card.modulate = Color.WHITE if i == _cursor else UNFOCUSED


func _visible_card_count() -> int:
	var count := 0
	for card: Button in _cards:
		if card.visible:
			count += 1
	return count


## 고르는 사람의 키만 받는다 (#320). 좌우로 짚고 특수·점프로 정한다.
##
## `_unhandled_input`이라 카드를 마우스로 누르는 것과 부딪히지 않는다 — 버튼이 먼저
## 가져간 이벤트는 여기까지 오지 않는다.
func _unhandled_input(event: InputEvent) -> void:
	if not _armed or _picker == 0 or not visible:
		return
	if event.is_action_pressed(GameState.action(_picker, "right")):
		_move_cursor(1)
	elif event.is_action_pressed(GameState.action(_picker, "left")):
		_move_cursor(-1)
	elif event.is_action_pressed(GameState.action(_picker, "skill")) \
			or event.is_action_pressed(GameState.action(_picker, "jump")):
		_on_card_pressed(_cursor)
	else:
		return
	get_viewport().set_input_as_handled()


## 고른 뒤의 화면. 고른 카드만 남기고 나머지는 어둡게 둔다 —
## 카드를 통째로 치우면 무엇을 골랐는지 확인할 곳이 없어진다.
func mark_chosen(index: int) -> void:
	_armed = false
	for i in _cards.size():
		var card: Button = _cards[i]
		card.disabled = true
		card.modulate = Color.WHITE if i == index else FADED


func close() -> void:
	_armed = false
	_picker = 0
	_ends_at = 0.0
	visible = false
	# 도는 중이던 연출을 끝내고 화면을 평소 값으로 돌려놓는다 (#263) — 안 돌려놓으면
	# 다음 라운드의 첫 프레임이 지난번에 멈춘 크기·옅기로 뜬다.
	_end_intro()


func _on_card_pressed(index: int) -> void:
	if not _armed:
		return
	_cursor = index
	mark_chosen(index)
	_status.text = "%dP 선택 완료" % _picker
	weapon_chosen.emit(index)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
