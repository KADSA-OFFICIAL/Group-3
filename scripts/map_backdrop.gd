extends Node2D
## 전투 화면에서 **맵 밖으로 남는 자리**를 그 맵의 배경으로 채운다 (#329).
##
## 화면 비율이 `expand` 로 바뀌면서(`project.godot` 의 `window/stretch/aspect`)
## 뷰포트는 기기 비율을 그대로 따라간다 — 20:9 폰이면 1440x648, 4:3 태블릿이면
## 1152x864 다. 반면 **맵은 여전히 1152x648 한 칸에만 그려진다**: 배경 원화가
## `scale 0.6` 으로 딱 그 크기에 맞춰져 있고(#264), 원화 픽셀에 0.6 을 곱한 값이
## 곧 충돌 상자 좌표라 원화만 키우면 그림의 발판과 실제 발판이 어긋난다.
##
## 그래서 **전투가 벌어지는 칸은 1152x648 그대로 두고, 남는 자리만 여기서 채운다.**
## 맵 지형·발판 높이·스폰 위치는 한 픽셀도 안 움직인다.
##
## 채우는 그림은 **그 맵의 배경 원화 그대로**이고, 화면을 덮도록 키운 뒤
## `DIM` 만큼 어둡게 깐다. 어둡게 하는 것은 장식이 아니라 **경계 표시다** —
## 원화 맵 4종은 `x = -20`·`1172` 에 보이지 않는 벽이 있어서, 밝게 채우면
## 걸어갈 수 있어 보이는 자리에서 막힌다. 어두우면 "여기는 전투 영역 밖"으로 읽힌다.
## 벽이 없는 바다 맵은 자기 `ColorRect` 를 화면 밖까지 늘려 두었으므로
## 이 노드가 보일 일이 없다 — 세상이 실제로 이어지는 맵이라 경계 표시가 없는 것이 맞다.
##
## **`z_index` 를 내리지 않고 `CanvasLayer`(layer = -1) 안에 둔다** (#146).
## 맵이 자기 배경을 z 0 의 불투명한 것으로 깔기 때문에 z 를 내리는 것으로는
## 그 뒤로 갈 수 없다 — 레이어가 다르면 z 와 무관하게 먼저 그려진다.


## 채움을 얼마나 어둡게 깔지. 1 보다 작을수록 어둡다.
## 0.62 는 전투 영역과 확실히 갈리면서 무엇이 그려져 있는지는 읽히는 선이다.
const DIM := Color(0.62, 0.62, 0.68)

## 맵에 배경이 아예 없을 때 쓰는 색. 보이면 안 되는 색이라 눈에 띄지 않는 회색이다.
const FALLBACK := Color(0.16, 0.14, 0.18)

## 지금 깔린 맵의 배경 원화. 없으면 null 이고 `_color` 로 채운다.
var _texture: Texture2D = null
## 원화가 없는 맵(바다)의 배경색.
var _color := FALLBACK


func _ready() -> void:
	# 창 크기가 바뀌면 채울 넓이도 바뀐다. 기기에서는 회전·분할 화면, PC 에서는 창 조절.
	get_viewport().size_changed.connect(queue_redraw)


## 맵이 깔릴 때마다 `main.gd` 의 `_load_map()` 이 부른다.
##
## 맵 씬 계약(`Maps`)이 "배경까지 맵이 그린다"이므로 배경 노드 이름(`Background`)만
## 알면 되고, 맵마다 채움 색을 따로 적어 둘 표는 필요 없다 — 맵을 추가해도
## 여기는 고칠 것이 없다.
func show_map(map: Node) -> void:
	_texture = null
	_color = FALLBACK
	if map == null:
		queue_redraw()
		return
	# `as` 로 받는다 — `is` 로 가른 뒤 속성을 읽으면 정적 타입이 Node 라 찾지 못한다.
	var background := map.get_node_or_null("Background")
	var sprite := background as Sprite2D
	var rect := background as ColorRect
	if sprite != null and sprite.texture != null:
		_texture = sprite.texture
	elif rect != null:
		_color = rect.color
	queue_redraw()


func _draw() -> void:
	var screen := get_viewport_rect().size
	if _texture == null:
		draw_rect(Rect2(Vector2.ZERO, screen), _color * DIM)
		return
	# 화면을 덮도록(aspect-fill) 키운다 — 비율을 지키면서 모자란 쪽이 없게 한다.
	# `map_preview.gd` 가 카드 배경에 쓰던 것과 같은 방식이고, 이유도 같다:
	# 배경이라 여백이 남으면 뚫려 보인다.
	var art := Vector2(_texture.get_size())
	if art.x <= 0.0 or art.y <= 0.0:
		return
	var factor := maxf(screen.x / art.x, screen.y / art.y)
	var size := art * factor
	draw_texture_rect(_texture, Rect2((screen - size) * 0.5, size), false, DIM)
