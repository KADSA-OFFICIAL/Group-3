extends Node2D
## 폭탄이 터질 때 데미지·넉백이 들어가는 반경 표시 (#140).
##
## 폭탄은 **닿지 않아도 맞는** 유일한 무기다. 반경이 200px, 젤리 몸통(72px)의 세 배 가까운데
## 화면에는 폭탄 그림(40px)만 보여서 피할 수 있는 거리인지 아닌지를 볼 근거가 없다.
## 강화 폭탄 그림을 따로 둔 이유(#131)와 같은 문제다.
##
## **투사체 씬 루트가 아니라 자식 노드에서 그린다.** 루트에는 미사일 불꽃 때문에 가산 혼합
## (`CanvasItemMaterial`)이 걸려 있는데, 가산은 밝게만 만들 수 있어서 평지 하늘처럼 이미 흰
## 배경 위에서는 아무리 그려도 보이지 않는다. 자식은 그 재질을 물려받지 않으므로 여기서는
## 보통의 알파 혼합으로 그려져 어느 맵에서나 같게 읽힌다 (#112).
##
## 씬에서 `z_index = -1`이라 폭탄 그림 뒤에 깔린다. 순수 표시라 판정과는 무관하다 —
## 실제 판정은 `projectile.gd`의 `_explode()`가 한다.

## 안을 채우는 옅은 색. 원 전체를 덮으므로 진하면 그 안의 지형과 젤리가 묻힌다.
const FILL := Color(1.0, 0.86, 0.72)
const FILL_ALPHA := 0.16
## 경계선. **판정 경계와 정확히 같은 자리**라 이 표시의 알맹이다 — 채움만 있으면
## 옅은 쪽이 어디서 끝나는지 눈으로 짚을 수 없어 "어디까지가 안인지"를 못 읽는다.
const EDGE := Color(1.0, 0.42, 0.24)
const EDGE_ALPHA := 0.85
const EDGE_WIDTH := 3.0
## 원을 몇 조각으로 나눠 그릴지. 200px 반지름에서 이 정도면 각진 데가 안 보인다.
const EDGE_SEGMENTS := 64

## 표시할 반지름(px). 0이면 아무것도 그리지 않는다 — 폭탄이 아닌 투사체가 여기 해당한다.
var radius := 0.0:
	set(value):
		radius = value
		queue_redraw()


## 폭탄이 움직여도 다시 그릴 필요가 없다. 원점을 기준으로 그려 두면 노드가 옮겨질 때
## 그려 둔 것이 함께 따라간다.
func _draw() -> void:
	if radius <= 0.0:
		return
	draw_circle(Vector2.ZERO, radius, Color(FILL, FILL_ALPHA))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, EDGE_SEGMENTS,
		Color(EDGE, EDGE_ALPHA), EDGE_WIDTH, true)
