extends Control
## 캐릭터 선택창 가운데 장식 — 맨 위 `캐릭터 선택` 리본과 가운데 `VS` (요청).
##
## **배경은 이제 이 노드가 그리지 않는다**(#341). 사용자가 준 무기 진열장 원화
## (`assets/ui/select_bg.png`)를 씬의 `Wall`(TextureRect)이 화면에 꽉 차게 깐다.
## 예전에 여기서 `_draw()`로 그리던 그라데이션·구름·번개·별·젤리 조각·꽃밭은 원화가
## 대신하므로 지웠다. 남긴 것은 그림이 아니라 정보를 주는 둘뿐이다 — 이 화면이 무엇인지
## (리본)와 두 사람이 맞붙는다는 것(`VS`).
##
## **이 노드는 아무것도 가리지 않는다.** 씬에서 `Wall` 다음에 두어 카드·버튼·글자가
## 모두 이 위에 그려진다. 리본과 `VS`는 카드 사이 빈 자리에만 있으므로 뒤에서 그려도
## 가려지지 않는다.

# ─────────────────────────── VS ───────────────────────────
## `VS` 의 중심과 크기. 두 글자를 따로 그려 색을 나눈다 — 한 덩어리로 적으면
## 어느 쪽이 누구인지 색으로 읽히지 않는다.
const VS_CENTER_Y := 208.0
const VS_SIZE := 116
const VS_OUTLINE := 22
const VS_LEFT_COLOR := Color(0.93, 0.28, 0.50)
const VS_RIGHT_COLOR := Color(0.36, 0.60, 0.95)
const VS_OUTLINE_COLOR := Color(1.0, 1.0, 1.0)

# ─────────────────────────── 리본 ───────────────────────────
## 맨 위 가운데의 `캐릭터 선택` 이름표. 좌우가 접힌 리본 모양이다.
const RIBBON_TEXT := "캐릭터 선택"
const RIBBON_TOP := 22.0
const RIBBON_HEIGHT := 44.0
const RIBBON_HALF := 136.0
## 좌우로 접혀 들어가는 깊이.
const RIBBON_FOLD := 20.0
const RIBBON_SIZE := 24
const RIBBON_COLOR := Color(0.94, 0.44, 0.64)
const RIBBON_EDGE := Color(0.78, 0.26, 0.48)

const FONT := preload("res://resources/display_font.tres")


func _draw() -> void:
	_draw_vs()
	_draw_ribbon()


## 가운데의 `VS`. 두 글자를 따로 그려 왼쪽은 분홍, 오른쪽은 파랑으로 나눈다.
func _draw_vs() -> void:
	var center := Vector2(size.x * 0.5, VS_CENTER_Y)
	var v_width := FONT.get_string_size("V", HORIZONTAL_ALIGNMENT_LEFT, -1.0, VS_SIZE).x
	var s_width := FONT.get_string_size("S", HORIZONTAL_ALIGNMENT_LEFT, -1.0, VS_SIZE).x
	var total := v_width + s_width
	var baseline := center.y + VS_SIZE * 0.36
	var v_at := Vector2(center.x - total * 0.5, baseline)
	var s_at := Vector2(v_at.x + v_width, baseline)
	# 두 글자 뒤에 흰 빛무리를 깔아 진열장 원화 위에서 글자가 뜨게 한다.
	Art.draw_glow(self, center, VS_SIZE * 1.1, Color(1.0, 0.95, 1.0), 0.3, 16)
	# 테두리를 흰색으로 둘러 어느 쪽 배경에서도 글자가 뜬다.
	# **테두리 둘을 먼저 다 두르고 속을 채운다** — 한 글자씩 테두리·속을 번갈아 그리면
	# 뒷 글자의 테두리가 앞 글자의 속을 덮는다(`V` 와 `S` 는 붙어 있다).
	draw_string_outline(FONT, v_at, "V", HORIZONTAL_ALIGNMENT_LEFT, -1.0, VS_SIZE,
			VS_OUTLINE, VS_OUTLINE_COLOR)
	draw_string_outline(FONT, s_at, "S", HORIZONTAL_ALIGNMENT_LEFT, -1.0, VS_SIZE,
			VS_OUTLINE, VS_OUTLINE_COLOR)
	draw_string(FONT, v_at, "V", HORIZONTAL_ALIGNMENT_LEFT, -1.0, VS_SIZE, VS_LEFT_COLOR)
	draw_string(FONT, s_at, "S", HORIZONTAL_ALIGNMENT_LEFT, -1.0, VS_SIZE, VS_RIGHT_COLOR)


## 맨 위 가운데의 `캐릭터 선택` 리본. 좌우가 접혀 들어간 띠에 글자를 얹는다.
func _draw_ribbon() -> void:
	var cx := size.x * 0.5
	var top := RIBBON_TOP
	var bottom := RIBBON_TOP + RIBBON_HEIGHT
	var mid := (top + bottom) * 0.5
	var body := PackedVector2Array([
		Vector2(cx - RIBBON_HALF, top),
		Vector2(cx + RIBBON_HALF, top),
		Vector2(cx + RIBBON_HALF - RIBBON_FOLD, mid),
		Vector2(cx + RIBBON_HALF, bottom),
		Vector2(cx - RIBBON_HALF, bottom),
		Vector2(cx - RIBBON_HALF + RIBBON_FOLD, mid),
	])
	draw_colored_polygon(body, RIBBON_COLOR)
	draw_polyline(body + PackedVector2Array([body[0]]), RIBBON_EDGE, 3.0, true)
	_draw_centered(RIBBON_TEXT, Vector2(cx, mid + RIBBON_SIZE * 0.36), RIBBON_SIZE,
			Color(1.0, 1.0, 1.0), 4, RIBBON_EDGE)
	# 글자 좌우의 작은 별. 목업의 리본에 있던 것이다.
	for direction: float in [-1.0, 1.0]:
		_draw_star(Vector2(cx + direction * (RIBBON_HALF - 26.0), mid), 8.0,
				Color(1.0, 0.86, 0.42))


## 오각별 하나. 리본 장식과 카드 배지가 같은 모양을 쓴다.
func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * float(i) / 5.0
		var r := radius if i % 2 == 0 else radius * 0.46
		points.append(center + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(points, color)


func _draw_centered(text: String, center: Vector2, font_size: int, color: Color,
		outline := 0, outline_color := Color(0, 0, 0, 0)) -> void:
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var at := Vector2(center.x - width * 0.5, center.y)
	if outline > 0:
		draw_string_outline(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size,
				outline, outline_color)
	draw_string(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
