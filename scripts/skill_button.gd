extends Control
## 궁극기(특수 공격) 버튼 하나 (#322).
##
## `virtual_stick.gd` 와 같은 방식이다 — 손가락을 직접 받지 않고 `touch_controls.gd` 가
## 나눠 주며, `Input.parse_input_event()` 로 `p1_skill`·`p2_skill` 을 흉내 낸다.
##
## **누르고 있는 시간이 그대로 유지되어야 한다** — 방패는 짧게/길게를 누른 길이로 가르고
## (`Player._check_long_press()`), 그 길이를 재는 것은 판정 쪽이다. 여기서 눌림을 한 프레임만
## 내보내면 긴 누름이 영영 안 나온다. 그래서 뗄 때까지 눌린 상태로 둔다.
##
## `Button` 을 쓰지 않고 직접 그리는 이유는 멀티터치다 — `Button` 은 마우스 에뮬레이션으로
## 오는 손가락 하나만 받아서, 두 사람이 동시에 누르면 한쪽이 먹힌다.

const RADIUS := 48.0

## 조이스틱과 같은 옅기다. 눌린 동안에만 진해져서 들어간 것이 보인다.
const BASE_COLOR := Color(0.16, 0.14, 0.22, 0.34)
const RIM_COLOR := Color(0.99, 0.95, 0.92, 0.46)

## 선택 창 캐릭터 패널과 같은 배색이다 (`select.tscn`의 `P1Panel`/`P2Panel` `accent`) —
## 1P·2P를 가르는 색을 이 게임에서 이미 정해 둔 자리라 여기서 새로 고르지 않는다.
const ACCENTS := {1: Color(0.96, 0.55, 0.78), 2: Color(0.56, 0.59, 0.91)}

## 차오른 칸의 테두리를 그릴 때 쓰는 꼭짓점 수. 원의 일부라 40 이면 매끄럽다.
const CHARGE_STEPS := 40
## 무기 그림이 원 밖으로 삐져나오지 않도록 두는 안전 비율 — 원에 내접하는
## 정사각형(둘레의 약 0.707배)보다 조금 더 작게 잡는다.
const ART_FILL := 0.68

## 쿨타임이 없는 상태(다 참)를 나타내는 값.
const READY := 1.0

@export var player_id: int = 1:
	set(value):
		player_id = value
		_accent = ACCENTS.get(value, ACCENTS[1])
		queue_redraw()

## 지금 든 무기 (#334). `main.gd`가 라운드마다 무기를 정한 직후 넘겨준다 — 그림이 있는
## 무기(7종)는 궁극기 버튼에도 그 무기가 보여야 어느 무기를 들었는지 손끝만 보고 안다.
## 그림이 없는 무기는 `weapon_preview.gd`와 같은 이유로 아무것도 그리지 않는다 —
## 글자(`_label`)가 대신 알려준다.
@export var weapon_id := "":
	set(value):
		weapon_id = value
		_art = Weapons.preview_texture(value)
		queue_redraw()

## 1P는 분홍, 2P는 인디고 — `player_id`가 바뀌는 순간 그 값으로 다시 잡힌다.
var _accent := ACCENTS[1]
var _art: Texture2D = null

var _pressed := false

## 0.0(방금 썼다) ~ 1.0(다 찼다). `main.gd` 가 정한 값을 받아 그리기만 한다 —
## 여기서는 시간을 재지 않는다. 전투 판정의 주인이 아니기 때문이다.
var _charge := READY
## 남은 초(올림). 글자에 적는다. 0 이면 다 찬 것이라 `궁극기` 로 되돌린다.
var _seconds_left := 0

@onready var _label: Label = $Label


## `_label` 의 원래 글자. 다 찼을 때 되돌릴 값이라 씬에 적힌 것을 그대로 쓴다 —
## 코드에 다시 적으면 씬에서 글자를 고쳤을 때 조용히 어긋난다.
@onready var _ready_text: String = _label.text


## 쿨타임 상태를 받는다 (#334). `main.gd` 의 `_sync_special_ready()` 가 매 물리 틱마다
## 부르므로 **그린 그림이 달라질 때만** 다시 그린다 — 칸 경계가 1px 도 안 움직였는데
## 60번 다시 그릴 이유가 없다.
func set_cooldown(remaining: float, total: float) -> void:
	var charge := READY if total <= 0.0 else clampf(1.0 - remaining / total, 0.0, READY)
	var seconds := int(ceilf(maxf(remaining, 0.0)))
	# 0.4초가 남았는데 `0` 을 띄우면 눌러도 안 나가는 순간이 생긴다 — 그래서 올림이다.
	# 다 찬 뒤에는 0 이라 글자가 `궁극기` 로 돌아온다.
	if charge >= READY:
		seconds = 0
	if roundi(_charge * RADIUS * 2.0) == roundi(charge * RADIUS * 2.0) and _seconds_left == seconds:
		return
	_charge = charge
	if _seconds_left != seconds:
		_seconds_left = seconds
		_label.text = _ready_text if seconds <= 0 else str(seconds)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var pressed_color := Color(_accent.r, _accent.g, _accent.b, 0.78)
	draw_circle(center, RADIUS, pressed_color if _pressed else BASE_COLOR)
	if _art != null:
		_draw_art(center)
	# **누르고 있는 동안에도 그린다** — 쿨타임이 도는 중에 눌러 보는 것은 흔한 일이고,
	# 그때 칸을 숨기면 버튼이 가득 찬 것처럼 보여 쓸 수 있다고 읽힌다.
	if _charge > 0.0:
		_draw_charge(center)
	# 누르고 있을 때와 **다 찼을 때** 쓰는 밝은 테두리 (#334). 칸이 가득 찬 것과
	# 거의 찬 것이 한눈에 갈린다 — 마지막 몇 px 는 눈으로 재기 어렵다.
	var pressed_rim_color := _accent.lerp(Color.WHITE, 0.25)
	pressed_rim_color.a = 0.9
	draw_arc(center, RADIUS, 0.0, TAU, 40,
			pressed_rim_color if _pressed or _charge >= READY else RIM_COLOR, 3.0, true)


## 들고 있는 무기 그림을 가운데에 그린다. `weapon_preview.gd`와 같은 방식(`Art.content_rect()`로
## 투명 여백을 뺀 뒤 칸에 맞춰 키운다)이지만 칸이 네모가 아니라 원이라 `ART_FILL`로 더 좁힌다.
func _draw_art(center: Vector2) -> void:
	var region := Art.content_rect(_art)
	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return
	var box := RADIUS * 2.0
	var fit := minf(box / region.size.x, box / region.size.y) * ART_FILL
	var draw_size := region.size * fit
	draw_texture_rect_region(_art, Rect2(center - draw_size * 0.5, draw_size), region)


## 차오른 만큼을 **왼쪽에서 오른쪽으로** 덮는다 (#334).
##
## 원을 세로선으로 자른 조각이라 **볼록**하다 — `draw_colored_polygon()` 이 삼각형을
## 나누는 방식이 볼록한 것을 전제로 해서, 오목한 모양이면 엉뚱한 자리가 메워진다
## (`select_decor.gd` 의 꽃밭 띠가 그래서 세로 조각으로 그려져 있다).
##
## 경계선의 각도는 `acos` 로 얻는다. 채우는 쪽 경계가 `x = center.x + RADIUS * t` 이면
## 그 세로선이 원과 만나는 곳이 `±acos(t)` 이고, 왼쪽 조각은 그 둘 사이를 **π 를 지나며**
## 잇는 호다.
func _draw_charge(center: Vector2) -> void:
	# 눌렸을 때(0.78)보다 옅어서 "찼다"와 "누르고 있다"가 구분되고, 조작물이 젤리가
	# 서는 자리와 겹치므로(#322) 발이 사라질 만큼 진하지 않다.
	var charge_color := Color(_accent.r, _accent.g, _accent.b, 0.44)
	if _charge >= READY:
		draw_circle(center, RADIUS, charge_color)
		return
	var edge := acos(clampf(_charge * 2.0 - 1.0, -1.0, 1.0))
	var points := PackedVector2Array()
	for i in CHARGE_STEPS + 1:
		var angle := lerpf(edge, TAU - edge, float(i) / float(CHARGE_STEPS))
		points.append(center + Vector2(cos(angle), sin(angle)) * RADIUS)
	draw_colored_polygon(points, charge_color)


func press(_global_pos: Vector2) -> void:
	_set_pressed(true)


## 손가락이 버튼 밖으로 미끄러져도 놓지 않는다 — 누르고 있는 중에 조금 움직이는 것은
## 흔한 일이고, 그때마다 특수가 끊기면 긴 누름을 유지할 수 없다.
func drag(_global_pos: Vector2) -> void:
	pass


func release() -> void:
	_set_pressed(false)


func release_all() -> void:
	release()


func _set_pressed(down: bool) -> void:
	if _pressed == down:
		return
	_pressed = down
	var ev := InputEventAction.new()
	ev.action = GameState.action(player_id, "skill")
	ev.pressed = down
	ev.strength = 1.0 if down else 0.0
	Input.parse_input_event(ev)
	queue_redraw()
