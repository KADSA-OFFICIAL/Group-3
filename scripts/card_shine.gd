class_name CardShine
extends Control
## 무기 선택 카드가 뜰 때 카드 위로 타오르는 황금빛 (#263).
##
## 카드 **안에서 솟는 빛기둥**과 **테두리 광채** 둘을 그린다. 참고한 영상에서 카드가
## 떠오를 때 일어나던 일이 그 둘이었고, 둘 다 잠깐 가장 밝았다가 사라져 **끝나면 지금까지의
## 화면과 똑같아진다** — 남는 것이 없어야 카드를 읽는 데 방해가 되지 않는다.
##
## **카드 위에 겹쳐 그린다.** 카드는 `Button`이고 그 안에 그림·이름·설명이 자식으로 들어
## 있어서, 카드 밑에 깔면 빛이 카드 배경(불투명한 `StyleBoxFlat`)에 통째로 가려진다.
## 위에 얹되 잠깐 지나가는 빛이라 글자를 오래 가리지 않는다.
##
## **마우스를 가로채지 않는다** (씬에서 `mouse_filter = 2`). 카드 위를 덮는 노드라
## 그대로 두면 연출이 도는 동안 카드를 누를 수 없다 — 연출은 표시일 뿐이고 조작을
## 막지 않는다는 것이 이 연출의 전제다.
##
## 카드 자리는 **부모가 넘겨 준 카드 노드에서 그때그때 되짚는다**(`_card_rect()`).
## 여기서 좌표를 따로 계산하면 카드가 커지는 동안(부모가 `scale`을 몬다) 빛만 제자리에
## 남는다 — 잔상이 무기 자세를 되짚는 것(`Player._blade_ends()`)과 같은 이유다.
##
## 진행은 부모(`weapon_pick.gd`)가 잰다. 여기는 `progress`를 받아 그리기만 한다 —
## 어둡기·카드 크기와 박자가 갈라지면 안 되므로 시계는 한 곳에만 둔다.

## 황금색. 카드의 보라 테두리는 그대로 두고 이 빛만 금색이다 — 시계(`Timer`)와
## 눌린 카드 테두리(`focus`)가 이미 쓰는 색이라 화면에 없던 색이 아니다.
const GOLD := Color(1.0, 0.85, 0.55)
const GOLD_HOT := Color(1.0, 0.96, 0.86)

## ── 빛기둥 ──
## 기둥이 가장 밝아지는 시점(0~1)과 다 사라지는 시점.
const SHAFT_PEAK := 0.34
const SHAFT_END := 0.86
## 가장 밝을 때의 옅기. **옅어야 한다** — 진하면 카드 그림과 글자가 빛에 묻힌다.
const SHAFT_ALPHA := 0.58
## 기둥의 폭 (카드 폭에 대한 비율). 위가 좁고 아래로 갈수록 넓다 —
## 참고한 영상에서 빛이 그림 쪽에서 아래로 퍼져 내려왔다.
const SHAFT_TOP_RATIO := 0.22
const SHAFT_BOTTOM_RATIO := 0.72
## 기둥이 가장 밝은 높이 (카드 높이에 대한 비율, 0이 위). 그림이 있는 자리다.
const SHAFT_WAIST := 0.34

## ── 테두리 광채 ──
## 테두리가 가장 밝아지는 시점(0~1)과 다 사라지는 시점. 기둥보다 조금 일찍 붙고
## 조금 늦게까지 남는다 — 둘이 같은 박자면 한 덩어리로 번쩍이고 만다.
const EDGE_PEAK := 0.26
const EDGE_END := 1.0
const EDGE_ALPHA := 0.9
## 광채를 몇 겹으로 쌓는지와 가장 바깥 겹의 굵기(px). 넓고 옅은 것 위에 좁고 밝은 것을
## 얹어 번지는 빛을 흉내낸다 (`skill_arcs.gd`·`weapon_trail.gd`와 같은 방식).
const EDGE_LAYERS := 4
const EDGE_WIDTH := 13.0
## 카드 모서리의 둥근 반지름(px). **씬의 `StyleBoxFlat`과 같은 값이어야 한다** —
## 어긋나면 광채가 카드 모서리에서 벗어나 뜬다.
const CORNER_RADIUS := 22.0
## 모서리 하나를 몇 조각으로 꺾어 그릴지. 작으면 각져 보인다.
const CORNER_STEPS := 5

## ── 첫 번쩍임 ──
## 카드가 뜨는 순간 카드 전체를 덮었다 사라지는 흰빛. 아주 짧다 — 길면 카드가
## 켜지는 것이 아니라 하얀 판이 놓였다 치워지는 것으로 보인다.
const FLASH_END := 0.22
const FLASH_ALPHA := 0.42

## 빛을 입힐 카드들. 부모가 `_ready()`에서 넣어 준다.
var cards: Array = []
## 카드마다의 진행(0~1). 1이면 다 끝난 것이라 아무것도 그리지 않는다.
## 부모가 매 프레임 채운다 — 장마다 어긋나 뜨므로 하나가 아니라 배열이다.
var progress: Array = []


## 부모가 진행을 갱신한 뒤 부른다. 다 끝났으면 부모가 이 노드를 숨긴다.
func refresh(values: Array) -> void:
	progress = values
	queue_redraw()


func _draw() -> void:
	for i in mini(cards.size(), progress.size()):
		var card: Control = cards[i]
		# **`visible` 이 아니라 `is_visible_in_tree()` 다.** 관전자 화면은 카드를 담은
		# 상자(`Cards`)째로 숨기는데(`open_watching`), 카드 자신의 `visible` 은 참으로
		# 남아 있다 — 그것만 보면 아무것도 없는 자리에 빛 세 덩이가 뜬다.
		if card == null or not card.is_visible_in_tree():
			continue
		var t: float = progress[i]
		if t <= 0.0 or t >= 1.0:
			continue
		var rect := _card_rect(card)
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		_draw_shaft(rect, t)
		_draw_flash(rect, t)
		_draw_edge(rect, t)


## 카드가 지금 화면에서 차지한 자리를 이 노드의 지역 좌표로.
##
## 크기(`scale`)까지 따라간다 — 부모가 카드를 작은 크기에서 키우는 동안 빛도 같이 커져야
## "카드가 빛을 내며 떠오른다"로 읽힌다.
func _card_rect(card: Control) -> Rect2:
	var size := card.size * card.scale
	# 카드는 제 가운데를 축으로 커진다(부모가 `pivot_offset`을 가운데로 잡는다).
	var top_left := card.global_position - (size - card.size) * 0.5
	# **`to_local()` 은 `Node2D` 것이라 `Control` 에는 없다.** 변환으로 직접 되돌린다.
	return Rect2(get_global_transform().affine_inverse() * top_left, size)


## 한 구간에서의 세기 — `peak`까지 빠르게 차오르고 `finish`까지 천천히 빠진다.
## 반대로 하면 빛이 켜지는 것이 아니라 꺼지는 것으로 보인다.
func _swell(t: float, peak: float, finish: float) -> float:
	if t <= 0.0 or t >= finish:
		return 0.0
	if t < peak:
		var rise := t / peak
		return rise * rise
	var fall := (t - peak) / (finish - peak)
	return (1.0 - fall) * (1.0 - fall)


## 카드 안에서 솟는 황금빛 기둥.
##
## **위아래 끝이 투명한 사다리꼴 둘**이다. 한 덩어리로 그리면 빛이 카드 안에 놓인
## 도형으로 보이고, 끝이 흐려져야 새어 나오는 빛으로 읽힌다. 꼭짓점마다 색을 따로 주는
## `draw_polygon`이라 겹을 여러 개 쌓지 않아도 그러데이션이 나온다.
func _draw_shaft(rect: Rect2, t: float) -> void:
	var strength := _swell(t, SHAFT_PEAK, SHAFT_END)
	if strength <= 0.0:
		return
	var alpha := SHAFT_ALPHA * strength
	var mid_x := rect.position.x + rect.size.x * 0.5
	var waist_y := rect.position.y + rect.size.y * SHAFT_WAIST
	var top_half := rect.size.x * SHAFT_TOP_RATIO * 0.5
	var waist_half := rect.size.x * lerpf(SHAFT_TOP_RATIO, SHAFT_BOTTOM_RATIO, 0.5) * 0.5
	var bottom_half := rect.size.x * SHAFT_BOTTOM_RATIO * 0.5
	var clear := Color(GOLD, 0.0)
	# 허리는 **금색**이다. 흰빛(`GOLD_HOT`)으로 두었더니 기둥이 잿빛 원뿔로 보여
	# 카드에 김이 서린 것 같았다 — 테두리 광채와 같은 금색이어야 한 빛으로 읽힌다.
	var lit := Color(GOLD, alpha)
	# 위쪽 — 카드 꼭대기에서 허리까지, 위로 갈수록 투명해진다.
	draw_polygon(
		PackedVector2Array([
			Vector2(mid_x - top_half, rect.position.y),
			Vector2(mid_x + top_half, rect.position.y),
			Vector2(mid_x + waist_half, waist_y),
			Vector2(mid_x - waist_half, waist_y),
		]),
		PackedColorArray([clear, clear, lit, lit]))
	# 아래쪽 — 허리에서 카드 바닥까지, 넓어지면서 옅어진다.
	draw_polygon(
		PackedVector2Array([
			Vector2(mid_x - waist_half, waist_y),
			Vector2(mid_x + waist_half, waist_y),
			Vector2(mid_x + bottom_half, rect.position.y + rect.size.y),
			Vector2(mid_x - bottom_half, rect.position.y + rect.size.y),
		]),
		PackedColorArray([lit, lit, clear, clear]))


## 카드가 뜨는 순간의 흰 번쩍임. 카드 전체를 덮었다 곧 사라진다.
func _draw_flash(rect: Rect2, t: float) -> void:
	if t >= FLASH_END:
		return
	var life := 1.0 - t / FLASH_END
	draw_rect(rect, Color(GOLD_HOT, FLASH_ALPHA * life * life))


## 테두리 광채. 넓고 옅은 것 위에 좁고 밝은 것을 얹어 번지는 빛을 흉내낸다.
func _draw_edge(rect: Rect2, t: float) -> void:
	var strength := _swell(t, EDGE_PEAK, EDGE_END)
	if strength <= 0.0:
		return
	var points := _rounded_rect(rect, CORNER_RADIUS)
	for layer in EDGE_LAYERS:
		var share := float(layer) / float(EDGE_LAYERS - 1)
		# 바깥일수록 넓고 옅다. 가장 안쪽 겹만 흰빛에 가깝다.
		var width := lerpf(EDGE_WIDTH, 2.0, share)
		var color := GOLD.lerp(GOLD_HOT, share)
		var alpha := EDGE_ALPHA * strength * lerpf(0.22, 1.0, share)
		draw_polyline(points, Color(color, alpha), width, true)


## 모서리가 둥근 네모의 테두리 점들. 씬의 `StyleBoxFlat`이 그리는 모양과 같아야 한다.
func _rounded_rect(rect: Rect2, corner: float) -> PackedVector2Array:
	var radius := minf(corner, minf(rect.size.x, rect.size.y) * 0.5)
	var points := PackedVector2Array()
	# 네 모서리의 중심과 그 모서리가 도는 시작 각(오른쪽 아래부터 시계 방향).
	var corners := [
		[rect.position + Vector2(rect.size.x - radius, rect.size.y - radius), 0.0],
		[rect.position + Vector2(radius, rect.size.y - radius), PI * 0.5],
		[rect.position + Vector2(radius, radius), PI],
		[rect.position + Vector2(rect.size.x - radius, radius), PI * 1.5],
	]
	for entry in corners:
		var center: Vector2 = entry[0]
		var start: float = entry[1]
		for step in CORNER_STEPS + 1:
			var angle := start + PI * 0.5 * float(step) / float(CORNER_STEPS)
			points.append(center + Vector2.RIGHT.rotated(angle) * radius)
	# 시작점으로 돌아와 테두리를 닫는다 — 안 닫으면 오른쪽 아래에 틈이 보인다.
	points.append(points[0])
	return points
