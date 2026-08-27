extends Control
## 카드 모서리에 달리는 오각별 배지 (요청, 사용자가 준 목업 기준).
##
## 카드 위에 얹히려면 `Card` **다음에** 있어야 하므로 씬에서 맨 마지막 자식으로 둔다 —
## 부모의 `_draw()` 는 자식보다 먼저 그려지기 때문에 `player_panel.gd` 안에서 그릴 수 없다.
##
## 색은 `player_panel.gd` 가 편 색(`accent`)으로 채워 준다.

@export var color := Color(0.96, 0.55, 0.78):
	set(value):
		color = value
		queue_redraw()

## 칸에 대한 별의 크기. 1.0이면 칸에 꽉 차서 테두리가 잘려 보인다.
@export_range(0.2, 1.0, 0.05) var fill_ratio := 0.86:
	set(value):
		fill_ratio = value
		queue_redraw()

## 안쪽 꼭짓점이 바깥 꼭짓점의 몇 배 거리인지. 작을수록 뾰족하다.
const INNER_RATIO := 0.46
## 흰 테두리 두께(px). 어떤 배경 위에서도 별이 뜨게 한다.
const RIM := 4.0


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 * fill_ratio
	if radius <= 0.0:
		return
	# 그림자 → 흰 테두리 → 속 순서로 겹친다. 테두리를 따로 그리는 것보다
	# 큰 별을 흰색으로 깔고 그 위에 작은 별을 얹는 것이 모서리가 깔끔하다.
	draw_colored_polygon(_star(center + Vector2(0.0, 3.0), radius + RIM),
			Color(color.darkened(0.45), 0.28))
	draw_colored_polygon(_star(center, radius + RIM), Color(1.0, 1.0, 1.0))
	draw_colored_polygon(_star(center, radius), color)
	# 왼쪽 위에 흰 빛 한 점 — 젤리처럼 반짝이게 한다.
	draw_circle(center + Vector2(-radius * 0.24, -radius * 0.3), radius * 0.16,
			Color(1.0, 1.0, 1.0, 0.85))


func _star(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		# 위쪽 꼭짓점부터 시작해 바깥·안쪽을 번갈아 돈다.
		var angle := -PI * 0.5 + PI * float(i) / 5.0
		var r := radius if i % 2 == 0 else radius * INNER_RATIO
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	return points
