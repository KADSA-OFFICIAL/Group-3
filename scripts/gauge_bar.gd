extends Node2D
## 너클 게이지 바 — 젤리 **머리 위**에 떠 있다 (#225).
##
## **부모(`Player`)의 값을 읽어 그리기만 한다.** 채우는 것도 비우는 것도 서버가 정하고
## `Player.gauge`가 복제되므로 여기서는 아무 판단도 하지 않는다 — 두 화면에 같은 눈금이 뜬다.
##
## 게이지를 쓰는 무기(`gauge_max`가 있는 무기)를 들었을 때만 보인다. 보이고 숨는 것은
## `Player._apply_weapon()`이 정한다 — 무기가 바뀌는 순간이 거기 하나뿐이라서다.
##
## 씬 루트(`Player`)에는 가산 혼합이 걸려 있지만 **이 노드는 자기 재질이 없어 평소 혼합**으로
## 그린다. 게이지 바는 빛이 아니라 눈금이라, 잔디 위에서도 또렷한 색으로 읽혀야 한다.

## 바의 크기(px). 젤리 몸통(48px)보다 조금 넓다 — 머리 위에 얹힌 것으로 보이는 폭이다.
const WIDTH := 46.0
const HEIGHT := 7.0
## 바를 놓을 높이. 이름표(`NameLabel`, -96 ~ -72)와 머리(약 -44) 사이의 빈 자리다.
const CENTER_Y := -60.0

const BG_COLOR := Color(0.16, 0.14, 0.22, 0.85)
const BORDER_COLOR := Color(0.88, 0.86, 0.94, 0.55)
## 평소 채움 — 무기 선택 카드 테두리와 같은 보라다.
const FILL_COLOR := Color(0.62, 0.52, 0.86)
## 75% 이상 채움 — 오라와 같은 자홍이다. 색이 갈리는 것 자체가 "지금 세다"의 표시다.
const CHARGED_COLOR := Color(0.95, 0.36, 0.88)

## 참조를 들고 있지 않고 매번 부모를 본다 — 부모가 정해 주는 값이 하나뿐이라 그게 더 짧다.
var _player: Node = null


func _ready() -> void:
	_player = get_parent()


## 게이지는 매 프레임 바뀔 수 있다 (맞을 때마다). 보일 때만 다시 그린다.
func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if _player == null:
		return
	var ratio: float = clampf(_player.gauge_ratio(), 0.0, 1.0)
	var charged: bool = _player.is_charged()
	var half := WIDTH * 0.5
	var box := Rect2(-half, CENTER_Y - HEIGHT * 0.5, WIDTH, HEIGHT)

	draw_rect(box, BG_COLOR, true)
	if ratio > 0.0:
		var fill := box.grow(-1.0)
		fill.size.x = maxf(fill.size.x * ratio, 1.0)
		var color := CHARGED_COLOR if charged else FILL_COLOR
		# 다 찬 뒤에도 숨을 쉬게 해서 "지금 쓸 수 있다"가 눈에 걸리게 한다.
		if charged:
			color = color.lerp(Color.WHITE, 0.18 + 0.18 * sin(_now() * 8.0))
		draw_rect(fill, color, true)
	# 테두리를 마지막에 덧그려 채움이 밖으로 새어 보이지 않게 한다.
	draw_rect(box, BORDER_COLOR, false, 1.0)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
