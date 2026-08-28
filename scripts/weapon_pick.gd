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

## 창 내용을 오른쪽으로 미는 양(px, 기준 화면 1152×648). **0이면 지금까지와 같은 화면**이다.
##
## 릴리즈한 exe를 다른 기기에서 켜면 이 창이 통째로 왼쪽으로 쏠려 보인다는 보고가 있었는데
## (#299), 저장소 안에서는 재현되지 않았다 — 카드 상자는 폭 900에 내용도 정확히 900이라
## 해상도와 무관하게 가운데로 계산되고(1152x648·1920x1080·1366x768·800x600 에서 전부
## 좌우 여백 126 : 126), 16:9가 아닌 창에서도 엔진의 letterbox가 가운데로 잡혔다.
## 디스플레이 배율 100%·기본 해상도에서도 증상이 남아 DPI 쪽도 아니었다.
##
## 그래서 원인을 잡는 대신 **미는 양을 여기 한 곳에 두고** 눈으로 맞춘다. 값을 바꿀 때는
## 씬이 아니라 이 줄을 고친다 — 씬과 스크립트 두 곳에 자리 값이 갈리면 한쪽만 고쳤을 때
## 조용히 어긋난다.
##
## **지금 값은 기준 화면을 넘긴다 (#302).** 카드 상자는 원래 x 126~1026에 놓이므로
## 126을 넘겨 밀면 오른쪽 카드가 기준 화면(1152) 밖으로 나간다 — 240이면 바깥 114px이
## 잘린다. 120으로는 문제의 기기에서 화면이 그대로로 보인다는 확인을 받아 **잘림을
## 감수하고** 키운 값이다. 정상으로 보이던 기기에서는 오른쪽 카드가 그만큼 잘린다.
const SHIFT_X := 240.0

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
## 남은 시간을 세는 기준 시각. 0이면 세지 않는다 (관전자도 세지만 표시뿐이다).
var _ends_at := 0.0


func _ready() -> void:
	for index in _cards.size():
		_cards[index].pressed.connect(_on_card_pressed.bind(index))
	_dim_alpha = _dim.color.a
	_shine.cards = _cards
	_apply_shift()


## 창 내용을 `SHIFT_X` 만큼 오른쪽으로 옮긴다 (#299).
##
## **`Dim` 은 밀지 않는다** — 화면 전체를 덮는 것이 그 노드의 일이라, 밀면 왼쪽에 안 덮인
## 띠가 생긴다. **`Shine` 도 밀지 않는다** — 카드 자리를 그때그때 되짚어 그리므로
## (`card_shine.gd` 의 `_card_rect()`) 카드를 옮기면 저절로 따라온다.
##
## `_ready()` 에서 딱 한 번 돈다. 창을 열 때마다 부르면 라운드마다 조금씩 더 밀린다 —
## 앵커로 놓인 노드에 `position` 을 주는 것은 offset 을 그만큼 옮기는 일이라 누적된다.
func _apply_shift() -> void:
	if is_zero_approx(SHIFT_X):
		return
	for node: Control in [$Title, $Timer, $Cards, $Status]:
		node.position.x += SHIFT_X


## 남은 시간 표시와 등장 연출.
##
## **시계가 멈춰 있어도 연출은 돈다** — 관전자 화면에는 카드가 없고(`open_watching`)
## 어둡기만 깔리는데, 그것도 등장 연출의 일부다.
func _process(_delta: float) -> void:
	if not visible:
		return
	_tick_intro()
	if _ends_at <= 0.0:
		return
	# 진짜 마감은 서버가 재고 여기서는 보여주기만 한다 — 시계가 0에서 멈춰 있어도
	# 서버가 자동 선택을 넣어 라운드를 연다.
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
	# 카드 내용을 다 채운 **뒤에** 연출을 건다 (#263) — 먼저 걸면 빈 카드가 떠오른다.
	_start_intro()


## 고를 것이 없는 화면 (관전자). 카드를 잠그는 대신 아예 치운다 —
## 대기실에서 관전자를 다루는 방식과 같다 (이슈 #184).
func open_watching(seconds: float) -> void:
	_armed = false
	_ends_at = _now() + seconds
	_card_box.visible = false
	_status.text = "두 사람이 무기를 고르는 중..."
	visible = true
	# 카드가 없어도 어둡기는 깔린다 — 관전자에게도 라운드가 넘어간 것이 보여야 한다.
	_start_intro()


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
	# 도는 중이던 연출을 끝내고 화면을 평소 값으로 돌려놓는다 (#263) — 안 돌려놓으면
	# 다음 라운드의 첫 프레임이 지난번에 멈춘 크기·옅기로 뜬다.
	_end_intro()


func _on_card_pressed(index: int) -> void:
	if not _armed:
		return
	mark_chosen(index)
	_status.text = "상대를 기다리는 중..."
	weapon_chosen.emit(index)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
