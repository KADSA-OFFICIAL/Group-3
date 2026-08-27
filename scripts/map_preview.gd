extends Control
## 대기실 맵 카드의 배경 그림 (#289). 맵 배경 원화를 **칸을 꽉 채우도록**
## 비율을 지켜 잘라 그린다. `jelly_preview.gd`·`weapon_preview.gd`와 같은 형태다.
##
## 저 둘과 다른 점은 **채우는 방식**이다 — 캐릭터·무기는 칸 안에 여백을 두고 다
## 들어가야 하지만(aspect-fit), 이쪽은 배경이라 여백이 남으면 카드가 뚫려 보인다.
## 원화가 16:9이고 칸은 세로로 긴 절반이라 가로를 가운데만 잘라 쓴다.
##
## 원화가 없는 맵(바다)·`랜덤`·빈 자리는 `Maps.art_color()`의 단색으로 채운다 —
## 아무것도 그리지 않으면 카드가 반쪽만 색이 있는 모양이 된다.
##
## 여백을 재는 `Art.content_rect()`는 쓰지 않는다 — 맵 원화는 화면을 꽉 채우는
## 그림이라 투명 여백이 없다.
##
## **둥근 모서리는 이 노드가 만들지 않는다.** 뒤에 깔린 `ScreenRect`(둥근 판)보다
## 조금 안쪽에 놓여 그 판이 테두리로 보이게 하는 방식이다 — `clip_children`은
## GL Compatibility 렌더러에서 동작하지 않아 모서리가 각지게 잘렸다.

## 원화 위에 덮는 색. 카드 바탕색이라 원화가 있든 없든 카드의 톤이 유지된다.
const SCRIM_COLOR := Color(0.27, 0.22, 0.32)

@export var map_name := "":
	set(value):
		map_name = value
		_texture = Maps.art_texture(value)
		_color = Maps.art_color(value)
		queue_redraw()

## 원화 위에 덮는 어둡기. 맵마다 밝기가 크게 달라(#112) 그대로 두면 카드 톤이
## 들쭉날쭉하고, 가운데 `?` 배지가 밝은 맵 위에서 떠 보인다.
##
## **글자 가독성을 이 값에 맡기지 않는다** — 원화 위의 흰 글자는 아무리 덮어도
## 밝은 하늘에서 3:1을 넘기지 못한다. 글자는 불투명한 배지 위에 둔다.
@export_range(0.0, 1.0, 0.05) var scrim := 0.12:
	set(value):
		scrim = value
		queue_redraw()

var _texture: Texture2D = null
var _color := Maps.UNKNOWN_COLOR


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if _texture == null:
		draw_rect(rect, _color)
		return
	var art_size := _texture.get_size()
	if art_size.x <= 0.0 or art_size.y <= 0.0:
		draw_rect(rect, _color)
		return
	# 칸을 꽉 채우는 배율을 고르고(둘 중 큰 쪽) 그만큼만 원화에서 잘라 온다.
	# 잘라내는 곳은 가운데다 — 발판과 지형이 원화 가운데에 몰려 있다.
	var fill := maxf(size.x / art_size.x, size.y / art_size.y)
	var region_size := size / fill
	draw_texture_rect_region(_texture, rect, Rect2((art_size - region_size) * 0.5, region_size))
	if scrim > 0.0:
		draw_rect(rect, Color(SCRIM_COLOR, scrim))
